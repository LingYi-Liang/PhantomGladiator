package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Targets=require('companion_target')
local U=require('ue_observe')
local sequence=0
local function obj(label,outer)
    sequence=sequence+1;local key=sequence
    local v={live=true,label=label,outer=outer,hp=100}
    function v:IsValid()return self.live end
    function v:GetAddress()assert(self.live);return key end
    function v:GetFullName()assert(self.live);return self.label end
    function v:GetOuter()assert(self.live);return self.outer end
    return v
end
local function npc(label,world)
    local v=obj(label,world)
    local native=obj('Class /Script/ProjectPBZ.PBZCharacter_NPC')
    local cls=obj('BlueprintGeneratedClass /Game/Test.Test_C')
    function cls:GetSuperStruct()return native end
    function v:GetClass()return cls end
    return v
end
local function fixture()
    local h={owned=true,relation=2,values={},queries=0,logs={}}
    h.world=obj('World');h.player=obj('Player',h.world);h.actor=npc('Companion',h.world);h.enemy=npc('Enemy',h.world);h.ally=npc('Ally',h.world)
    h.bb=obj('Blackboard',h.world)
    function h.bb:GetValueAsObject(key)h.queries=h.queries+1;if h.throwRead then error('unreadable')end;return h.values[key]end
    h.handler=obj('Handler',h.actor);h.handler.Blackboard=h.bb;h.handler['Target Key']='target';h.handler.LastSensedActorKey='last'
    h.component=obj('Targeting',h.actor);h.component.DefaultTargetHandler=h.handler
    function h.component:GetOwner()return h.actor end
    h.actor['Targeting Component']=h.component
    local faction=obj('Faction',h.actor)
    function faction:GetFactionRelation()return h.relation end
    h.actor['Faction Component']=faction
    h.members={{actor=h.actor,team='companion'},{actor=h.ally,team='companion'}}
    h.options={hp=function(actor)assert(actor.live);return actor.hp end,world=function()return h.world end,player=function()return h.player end,
        stillOwned=function()return h.owned end,boardOf=function()return h.ownBoard or h.bb end,log=function(s)h.logs[#h.logs+1]=s end,
        clock=function()return h.clock or 0 end}
    h.reader=Targets.new(h.options);h.reader:sync(h.members)
    return h
end
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('the current private blackboard enemy is read again when it changes',function()
    local h=fixture();h.values.target=h.enemy;assert(h.reader:current(h.actor)==h.enemy)
    local another=npc('Another',h.world);h.values.target=another;assert(h.reader:current(h.actor)==another and #h.logs==2)
end)
local function nativeBindings(h)
    local file=assert(io.open('Mods/PhantomGladiator/Scripts/main.lua','rb'))
    local code=file:read('*a');file:close()
    local support={}
    local env=setmetatable({arenaSupport=support,UEObserve=U,FName=function(s)return s end,log=function()end,
        objectName=function(a)return a:GetFullName()end,
        GetCurrentWorld=function()return h.world end,GameSeconds=function()return h.now or 1 end,
        GetAIComp=function(actor)return actor.ai end,
        FindAllOf=function()h.scans=(h.scans or 0)+1;return h.handlers or {} end},{__index=_G})
    for _,bounds in ipairs({{'function arenaSupport:targetHandler(','-- 不再调用通用'},
        {'function arenaSupport.hunNativeTarget(','arenaSupport.hunBody=require'}}) do
        local first=assert(code:find(bounds[1],1,true));local last=assert(code:find(bounds[2],first,true))
        assert(load(code:sub(first,last-1),'native targeting adapter','t',env))()
    end
    h.actor.ai=obj('AI',h.actor);h.actor.ai.BlackboardComponent=h.bb
    return support
end
test('Hun verifies the live target in the same order as the native AI handler',function()
    local h=fixture();local support=nativeBindings(h)
    h.values.last=h.enemy
    assert(h.reader:current(h.actor)==h.enemy and support.hunNativeTarget(h.actor)==h.enemy,'an empty primary hides the real last-sensed opponent')
    h.values.target=h.player
    assert(support.hunNativeTarget(h.actor)==h.player,'a live primary takes precedence, including the player')
    h.values.target=nil;h.throwRead=true
    assert(support.hunNativeTarget(h.actor)==nil,'a failed primary read is not an empty primary')
    h.throwRead=false;h.handler.Blackboard=obj('foreign')
    assert(not support.hunNativeTarget(h.actor,true),'private checks cannot use a handler from a different board')
    h.handler.Blackboard=h.bb;h.actor.ai.Pawn=h.player
    assert(not support.hunNativeTarget(h.actor),'a component already assigned to another pawn cannot supply a target')
end)
test('discovery is shared across fighters while every target value is freshly read',function()
    local h=fixture();local support=nativeBindings(h);h.handlers={};local crowd={}
    for i=1,24 do
        local a=npc('Hun'..i,h.world);a.ai=obj('AI',a);local bb=obj('board',a);a.ai.BlackboardComponent=bb
        function bb:GetValueAsObject(key)assert(key=='victim');return self.enemy end
        bb.enemy=h.enemy;local handler=obj('fallback',a);handler.Blackboard=bb;handler['Target Key']='victim'
        h.handlers[i]=handler;crowd[i]=a
    end
    for _=1,10 do for _,a in ipairs(crowd) do assert(support.hunNativeTarget(a)==h.enemy) end end
    assert(h.scans==1,'one world scan for 240 target decisions, got '..h.scans)
    local a=crowd[1];a.ai.BlackboardComponent.enemy=h.ally;assert(support.hunNativeTarget(a)==h.ally)
    local old=h.handlers[1];old.Blackboard=h.bb;local bb=a.ai.BlackboardComponent
    function bb:GetValueAsObject(key)return key=='replacement' and h.enemy or nil end
    local changed=obj('replacement handler',a);changed.Blackboard=bb;changed['Target Key']='replacement';h.handlers[1]=changed
    h.now=3;assert(support.hunNativeTarget(a)==h.enemy and h.scans==2)
    a['Targeting Component']=obj('private component',a);a['Targeting Component'].DefaultTargetHandler=changed
    assert(support.hunNativeTarget(a,true)==h.enemy and h.scans==2)
end)
test('player follow keys can fall back to a confirmed hostile last sensed NPC',function()
    local h=fixture();h.values.target=h.player;h.values.last=h.enemy;assert(h.reader:current(h.actor)==h.enemy)
    h.values.last=h.player;assert(h.reader:current(h.actor)==nil)
end)
test('player, self, companions, friendly and neutral actors cannot become spell targets',function()
    local h=fixture()
    for _,actor in ipairs({h.player,h.actor,h.ally})do h.values.target=actor;assert(h.reader:current(h.actor)==nil)end
    h.values.target=h.enemy
    for _,relation in ipairs({0,1})do h.relation=relation;assert(h.reader:current(h.actor)==nil)end
end)
test('unknown or dead actors and foreign worlds are rejected',function()
    local h=fixture();h.values.target=h.enemy
    h.enemy.hp=nil;assert(h.reader:current(h.actor)==nil)
    h.enemy.hp=0;assert(h.reader:current(h.actor)==nil)
    h.enemy.hp=100;h.enemy.outer=obj('OtherWorld');assert(h.reader:current(h.actor)==nil)
end)
test('recovery distinguishes a genuinely empty board from unreadable state while preserving a live enemy',function()
    local h=fixture();h.values.target=nil;h.values.last=nil
    local target,known=h.reader:inspect(h.actor);assert(not target and known)
    h.values.target=h.enemy
    target,known=h.reader:inspect(h.actor);assert(target==h.enemy and known)
    h.enemy.hp=nil;target,known=h.reader:inspect(h.actor);assert(not target and not known)
    h.enemy.hp=0;target,known=h.reader:inspect(h.actor);assert(not target and known)
    h.actor['Targeting Component']=nil;target,known=h.reader:inspect(h.actor);assert(not known)
end)
test('foreign blackboards are not queried after controller replacement',function()
    local h=fixture();h.values.target=h.enemy;h.ownBoard=obj('NewBoard',h.world)
    assert(h.reader:current(h.actor)==nil and h.queries==0)
end)
test('a spell reads the handler bound to its own live board when the default is a template',function()
    local h=fixture();local support=nativeBindings(h)
    local foreign=obj('old board',h.world)
    function foreign:GetValueAsObject()error('foreign board read')end
    local template=obj('default template');template.Blackboard=foreign
    h.component.DefaultTargetHandler=template;h.handlers={h.handler}
    h.options.boundHandler=function(actor,bb)return support:targetHandler(actor,bb)end
    h.values.target=h.player;h.values.last=h.enemy
    assert(h.reader:current(h.actor)==h.enemy,'the companion lost its live map enemy')
    h.relation=0;assert(h.reader:current(h.actor)==nil)
    h.relation=2;h.ownBoard=foreign;h.options.boundHandler=function()return h.handler end
    h.component.DefaultTargetHandler=nil
    assert(h.reader:current(h.actor)==nil,'a binding for a retired board cannot supply a spell target')
end)
test('unreadable targeting keys do not get treated as an empty native target',function()
    local h=fixture();h.values.last=h.enemy;h.throwRead=true;assert(h.reader:current(h.actor)==nil and h.queries==1)
end)
test('an airborne volley can retain only its own living, still hostile enemy',function()
    local h=fixture();local id=h.enemy:GetFullName()
    h.values.target=h.player
    assert(h.reader:current(h.actor,h.enemy,id)==h.enemy and h.reader:current(h.actor)==nil)
    local newer=npc('Next',h.world);h.values.last=newer
    assert(h.reader:current(h.actor,h.enemy,id)==newer,'a fresh native enemy takes precedence')
    h.values.last=nil;h.enemy.hp=0;assert(h.reader:current(h.actor,h.enemy,id)==nil)
    h.enemy.hp=100;h.relation=0;assert(h.reader:current(h.actor,h.enemy,id)==nil)
    h.relation=2;h.enemy.label='Reused';assert(h.reader:current(h.actor,h.enemy,id)==nil)
    h.enemy.label=id;h.throwRead=true;assert(h.reader:current(h.actor,h.enemy,id)==nil)
end)
test('retired sources and identity changes stop being trusted immediately',function()
    local h=fixture();h.values.target=h.enemy;h.owned=false;assert(h.reader:current(h.actor)==nil)
    h.owned=true;h.actor.label='Recycled';assert(h.reader:current(h.actor)==nil)
    h.reader:sync({});assert(h.reader:current(h.actor)==nil)
end)
test('a skill lock may fall back to the enemy of a moment ago, checked again, never to the player or a stale one',function()
    local h=fixture()
    assert(h.reader:lastEnemy(h.actor)==nil,'nothing was ever read')
    h.values.target=h.enemy;h.clock=10;assert(h.reader:lastEnemy(h.actor)==h.enemy,'the current enemy first')
    h.values.target=nil;h.clock=12
    assert(h.reader:current(h.actor)==nil,'the ordinary reader still says there is no enemy')
    assert(h.reader:lastEnemy(h.actor)==h.enemy,'the AI key is empty for a moment: the enemy read two seconds ago')
    h.values.target=h.player;assert(h.reader:current(h.actor)==nil and h.reader:lastEnemy(h.actor)==h.enemy,'the key holds the player: still the enemy')
    h.clock=25;assert(h.reader:lastEnemy(h.actor)==h.enemy,'falling back does not renew the memory')
    h.clock=31;assert(h.reader:lastEnemy(h.actor)==nil,'older than MEMORY_SECONDS')
    h.values.target=h.enemy;h.clock=40;assert(h.reader:current(h.actor)==h.enemy);h.values.target=nil
    h.enemy.hp=0;assert(h.reader:lastEnemy(h.actor)==nil,'dead');h.enemy.hp=100
    h.relation=1;assert(h.reader:lastEnemy(h.actor)==nil,'no longer hostile');h.relation=2
    h.enemy.label='Recycled';assert(h.reader:lastEnemy(h.actor)==nil,'the address now names another actor');h.enemy.label='Enemy'
    assert(h.reader:lastEnemy(h.actor)==h.enemy)
    h.reader:sync({});assert(h.reader:lastEnemy(h.actor)==nil)
    h.reader:sync(h.members);assert(h.reader:lastEnemy(h.actor)==nil,'a companion that left takes its memory with it')
end)
test('reserved stands never become a target and the current lock can be checked without rewriting it',function()
    local h=fixture();h.members[2].stand=true;h.members[2].reserve=true
    h.reader:sync(h.members);h.values.target=h.ally
    assert(h.reader:current(h.actor)==nil and h.reader:aimedAt(h.actor,h.ally))
    h.values.target=h.player;assert(h.reader:aimedAt(h.actor,h.player) and not h.reader:aimedAt(h.actor,h.enemy))
end)
print('companion_target: PASS ('..n..' live-target and ownership checks; no game accessed)')
