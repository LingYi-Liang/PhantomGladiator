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
local function fixture(ai,wrongOwner,resources)
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
        inst['Give Perfect Window']=function() assert(not wrongOwner);inst['Perfect Window']=0.1 end
        inst['Activate Stance Ability']=function() assert(inst['Stance Key Down']); t.presses=t.presses+1 end
        inst['On Stance Key Release']=function() inst['Stance Key Down']=false;t.released=true end
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
        fname=function(x)return x end,
        find=function(p) return cls(p:match('%.([^%.]+)$')) end, findAll=function()return {} end,
        current=function(x) return x==r and t.allowed end, fighting=function()t.fightChecks=(t.fightChecks or 0)+1;return t.battle end,
        register=function(path,callback) assert(path:find('OnEvadeDamage',1,true));t.result=callback;return 11,12 end,
        unregister=function(_,a,b) assert(a==11 and b==12);t.result=nil end,
        log=function(message) t.logs=t.logs or {};t.logs[#t.logs+1]=message end,
        now=function()return t.time end, random=function()return t.roll end,
        loop=function(ms,callback) assert(ms==20); t.callback=callback;return 41 end,
        cancel=function(h) assert(h==41);t.cancelled=true;t.callback=nil end,
    }
    t.module:start(r)
    return t
end
local function frame(hit,dodge,strength)
    return {HitGameTime=hit,IsDodge=dodge,IsHit=false,DeflectStrength={TagName=strength or 'Light'}}
end
local f=fixture()
assert(f.callback and #f.asc.ActivatableAbilities.Items==2)
f.frames[1]=frame(5.10,false)
f.callback();assert(f.presses==0 and #f.asc.ActivatableAbilities.Items==6)
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
g.frames[1]=frame(5.04,false);g.callback();assert(g.presses==0)
g.roll=0.01;g.time=5.01;g.callback();assert(g.presses==0) -- one trial per forecast
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
for i=0,49 do idle.time=8+i*.02;idle.callback() end
assert(idle.fightChecks<=4 and #idle.asc.ActivatableAbilities.Items==2)
idle.module:silence()
local wrong=fixture(nil,true)
assert(not wrong.callback and wrong.clears==2 and wrong.presses==0)
assert(select(2,Defense.window{strength='KnockBack'})==0.13)
assert(Defense.window{kind=3}=='dodge')
print('PASS hun_defense timing, ownership, native grants, chances, locks and cleanup')
