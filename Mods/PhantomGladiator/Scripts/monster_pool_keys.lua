-- Saved by the local panel. Only resolved pool requests reach the normal summon path.
local Router=require('key_router')
local Keys={}
local MAX_BYTES=1048576
local TEAMS={blue=true,red=true,neutral=true,companion=true}

local function readRevision(header)
    local revision=tonumber((header or ''):match('^MonsterPoolsV1\t(%d+)\n'))
    return revision and revision>=1 and revision<=2147483646 and revision or nil
end

local function parse(text)
    local pools,ids,chords={},{},{}
    if not text or #text>MAX_BYTES or text:sub(-1)~='\n' then return nil end
    local header=true
    for line in text:gmatch('([^\n]*)\n') do
        if header then header=false
        else
            local id,name,team,count,vk,mask,members=line:match('^([^\t]+)\t([^\t]+)\t(%a+)\t(%d+)\t(%d+)\t(%d+)\t([^\t]*)$')
            count,vk,mask=tonumber(count),tonumber(vk),tonumber(mask)
            if not id or not id:match('^pool%-[a-z0-9]+$') or #id>37 or #pools>=24 or ids[id] or
                #name>192 or name:find('[%z\1-\31\127]') or not TEAMS[team] or not count or count<1 or count>100 or
                not Router.valid(vk,mask) or (vk==0 and mask~=0) then return nil end
            local slot=Router.slot(vk,mask)
            if vk>0 and chords[slot] then return nil end
            local paths,seen={},{}
            if members~='' then
                for path in (members..';'):gmatch('([^;]*);')do
                    if #paths>=256 or #path>512 or seen[path] or not path:match('^/[%w_/%-%.]+%.[%w_%-]+_C$')
                        or path:find('..',1,true) or path:find('//',1,true) then return nil end
                    paths[#paths+1]=path;seen[path]=true
                end
            end
            pools[#pools+1]={id=id,name=name,team=team,count=count,vk=vk,mask=mask,slot=slot,paths=paths}
            ids[id]=true;chords[slot]=true
        end
    end
    return pools
end

function Keys.new(options)
    local self={revision=0,pools={},active={},owners={},errors={}}
    local source=options.path..'/monster-pools.tsv'
    local state=options.path..'/monster-pools-state.tsv'
    local log=options.log or function()end

    local function publish()
        local lines={'MonsterPoolKeysV1\t'..self.revision..'\t'..self.session}
        for _,pool in ipairs(self.pools) do
            if pool.vk>0 then
                local msg=tostring(self.errors[pool.id] or ''):gsub('[%z\1-\31\127]',' ')
                lines[#lines+1]=pool.id..'\t'..(self.active[pool.slot]==pool and '1' or '0')..'\t'..msg
            end
        end
        local text=table.concat(lines,'\n')..'\n'
        local file=io.open(state,'wb');if not file then return false end
        local written=file:write(text);local closed=file:close()
        if not written or not closed then return false end
        file=io.open(state,'rb');if not file then return false end
        local readback=file:read(#text+1);file:close()
        return readback==text
    end

    function self:refresh(session)
        local file,_,errno=io.open(source,'rb')
        if not file and errno~=2 then return end -- retry transient file sharing errors
        local revision=file and (readRevision(file:read(64)) or -1) or 0
        local changed=revision~=self.revision
        local text=changed and revision>0 and file:seek('set',0) and file:read(MAX_BYTES+1) or nil
        if file then file:close() end
        if changed then
            local pools=parse(text)
            self.revision,self.pools,self.active,self.owners,self.errors=revision,pools or {},{},{},{}
            for _,pool in ipairs(self.pools)do
                if pool.vk>0 then
                    self.owners[pool.slot]=pool
                    local blocked=options.conflict(pool.vk,pool.mask)
                    local ok,reason
                    if blocked then ok,reason=false,'已被'..blocked..'占用'
                    else ok,reason=options.router:ensure(pool.vk,pool.mask) end
                    if ok then self.active[pool.slot]=pool else self.errors[pool.id]=reason end
                    log('[PoolKeys] 注册读回 pool='..pool.id..' key='..Router.label(pool.vk,pool.mask)
                        ..' active='..tostring(ok)..(ok and '' or ' reason='..tostring(reason)))
                end
            end
            if revision~=0 then
                log('[PoolKeys] 读取配置 revision='..revision..'；读回='..(pools and (#pools..' 个池') or '配置无效，未启用'))
            end
        end
        if changed or session~=self.session then self.pending=true end
        self.session=session
        if revision<=0 then self.pending=false;return end
        if self.pending and type(session)=='string' and session~='' then
            local ok=publish()
            self.pending=not ok
            if ok and changed then log('[PoolKeys] 按键状态文件读回确认 revision='..revision) end
        end
    end

    function self:owner(vk,mask)
        local pool=self.owners[Router.slot(vk,mask or 0)]
        return pool and pool.name
    end

    function self:dispatch(vk,mask)
        local slot=Router.slot(vk,mask)
        local pool=self.active[slot]
        if not pool then return false end
        local choices={}
        for _,path in ipairs(pool.paths)do
            if options.eligible(path,pool.count) then choices[#choices+1]=path end
        end
        if #choices==0 then log('[PoolKeys] '..pool.id..'；读回=没有符合数量的可召唤单位');return true end
        local path=choices[math.random(#choices)]
        local expectedSession=self.session
        local result=options.queue(function()
            if self.active[slot]~=pool then return end
            local session=options.session()
            if session.game_ready~=true or session.game_session~=expectedSession then
                log('[PoolKeys] '..pool.id..'；读回=游戏未就绪或已换图，未召唤');return
            end
            local outcome=options.spawn(path,pool.team,pool.count)
            log('[PoolKeys] 召唤 pool='..pool.id..' path='..path..'；读回='..tostring(outcome and outcome.message))
        end,path,pool.team,pool.count)
        if result then
            log('[PoolKeys] 排队 pool='..pool.id..' path='..path..'；读回='..tostring(result.message))
        end
        return true
    end
    return self
end
return Keys
