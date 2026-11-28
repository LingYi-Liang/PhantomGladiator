-- The panel owns the preference. The game owns the last party and its world claim.
-- Persist only direct summon recipes. Actors, skill helpers and combat state never cross a map.
local Files=require('companion_profile')
local Squad={}
local LIMIT=1024*1024

local function recipe(path,dual)
    if type(path)~='string' or #path>512 or not path:match('^/[%w_/%-]+%.[%w_%-]+_C$') or path:find('//',1,true) then return end
    if dual then
        if not Files.phase(path) then return end
        return Files.first,'dual'
    end
    return path,'unit'
end

local function add(rows,path,mode,n)
    for _,row in ipairs(rows) do
        if row.path==path and row.mode==mode then row.count=row.count+n;return end
    end
    rows[#rows+1]={path=path,mode=mode,count=n}
end

local function decode(text)
    if type(text)~='string' or #text>LIMIT or text:sub(-1)~='\n' then return end
    local generation,world,body=text:match('^PGCS1\t([0-9a-f]+)\t([%w_%-]+)\n(.*)$')
    if not generation or #generation~=24 or #world>180 then return end
    local rows,seen={},{}
    for line in body:gmatch('([^\n]*)\n') do
        local mode,amount,path=line:match('^(%a+)\t([1-9]%d*)\t([^\t]+)$')
        local n=tonumber(amount)
        if (mode~='unit' and mode~='dual') or not n or n>2147483647 or recipe(path,mode=='dual')~=path then return end
        local key=mode..path
        if seen[key] then return end
        seen[key]=true;rows[#rows+1]={path=path,mode=mode,count=n}
    end
    return generation,world,rows
end

function Squad.new(o)
    local self={enabled=false,total=0,state='off'}
    local pref=o.path..'/companion-squad-settings.tsv'
    local file=o.path..'/companion-squad.tsv'
    local read,write,clock=o.read or Files.read,o.write or Files.write,o.clock or os.time
    local log=o.log or function()end
    local rows,pending={},{}
    local generation,claimed,world,readySince,failed,dirty,unreadable,restoring,rescan
    local nextPref,nextTick,nextSave=0,0,0
    local prefReadable=true

    local function store()
        dirty=true
        local lines={table.concat({'PGCS1',generation,claimed or 'none'},'\t')}
        local total=0
        for _,r in ipairs(rows) do
            lines[#lines+1]=table.concat({r.mode,r.count,r.path},'\t')
            total=total+r.count
        end
        self.total=total
        local data=table.concat(lines,'\n')..'\n'
        if #data>LIMIT or not write(file,data) then
            if self.state~='save_error' then log('[CompanionSquad] 队伍写入未确认，暂停恢复') end
            self.state='save_error';nextSave=clock()+3;return false
        end
        dirty=false
        self.state=#pending>0 and 'restoring' or failed and 'partial' or 'remembered'
        return true
    end

    local function preference(now,force)
        if not force and now<nextPref then return end
        nextPref=now+2
        local data=read(pref,96)
        local flag,revision
        if data then flag,revision=data:match('^PGCR1\t([01])\t([0-9a-f]+)\n$') end
        prefReadable=(flag~=nil and #revision==24) or (data==nil and not self.enabled)
        if not prefReadable then self.state='read_error';return end
        self.preferenceRevision=revision or '0'
        if flag~='1' then
            if not self.enabled then return end
            generation,world,claimed,readySince,dirty,unreadable=nil,nil,nil,nil,false,false
            self.enabled,self.total,self.state=false,0,'off'
            rows,pending={},{}
            return
        end
        if revision==generation then
            if self.state=='read_error' and not unreadable then self.state=#pending>0 and 'restoring' or failed and 'partial' or 'remembered' end
            return
        end
        generation,world,claimed,readySince,failed,dirty,unreadable=revision,nil,nil,nil,false,false,false
        self.enabled,self.total,self.state=true,0,'waiting'
        rows,pending={},{}
        local data=read(file,LIMIT)
        if data==nil then data=read(file..'.bak',LIMIT) end
        if data then
            local saved,stamp,loaded=decode(data)
            if not saved then
                -- A corrupt snapshot must not generate a partial party. A fresh preference
                -- generation can safely replace a malformed snapshot from a different generation.
                if data:match('^PGCS1\t([0-9a-f]+)\t')==generation then
                    unreadable=true;self.state='read_error';log('[CompanionSquad] 保存的队伍无法完整读取');return
                end
            elseif saved==generation then
                rows,claimed=loaded,stamp
                for _,r in ipairs(rows) do self.total=self.total+r.count end
            end
        end
    end

    local function session()
        local s=o.session()
        local key=s and s.game_ready==true and s.game_world
        if type(key)=='string' and #key<=180 and key:match('^[%w_%-]+$') then return key end
    end

    local function reconcile(live)
        local counts,changed={},false
        for _,r in ipairs(live) do
            local path,mode=recipe(r.path,r.dual)
            if path then
                local id=mode..path
                counts[id]=(counts[id] or 0)+1
            end
        end
        pending={};failed=false
        for _,r in ipairs(rows) do
            local id=r.mode..r.path
            local present=counts[id] or 0
            if present<r.count then pending[#pending+1]={path=r.path,mode=r.mode,count=r.count-present}
            elseif present>r.count then r.count=present;changed=true end
            counts[id]=nil
        end
        for _,r in ipairs(live) do
            local path,mode=recipe(r.path,r.dual)
            local id=path and mode..path
            if id and counts[id] then
                rows[#rows+1]={path=path,mode=mode,count=counts[id]}
                counts[id]=nil;changed=true
            end
        end
        return changed
    end

    local function enter(key,now)
        if world==key then return true end
        if claimed==key then
            -- Reload may leave actors with no ownership records in the new Lua instance.
            world=key;pending={};failed=false;self.state='remembered';return true
        end
        local live=o.members()
        if not live then self.state='waiting';return false end
        reconcile(live)
        world,claimed,readySince,rescan=key,key,now,#pending>0
        store() -- claim this world before the first spawn, including over hot reload
        return false -- live already includes the batch that caused entry
    end

    function self:added(path,dual,n)
        if restoring then return end
        local now=clock()
        preference(now,true)
        if not self.enabled or not prefReadable or unreadable or not n or n<1 then return end
        local path,mode=recipe(path,dual)
        if not path then return end
        local key=session()
        if not key or not enter(key,now) then return end
        for i,r in ipairs(pending) do
            if r.path==path and r.mode==mode then
                local covered=math.min(n,r.count)
                n=n-covered;r.count=r.count-covered
                if r.count==0 then table.remove(pending,i) end
                break
            end
        end
        if n>0 then add(rows,path,mode,n) end
        store()
    end

    function self:dismiss()
        preference(clock(),true)
        if not self.enabled then return true end
        rows,pending={},{}
        unreadable,failed=false,false
        claimed=session() or claimed;world=claimed
        local ok=store()
        if ok then log('[CompanionSquad] 主动遣散，已读回保存人数=0') end
        return ok
    end

    function self:tick()
        local now=clock()
        if now<nextTick then return end
        nextTick=now+1
        preference(now,#pending>0)
        if not self.enabled or not prefReadable or unreadable then return end
        if dirty and (now<nextSave or not store()) then return end
        local key=session()
        if not key then readySince=nil;return end
        if world~=key then enter(key,now);return end
        if #pending==0 then return end
        readySince=readySince or now
        if now-readySince<2 or o.busy and o.busy() then return end
        if rescan then
            -- Actors carried through streaming may appear after the first ready heartbeat.
            local live=o.members()
            if not live then return end
            local changed=reconcile(live);rescan=false
            if changed and not store() then return end
            if #pending==0 then self.state='remembered';return end
        end
        local row=pending[1]
        restoring=true
        local ok,result=pcall(o.spawn,row.path,row.mode=='dual')
        restoring=false
        if not ok or type(result)~='table' or result.uncertain or result.spawned_count=='unknown' then
            pending={};failed=true;self.state='uncertain'
            log('[CompanionSquad] 生成结果不明，本图停止恢复 '..row.path)
            return
        end
        if result.ok==true and result.spawned_count==1 then
            row.count=row.count-1
            if row.count==0 then table.remove(pending,1) end
        else
            failed=true;table.remove(pending,1)
            log('[CompanionSquad] 本图跳过未确认的队员 '..row.path..' '..tostring(result.message))
        end
        self.state=#pending>0 and 'restoring' or failed and 'partial' or 'remembered'
        if #pending==0 then log('[CompanionSquad] 恢复结束；目标人数='..self.total..' 状态='..self.state) end
    end
    return self
end
return Squad
