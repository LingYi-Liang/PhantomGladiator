package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Passage=require('companion_passage')
local index=0
local function object(label,fields)
    index=index+1;local id=index;local a=fields or {}
    a.label=label;a.valid=true
    function a:IsValid()return self.valid end
    function a:GetAddress()return id end
    function a:GetFullName()return self.label end
    return a
end
local PLAYER_CHANNEL,AI_CHANNEL=2,19
-- An NPC with a capsule whose responses are a table channel -> response (2 = block).
local function npc(label,h)
    local actor=object(label)
    local capsule=object('CapsuleComponent '..label..'.CollisionCylinder',{responses={[PLAYER_CHANNEL]=2,[AI_CHANNEL]=2}})
    function capsule:GetOwner()return actor end
    function capsule:GetCollisionResponseToChannel(channel)return self.responses[channel]end
    function capsule:SetCollisionResponseToChannel(channel,response)
        h.writes[#h.writes+1]={capsule=self,channel=channel,response=response,logs=#h.logs}
        if not self.stuck then self.responses[channel]=response end
    end
    actor.CapsuleComponent=capsule
    return actor
end
local function fixture(saved)
    local h={logs={},writes={},members={},files={},mounts={}}
    if saved then h.files['R/companion-passage.tsv']=saved end
    h.io={open=function(path,mode)
        if mode=='r'then
            local data=h.files[path];if not data then return nil end
            return {read=function()return data end,close=function()return true end}
        end
        if h.readOnly then return nil end
        return {write=function(_,text)h.files[path]=text;return true end,close=function()return true end}
    end}
    h.player=object('BP_Renewal_Hun_C Player')
    h.player.CapsuleComponent=object('CapsuleComponent Player.CollisionCylinder',{type=PLAYER_CHANNEL,writes=0})
    function h.player.CapsuleComponent:GetCollisionObjectType()return self.type end
    function h.player.CapsuleComponent:SetCollisionResponseToChannel()self.writes=self.writes+1 end
    h.mod=Passage.new({path='R',io=h.io,clock=function()return h.now or 0 end,log=function(s)h.logs[#h.logs+1]=s end,members=function()return h.members end,
        player=function()return h.player end,mount=function(actor)return h.mounts[actor]end})
    function h:logged(text)local n=0;for _,line in ipairs(self.logs)do if line:find(text,1,true)then n=n+1 end end;return n end
    return h
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end

test('a companion capsule ignores the player channel, announced first and read back; enemies and the player are untouched',function()
    local h=fixture();assert(h.mod.on==true,'on by default')
    local buddy,blue,enemy=npc('BP_Monster_Buddy_C',h),npc('BP_Monster_Blue_C',h),npc('BP_Monster_Enemy_C',h)
    h.members={{actor=buddy,team='companion'},{actor=blue,team='blue'},{actor=enemy,team='red'}}
    h.mod:tick()
    assert(buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==0 and buddy.CapsuleComponent.responses[AI_CHANNEL]==2,'only the player channel')
    assert(blue.CapsuleComponent.responses[PLAYER_CHANNEL]==2 and enemy.CapsuleComponent.responses[PLAYER_CHANNEL]==2)
    assert(#h.writes==1 and h.writes[1].channel==PLAYER_CHANNEL and h.writes[1].response==0)
    assert(h.logs[h.writes[1].logs]:find('即将 让玩家穿过 BP_Monster_Buddy_C：胶囊体对玩家通道2的碰撞 2→0',1,true),'the announcement is the last line before the call')
    assert(h:logged('让玩家穿过 读回 BP_Monster_Buddy_C 通道2=0 verified=true')==1)
    assert(h.player.CapsuleComponent.writes==0,'the player capsule is only read')
    h.mod:tick();h.mod:tick();assert(#h.writes==1 and h.mod:status().applied==1,'already ignoring: nothing more is written')
    buddy.CapsuleComponent.responses[PLAYER_CHANNEL]=2;h.mod:tick()
    assert(#h.writes==2 and buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==0,'the game put it back: applied again')
end)
test('leaving the team, the switch going off and unloading put the recorded response back',function()
    local h=fixture();local buddy=npc('BP_Monster_Buddy_C',h);buddy.CapsuleComponent.responses[PLAYER_CHANNEL]=1
    h.members={{actor=buddy,team='companion'}};h.mod:tick()
    assert(buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==0)
    h.members={{actor=buddy,team='blue'}};h.mod:tick()
    assert(buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==1 and h:logged('还原 BP_Monster_Buddy_C 对玩家通道2的碰撞 0→1（原值1） 原因=随从离队 已还原=true')==1,'the value it had, not a guess')
    h.members={{actor=buddy,team='companion'}};h.mod:tick();assert(buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==0)
    assert(h.mod:set('OFF').ok and h.mod.on==false and buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==1)
    local writes=#h.writes;h.mod:tick();assert(#h.writes==writes,'off: nothing is written')
    assert(h.files['R/companion-passage.tsv']=='CompanionPassageV1\ton=0\n')
    assert(fixture(h.files['R/companion-passage.tsv']).mod.on==false,'the switch is read back after a restart')
    assert(h.mod:set('ON').ok);h.mod:tick();assert(buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==0)
    h.mod:silence(false);assert(buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==0,'off the game thread nothing is written')
    h=fixture();buddy=npc('BP_Monster_Buddy_C',h);h.members={{actor=buddy,team='companion'}};h.mod:tick()
    h.mod:silence(true);assert(buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==2 and h:logged('原因=Mod 卸载')==1)
    h.mod:tick();assert(buddy.CapsuleComponent.responses[PLAYER_CHANNEL]==2,'nothing after unloading')
    assert(not h.mod:set('MAYBE').ok)
    h=fixture();h.readOnly=true;assert(not h.mod:set('OFF').ok and h.mod.on==true,'an unsaved switch does not change')
end)
test('mounts, reserves, a setting the game already has, a reused address and unreadable objects',function()
    local h=fixture();local rider,horse,spare=npc('BP_Monster_Rider_C',h),npc('BP_Monster_Horse_C',h),npc('BP_Monster_Spare_C',h)
    h.mounts[rider]=horse
    h.members={{actor=rider,team='companion'},{actor=spare,team='companion',reserve=true}};h.mod:tick()
    assert(rider.CapsuleComponent.responses[PLAYER_CHANNEL]==0 and horse.CapsuleComponent.responses[PLAYER_CHANNEL]==0,'the mount too')
    assert(spare.CapsuleComponent.responses[PLAYER_CHANNEL]==2,'a reserve is not in the field')
    h.mounts[rider]=nil;h.mod:tick();assert(horse.CapsuleComponent.responses[PLAYER_CHANNEL]==2,'dismounted: the horse blocks again')
    local ghost=npc('BP_Monster_Ghost_C',h);ghost.CapsuleComponent.responses[PLAYER_CHANNEL]=0
    h.members={{actor=ghost,team='companion'}};h.mod:tick();h.members={};h.mod:tick()
    assert(ghost.CapsuleComponent.responses[PLAYER_CHANNEL]==0,'it ignored the player by itself: not ours to restore')
    local old=npc('BP_Monster_Old_C',h);h.members={{actor=old,team='companion'}};h.mod:tick()
    old.label='BP_Monster_Recycled_C';h.members={};h.mod:tick()
    assert(old.CapsuleComponent.responses[PLAYER_CHANNEL]==0 and h:logged('还原 BP_Monster_Old_C')==0,'the address names another actor now: left alone')
    local stuck=npc('BP_Monster_Stuck_C',h);stuck.CapsuleComponent.stuck=true
    h.members={{actor=stuck,team='companion'}};h.mod:tick()
    assert(h:logged('让玩家穿过 读回 BP_Monster_Stuck_C 通道2=2 verified=false')==1 and h.mod:status().applied==0)
    h=fixture();local buddy=npc('BP_Monster_Buddy_C',h);h.members={{actor=buddy,team='companion'}}
    h.player.CapsuleComponent.type=nil;h.mod:tick();h.mod:tick()
    assert(#h.writes==0 and h:logged('读不到玩家胶囊体的碰撞通道')==1,'no channel, no write, said once')
    h.player.CapsuleComponent.type=7;h.mod:tick();assert(#h.writes==0,'a response that cannot be read is not written over')
    buddy.CapsuleComponent.responses[7]=2;h.mod:tick();assert(h.writes[1].channel==7,'the channel is read, never assumed')
    h.player.valid=false;buddy.CapsuleComponent.responses[7]=2;h.mod:tick();assert(#h.writes==1,'no player, no write')
end)
test('changing the player channel restores its old response; rejected writes back off and recover',function()
    local h=fixture();local npc1=npc('Companion',h);local cap=npc1.CapsuleComponent
    h.members={{actor=npc1,team='companion'}};h.mod:tick()
    cap.responses[7]=1;h.player.CapsuleComponent.type=7;h.mod:tick()
    print('MEASURE previous collision channel after migration='..cap.responses[PLAYER_CHANNEL])
    assert(cap.responses[PLAYER_CHANNEL]==2 and cap.responses[7]==0)
    cap.stuck=true;assert(h.mod:set('OFF').ok);local tries=#h.writes
    for i=1,120 do h.now=i/10;h.mod:tick() end
    assert(#h.writes-tries<=6 and cap.responses[7]==0)
    cap.stuck=false;h.now=22;h.mod:tick();assert(cap.responses[7]==1)
    cap.stuck=true;assert(h.mod:set('ON').ok);tries=#h.writes
    for i=1,120 do h.now=22+i/10;h.mod:tick() end
    print('MEASURE denied passage: writes in 12 seconds='..(#h.writes-tries))
    assert(#h.writes-tries<=6 and h.mod:status().applied==0)
    cap.stuck=false;h.now=45;h.mod:tick();assert(cap.responses[7]==0 and h.mod:status().applied==1)
end)
print('companion passage: PASS '..n..' apply/readback/restore/switch/mount checks; walking through remains unverified in game')
