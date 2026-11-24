-- Keys for the teleport: one per place (a code of teleport_places.lua) and one for BACK, the return to where the
-- player stood before the last teleport. Built like unit_keybinds.lua: the saved file holds place codes and numeric
-- keys, never Lua code; every key goes through the shared key router; a key another feature owns is refused.
-- One press teleports; there is no confirmation step (the user's choice).
local Keys={}
local KeyRouter=require('key_router')
Keys.BACK='BACK'
local RESERVED={[121]=true,[192]=true,[91]=true,[92]=true}
local function integer(v,min,max)return type(v)=='number' and v==v and v%1==0 and v>=min and v<=max end
local function clean(s)return (tostring(s or ''):gsub('[\t\r\n]',' '))end
local function read(path)
    local f=io.open(path,'rb');if not f then return nil end
    local s=f:read(262145);f:close();return s and #s<=262144 and s or nil
end
local function write(path,data)
    local f,e=io.open(path,'wb');if not f then return false,e end
    local ok=f:write(data);local flushed=f:flush();local closed=f:close()
    return ok~=nil and flushed~=nil and closed~=nil and read(path)==data
end
-- options: path, log, router, keys (the UE4SS Key table), valid(target) -> name or nil, go(target) -> result,
-- ready() -> ok, reason, reserved(vk,mask) -> who owns the chord elsewhere, queue(fn) -> runs fn on the game thread.
function Keys.new(options)
    local self={entries={},active={},errors={},revision=0,alive=true,event=0,message=''}
    self.epoch='tpkeys-'..os.time()..'-'..tostring({}):gsub('[^%w]','')
    local keyTable=options.keys or Key or {}
    local log=options.log or function()end
    local queue=options.queue or function(fn)fn()end
    local supported={};for _,value in pairs(keyTable)do if integer(value,1,255)then supported[value]=true end end
    for code=65,90 do local value=keyTable[string.char(code)];if integer(value,1,255)then supported[value]=true end end
    for n=1,24 do local value=keyTable['F'..n];if integer(value,1,255)then supported[value]=true end end
    local filename=options.path..'/teleport-keybinds.tsv';local statefile=options.path..'/teleport-keybinds-state.tsv'
    local function nameOf(target)
        if target==Keys.BACK then return '返回传送前的位置' end
        local ok,name=pcall(options.valid,target)
        return ok and type(name)=='string' and name or nil
    end
    -- Who a chord belongs to here, as a text for the other features' refusals; nil when it is free.
    function self:owner(vk,mask)
        for target,e in pairs(self.entries)do
            if e.key_code==vk and e.modifiers==(mask or 0) then return '传送：'..(nameOf(target) or target) end
        end
    end
    function self:dispatch(vk,mask)
        if not self.alive then return end
        local slot=KeyRouter.slot(vk,mask)
        local binding=self.active[slot]
        if not binding then return end
        local revision,target=self.revision,binding.target
        queue(function()
            if not self.alive or revision~=self.revision or not self.active[slot] or self.active[slot].target~=target then return end
            self.event=self.event+1
            local label=nameOf(target) or target
            local ok,ready,reason=pcall(options.ready)
            if not ok or ready~=true then
                self.message='未传送：'..tostring(reason or '游戏未就绪');log('[TeleportKeys] '..self.message);return
            end
            local called,result=pcall(options.go,target)
            self.message=called and type(result)=='table' and tostring(result.message) or '传送返回未确认'
            log('[TeleportKeys] 传送快捷键 vk='..vk..' modifiers='..mask..' 目标='..label..'；读回='..self.message)
        end)
        return true
    end
    local function ensure(binding)
        local vk,mask=binding.key_code,binding.modifiers
        if not supported[vk] and not (options.router and KeyRouter.isXbox(vk)) then return false,'当前UE4SS未提供这个按键' end
        local system=KeyRouter.reserved(vk,mask)
        if RESERVED[vk] or system then return false,'该键已被「'..(system or '系统')..'」占用' end
        local elsewhere=options.reserved and options.reserved(vk,mask)
        if elsewhere then return false,'该键已被'..tostring(elsewhere)..'占用' end
        if not options.router then return false,'按键路由不可用' end
        return options.router:ensure(vk,mask)
    end
    local function publish()
        local lines={'TeleportKeyStateV1\t'..self.revision..'\t'..self.epoch};local targets={}
        for target in pairs(self.entries)do targets[#targets+1]=target end;table.sort(targets)
        for _,target in ipairs(targets)do
            local entry=self.entries[target];local active=self.active[KeyRouter.slot(entry.key_code,entry.modifiers)]
            local ok=active~=nil and active.target==target
            lines[#lines+1]=target..'\t'..entry.key_code..'\t'..entry.modifiers..'\t'..(ok and '1' or '0')..'\t'..clean(self.errors[target])
        end
        return write(statefile,table.concat(lines,'\n')..'\n')
    end
    local function rebuild()
        self.active,self.errors={},{}
        for target,entry in pairs(self.entries)do
            local ok,reason
            if not nameOf(target) then ok,reason=false,'这个地点不在本版模组的地点表里'
            else ok,reason=ensure(entry) end
            if ok then self.active[KeyRouter.slot(entry.key_code,entry.modifiers)]={target=target}
            else self.errors[target]=reason or '按键没有注册上' end
        end
        publish()
    end
    function self:refresh()rebuild()end
    function self:start()
        local data=read(filename)
        if data then
            local rev=data:match('^TeleportKeysV1\t(%d+)\r?\n');local parsed,seen={},{}
            local valid=integer(tonumber(rev),0,2147483646)
            for line in data:gmatch('[^\r\n]+')do
                if not line:match('^TeleportKeysV1\t')then
                    local target,key,mask=line:match('^([A-Z0-9_]+)\t(%d+)\t(%d+)$')
                    key,mask=tonumber(key),tonumber(mask)
                    if not target or #target>32 or not integer(key,1,255) or not integer(mask,0,7)
                        or parsed[target] or seen[KeyRouter.slot(key,mask)] then valid=false;break end
                    parsed[target]={key_code=key,modifiers=mask};seen[KeyRouter.slot(key,mask)]=true
                end
            end
            if valid then self.entries=parsed;self.revision=tonumber(rev)
            else self.message='传送快捷键文件格式无效，未启用任何条目';log('[TeleportKeys] '..self.message) end
        end
        rebuild()
        local count=0;for _ in pairs(self.entries)do count=count+1 end
        log('[TeleportKeys] 已读取传送快捷键 '..count..' 条；默认无绑定；revision='..self.revision)
    end
    -- vk 0 removes the target's key.
    function self:configure(target,vk,mask)
        if type(target)~='string' or not target:match('^[A-Z0-9_]+$') or #target>32 or not nameOf(target) then
            return {ok=false,message='这个地点不在本版模组的地点表里，请先更新游戏内的模组',spawned_count=0}
        end
        if not integer(vk,0,255) or not integer(mask,0,7) then return {ok=false,message='按键格式无效',spawned_count=0} end
        local proposal={};for other,entry in pairs(self.entries)do proposal[other]=entry end
        proposal[target]=nil
        if vk>0 then
            for other,entry in pairs(proposal)do
                if entry.key_code==vk and entry.modifiers==mask then
                    return {ok=false,message='这个组合键已被「传送：'..(nameOf(other) or other)..'」占用，请先解除那一个',spawned_count=0}
                end
            end
            local entry={key_code=vk,modifiers=mask};local ok,reason=ensure(entry)
            if not ok then return {ok=false,message=reason or '按键没有注册上',spawned_count=0} end
            proposal[target]=entry
        end
        local revision=self.revision+1;local lines={'TeleportKeysV1\t'..revision};local targets={}
        for other in pairs(proposal)do targets[#targets+1]=other end;table.sort(targets)
        for _,other in ipairs(targets)do local e=proposal[other];lines[#lines+1]=other..'\t'..e.key_code..'\t'..e.modifiers end
        if not write(filename,table.concat(lines,'\n')..'\n') then return {ok=false,message='快捷键保存未读回，旧绑定保留',spawned_count=0} end
        self.entries,self.revision=proposal,revision;rebuild()
        log('[TeleportKeys] 保存并读回 目标='..target..' key='..vk..' modifiers='..mask..' revision='..revision)
        return {ok=true,message=vk==0 and '已解除这个传送快捷键' or '传送快捷键已注册并保存；在游戏内按一次就传送',spawned_count=0}
    end
    function self:status()return {epoch=self.epoch,revision=self.revision,event=self.event,message=self.message}end
    function self:silence()self.alive=false end
    return self
end
return Keys
