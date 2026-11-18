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
    local hooks,logs={},{}
    local role=Role.new({current=function(x)return x==r end,load=function(p)assert(p==base..'.StateTreeConfig_Humaniod');return normal end,
        aiOf=function(a)assert(a==actor);return ai end,player=function()return player end,fname=function(s)return s end,
        gameThread=function()return true end,find=function()return object('fixture')end,
        register=function(key,pre,post)hooks[key]={pre,post};return 1,2 end,unregister=function(key)hooks[key]=nil end,
        stat=function(owner,key)assert(owner==actor);return key=='Shachi' and actor.shachi or 100 end,log=function(s)logs[#logs+1]=s end})
    role:prepare(r);role:excludePlayer(r)
    assert(ai:GetStateTreeConfig()==(team=='companion' and summon or normal))
    if team=='blue' or team=='red' then
        assert(faction.relation==2 and #hatred.HatredList==1 and values.FollowTargetActor==nil and values.Sensed==nil)
        local hate=hooks['/SGameAI/Tools/Hatred/BP_SGameHatredManagerComponent.BP_SGameHatredManagerComponent_C:CheckCanHatredTarget'][1]
        assert(hate(hatred,player)==false and hate(hatred,enemy)==nil)
        local hit=hooks['/Script/SGameCombatSystem.BulletAttackModule:DealDamageToAvatar']
        local module=object('bullet');module.LastOwnerAvatar=player
        actor.shachi=80;hit[1](module,actor,0,0,0,0);actor.shachi=44;hit[2](module,actor,0,0,0,0)
        assert(logs[#logs]:find('杀气=80→44',1,true))
        local written=#logs;module.LastOwnerAvatar=enemy;hit[1](module,actor,0,0,0,0);hit[2](module,actor,0,0,0,0)
        assert(#logs==written,'another NPC hit must not be attributed to the player')
        role:restore(r);assert(next(hooks)==nil)
    else assert(faction.relation==2 and #hatred.HatredList==2 and values.FollowTargetActor==player)end
    assert(values.Enemy==enemy and hatred.HatredList[1]==enemy)
end
print('PASS independent arena and challenge AI, companion follow, one-way player exclusion and preserved opponent')
