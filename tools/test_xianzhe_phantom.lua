package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Phantom=require('xianzhe_phantom')
local ACTOR='/PBZCombatAsset/ActorData/Mobs/071_XianZhe/BP_Monster_XianZhe.BP_Monster_XianZhe_C'
local ACTION='/PBZCombatAsset/Prototypes/Actions/GAA_DodgeInvulnerable.GAA_DodgeInvulnerable_C'
local EFFECT='/PBZCombatAsset/Prototypes/GameplayEffects/GE_DodgeInvulnerable.GE_DodgeInvulnerable_C'
local serial=0
local function obj(path,kind)
    serial=serial+1
    local class={IsValid=function()return true end,GetFullName=function()return 'BlueprintGeneratedClass '..path end}
    local o={valid=true,key=serial,full=(kind or 'Object')..' /World/Object_'..serial}
    function o:IsValid()return self.valid end
    function o:GetAddress()assert(self.valid);return self.key end
    function o:GetFullName()assert(self.valid);return self.full end
    function o:GetClass()assert(self.valid);return class end
    return o
end
local function param(value)return {type=function()return 'RemoteUnrealParam'end,get=function()return value end}end
local function typedHandle(id,deny)
    local values={Handle=id,bPassedFiltersAndWasExecuted=true}
    return setmetatable({type=function()return 'UScriptStruct'end},{__index=values,__newindex=function(_,k,v)
        assert(k=='Handle' and type(v)=='number','only the native integer member may be written')
        if not deny then values[k]=v end
    end})
