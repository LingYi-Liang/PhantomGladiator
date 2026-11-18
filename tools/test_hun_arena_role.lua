package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Role=require('hun_arena_role')
local serial=0
local function object(name)
    serial=serial+1;local id=serial
    return {IsValid=function()return true end,GetAddress=function()return id end,GetFullName=function()return name end}
end
local base='/PBZCombatAsset/Prototypes/AI/Template/StateConfig/StateTreeConfig_Humaniod'
local summon=object('StateTreeConfig '..base..'_Summon.StateTreeConfig_Humaniod_Summon')
local normal=object('StateTreeConfig '..base..'.StateTreeConfig_Humaniod')
for _,team in ipairs({'blue','red','companion','neutral'})do
    local actor,player,enemy=object('npc'),object('player'),object('enemy')
    local ai,board,faction,hatred,handler=object('ai'),object('board'),object('faction'),object('hatred'),object('handler')
    ai.Pawn,ai.BlackboardComponent=actor,board
    function ai:GetStateTreeConfig()return self.OverrideStateTreeConfig or summon end
    actor['Faction Component'],actor.BP_PBZHatredManagerComponent=faction,hatred
    local targeting=object('targeting');actor['Targeting Component']=targeting;targeting.DefaultTargetHandler=handler
    handler.Blackboard=board;handler['Target Key']='Enemy';handler.LastSensedActorKey='Sensed'
    local values={FollowTargetActor=player,Enemy=enemy,Sensed=player}
    function board:GetValueAsObject(k)return values[k]end
    function board:ClearValue(k)values[k]=nil end
    faction.relation=2
    function faction:GetFactionRelation(target)assert(target==player);return self.relation end
    function faction:SetFactionRelationOverride(target,v,both)assert(target==player and both==false);self.relation=v end
    hatred.HatredList={enemy,player}
    function hatred:RemoveActorFromHatredList(a)assert(a==player);table.remove(self.HatredList,2)end
    local r={actor=actor,team=team,name='test'}
    local role=Role.new({current=function(x)return x==r end,load=function(p)assert(p==base..'.StateTreeConfig_Humaniod');return normal end,
        aiOf=function(a)assert(a==actor);return ai end,player=function()return player end,fname=function(s)return s end,log=function()end})
    role:prepare(r);role:excludePlayer(r)
    assert(ai:GetStateTreeConfig()==(team=='companion' and summon or normal))
    if team=='blue' or team=='red' then
        assert(faction.relation==1 and #hatred.HatredList==1 and values.FollowTargetActor==nil and values.Sensed==nil)
    else assert(faction.relation==2 and #hatred.HatredList==2 and values.FollowTargetActor==player)end
    assert(values.Enemy==enemy and hatred.HatredList[1]==enemy)
end
print('PASS independent arena and challenge AI, companion follow, one-way player exclusion and preserved opponent')
