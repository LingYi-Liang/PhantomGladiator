
package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Guillotine=require('arena_guillotine')
local MBOSS='/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_MBoss.BP_Monster_MBoss_C'
local ROOT='/PBZCombatAsset/ActorData/Mobs/012_MBoss/'
local C4=ROOT..'Abilities/GA_MBoss_Skill_02_C4.GA_MBoss_Skill_02_C4_C:'
local HIT=C4..'EventReceived_B050170643A0D6231C0901B07314DB59'
local ENDED=C4..'K2_OnEndAbility'
local BLADE=ROOT..'BulletData/BulletData_MBoss_Kill.BulletData_MBoss_Kill'
local MONTAGE=ROOT..'Montages/Skill/MBoss_Skill_02_D1_Montage.MBoss_Skill_02_D1_Montage'

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
local function remote(value)
    return {type=function()return 'RemoteUnrealParam'end,get=function()return value end}
end
local function key(actor)return tostring(actor.address)end
local npcBase=object('Class /Script/ProjectPBZ.PBZCharacter_NPC')
local npcClass=object('BlueprintGeneratedClass /Test/NPC.NPC_C',{GetSuperStruct=function()return npcBase end})
local active={battle_active=true,blue_count=1,red_count=1}

local function fixture()
    local h={members={},hits=0,grabs={},timers={},loops={},hooks={},aims=0,finds=0,now=0,logs={},
        inGame=true,protect={},world='one',position=3.2,playing=true}
    local kill=object('GE_Kill')
    local montage=object('AnimMontage '..MONTAGE)
    local anim=object('AnimInstance',{
        Montage_IsPlaying=function(_,asset)assert(asset==montage);return h.playing end,
        Montage_GetPosition=function(_,asset)assert(asset==montage);return h.position end,
    })
    local function npc(name)
        local actor=object('NPC /Test/World.'..name,{hp=200,floor=0,tags={},Mesh=object('Mesh'),GetClass=function()return npcClass end})
        actor.AbilitySystemComponent=object('ASC',{
            GetGameplayTagCount=function(_,tag)return actor.tags[tag.TagName] or 0 end,
            BP_ApplyGameplayEffectToSelf=function(_,effect,level,context)
                assert(effect==kill and level==0 and type(context)=='table')
                assert(not h.held,'restore the controlled victim before triggering the native death path')
                h.hits=h.hits+1
                actor.hp=0
            end,
        })
        return actor
    end
    h.boss,h.foe,h.ally=npc('HuangXingZi'),npc('Opponent'),npc('Ally')
    h.boss.Mesh.GetAnimInstance=function()return anim end
    h.player=object('Player /Test/World.Hun',{Mesh=object('PlayerMesh')})
    h.component=object('Guillotine',{TargetActor=h.player,TargetMesh=h.player.Mesh})
    h.boss.BP_Guillotine=h.component
    h.members={{actor=h.boss,team='blue',class_path=MBOSS},{actor=h.foe,team='red'},{actor=h.ally,team='blue'}}
    h.opponent=h.foe
    local library=object('Library',{SendGameplayEventToActor=function(_,actor,tag,event)
        assert(actor==h.boss and tag.TagName=='GameplayEvent.AI.TargetChanged')
        assert(event.Instigator==actor and event.EventTag==tag)
        h.aims=h.aims+1
        h.component.TargetActor,h.component.TargetMesh=event.Target,event.Target.Mesh
    end})
    local fn=object('C4Event')
    h.loaded=true
    h.module=Guillotine.new({log=function(line)h.logs[#h.logs+1]=line end,
        staticFind=function(path)
            h.finds=h.finds+1
            if path==HIT or path==ENDED then return h.loaded and fn or nil end
            if path==MONTAGE then return montage end
            if path:find('AbilitySystemBlueprintLibrary',1,true) then return library end
            if path:find('GE_Kill',1,true) then return kill end
        end,
        registerHook=function(path,callback)
            assert((path==HIT or path==ENDED) and not h.hooks[path])
            h.hooks[path]=callback;return 19,19
        end,
        clock=function()return h.now end,fname=function(name)return name end,
        inGameThread=function()return h.inGame end,
        session=function()return {game_ready=h.world~=nil,game_session=h.world}end,
        live=function(actor)return actor and actor:IsValid() and not actor.destroying end,
        opponentOf=function(owner)assert(owner==key(h.boss));return h.opponent end,
        isImmortal=function(team)return h.protect[team]==true end,
        playGrab=function(actor,stillValid)
            assert(stillValid())
            h.grabs[#h.grabs+1]=actor
            h.held=actor
            return true
        end,
        grabHeld=function(actor)return h.held==actor,h.visualDone==true end,
        stopGrab=function()
            if h.restoreFails then return false,'恢复待重试' end
            h.held=nil
            return true,'控制已恢复'
        end,
        defer=function(callback)h.timers[#h.timers+1]=callback;return #h.timers end,
        loop=function(ms,callback)assert(ms==25);h.loops[callback]=true;return callback end,
        cancel=function(handle)h.loops[handle]=nil end,
        attributes={read=function(_,actor,field)
            local value=field=='Health' and actor.hp or actor.floor
            return value and {current=value,base=value}
        end},
    })
    h.ability=object('C4 instance',{bIsActive=true,GetAvatarActorFromActorInfo=function()return h.boss end})
    local blade=object('BulletData '..BLADE)
    h.other=object('BulletData /Test/Other')
    function h:hit(target,data,owner)
        local bullet=object('SweepTraceBullet',{BulletData=data or blade,BulletOwnerAvatar=owner or self.boss})
        self.hooks[HIT](remote(self.ability),remote({OptionalObject=bullet,Target=target}))
    end
    function h:endCast(cancelled,ability)
        self.hooks[ENDED](remote(ability or self.ability),remote(cancelled))
    end
    function h:tick(status)self.module:tick(self.members,status or active)end
    function h:frame(position)
        self.position=position
        self.now=self.now+0.025
        for callback in pairs(self.loops)do callback()end
    end
    function h:catch(target)
        self:tick()
        self:hit(target or self.foe)
        self.timers[#self.timers]()
    end
    function h:retract()
        for _,p in ipairs({3.6,4.0,4.4,4.8,4.95})do self:frame(p)end
    end
    return h
end

do
    local h=fixture()
    h:tick({battle_active=false,blue_count=1,red_count=1})
    assert(h.finds==0 and h.aims==0)
    h.loaded=false
    h.module:prepare(h.members)
    h:tick()
    assert(next(h.hooks)==nil and h.aims==1)
    h.now=1;h.loaded=true;h:tick();h:tick()
    assert(h.hooks[HIT] and h.hooks[ENDED] and h.component.TargetActor==h.foe and h.component.TargetMesh==h.foe.Mesh)
    print('PASS chain targets the assigned opponent and requires both native C4 hooks')
end

do
    local h=fixture()
    h:tick()
    h:hit(h.foe,h.other)
    h:hit(h.foe,nil,h.ally)
    h:hit(h.ally)
    h:hit(h.player)
    h.inGame=false;h:hit(h.foe);h.inGame=true
    h.playing=false;h:hit(h.foe);h.playing=true
    h.position=4.2;h:hit(h.foe);h.position=3.2
    assert(#h.timers==0,'other attacks, non-opponents, off-thread and unconfirmed animations cannot arm a kill')
    h:hit(h.foe);h:hit(h.foe)
    assert(#h.grabs==0 and #h.timers==1,'defer and deduplicate one capture')
    h.timers[1]()
    assert(h.held==h.foe and h.hits==0 and h.foe.hp==200)
    h:retract()
    h.visualDone=true;h:frame(5.0)
    assert(h.held==h.foe and h.hits==0,'the retrieval and visual alone cannot settle a cast')
    h.visualDone=false
    h:endCast(false,object('other cast'));h:frame(5.2)
    assert(h.held==h.foe and h.hits==0,'another ability end cannot settle this cast')
    h:endCast(false);h:frame(7.2)
    assert(h.held==h.foe and h.hits==0,'wait for the victim to finish the borrowed pose')
    h.visualDone=true;h:frame(7.2);h:frame(7.2)
    assert(h.held==nil and h.hits==1 and h.foe.hp==0)
    local log=table.concat(h.logs,'\n')
    assert(log:find('铡刀正常结束读回',1,true) and log:find('判死读回=true',1,true))
    print('PASS exact retrieval, normal end and final pose are all required for one native kill')
end

for _,interruption in ipairs({
    function(h)h:endCast(true);h:frame(3.3)end,
    function(h)h:endCast(false);h:frame(3.3)end,
    function(h)h:frame(5.0)end,
    function(h)h.playing=false;h:frame(3.3)end,
    function(h)h.world='two';h:frame(3.3)end,
    function(h)h.boss.hp=0;h:frame(3.3)end,
    function(h)h.foe.destroying=true;h:frame(3.3)end,
    function(h)h.protect.red=true;h:frame(3.3)end,
    function(h)h.now=12;h:frame(3.3)end,
    function(h)h.module:stop()end,
    function(h)h.module:silence()end,
    function(h)h:retract();h:endCast(true);h:frame(5.0)end,
})do
    local h=fixture();h:catch();h.visualDone=true
    interruption(h)
    h:endCast(false);h:frame(7.2)
    assert(h.held==nil and next(h.loops)==nil and h.hits==0 and h.foe.hp==200)
end
print('PASS cancelled, jumped, interrupted and stale casts restore the victim without killing')

do
    local h=fixture()
    h.foe.tags['CharacterState.Immortal']=1
    h:catch()
    assert(#h.grabs==0)
    h.foe.tags={}
    h:catch();h:retract();h:endCast(false);h.visualDone=true
    h.restoreFails=true;h:frame(7.2)
    assert(h.hits==0 and not h.module:stop())
    h.restoreFails=false
    assert(h.module:stop() and h.held==nil and h.foe.hp==200)
    print('PASS protected targets are skipped, and unverified restoration blocks death')
end
