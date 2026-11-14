-- Per spawned unit: opt out of ranged retaliation while preserving the original incoming hit and melee defence.
local U=require('ue_observe')
local Remote=require('remote_attack')
local Retry=require('lookup_retry')
local Reflect={}
Reflect.paths={
    damage='/Script/SGameCombatSystem.BulletAttackModule:DealDamageCustom',
    owner='/Script/SGameAttributes.DamagePreTakePayload:GetDamageSourceOwner',
    magnitude='/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:AssignTagSetByCallerMagnitude',
    modify='/Script/SGameAttributes.DamagePreTakePayload:ApplyModify',
    children='/Script/SGameAttributes.DamagePreTakePayload:ApplyModifyToChildren',
    collision='/Script/Engine.PrimitiveComponent:SetCollisionResponseToChannel',
}
local COUNTERS={GE_JingYe_Shield_Counter_C=true,GE_MaleThug_ClubShield_Counter_C=true}
local COUNTER_TAG='SetByCaller.Shield.CounterDamage.'
local ATTACKER='Damage.Damage.Attacker.'
local REBOUND='GAAction_ReboundProjectile_C'
local CLONE_FIELDS={AttackerAngerDamageMultiplier=0,CanBreakAttacker=false,CanBreakAttackerFinal=false}
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
    local findAll=options.findAll or FindAllOf
    local construct=options.construct or StaticConstructObject
    local fname=options.fname or FName
    local register=options.register or RegisterHook
    local unregister=options.unregister or UnregisterHook
    local inGameThread=options.inGameThread or IsInGameThread
    local self={blocked=0,unknown=0}
    local records,hooks,seen,clones,pendingCollision={},{},{},{},{}
    local alive,serial=true,0
    local lines={}
    local function say(key,line)
        lines[key]=(lines[key] or 0)+1
        if lines[key]<=8 then options.log('[RemoteReflect] '..line) end
    end
    local retry=Retry.new({clock=clock,log=function(line)say('lookup',line)end})
    local function library(path)return retry:find(path,find)end
    local function ready()return alive and (not options.ready or options.ready()==true)end
    local function onGameThread()
        if type(inGameThread)~='function' then return true end
        local ok,value=pcall(inGameThread)
        return ok and value==true
    end
    local function selected(actor)
        if not ready() then return false end
        local key=U.key(actor)
        local record=key and records[key]
        return record and record.off and type(record.name)=='string' and U.key(record.actor)==key and fullName(actor)==record.name or false
    end
    local classifier=Remote.new({fname=fname,isProjectile=function(bullet)
        return call(library('/Script/PBZCombatAsset.Default__PBZCombatUtils'),'IsProjectile',bullet)
    end})
    local function remotePayload(payload)
        if not U.valid(payload) or not selected(U.field(payload,'TargetActor')) then return false end
        local ranged,reason=classifier:source(U.field(payload,'DamageSource'))
        if ranged==nil then self.unknown=self.unknown+1;say('unknown','伤害源未识别，保留原版 '..tostring(reason)) end
        return ranged==true,reason
    end
    local function changed(key,line)
        self.blocked=self.blocked+1
        say(key,line)
    end
    local function copiedCalculator(original,actor)
        if not Remote.isA(original,{DamageCalculator_PBZDeflect=true}) then return nil end
        local key=U.key(actor)..':'..U.key(original)
        local old=clones[key]
        if old and U.valid(old.copy) and old.source==fullName(original) and old.actorName==fullName(actor) then return old.copy end
        local cls=call(original,'GetClass')
        if not U.valid(cls) or type(construct)~='function' or type(fname)~='function' then return nil end
        serial=serial+1
        -- Template cloning preserves the target's normal/perfect defence, difficulty data and elemental reduction.
        local ok,copy=pcall(construct,cls,actor,fname('PG_RemoteReflect_'..serial),0x40,0,false,false,original)
        copy=ok and U.unwrap(copy) or nil
        if not U.valid(copy) or U.key(copy)==U.key(original) then return nil end
        for field,wanted in pairs(CLONE_FIELDS)do
            local before,read=U.field(copy,field)
            if not read or type(before)~=type(wanted) then return nil end
            local wrote=pcall(function()copy[field]=wanted end)
            if not wrote or U.field(copy,field)~=wanted then return nil end
        end
        local targetSame=U.field(copy,'TargetAngerDamageMultiplier')==U.field(original,'TargetAngerDamageMultiplier')
            and U.field(copy,'CanBreakTarget')==U.field(original,'CanBreakTarget')
        if not targetSame then return nil end
        clones[key]={copy=copy,source=fullName(original),actor=U.key(actor),actorName=fullName(actor)}
        say('clone','建立独立弹反结算 反扣杀气倍率读回=0 攻击者破防读回=false 防御方参数一致='..tostring(targetSame))
        return copy
    end
    local callbacks={}
    callbacks.damage=function(context,target,_,_,cause,calculator)
        local actor=U.unwrap(target)
        if not selected(actor) or (Remote.tag(cause) or ''):find('Damage.Cause.Deflect',1,true)~=1 then return end
        local ranged,reason=classifier:source(U.unwrap(context))
        if ranged~=true then return end
        local copy=copiedCalculator(U.unwrap(calculator),actor)
        if copy and setParam(calculator,copy) then changed('deflect','远程弹反改用独立结算 类型='..reason..' 参数读回=true')
        else say('deflect-fail','独立弹反结算未读回，保留原版') end
    end
    callbacks.owner=function(context)
        local payload=U.unwrap(context)
        local actor=U.field(payload,'TargetActor')
        if selected(actor) then seen[U.key(actor)]={payload=payload,at=clock()} end
    end
    callbacks.magnitude=function(_,spec,tag,magnitude)
        if not ready() or (Remote.tag(tag) or ''):find(COUNTER_TAG,1,true)~=1 then return end
        local lib=library('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
        local handle=U.unwrap(spec)
        local effect=call(lib,'GetGameplayEffectFromSpecHandle',handle)
        if not COUNTERS[U.className(effect)] then return end
        local effectContext=call(lib,'GetEffectContext',handle)
        if effectContext==nil then return end
        local actor=call(lib,'EffectContextGetEffectCauser',effectContext)
        if not selected(actor) then actor=call(lib,'EffectContextGetInstigatorActor',effectContext) end
        if not selected(actor) then return end
        local row=seen[U.key(actor)]
        if not row or clock()-row.at<0 or clock()-row.at>0.05 or U.key(U.field(row.payload,'TargetActor'))~=U.key(actor) then
            say('shield-source','刺盾原始命中未读回，保留原版');return
        end
        local ranged,reason=remotePayload(row.payload)
        if ranged and setParam(magnitude,0) then changed('shield','远程刺盾反伤置零 '..tostring(Remote.tag(tag))..' 类型='..reason..' 参数读回=0') end
    end
    local function modify(context,tag,kind,value)
        local text=Remote.tag(tag) or ''
        if text:find(ATTACKER,1,true)~=1 or text:lower():find('regen',1,true) or text:lower():find('recover',1,true) then return end
        local ranged=remotePayload(U.unwrap(context))
        if ranged then
            local originalKind,originalValue=U.unwrap(kind),U.unwrap(value)
            if setParam(kind,3) then
                if setParam(value,0) then changed('modify','远程反伤附加修正 类型读回=Override 数值读回=0')
                else
                    setParam(kind,originalKind);setParam(value,originalValue)
                    say('modify-fail','反伤修正参数未读回，已还原原参数')
                end
            end
        end
    end
    callbacks.modify=modify
    callbacks.children=modify
    callbacks.collision=function(context,channel,response)
        if not ready() or U.unwrap(channel)~=24 or U.unwrap(response)~=1 then return end
        local component=U.unwrap(context)
        local trigger=call(component,'GetOwner')
        if U.className(trigger)~='TriggerCapsule' then return end
        local actor=call(trigger,'GetAttachParentActor')
        if not selected(actor) then return end
        local ok,actions=pcall(findAll,REBOUND)
        for _,action in ipairs(ok and U.array(actions) or {})do
            if U.valid(action) and U.key(U.field(action,'Trigger'))==U.key(trigger)
                and U.key(call(action,'GetAvatarActor'))==U.key(actor) then
                if setParam(response,0) then pendingCollision[U.key(component)]=true end
                return
            end
        end
    end
    local function install()
        if type(register)~='function' or type(find)~='function' then return end
        for name,path in pairs(Reflect.paths)do
            if not hooks[name] and U.valid(retry:find(path,find)) then
                local ok,pre,post=pcall(register,path,function(...)
                    if alive and onGameThread() and ready() then
                        local called,err=pcall(callbacks[name],...)
                        if not called then say('error-'..name,'处理失败 '..name..' '..tostring(err)) end
                    end
                end,function(context)
                    if alive and onGameThread() and name=='collision' then
                        local component=U.unwrap(context)
                        local key=U.key(component)
                        if key and pendingCollision[key] then
                            pendingCollision[key]=nil
                            local value=call(component,'GetCollisionResponseToChannel',24)
                            if value==0 then changed('rebound','关闭此单位招式反弹区 实际碰撞响应读回=Ignore')
                            else say('rebound-fail','反弹区关闭未读回 响应='..tostring(value)) end
                        end
                    end
                end)
                if ok and pre~=nil then hooks[name]={pre,post};say('hook-'..name,'挂钩安装 '..name..' 读回ID='..tostring(pre)) end
            end
        end
    end
    function self:capture(actor,path,escort)
        if escort or not U.valid(actor) then return end
        local key=U.key(actor)
        local name=fullName(actor)
        if not key or type(name)~='string' then return end
        if records[key] and records[key].name==name then return end
        local id=type(path)=='string' and path:match('%.([%w_]+)_C$') or (U.className(actor) or ''):gsub('_C$','')
        local off=options.rule(id)=='off'
        records[key]={actor=actor,name=name,off=off,id=id}
        if off then install();say('capture','登记关闭远程反伤 单位='..id..' 本次召唤读回=true') end
    end
    function self:tick()
        if not ready() then records={};seen={};clones={};return end
        local present,off={},false
        for _,member in ipairs(options.members() or {})do
            if U.valid(member.actor) then
                self:capture(member.actor)
                local key=U.key(member.actor);present[key]=true;off=off or records[key] and records[key].off
            end
        end
        for key in pairs(records)do if not present[key] then records[key]=nil;seen[key]=nil end end
        for key,row in pairs(clones)do if not present[row.actor] or not U.valid(row.copy) then clones[key]=nil end end
        for key,row in pairs(seen)do if not U.valid(row.payload) or clock()-row.at>0.05 then seen[key]=nil end end
        if off then install() end
    end
    function self:status()
        local count=0;for _ in pairs(hooks)do count=count+1 end
        return {supported=type(register)=='function' and type(find)=='function' and type(construct)=='function',hooks=count,blocked=self.blocked,unknown=self.unknown}
    end
    function self:silence()
        alive=false
        for name,ids in pairs(hooks)do pcall(unregister,Reflect.paths[name],ids[1],ids[2]) end
        hooks={};records={};seen={};clones={};pendingCollision={}
    end
    return self
end
return Reflect
