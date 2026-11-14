-- Per spawned thorns shield: suppress only ranged physical/bleed retaliation from its shield GE.
local U=require('ue_observe')
local Remote=require('remote_attack')
local Retry=require('lookup_retry')
local THORNS=require('unit_rules').THORN_COUNTERS
local Reflect={}
Reflect.paths={
    owner='/Script/SGameAttributes.DamagePreTakePayload:GetDamageSourceOwner',
    magnitude='/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:AssignTagSetByCallerMagnitude',
}
local COUNTERS={GE_JingYe_Shield_Counter_C=true,GE_MaleThug_ClubShield_Counter_C=true}
local COUNTER_TAG='SetByCaller.Shield.CounterDamage.'
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args={...}
    local ok,result=pcall(function()return object[method](object,table.unpack(args))end)
    return ok and U.unwrap(result) or nil
end
local function fullName(object)return call(object,'GetFullName')end
local function setParam(parameter,value)
    local ok=pcall(function()parameter:set(value)end)
    local actual=U.unwrap(parameter)
    return ok and (type(value)=='number' and actual==value or U.key(value)~=nil and U.key(actual)==U.key(value))
end
function Reflect.new(options)
    local clock=options.clock or os.clock
    local find=options.find or StaticFindObject
    local fname=options.fname or FName
    local register=options.register or RegisterHook
    local unregister=options.unregister or UnregisterHook
    local inGameThread=options.inGameThread or IsInGameThread
    local self={blocked=0,unknown=0}
    local records,hooks,seen={},{},{}
    local alive=true
    local unhookAt=0
    local lines={}
    local function say(key,line)
        lines[key]=(lines[key] or 0)+1
        if lines[key]<=8 then options.log('[ShieldReflect] '..line) end
    end
    local retry=Retry.new({clock=clock,log=function(line)say('lookup',line)end})
    local function library(path)return retry:find(path,find)end
    local function ready()return alive and (not options.ready or options.ready()==true)end
    local function onGameThread()
        if type(inGameThread)~='function' then return true end
        local ok,value=pcall(inGameThread)
        return ok and value==true
    end
    local function selection(actor)
        local key=U.key(actor)
        local record=key and records[key]
        if record and record.off and type(record.name)=='string' and U.key(record.actor)==key and fullName(actor)==record.name then
            return record,key
        end
    end
    local classifier=Remote.new({fname=fname,isProjectile=function(bullet)
        return call(library('/Script/PBZCombatAsset.Default__PBZCombatUtils'),'IsProjectile',bullet)
    end})
    local function remotePayload(payload,key)
        if not U.valid(payload) or U.key(U.field(payload,'TargetActor'))~=key then return false end
        local ranged,reason=classifier:source(U.field(payload,'DamageSource'))
        if ranged==nil then self.unknown=self.unknown+1;say('unknown','伤害源未识别，保留原版 '..tostring(reason)) end
        return ranged==true,reason
    end
    local function changed(key,line)
        self.blocked=self.blocked+1
        say(key,line)
    end
    local callbacks={}
    callbacks.owner=function(context)
        local payload=U.unwrap(context)
        local actor=U.field(payload,'TargetActor')
        local record,key=selection(actor)
        if record and ready() then seen[key]={payload=payload,at=clock()} end
    end
    callbacks.magnitude=function(_,spec,tag,magnitude)
        if (Remote.tag(tag) or ''):find(COUNTER_TAG,1,true)~=1 then return end
        local lib=library('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
        local handle=U.unwrap(spec)
        local effect=call(lib,'GetGameplayEffectFromSpecHandle',handle)
        if not COUNTERS[U.className(effect)] then return end
        local effectContext=call(lib,'GetEffectContext',handle)
        if effectContext==nil then return end
        local actor=call(lib,'EffectContextGetEffectCauser',effectContext)
        local record,key=selection(actor)
        if not record then
            actor=call(lib,'EffectContextGetInstigatorActor',effectContext)
            record,key=selection(actor)
        end
        if not record or record.counter~=U.className(effect) or not ready() then return end
        local row=seen[key]
        if not row or clock()-row.at<0 or clock()-row.at>0.05 then
            say('shield-source','刺盾原始命中未读回，保留原版');return
        end
        local ranged,reason=remotePayload(row.payload,key)
        if ranged and setParam(magnitude,0) then changed('shield','远程刺盾反伤置零 '..tostring(Remote.tag(tag))..' 类型='..reason..' 参数读回=0') end
    end
    local function install()
        if type(register)~='function' or type(find)~='function' or type(unregister)~='function' then return end
        for name,path in pairs(Reflect.paths)do
            if not hooks[name] and U.valid(retry:find(path,find)) then
                local ok,pre,post=pcall(register,path,function(...)
                    if alive and onGameThread() then
                        local called,err=pcall(callbacks[name],...)
                        if not called then say('error-'..name,'处理失败 '..name..' '..tostring(err)) end
                    end
                end,function()end)
                if ok and pre~=nil then hooks[name]={pre,post};say('hook-'..name,'挂钩安装 '..name..' 读回ID='..tostring(pre)) end
            end
        end
    end
    local function uninstall(force)
        if not next(hooks) or not force and clock()<unhookAt then return end
        unhookAt=clock()+1
        local kept={}
        for name,ids in pairs(hooks)do
            local ok,value=pcall(unregister,Reflect.paths[name],ids[1],ids[2])
            if not ok or value==false then kept[name]=ids end
        end
        hooks=kept
        if not next(hooks) then unhookAt=0 end
        say('unhook','刺盾挂钩摘除 读回剩余='..tostring(next(hooks)~=nil))
    end
    function self:capture(actor,path,escort,deferInstall)
        if not alive or escort then return end
        local id=type(path)=='string' and path:match('%.([%w_]+)_C$') or (U.className(actor) or ''):gsub('_C$','')
        local counter=THORNS[id]
        if not counter or not U.valid(actor) then return end
        local key=U.key(actor)
        local name=fullName(actor)
        if not key or type(name)~='string' then return end
        if records[key] and records[key].name==name then return key end
        local off=options.rule(id)=='off'
        records[key]={actor=actor,name=name,off=off,id=id,counter=counter}
        if off then
            if not deferInstall then install() end
            say('capture','登记刺盾不反远程 单位='..id..' 本次召唤读回=true')
        end
        return key
    end
    function self:tick()
        if not alive then return end
        local members=options.members() or {}
        if not next(records) and not next(hooks) then
            -- Roster discovery can run while the player is dead/loading; only a ready tick installs hooks.
            for _,member in ipairs(members)do self:capture(member.actor,member.class_path,nil,true) end
            if not next(records) and not next(hooks) then return end
        end
        if not ready() then records={};seen={};uninstall();return end
        local present,off={},false
        for _,member in ipairs(members)do
            local key=self:capture(member.actor,member.class_path,nil,true)
            if key then present[key]=true;off=off or records[key].off end
        end
        for key in pairs(records)do if not present[key] then records[key]=nil;seen[key]=nil end end
        for key,row in pairs(seen)do if not U.valid(row.payload) or clock()-row.at>0.05 then seen[key]=nil end end
        if off then install() else uninstall() end
    end
    function self:status()
        local count=0;for _ in pairs(hooks)do count=count+1 end
        return {supported=type(register)=='function' and type(find)=='function' and type(fname)=='function' and type(unregister)=='function',hooks=count,blocked=self.blocked,unknown=self.unknown}
    end
    function self:silence()
        alive=false
        uninstall(true)
        records={};seen={}
    end
    return self
end
return Reflect
