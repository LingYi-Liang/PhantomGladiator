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
    address=address+1;o.address=address
    function o:IsValid()return not self.invalid end
    function o:GetAddress()return self.address end
    function o:GetFullName()return name end
    return o
end
local function remote(value)return {type=function()return 'RemoteUnrealParam'end,get=function()return value end}end
local function key(actor)return tostring(actor.address)end
local npcBase=object('Class /Script/ProjectPBZ.PBZCharacter_NPC')
local npcClass=object('BlueprintGeneratedClass /Test/NPC.NPC_C',{GetSuperStruct=function()return npcBase end})
local active={battle_active=true,blue_count=1,red_count=1}
local function fixture()
    local h={members={},writes=0,grabs={},held={},loops={},timers={},hooks={},logs={},protect={},world='one',now=0,
        inGame=true,finds=0,aims=0,loaded=true,finishes=0}
    local montage=object('AnimMontage '..MONTAGE)
    function h:npc(name,team,isBoss)
        local actor=object('NPC /Test/World.'..name,{hp=200,floor=0,tags={},['Death Delay']=0,GetClass=function()return npcClass end})
        actor.Mesh=object('Mesh')
        actor.ability=object('Ability /Test/'..name,{bIsActive=true,position=3.2,playing=true,
            GetAvatarActorFromActorInfo=function()return actor end})
        actor.Mesh.GetAnimInstance=function()return object('AnimInstance',{
            Montage_IsPlaying=function(_,asset)assert(asset==montage);return actor.ability.playing end,
            Montage_GetPosition=function(_,asset)assert(asset==montage);return actor.ability.position end,
        })end
        actor.AbilitySystemComponent=object('ASC',{GetGameplayTagCount=function(_,tag)return actor.tags[tag.TagName] or 0 end})
        actor.BP_Guillotine=object('Guillotine')
        self.members[#self.members+1]={actor=actor,team=team,class_path=isBoss and MBOSS or '/Test/NPC.NPC_C'}
        return actor
    end
    h.boss=h:npc('HuangXingZi','blue',true)
    h.foe=h:npc('Opponent','red')
    h.ally=h:npc('Ally','blue')
    h.player=object('Player /Test/Hun')
    h.opponent=h.foe
    local fn=object('C4Event')
    local lib=object('Library',{SendGameplayEventToActor=function(_,actor,tag,event)
        assert(tag.TagName=='GameplayEvent.AI.TargetChanged' and event.Instigator==actor)
        h.aims=h.aims+1
        actor.BP_Guillotine.TargetActor,actor.BP_Guillotine.TargetMesh=event.Target,event.Target.Mesh
    end})
    local blade=object('BulletData '..BLADE)
    h.other=object('BulletData /Test/Other')
    h.module=Guillotine.new({
        log=function(s)h.logs[#h.logs+1]=s end,
        staticFind=function(path)
            h.finds=h.finds+1
            if path==HIT or path==ENDED then return h.loaded and fn or nil end
            if path==MONTAGE then return montage end
            if path:find('AbilitySystemBlueprintLibrary',1,true)then return lib end
        end,
        registerHook=function(path,callback)assert(not h.hooks[path]);h.hooks[path]=callback;return 19,19 end,
        clock=function()return h.now end,now=function()return h.now end,fname=function(s)return s end,
        inGameThread=function()return h.inGame end,
        session=function()return {game_ready=h.world~=nil,game_session=h.world}end,
        live=function(actor)return actor and actor:IsValid() and not actor.destroying end,
        opponentOf=function()return h.opponent end,isImmortal=function(team)return h.protect[team]==true end,
        playGrab=function(actor,stillValid)
            assert(stillValid())
            h.grabs[#h.grabs+1]=actor
            if h.playFails then return false,'no compatible visual' end
            h.held[actor]=true
            return true
        end,
        finishGrab=function(actor)
            assert(h.held[actor])
            h.finishes=h.finishes+1
            if h.finishFailsOnce then h.finishFailsOnce=false;return false end
            return true
        end,
        grabHeld=function(actor)return h.held[actor]==true,h.visualDone==true end,
        stopGrab=function(_,actor)
            if h.restoreFails then return false,'restore pending' end
            h.held[actor]=nil
            return true
        end,
        defer=function(callback)h.timers[#h.timers+1]=callback;return #h.timers end,
        loop=function(ms,callback)assert(ms==25);h.loops[callback]=true;return callback end,
        cancel=function(handle)h.loops[handle]=nil end,
        attributes={
            read=function(_,actor,field)
                local v=field=='Health' and actor.hp or actor.floor
                return {current=v,base=v}
            end,
            writeBase=function(_,actor,field,value)
                assert(field=='Health' and value==0,'same native Health Override=0 path')
                h.writes=h.writes+1
                assert(actor['Death Delay']>=3.788884,'defer native NPC presentation cleanup through the victim tail')
                actor.hp=math.max(actor.floor,0)
                return true
            end,
        },
    })
    function h:tick(status)self.module:tick(self.members,status or active)end
    function h:hit(target,data,source)
        source=source or self.boss
        local bullet=object('SweepTraceBullet',{BulletData=data or blade,BulletOwnerAvatar=source})
        self.hooks[HIT](remote(source.ability),remote({OptionalObject=bullet,Target=target}))
    end
    function h:frame(delta,position)
        self.now=self.now+delta
        if position then self.boss.ability.position=position end
        for callback in pairs(self.loops)do callback()end
    end
    function h:drain()local pending=self.timers;self.timers={};for _,callback in ipairs(pending)do callback()end end
    function h:catch(target,source)self:tick();self:hit(target or self.foe,nil,source);self:drain()end
    function h:endCast(cancelled,source)source=source or self.boss;self.hooks[ENDED](remote(source.ability),remote(cancelled))end
    return h
end
local function test(name,fn)fn();print('ok - '..name)end

test('the native commit occurs at catch+0.9 before caster retrieval or visual completion',function()
    local h=fixture();h:catch()
    h:frame(0.89,3.5)
    assert(h.writes==0 and h.held[h.foe])
    h:frame(0.011,3.6)
    assert(h.writes==1 and h.foe.hp==0 and h.finishes==1 and h.held[h.foe])
    h:endCast(false);h.boss.ability.bIsActive=false
    h:tick({battle_active=true,blue_count=1,red_count=0})
    h:frame(5)
    assert(h.held[h.foe] and h.writes==1,'caster end and natural victory preserve the dying animation')
    h.visualDone=true;h:frame(0.1);h:frame(0.1)
    assert(not h.held[h.foe] and next(h.loops)==nil and h.foe['Death Delay']==0 and h.writes==1)
end)

test('a forward montage skip does not discard the native catch',function()
    local h=fixture();h:catch()
    h:frame(0.91,5.0)
    assert(h.foe.hp==0 and h.writes==1)
    h.module:stop()
end)

test('the native early dash branch still commits after its 0.05 second delay',function()
    local h=fixture();h:catch()
    h.foe.tags['Ability.Action.Hun.Dash']=1
    h:frame(0.11)
    assert(h.writes==0)
    h:frame(0.051)
    assert(h.writes==1 and h.foe.hp==0)
    h.module:stop()
end)

test('different casters can catch different NPCs in the same frame',function()
    local h=fixture()
    local caster=h:npc('AnotherMBoss','blue',true)
    local target=h:npc('AnotherVictim','red')
    h:tick()
    h:hit(h.foe);h:hit(target,nil,caster);h:drain()
    assert(h.held[h.foe] and h.held[target] and #h.grabs==2)
    h:frame(0.91)
    assert(h.foe.hp==0 and target.hp==0 and h.writes==2 and h.finishes==2)
    h.visualDone=true;h:frame(0.1)
    assert(next(h.held)==nil and next(h.loops)==nil)
end)

test('one actual victim is reserved once, including duplicate hit events',function()
    local h=fixture()
    local caster=h:npc('OtherCaster','blue',true)
    h:tick();h:hit(h.foe);h:hit(h.foe);h:hit(h.foe,nil,caster);h:drain()
    h:frame(0.91)
    assert(#h.grabs==1 and h.writes==1)
    h.module:stop()
end)

test('an unavailable animation does not remove the original lethal result',function()
    local h=fixture();h.playFails=true;h:catch()
    h:frame(0.91)
    assert(h.writes==1 and h.foe.hp==0)
    h:frame(0.1)
    assert(next(h.loops)==nil)
end)

for _,interrupt in ipairs({
    function(h)h:endCast(true)end,
    function(h)h:endCast(false)end,
    function(h)h.boss.ability.bIsActive=false end,
    function(h)h.world='two'end,
    function(h)h.boss.hp=0 end,
    function(h)h.foe.destroying=true end,
    function(h)h.protect.red=true end,
    function(h)h.boss.ability.position=1.0 end,
})do
    local h=fixture();h:catch();interrupt(h);h:frame(1)
    assert(h.writes==0 and next(h.held)==nil and next(h.loops)==nil)
end
print('ok - cancellation before the native lethal point restores without a kill')

test('cancellation after native death preserves the committed result and victim tail',function()
    local h=fixture();h:catch();h:frame(0.91)
    h:endCast(true);h:frame(0.1)
    assert(h.foe.hp==0 and h.held[h.foe] and h.writes==1)
    h.visualDone=true;h:frame(0.1)
    assert(not h.held[h.foe])
end)

test('a transient finishing-animation readback retries without repeating the lethal write',function()
    local h=fixture();h.finishFailsOnce=true;h:catch();h:frame(0.91)
    assert(h.writes==1 and h.finishes==1 and h.foe.hp==0)
    h:frame(0.025)
    assert(h.writes==1 and h.finishes==2 and h.held[h.foe])
    h.visualDone=true;h:frame(0.1)
    assert(not h.held[h.foe])
end)

test('the same native attribute write leaves an actual Health_Min floor to the game',function()
    local h=fixture();h.foe.floor=2;h:catch();h:frame(0.91)
    assert(h.writes==1 and h.foe.hp==2 and h.foe.floor==2)
    h.visualDone=true;h:frame(0.1)
    assert(not h.held[h.foe] and h.foe['Death Delay']==0)
end)

test('wrong bullets, teams, player and off-thread callbacks cannot arm the adapter',function()
    local h=fixture();h:tick()
    h:hit(h.foe,h.other);h:hit(h.ally);h:hit(h.player);h:hit(h.foe,nil,h.ally)
    h.inGame=false;h:hit(h.foe);h.inGame=true
    h.foe.tags['CharacterState.Immortal']=1;h:hit(h.foe)
    assert(#h.timers==0 and h.writes==0)
end)

test('restoration retry after death never rewrites health or revives the victim',function()
    local h=fixture();h:catch();h:frame(0.91)
    h.visualDone=true;h.restoreFails=true;h:frame(0.1)
    assert(h.writes==1 and not h.module:stop() and h.foe.hp==0)
    h.restoreFails=false
    assert(h.module:stop() and next(h.held)==nil and h.writes==1)
end)
