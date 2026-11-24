-- Suppress the two native off-combat heals only on actors owned by the mod.
-- Replace the per-call class with the verified empty native effect; never edit a shared effect default.
local U=require('ue_observe')
local Retry=require('lookup_retry')
local Regen={}
Regen.path='/Script/GameplayAbilities.AbilitySystemComponent:BP_ApplyGameplayEffectToSelf'
local EMPTY='/Script/GameplayAbilities.GameplayEffect'
local PREFIX='/PBZCombatAsset/Prototypes/GameplayEffects/'
Regen.effects={PREFIX..'GE_OffCombatRegen.GE_OffCombatRegen_C',PREFIX..'GE_OffCombatRegenImmediately.GE_OffCombatRegenImmediately_C'}
local blocked={};for _,path in ipairs(Regen.effects)do blocked[path]=true end
local HEADER='OffCombatRegenV1'
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args={...}
    local ok,value=pcall(function()return object[method](object,table.unpack(args))end)
    return ok and U.unwrap(value) or nil
end
local function pathOf(object)
    local name=call(object,'GetFullName')
    return type(name)=='string' and name:match('^%S+ (/.+)$') or nil
end
function Regen.new(options)
    local self={on=false,alive=true,blocked=0,cleared=0,failures=0,state='off'}
    local fs,clock=options.io or io,options.clock or os.clock
    local find,register,unregister=options.find or StaticFindObject,options.register or RegisterHook,options.unregister or UnregisterHook
    local inGameThread=options.inGameThread or IsInGameThread
    local file=options.path..'/offcombat-regen.tsv'
    local hook,records,emptyClass,unhookAt,hookRetryAt=nil,{},nil,0,0
    local interceptionFailed=false
    local lines={}
    local function say(kind,text)
        lines[kind]=(lines[kind] or 0)+1
        if lines[kind]<=12 then (options.log or function()end)('[OffCombatRegen] '..text) end
    end
    local retry=Retry.new({clock=clock,log=function(text)say('lookup',text)end})
    local function read()
        local f=fs.open(file,'r');if not f then return nil end
        local text=f:read('*a');f:close();return text
    end
    self.on=read()==HEADER..'\tON\n'
    self.state=self.on and 'waiting' or 'off'
    local function supported()return type(find)=='function' and type(register)=='function' and type(unregister)=='function'end
    local function ready()return not options.ready or options.ready()==true end
    local function gameThread()
        if type(inGameThread)~='function' then return true end
        local ok,yes=pcall(inGameThread);return ok and yes==true
    end
    local function empty()
        if U.valid(emptyClass) and pathOf(emptyClass)==EMPTY then return emptyClass end
        emptyClass=nil
        local cls=retry:find(EMPTY,find)
        if not U.valid(cls) or pathOf(cls)~=EMPTY or call(cls,'IsAnyClass')~=true then return nil end
        local cdo=call(cls,'GetCDO')
        if not U.valid(cdo) or U.field(cdo,'DurationPolicy')~=0 then return nil end
        for _,field in ipairs({'Modifiers','Executions','ApplicationRequirements','ConditionalGameplayEffects','OverflowEffects'})do
            local list=U.array(U.field(cdo,field))
            if not list or #list~=0 then return nil end
        end
        emptyClass=cls
        say('empty','空效果默认值只读核对=true；即时、无修改项/执行器/附带效果')
        return cls
    end
    -- Check the current roster on each matching heal, including after the fight has ended.
    local function owned(asc)
        if not U.valid(asc) then return nil end
        local actor=U.field(asc,'AvatarActor')
        if not U.valid(actor) then actor=U.field(asc,'OwnerActor') end
        local key=U.key(actor)
        if not key or U.key(U.field(actor,'AbilitySystemComponent'))~=U.key(asc) then return nil end
        local name=call(actor,'GetFullName')
        if type(name)~='string' then return nil end
        if options.actorOf then
            local listed=options.actorOf(key)
            if U.key(listed)==key and call(listed,'GetFullName')==name and U.key(U.field(listed,'AbilitySystemComponent'))==U.key(asc) then return actor end
            return nil
        end
        for _,member in ipairs(options.members() or {})do
            if U.key(member.actor)==key and call(member.actor,'GetFullName')==name then return actor end
        end
    end
    local function intercept(context,effect)
        if not self.alive or not gameThread() or not self.on and not (options.customActive and options.customActive()) then return end
        local cls=U.unwrap(effect)
        if not blocked[pathOf(cls)] then return end
        local asc=U.unwrap(context)
        local actor=owned(asc)
        if not actor or not self.on and not (options.custom and options.custom(actor)) or not ready() then return end
        local replacement=empty()
        if not replacement then
            interceptionFailed=true
            self.failures=self.failures+1;self.state='failed'
            say('empty-failed','空效果未确认，保留原版；读回=false');return
        end
        local before=pathOf(cls)
        local ok=pcall(function()effect:set(replacement)end)
        local verified=ok and U.key(U.unwrap(effect))==U.key(replacement) and pathOf(U.unwrap(effect))==EMPTY
        if verified then
            interceptionFailed=false
            self.blocked=self.blocked+1
            say('blocked','拦截 '..before..'；本次参数读回='..EMPTY)
        else
            interceptionFailed=true
            self.failures=self.failures+1;self.state='failed'
            say('replace-failed','效果替换未确认；参数读回='..tostring(pathOf(U.unwrap(effect))))
        end
    end
    local function install()
        if hook then return true end
        if clock()<hookRetryAt then return false end
        hookRetryAt=clock()+1
        if not supported() or not empty() or not U.valid(retry:find(Regen.path,find)) then return false end
        local ok,pre,post=pcall(register,Regen.path,function(...)
            local called,err=pcall(intercept,...)
            if not called then interceptionFailed=true;self.failures=self.failures+1;self.state='failed';say('callback-failed','处理失败 '..tostring(err)) end
        end,function()end)
        if ok and pre~=nil and pre~=false then
            hook={pre,post};say('hook','安装脱战回血拦截；读回ID='..tostring(pre));return true
        end
        self.failures=self.failures+1;say('hook-failed','挂钩安装未确认；读回=false');return false
    end
    local function uninstall(force)
        if not hook or not force and clock()<unhookAt then return end
        unhookAt=clock()+1
        local ok,value=pcall(unregister,Regen.path,hook[1],hook[2])
        if ok and value~=false then hook=nil end
        say('unhook','摘除脱战回血挂钩；读回剩余='..tostring(hook~=nil))
    end
    -- Remove an already-running periodic heal on enable/new ownership. Retry only unconfirmed removals.
    local function clearActive(actor,asc)
        local confirmed=true
        for _,path in ipairs(Regen.effects)do
            local cls=retry:find(path,find)
            if U.valid(cls) and pathOf(cls)==path and call(cls,'IsAnyClass')==true then
                local before=call(asc,'GetGameplayEffectCount',cls,nil,false)
                if type(before)~='number' then confirmed=false
                elseif before>0 then
                    call(asc,'RemoveActiveGameplayEffectBySourceEffect',cls,nil,-1)
                    local after=call(asc,'GetGameplayEffectCount',cls,nil,false)
                    if after==0 then self.cleared=self.cleared+before else confirmed=false end
                    say('clear','移除已有脱战回血 '..path..'；效果数量读回='..tostring(before)..'→'..tostring(after))
                end
            end
        end
        if not confirmed then self.failures=self.failures+1;say('clear-failed','已有回血清除未确认；保留限频重试') end
        return confirmed
    end
    function self:tick()
        if not self.alive then return end
        if not self.on and not (options.customActive and options.customActive()) then records={};uninstall();self.state='off';return end
        if not ready() then records={};uninstall();self.state='waiting';return end
        local members=options.members() or {}
        if #members==0 then records={};uninstall();self.state='waiting';return end
        if not install() then self.state='failed';return end
        local present,pending={},false
        for _,member in ipairs(members)do
            local actor=member.actor
            local custom=not self.on and member.team=='companion' and not member.summoner and not member.stand
                and not member.reserve and options.custom and options.custom(actor)
            if self.on or custom then
                local key,name=U.key(actor),call(actor,'GetFullName')
                local asc=U.field(actor,'AbilitySystemComponent')
                local ascKey=U.key(asc)
                if key and type(name)=='string' and ascKey then
                    present[key]=true
                    local row=records[key]
                    if not row or row.name~=name or row.asc~=ascKey then row={name=name,asc=ascKey,nextAt=0};records[key]=row end
                    if not row.done and clock()>=row.nextAt then row.done=clearActive(actor,asc);row.nextAt=clock()+0.5 end
                    pending=pending or not row.done
                elseif key then pending=true end
            end
        end
        for key in pairs(records)do if not present[key] then records[key]=nil end end
        self.state=(pending or interceptionFailed) and 'failed' or 'on'
    end
    function self:canCustomHeal(actor)
        local r=records[U.key(actor)]
        return not self.on and hook~=nil and not interceptionFailed and r and r.done and r.name==call(actor,'GetFullName')
    end
    function self:set(token)
        if token~='ON' and token~='OFF' then return {ok=false,message='无效的脱战回血设置'} end
        if token=='ON' and not supported() then return {ok=false,message='脱战回血拦截接口未就绪'} end
        local text=HEADER..'\t'..token..'\n'
        local f=fs.open(file,'w')
        local wrote=f and f:write(text);local closed=f and f:close()
        local saved=f~=nil and wrote~=nil and wrote~=false and closed==true and read()==text
        say('setting','禁止脱战回血='..token..'；设置保存读回='..tostring(saved))
        if not saved then return {ok=false,message='脱战回血设置保存未确认，旧设置继续生效'} end
        self.on=token=='ON';records={};interceptionFailed=false;self:tick()
        local message='已关闭禁止脱战回血：后续恢复原版规则，不补回已拦截的血量'
        if self.on then
            message=self.state=='failed' and '禁止脱战回血设置已保存，但拦截或已有回血清理未确认，请查看面板状态'
                or self.state=='waiting' and '禁止脱战回血设置已保存，等待游戏就绪或召唤单位'
                or '已开启禁止脱战回血：仅拦截原版脱战回血，技能回血保留'
        end
        return {ok=true,message=message}
    end
    function self:status()
        return {supported=supported(),on=self.on,state=self.state,blocked=self.blocked,cleared=self.cleared,failures=self.failures,hooks=hook and 1 or 0}
    end
    function self:silence()
        self.alive=false;records={};uninstall(true)
    end
    return self
end
return Regen
