package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Guillotine=require('arena_guillotine')
local MBOSS='/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_MBoss.BP_Monster_MBoss_C'
local BLADE='/PBZCombatAsset/ActorData/Mobs/012_MBoss/BulletData/BulletData_MBoss_Kill.BulletData_MBoss_Kill'
local address=0
local function object(name,fields)
    local o=fields or {}
    address=address+1
    o.address=address
    function o:IsValid()return not self.invalid end
    function o:GetAddress()return self.address end
    function o:GetFullName()return name end
    return o
end
local function key(actor)return tostring(actor.address)end
local npcBase=object('Class /Script/ProjectPBZ.PBZCharacter_NPC')
local npcClass=object('BlueprintGeneratedClass /Test/NPC.NPC_C',{GetSuperStruct=function()return npcBase end})
local active={battle_active=true,blue_count=1,red_count=1}
local idle={battle_active=false,blue_count=1,red_count=1}

local function fixture()
    local h={members={},hits=0,aims=0,finds=0,registrations=0,now=0,logs={},inGame=true,protect={},world='one'}
    local kill=object('GE_Kill')
    local function npc(name,rank)
        local actor=object('NPC /Test/World.'..name,{hp=200,floor=0,tags={},Mesh=object('Mesh'),GetClass=function()return npcClass end})
        actor['Actor Config']=object('Config',{['Difficulty Tag']={TagName={ToString=function()return 'CharacterType.Difficulty.'..rank end}}})
        actor.AbilitySystemComponent=object('ASC',{
            GetGameplayTagCount=function(_,tag)return actor.tags[tag.TagName] or 0 end,
            BP_ApplyGameplayEffectToSelf=function(_,effect,level,context)
                assert(effect==kill and level==0 and type(context)=='table')
                h.hits=h.hits+1
                actor.hp=0
            end,
        })
        return actor
    end
    h.boss,h.foe,h.ally=npc('HuangXingZi','Boss'),npc('Opponent','Elite'),npc('Ally','Standard')
    h.player=object('Player /Test/World.Hun',{Mesh=object('PlayerMesh')})
    h.component=object('Guillotine',{TargetActor=h.player,TargetMesh=h.player.Mesh})
    h.boss.BP_Guillotine=h.component
    h.members={{actor=h.boss,team='blue',class_path=MBOSS},{actor=h.foe,team='red'},{actor=h.ally,team='blue'}}
    h.opponent=h.foe
    local library=object('Library',{SendGameplayEventToActor=function(_,actor,tag,event)
        assert(actor==h.boss and tag.TagName=='GameplayEvent.AI.TargetChanged' and event.Target==h.opponent)
        assert(event.Instigator==actor and event.EventTag==tag)
        h.aims=h.aims+1
        h.component.TargetActor,h.component.TargetMesh=event.Target,event.Target.Mesh
    end})
    local fn=object('C4HitEvent')
    h.loaded=true
    h.module=Guillotine.new({log=function(line)h.logs[#h.logs+1]=line end,
        staticFind=function(path)
            h.finds=h.finds+1
            if path:find('EventReceived_B050170643A0D6231C0901B07314DB59',1,true) then return h.loaded and fn or nil end
            if path:find('AbilitySystemBlueprintLibrary',1,true) then return library end
            if path:find('GE_Kill',1,true) then return kill end
        end,
        registerHook=function(path,callback)
            assert(path:find('GA_MBoss_Skill_02_C4_C:EventReceived_',1,true))
            h.registrations=h.registrations+1;h.hook=callback;return 19,19
        end,
        clock=function()return h.now end,fname=function(name)return name end,
        inGameThread=function()return h.inGame end,
        session=function()return {game_ready=h.world~=nil,game_session=h.world}end,
        live=function(actor)return actor and actor:IsValid() and not actor.destroying end,
        opponentOf=function(owner)assert(owner==key(h.boss));return h.opponent end,
        isImmortal=function(team)return h.protect[team]==true end,
        attributes={read=function(_,actor,field)
            local value=field=='Health' and actor.hp or actor.floor
            return value and {current=value,base=value}
        end},
    })
    h.ability=object('Ability',{GetAvatarActorFromActorInfo=function()return h.boss end})
    local blade=object('BulletData '..BLADE)
    local other=object('BulletData /Test/Other')
    function h:hit(target,data,owner)
        local bullet=object('SweepTraceBullet',{BulletData=data or blade,BulletOwnerAvatar=owner or self.boss})
        local payload={OptionalObject=bullet,Target=target}
        local remote={type=function()return 'RemoteUnrealParam'end,get=function()return payload end}
        self.hook(self.ability,remote)
    end
    h.other=other
    h.npc=npc
    function h:tick(status)self.module:tick(self.members,status or active)end
    return h
end

do
    local h=fixture()
    h:tick(idle)
    assert(h.finds==0 and h.aims==0)
    h.loaded=false
    h.module:prepare(h.members)
    h:tick()
    assert(h.registrations==0 and h.aims==1)
    h.now=1;h.loaded=true;h:tick();h:tick()
    assert(h.registrations==1 and h.component.TargetActor==h.foe and h.component.TargetMesh==h.foe.Mesh and h.aims==1)
    h.opponent=h.npc('Reinforcement','Mob')
    h.members[#h.members+1]={actor=h.opponent,team='red'}
    h:tick()
    assert(h.aims==2 and h.component.TargetActor==h.opponent and h.component.TargetMesh==h.opponent.Mesh)
    print('PASS chain receives the native AI target event and reads back both actor and mesh')
end

do
    local h=fixture()
    h:tick()
    h:hit(h.foe,h.other)
    h:hit(h.foe,nil,h.ally)
    h:hit(h.ally)
    h:hit(h.player)
    h.inGame=false;h:hit(h.foe);h.inGame=true
    h:tick()
    assert(h.hits==0,'normal strikes, another owner, allies and players must not enter the NPC kill path')
    h:hit(h.foe);h:hit(h.foe)
    assert(h.foe.hp==200,'the engine hit callback must not execute a death inline')
    h:tick()
    assert(h.hits==1 and h.foe.hp==0)
    assert(table.concat(h.logs,'\n'):find('HP=200 -> 0',1,true),'record the health readback')
    h:hit(h.foe);h:tick()
    assert(h.hits==1)
    print('PASS only the confirmed blade hit settles once on the next support tick')
end

do
    local h=fixture();h:tick()
    h.protect.red=true;h:hit(h.foe);h:tick();h.protect.red=nil
    h.foe.floor=1;h:hit(h.foe);h:tick();h.foe.floor=0
    h.foe.tags['CharacterState.Immortal']=1;h:hit(h.foe);h:tick();h.foe.tags={}
    local boss=h.npc('PhaseBoss','BigBoss')
    h.members[#h.members+1]={actor=boss,team='red'}
    h:tick();h:hit(boss);h:tick()
    assert(h.hits==0 and boss.hp==200)
    h:hit(h.foe);h.world='two';h:tick()
    h:hit(h.foe);h.module:stop();h:tick()
    h:hit(h.foe);h.foe.destroying=true;h:tick()
    h.foe.destroying=false;h:hit(h.foe);h.module:silence();h:tick()
    assert(h.hits==0,'protections, invalidation, session changes, stop and unload cancel settlement')
    print('PASS protected NPCs, world changes and teardown cannot receive a queued kill')
end
