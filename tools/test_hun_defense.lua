package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Defense=require('hun_defense')
local seq=0
local function obj(fields)
    seq=seq+1
    local id=seq
    fields=fields or {}
    function fields:IsValid() return self.valid~=false end
    function fields:GetAddress() return id end
    return fields
end
local function cls(name)
    return obj{GetFName=function() return {ToString=function()return name end} end}
end
local function fixture(ai,wrongOwner,resources,rejectFirst)
    local t={time=5,allowed=true,battle=true,presses=0,dodges={},frames={},clears=0,angles={},roll=0.5}
    local inputs,dc,asc=obj(),obj(),obj()
    local r={actor=obj(),name='NPC',loadout={ai=ai or {},resources=resources}};t.r=r
    local player=obj()
    dc.ReceiveFrames={ForEach=function(_,f) for k,v in pairs(t.frames) do f(k,v) end end}
    inputs.AbilitySystem=asc
    function inputs:TryActivateExternalActionAbilityInterruptLowerByTag(tag,ia,priority)
        assert(priority==-5 and ia:IsValid());t.dodges[#t.dodges+1]=tag.TagName;return not t.rejectCounter
    end
    function inputs:CanActivateExternalActionAbility(p) return p==-5 and not t.blockSkill end
    r.actor['Ability Input Component']=inputs;r.actor['Deflect Component']=dc;r.actor.AbilitySystemComponent=asc
    asc.ActivatableAbilities={Items={}};asc.tags={}
    function asc:GetGameplayTagCount(tag) return self.tags[tag.TagName] or 0 end
    local function give(self,asset,active)
        local inst=obj();inst['Deflect Component']=dc;inst['Input System Component']=inputs;inst['Global Config']=obj()
        inst['Anger Cost Data']={
            CostOfTime_6_1918214C431B290CEA5A4A9CAEAA8C4A=0,
            CostOfTimeStartDelay_10_D32DE2BC437394BD04342497EDBEB139=0,
            CostOfTimeEndDelay_11_85354FFE4DC3D6FB650ED1A8F9425022=0}
        function inst:GetClass() return asset end
        inst.GetAvatarActorFromActorInfo=function() return wrongOwner and player or r.actor end
        inst['On Stance Key Down']=function()assert(not wrongOwner);inst['Stance Key Down']=true;t.keyDown=(t.keyDown or 0)+1 end
        inst['Give Perfect Window']=function() assert(not wrongOwner);inst['Perfect Window']=0.1;t.windows=(t.windows or 0)+1 end
        inst['Activate Stance Ability']=function() assert(inst['Stance Key Down']); t.presses=t.presses+1;if not t.rejectStance then asc.tags['Ability.Action.Stance']=1 end end
        inst['On Stance Key Release']=function() inst['Stance Key Down']=false;t.released=true;asc.tags['Ability.Action.Stance']=0 end
        local specs=self.ActivatableAbilities.Items
        local spec={Handle={Handle=seq+1},Ability=obj{GetClass=function()return asset end},ActiveCount=active,
            NonReplicatedInstances={inst}}
        specs[#specs+1]=spec
        if asset:GetFName():ToString()=='BP_PlayerDeflectPassive_C' then t.stance=inst end
        return spec.Handle
    end
    function asc:K2_GiveAbilityAndActivateOnce(c) return give(self,c,1) end
    function asc:K2_GiveAbility(c) return give(self,c,0) end
    function inputs:TryActivateExternalActionAbilityByClass(c,action,priority)
        assert(action:IsValid() and priority==-5)
        for _,spec in ipairs(asc.ActivatableAbilities.Items) do
            if spec.Ability:GetClass()==c then
                assert(spec.Ability:GetClass():GetFName():ToString()=='GA_Hun_AdvancedDash_Double_C')
                t.pure=(t.pure or 0)+1;t.pureInst=spec.NonReplicatedInstances[1];return true
            end
        end
        return false
    end
    function asc:ClearAbility(h)
        local specs=self.ActivatableAbilities.Items
        for i,spec in ipairs(specs) do
            if spec.Handle.Handle==h.Handle then table.remove(specs,i);t.clears=t.clears+1;return end
        end
    end
    local weapon=obj{GetFullName=function() return 'WeaponConfig '..t.wpath end}
    r.actor['Character Weapons Component']=obj{
        GetCurrentWeaponIndex=function()return 0 end, GetSlotWeapon=function(_,_,_,out) out.WeaponConfig=weapon end}
    t.wpath='/PBZCombatAsset/ActorData/Mobs/000_Hun/Weapon/Weapon_Hun_JueYing.Weapon_Hun_JueYing'
    t.asc=asc
    t.module=Defense.new{
        pairProtected=function(_,attacker)return t.protected~=nil and t.protected==attacker end,
        paused=function()return t.paused==true end,
        fname=function(x)return x end,
        find=function(p) return cls(p:match('%.([^%.]+)$')) end, findAll=function()return {} end,
        current=function(x) return x==r and t.allowed end, fighting=function()t.fightChecks=(t.fightChecks or 0)+1;return t.battle end,
        register=function(path,callback) assert(path:find('OnEvadeDamage',1,true));t.result=callback;return 11,12 end,
        unregister=function(_,a,b) assert(a==11 and b==12);t.result=nil end,
        log=function(message) t.logs=t.logs or {};t.logs[#t.logs+1]=message end,
        guard={pressed=function(_,x)assert(x==r);t.announced=(t.announced or 0)+1 end},
        now=function()return t.time end, random=function()return t.roll end,
        loop=function(ms,callback)
            assert(ms==20);t.callback=callback
            if rejectFirst and not t.rejected then t.rejected=callback;return false end
            return 41 end,
        cancel=function(h) assert(h==41);t.cancelled=true;t.callback=nil end,
    }
    t.module:start(r)
    return t
end
local function frame(hit,dodge,strength)
    return {HitGameTime=hit,IsDodge=dodge,IsHit=false,DeflectStrength={TagName=strength or 'Light'}}
end
do
    local denied=fixture(nil,nil,nil,true);local initial=#denied.asc.ActivatableAbilities.Items
    denied.frames[1]=frame(denied.time+.04,false);denied.rejected();assert(denied.presses==0)
    denied.time=6;denied.frames[1]=frame(6.04,false)
    if denied.module.retryTimer then denied.module:retryTimer(denied.r) end
    assert(#denied.asc.ActivatableAbilities.Items==initial,'timer retry must not grant new passives')
    denied.rejected();assert(denied.presses==0);if denied.callback then denied.callback() end
    assert(denied.presses==1,'a rejected defense timer never resumed')
end
do
    local h=fixture();local old=h.callback;h.module:stop(h.r);h.module:start(h.r)
    h.frames[1]=frame(h.time+.04,false)
    old();assert(h.presses==0,'a retired defense timer acted on the new lifetime')
    h.callback();assert(h.presses==1)
    assert(h.announced==1,'a started guard is announced to the action guard')
end
do
    local h=fixture();local specs=h.asc.ActivatableAbilities.Items
    h.asc.ActivatableAbilities.Items=nil;h.callback()
    h.asc.ActivatableAbilities.Items=specs;h.time=5.6;h.callback()
    assert(#specs==6,'a late spec list must not leave the default blades without their four defensive abilities')
    h.wpath='/Game/AnotherWeapon.Config';h.asc.ActivatableAbilities.Items=nil
    h.time=6.2;h.callback();h.asc.ActivatableAbilities.Items=specs
    h.time=6.8;h.callback();assert(#specs==2,'finish removing the owned double-blade abilities after the list returns')
    h.module:stop(h.r);assert(#specs==0)
end
do
    local h=fixture();local give=h.asc.K2_GiveAbility
    function h.asc:K2_GiveAbility()return {Handle=0} end
    h.callback();assert(#h.asc.ActivatableAbilities.Items==2)
    h.asc.K2_GiveAbility=give;h.time=5.6;h.callback()
    assert(#h.asc.ActivatableAbilities.Items==6,'an explicitly invalid native grant must be retried')
end
do
    local h=fixture();h.r.intent={}
    local executing,enemy=obj(),obj()
    h.protected=executing
    local a,b=frame(5.025,false),frame(5.045,true)
    a.SourceAction=obj{GetAvatarActor=function()return executing end}
    b.SourceAction=obj{GetAvatarActor=function()return enemy end}
    h.frames={a};h.callback()
    assert(not h.r.intent.incomingUntil,'a protected source alone must not make the Hun release a charge')
    h.frames[2]=b;h.time=5.01;h.callback()
    assert(#h.dodges==1 and h.presses==0,'the earlier protected source cannot starve a real simultaneous attacker')
end
do
    local h=fixture();local scans=0;h.paused=true
    h.r.actor['Deflect Component'].ReceiveFrames.ForEach=function()scans=scans+1 end
    for _=1,100 do h.callback() end
    assert(scans==1,'unchanged world time repeated the native forecast scan '..scans..' times')
    h.time=5.001;h.callback();assert(scans==2,'slow motion still advances the forecast sampler')
end
do
    local broken=fixture()
    broken.asc.tags['CharacterState.Stand.Break']=1
    broken.frames[1]=frame(5.04,false);broken.callback()
    assert(broken.presses==0,'a broken Hun cannot auto-parry an incoming hit')
    broken.asc.tags['CharacterState.Stand.Break']=0
    broken.time=5.3;broken.frames[2]=frame(5.34,false);broken.callback();assert(broken.presses==1)
    broken.asc.tags['CharacterState.Stand.Break']=1
    broken.time=5.31;broken.callback();assert(broken.stance['Stance Key Down']==false,'release an owned guard during break')
end
do
    local h=fixture({deflect_chance=0})
    h.frames[1]=frame(5.42,false);h.callback()
    assert(h.keyDown==1 and h.presses==1 and not h.windows,'early defense must start native ordinary guard without a perfect window')
    h.time=5.40;h.callback();assert(h.stance['Stance Key Down'],'hold past original 0.3 s cost delay')
    h.time=5.45;h.frames[2]=frame(5.65,false);h.callback()
    assert(h.keyDown==1 and not h.windows,'successive hits must not reset the cost timer')
    h.time=6.4;h.callback();assert(h.released)
end
do
    local h=fixture({deflect_chance=0});h.rejectStance=true
    h.frames[1]=frame(5.45,false);h.callback();assert(h.stance['Stance Key Down'])
    h.time=5.09;h.callback()
    assert(h.released and not h.stance['Stance Key Down'] and (h.r.intent.busyUntil or 0)<=h.time,
        'a void native call with no active stance must not lock the fighter for the whole hold')
    local delayed=fixture({deflect_chance=0});delayed.rejectStance=true
    delayed.frames[1]=frame(5.45,false);delayed.callback();delayed.asc.tags['Ability.Action.Stance']=1
    delayed.time=5.03;delayed.callback();delayed.time=5.12;delayed.callback()
    assert(delayed.stance['Stance Key Down'] and not delayed.released)
end
local f=fixture()
do
    local h=fixture();local input=h.r.actor['Ability Input Component']
    input.InActionPhase=true;input.ActionPhase={TagName='CharacterState.Action.Phase.Act'}
    h.frames[42]=frame(5.059,false);h.callback()
    assert(h.presses==0 and not h.keyDown,'a forecast cannot interrupt a committed strike')
    h.time=5.045;input.ActionPhase.TagName='CharacterState.Action.Phase.Cancel';h.callback()
    assert(h.presses==1,'an unspent forecast can still defend inside a native cancel window')
end
f.r.intent={}
assert(f.callback and #f.asc.ActivatableAbilities.Items==2)
f.frames[1]=frame(5.42,false);f.callback();assert(f.presses==0,'100% waits for a precise window')
f.frames[1]=frame(5.10,false)
f.callback();assert(f.presses==0 and #f.asc.ActivatableAbilities.Items==6)
assert(f.r.intent.incomingUntil>=5.10,'forecast reaches the combat brain before a defensive action starts')
f.time=5.05;f.callback();assert(f.presses==1 and f.r.intent.busyUntil>f.time)
f.callback();assert(f.presses==1)
f.time=5.16;f.callback();assert(f.released and f.stance['Stance Key Down']==false)
f.asc.tags['Deflect.ReadyForDodge.CanDodge']=1
f.time=5.3;f.frames[2]=frame(5.38,true);f.callback();assert(f.dodges[1]=='Ability.Action.Hun.PerfectDodge')
f.r.loadout.ai.counter_chance=0
f.time=5.6;f.frames[3]=frame(5.66,true);f.callback();assert(f.pure==1 and #f.dodges==1)
assert(type(f.result)=='function')
f.result(f.pureInst,nil,nil,true)
assert(f.logs[#f.logs]:find('Perfect=true',1,true))
f.asc.tags['Ability.Action.Execution']=1
f.time=6;f.frames[4]=frame(6.08,true);f.callback();assert(#f.dodges==1 and f.pure==1)
f.asc.tags['Ability.Action.Execution']=0
f.time=6.5;f.wpath='/Game/AnotherWeapon.Config';f.callback();assert(#f.asc.ActivatableAbilities.Items==2)
f.time=6.7;f.allowed=false;f.frames[5]=frame(6.74,false);f.callback();assert(f.presses==1)
f.allowed=true;f.module:silence();assert(f.cancelled and f.clears==6 and not f.result)
local g=fixture({deflect_chance=0.2,red_dodge_chance=0.3})
g.frames[1]=frame(5.04,false);g.callback();assert(g.presses==1 and not g.windows)
g.roll=0.01;g.time=5.01;g.callback();assert(g.presses==1 and not g.windows) -- one trial per forecast
g.time=5.5;g.frames[2]=frame(5.55,true)
g.battle=false;g.callback();assert(#g.dodges==0)
g.battle=true;g.time=5.76;g.frames[2]=frame(5.80,true);g.callback();assert(g.dodges[1]=='Ability.Action.Hun.PerfectDodge')
g.module:stop(g.r)
local policy=fixture({red_dodge_chance=1,counter_chance=0},false,{consume_skill_resources=false})
assert(#policy.asc.ActivatableAbilities.Items==1,'skip the native automatic counter passive')
local rate='CostOfTime_6_1918214C431B290CEA5A4A9CAEAA8C4A'
assert(policy.stance['Anger Cost Data'][rate]==0 and f.stance['Anger Cost Data'][rate]==0)
policy.frames[1]=frame(5.06,true);policy.callback();assert(policy.pure==1 and #policy.dodges==0)
policy.result(policy.pureInst,nil,nil,false);assert(policy.logs[#policy.logs]:find('Perfect=false',1,true))
policy.module:stop(policy.r);assert(not policy.result)
local refuse=fixture()
assert(refuse.stance['Anger Cost Data'][rate]==20)
refuse.rejectCounter=true;refuse.frames[1]=frame(5.07,true);refuse.callback()
assert(refuse.dodges[1]=='Ability.Action.Hun.PerfectDodge' and refuse.pure==1)
refuse.module:silence();assert(refuse.stance['Anger Cost Data'][rate]==0)
local idle=fixture()
idle.battle=false
local validations=0
idle.r.actor.IsValid=function()validations=validations+1;return true end
for i=0,49 do idle.time=8+i*.02;idle.callback() end
assert(idle.fightChecks<=4 and #idle.asc.ActivatableAbilities.Items==2)
assert(validations<=5,'idle native validations in 50 callbacks: '..validations)
idle.module:silence()
local wrong=fixture(nil,true)
local unload=fixture({red_dodge_chance=1,counter_chance=0})
unload.frames[1]=frame(5.08,true);unload.callback()
local pendingTick,pendingResult=unload.callback,unload.result
assert(pendingResult and unload.pureInst)
local afterUnload=0
require('ue_observe').setEngineValidator(function()afterUnload=afterUnload+1;return true end)
unload.module:silence(false)
pendingTick();pendingResult(unload.pureInst,nil,nil,true)
require('ue_observe').setEngineValidator(nil)
assert(unload.cancelled and not unload.result and not unload.callback and afterUnload==0)
assert(not wrong.callback and wrong.clears==2 and wrong.presses==0)
assert(select(2,Defense.window{strength='KnockBack'})==0.13)
assert(Defense.window{kind=3}=='dodge')
print('PASS hun_defense timing, ownership, native grants, chances, locks and cleanup')