end
local function harness()
    local h={now=0,mode='off',ready=true,inGame=true,loads=0,lookups=0,registrations=0,removes=0,effects={},logs={}}
    h.actor=obj(ACTOR);h.asc=obj('/Script/GameplayAbilities.AbilitySystemComponent');h.actor.AbilitySystemComponent=h.asc
    h.ability=obj('/PBZCombatAsset/ActorData/Mobs/071_XianZhe/Ability/GA_XianZhe_Skill_07.GA_XianZhe_Skill_07_C')
    function h.ability:GetAvatarActorFromActorInfo()return h.actor end
    function h.ability:GetAbilitySystemComponentFromActorInfo()return h.asc end
    h.collider=obj('/Script/Engine.PrimitiveComponent');h.collider.enabled=1
    function h.collider:GetOwner()return h.actor end
    function h.collider:ComponentHasTag(tag)return tag=='Dodge Collider' end
    function h.collider:GetCollisionEnabled()return self.enabled end
    function h.collider:SetCollisionEnabled(value)assert(self.valid);if not h.denyCollider then self.enabled=value end end
    h.action=obj(ACTION);h.action.Collider=h.collider
    function h.action:GetAbility()return h.ability end
    function h.action:GetAvatarActor()return h.actor end
    function h.action:GetAbilitySystemComponent()return h.asc end
    setmetatable(h.action,{__index=function(_,k)if k=='Handle' then return h.current end end,
        __newindex=function(s,k,v)assert(k~='Handle','never assign an untyped table to native StructProperty');rawset(s,k,v)end})
    function h.asc:GetActiveEffects()
        assert(self.valid)
        if h.badList then return nil end
        local ids={};for id,row in pairs(h.effects)do if row.asc==self then ids[#ids+1]=typedHandle(id)end end;return ids
    end
    function h.asc:RemoveActiveGameplayEffect(handle)
        assert(self.valid);local id=handle.Handle;h.removes=h.removes+1
        if h.denyRemove==true or h.denyRemove==id or not h.effects[id] or h.effects[id].asc~=self then return false end
        h.effects[id]=nil;return true
    end
    h.lib=obj('/Script/GameplayAbilities.AbilitySystemBlueprintLibrary')
    function h.lib:GetGameplayEffectFromActiveEffectHandle(handle)return h.effects[handle.Handle] and h.effects[handle.Handle].effect end
    function h.lib:IsActiveGameplayEffectHandleActive(handle)return h.effects[handle.Handle]~=nil end
    h.fn=obj(Phantom.path);h.members={{actor=h.actor,team='blue'}}
    function h:begin(id,effect,denyHandle)
        self.current=typedHandle(id,denyHandle);self.effects[id]={effect=effect or obj(EFFECT),asc=self.asc};self.collider.enabled=1
        if self.callback then self.callback(param(self.action))end
    end
    function h:capture(escort)return self.feature:capture(self.actor,ACTOR,escort)end
    h.feature=Phantom.new({clock=function()return h.now end,ready=function()return h.ready end,
        inGameThread=function()return h.inGame end,fname=function(v)return v end,
        rule=function()return h.mode end,members=function()return h.members end,
        find=function(path)h.lookups=h.lookups+1;if path:find('Default__AbilitySystemBlueprintLibrary',1,true)then return h.lib end;if h.missingFn then return nil end;return h.fn end,
        load=function()h.loads=h.loads+1;if h.loadWorks then h.missingFn=false;return h.fn end end,
        register=function(path,fn)h.registrations=h.registrations+1;if h.denyRegister then error('denied')end;if path==Phantom.endPath then h.endCallback=fn else h.callback=fn end;return 1,2 end,
        unregister=function(path)if h.denyUnregister then return false end;if path==Phantom.endPath then h.endCallback=nil else h.callback=nil end;return true end,
        log=function(line)h.logs[#h.logs+1]=line end})
    return h
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('default keep and no capture have no hooks or asset loads',function()
    local h=harness();h.mode='keep';assert(h:capture());h.feature:tick()
    assert(h.registrations==0 and h.loads==0)
    local blank=harness();blank.feature:tick();assert(blank.lookups==0)
end)
test('only this action handle is removed, its typed field invalidated, collider disabled',function()
    local h=harness();assert(h:capture());h.effects[88]={effect=obj('/Game/Other.Other_C'),asc=h.asc}
    h:begin(11);assert(not h.effects[11] and h.effects[88] and h.current.Handle==-1 and h.collider.enabled==0)
    assert(h.feature:status().blocked==1)
    h.asc:RemoveActiveGameplayEffect(h.current);assert(h.effects[88],'native ActionEnd with invalid handle cannot remove another effect')
end)
test('all four direct-spawn teams are covered; automatic escorts are untouched',function()
    for _,team in ipairs({'blue','red','neutral','companion'})do
        local h=harness();h.members[1].team=team;assert(h:capture());h:begin(11);assert(not h.effects[11],team)
    end
    local h=harness();assert(h:capture({parent=true}));assert(not h.callback)
end)
test('choice is frozen per captured actor until another spawn',function()
    local h=harness();h.mode='keep';assert(h:capture());h.mode='off';assert(h:capture());h.feature:tick();assert(not h.callback)
end)
test('map actor and invalid identity do not pass capture',function()
    local h=harness();h.feature:tick();assert(not h.callback)
    h.actor.valid=false;assert(not h:capture())
end)
test('changed ownership, avatar or ASC never removes an effect',function()
    for _,mutation in ipairs({'roster','avatar','asc'})do
        local h=harness();assert(h:capture())
        if mutation=='roster'then h.members={}
        elseif mutation=='avatar'then h.action.GetAvatarActor=function()return obj(ACTOR)end
        else h.actor.AbilitySystemComponent=obj('/Other')end
        h:begin(11);assert(h.effects[11] and h.current.Handle==11 and h.collider.enabled==1,mutation)
    end
end)
test('foreign effect or foreign ASC handle is never removed',function()
    local h=harness();assert(h:capture());h:begin(11,obj('/Other.Other_C'));assert(h.effects[11] and h.removes==0)
    h.feature:tick();assert(h.effects[11])
    h.effects[11].asc=obj('/OtherASC');h.now=1;h.feature:tick();assert(h.effects[11] and h.current.Handle==11 and h.collider.enabled==1)
end)
test('failed removal retries at a deadline without requiring ActionEnd',function()
    local h=harness();assert(h:capture());h.denyRemove=true;h:begin(11)
    local removes=h.removes;for _=1,10 do h.feature:tick()end;assert(h.removes==removes and h.feature:status().pending==1)
    h.now=1;h.denyRemove=false;h.feature:tick();assert(not h.effects[11] and h.current.Handle==-1 and h.collider.enabled==0 and h.feature:status().pending==0)
end)
test('a reused live struct cannot redirect the old pending removal to a newer handle',function()
    local h=harness();assert(h:capture());h.denyRemove=true;h:begin(11)
    h.current.Handle=22;h.effects[22]={effect=obj('/Other.Other_C'),asc=h.asc}
    h.denyRemove=false;h.now=1;h.feature:tick()
    assert(not h.effects[11] and h.effects[22] and h.current.Handle==22 and h.collider.enabled==1)
end)
test('a newer Begin on the same action protects its shared collider and live handle from an old retry',function()
    local h=harness();assert(h:capture());h.denyRemove=11;h:begin(11)
    h.denyRemove=22;h:begin(22);h.now=1;h.feature:tick()
    assert(not h.effects[11] and h.effects[22] and h.current.Handle==22 and h.collider.enabled==1)
end)
test('different actions sharing a collider have separate generations',function()
    local h=harness();assert(h:capture());h.denyRemove=11;h:begin(11)
    local second=obj(ACTION);second.Collider=h.collider
    second.GetAbility=h.action.GetAbility;second.GetAvatarActor=h.action.GetAvatarActor;second.GetAbilitySystemComponent=h.action.GetAbilitySystemComponent
    local secondHandle=typedHandle(22)
    setmetatable(second,{__index=function(_,key)if key=='Handle'then return secondHandle end end,__newindex=function(o,k,v)assert(k~='Handle');rawset(o,k,v)end})
    h.effects[22]={asc=h.asc,effect=obj(EFFECT)};h.denyRemove=22;h.callback(param(second))
    h.now=1;h.feature:tick()
    assert(not h.effects[11] and h.effects[22] and secondHandle.Handle==22 and h.collider.enabled==1)
end)
test('native ActionEnd retires collision ownership while a failed effect removal can still retry',function()
    local h=harness();assert(h:capture());h.denyRemove=11;h:begin(11)
    h.collider.enabled=0;h.endCallback(param(h.action))
    h.collider.enabled=1 -- another native action now uses this component
    h.now=1;h.denyRemove=false;h.feature:tick()
    assert(not h.effects[11] and h.current.Handle==11 and h.collider.enabled==1 and h.feature:status().pending==0)
end)
test('native ActionEnd already removing the effect retires pending on confirmed false activity',function()
    local h=harness();assert(h:capture());h.denyRemove=11;h:begin(11)
    h.effects[11]=nil;h.collider.enabled=0;h.endCallback(param(h.action))
    h.now=1;h.feature:tick()
    assert(h.feature:status().pending==0 and h.feature:status().state=='on' and h.current.Handle==11 and h.collider.enabled==0)
end)
test('a rejected integer write remains visible and retryable',function()
    local h=harness();assert(h:capture());h:begin(11,nil,true)
    assert(not h.effects[11] and h.current.Handle==11 and h.feature:status().pending==1)
    h.current=typedHandle(11);h.now=1;h.feature:tick();assert(h.current.Handle==-1 and h.feature:status().pending==0)
end)
test('unknown live field readback retains pending and never touches the shared collider',function()
    local h=harness();assert(h:capture());h.denyRemove=11;h:begin(11)
    h.current=nil;h.denyRemove=false;h.now=1;h.feature:tick()
    assert(not h.effects[11] and h.collider.enabled==1 and h.feature:status().pending==1)
    h.current=typedHandle(11);h.now=2;h.feature:tick()
    assert(h.current.Handle==-1 and h.collider.enabled==0 and h.feature:status().pending==0)
end)
test('a malformed active-effect readback is not interpreted as an empty effect list',function()
    local h=harness();assert(h:capture())
    h.asc.GetActiveEffects=function()return {{Unreadable=true}}end
    h:begin(11);assert(h.effects[11] and h.current.Handle==11 and h.collider.enabled==1 and h.feature:status().pending==1)
end)
test('borrowed or unrelated abilities on the same actor keep their own dodge effects',function()
    local h=harness();assert(h:capture())
    h.ability.GetClass=function()return {IsValid=function()return true end,GetFullName=function()return 'BlueprintGeneratedClass /Game/Other.Other_C'end}end
    h:begin(11);assert(h.effects[11] and h.current.Handle==11 and h.collider.enabled==1)
end)
test('collider ownership/tag and disabled-mode readback are checked',function()
    local h=harness();assert(h:capture());h.denyCollider=true;h:begin(11);assert(h.feature:status().pending==1)
    h.now=1;h.denyCollider=false;h.collider.GetOwner=function()return obj(ACTOR)end;h.feature:tick();assert(h.collider.enabled==1)
    h.collider.GetOwner=function()return h.actor end;h.now=2;h.feature:tick();assert(h.collider.enabled==0 and h.feature:status().pending==0)
end)
test('pending selection survives temporary unreadiness and prunes after a world change',function()
    local h=harness();assert(h:capture());h.ready=false;h.feature:tick();assert(h.feature:status().state=='waiting')
    h.now=2;h.ready=true;h.feature:tick();h:begin(11);assert(not h.effects[11])
    h.members={};h.feature:tick();assert(h.feature:status().hooks==0)
end)
test('thread and stale callback guards survive failed unregistration',function()
    local h=harness();assert(h:capture());local old=h.callback;h.inGame=false;h:begin(11);assert(h.effects[11])
    h.inGame=true;h.denyUnregister=true;h.feature:silence();h:begin(22);old(param(h.action));assert(h.effects[22])
end)
test('asset/function loading is opt-in, confirmed and paced',function()
    local h=harness();h.missingFn=true;assert(not h:capture());assert(h.loads==1 and h.feature:status().state=='waiting')
    for _=1,10 do h.feature:tick()end;assert(h.loads==1)
    h.loadWorks=true;h.now=6;h.feature:tick();assert(h.loads==2 and h.feature:status().hooks==2)
end)
test('destroyed nodes and components never receive invalid native calls',function()
    local h=harness();assert(h:capture());h.action.valid=false;h:begin(11);assert(h.effects[11])
    h.action.valid=true;h.collider.valid=false;h:begin(22);assert(not h.effects[22] and h.feature:status().pending==0)
    h.actor.valid=false;h.feature:tick();assert(h.feature:status().pending==0)
end)
print('xianzhe_phantom: '..count..' checks passed')
