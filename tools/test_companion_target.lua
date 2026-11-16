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
        stillOwned=function()return h.owned end,boardOf=function()return h.ownBoard or h.bb end,log=function(s)h.logs[#h.logs+1]=s end}
    h.reader=Targets.new(h.options);h.reader:sync(h.members)
    return h
end
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('the current private blackboard enemy is read again when it changes',function()
    local h=fixture();h.values.target=h.enemy;assert(h.reader:current(h.actor)==h.enemy)
    local another=npc('Another',h.world);h.values.target=another;assert(h.reader:current(h.actor)==another and #h.logs==2)
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
test('foreign blackboards are not queried after controller replacement',function()
    local h=fixture();h.values.target=h.enemy;h.ownBoard=obj('NewBoard',h.world)
    assert(h.reader:current(h.actor)==nil and h.queries==0)
end)
test('unreadable targeting keys do not get treated as an empty native target',function()
    local h=fixture();h.values.last=h.enemy;h.throwRead=true;assert(h.reader:current(h.actor)==nil and h.queries==1)
end)
test('retired sources and identity changes stop being trusted immediately',function()
    local h=fixture();h.values.target=h.enemy;h.owned=false;assert(h.reader:current(h.actor)==nil)
    h.owned=true;h.actor.label='Recycled';assert(h.reader:current(h.actor)==nil)
    h.reader:sync({});assert(h.reader:current(h.actor)==nil)
end)
print('companion_target: PASS ('..n..' live-target and ownership checks; no game accessed)')
