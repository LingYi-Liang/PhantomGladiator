package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Body=require('hun_body')
local HATE,HIDE='AI.Hatred.CanNotBeHatred','CharacterState.Unselectable.Force.Hide'
local index=0
local function object(label,outer)
    index=index+1;local id=index;local a={label=label,outer=outer,valid=true}
    function a:IsValid()return self.valid end
    function a:GetFullName()assert(self.valid);return self.label end
    function a:GetOuter()assert(self.valid);return self.outer end
    function a:GetAddress()assert(self.valid);return id end
    return a
end
local function classObject(short)
    local c=object('Class /Script/Engine.'..short)
    function c:GetFName()return {ToString=function()return short end}end
    return c
end
local function fixture()
    local h={logs={},writes={},reads=0,scans=0,loose=true}
    h.world=object('World');h.player=object('Player',h.world)
    h.native=object('Class /Script/ProjectPBZ.PBZCharacter_NPC');function h.native:GetSuperStruct()return nil end
    h.cls=object('BlueprintGeneratedClass '..Body.path);function h.cls:GetSuperStruct()return h.native end
    h.source=object('Config /PBZCombatAsset/ActorData/Mobs/000_Hun/ActorConfig/ActorC_Monster_Hun.ActorC_Monster_Hun')
    h.source.InitialTags={GameplayTags={{TagName=HATE},{TagName=HIDE},{TagName='CharacterType.AI.Boss'}},ParentTags={}}
    h.actor=object('NPC Hun 1',h.world);h.actor['Actor Config']=h.source;h.actor.bHidden=false
    function h.actor:GetClass()return h.cls end
    function h.actor:SetActorHiddenInGame(value)self.bHidden=value;h.shown=(h.shown or 0)+1 end
    h.counts={[HATE]=1,[HIDE]=1}
    h.asc=object('ASC',h.actor)
    function h.asc:GetGameplayTagCount(tag)h.reads=h.reads+1;if h.onRead then h.onRead()end;return h.counts[tag.TagName]or 0 end
    h.actor.AbilitySystemComponent=h.asc
    h.lib=object('AbilityUtils')
    function h.lib:SetLooseGameplayTagCount(actor,tag,count)
        assert(actor==h.actor);h.writes[#h.writes+1]=tag.TagName..'='..count
        if h.loose then h.counts[tag.TagName]=count end
    end
    local skeletal,static=classObject('SkeletalMeshComponent'),classObject('StaticMeshComponent')
    local function component(label,owner,cls,property,asset)
        local c=object(label,owner);c[property]=object('Mesh /Game/Hun.'..asset);c.bHiddenInGame=false;c.ForcedLodModel=0
        function c:GetOwner()return owner end
        function c:GetClass()return cls end
        function c:IsVisible()return true end
        return c
    end
    h.other=object('NPC Other',h.world)
    h.hat=object('Hat actor',h.world);function h.hat:GetOwner()return h.actor end
    h.components={
        SkeletalMeshComponent={component('Comp /Game/Map.Hun:Body',h.actor,skeletal,'SkeletalMeshAsset','SK_Body'),component('Comp /Game/Map.Other:Body',h.other,skeletal,'SkeletalMeshAsset','SK_Other')},
        StaticMeshComponent={component('Comp /Game/Map.Hun:Head',h.actor,static,'StaticMesh','SM_Head'),component('Comp /Game/Map.Hat:Mesh',h.hat,static,'StaticMesh','SM_Hat')},
    }
    h.options={world=function()return h.world end,player=function()return h.player end,log=function(s)h.logs[#h.logs+1]=s end,
        hp=function()return 100 end,aiOf=function()return object('AI')end,fname=function(s)return s end,
        find=function(path)assert(path=='/Script/SGameUtils.Default__AbilityUtils');return h.lib end,
        findAll=function(className)h.scans=h.scans+1;return h.components[className]end}
    h.mod=Body.new(h.options)
    function h:run()
        return self.mod:spawn({spawn=function(_,path,team,count)
            assert(path==Body.path);self.mod:capture(self.actor,path)
            local ok,why=self.mod:prepare(self.actor)
            if ok and self.duringBirth then self.duringBirth()end
            if ok then ok,why=self.mod:finished(self.actor)end
            return {ok=ok,message=why or'',spawned_count=1}
        end},'blue',1,'1')
    end
    function h:tick(times)for _=1,times or 1 do self.mod:tick({{actor=self.actor}})end end
    function h:logged(text)
        local hits=0;for _,line in ipairs(self.logs)do if line:find(text,1,true)then hits=hits+1 end end
        return hits
    end
    return h
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end
test('body is born with its template untouched and both tags cleared on the instance',function()
    local h=fixture();local r=h:run();assert(r.ok)
    assert(h.actor['Actor Config']==h.source and #h.source.InitialTags.GameplayTags==3)
    assert(h.counts[HATE]==0 and h.counts[HIDE]==0 and #h.writes==2)
    assert(h:logged('出生前读回')==1 and h:logged(HATE..'|'..HIDE..'|CharacterType.AI.Boss')==1)
    assert(h:logged(HATE..' 1→0（写入=true）')==1 and h:logged(HIDE..' 1→0（写入=true）')==1 and h:logged('两项都为0=true')==1)
    assert(h.mod:status().full_ready==false and h.mod:status().prepared==1)
end)
test('normal summons are neither read nor written',function()
    local h=fixture();h.mod:capture(h.actor,Body.path)
    assert(h.mod:prepare(h.actor)and h.mod:finished(h.actor));h:tick(3)
    assert(#h.logs==0 and h.reads==0 and #h.writes==0 and h.scans==0)
end)
test('tags the game adds later are cleared again and logged once per change',function()
    local h=fixture();assert(h:run().ok);h:tick(2)
    local before=h:logged('标签变化');h.counts[HIDE]=1;h:tick(1)
    assert(h.counts[HIDE]==0 and h:logged('标签变化')==before+1 and h:logged(HIDE..' 1→0（写入=true）')==2)
    h:tick(3);assert(h:logged('标签变化')==before+2,'only the return to the quiet state is logged again')
end)
test('a tag that does not respond to the write is reported and does not block the birth',function()
    local h=fixture();h.loose=false;local r=h:run()
    assert(r.ok and h.counts[HIDE]==1 and h:logged(HIDE..' 1→1（写入=true）')==1 and h:logged('两项都为0=false')==1)
    assert(h.mod:status().message:find('还没读回为0',1,true))
    h.actor.bHidden=true;h:tick(25);assert(h.shown==nil and h.actor.bHidden==true,'a body whose tags are still set is not force-shown')
    assert(h:logged('复查结束')==1 and h.mod:status().message:find('没能保持为0',1,true))
end)
test('an ability system that is not ready at birth is retried by the support cycle',function()
    local h=fixture();h.actor.AbilitySystemComponent=nil;assert(h:run().ok)
    assert(h:logged('ASC未就绪')==1 and #h.writes==0)
    h.actor.AbilitySystemComponent=h.asc;h:tick(1);assert(h.counts[HATE]==0 and h.counts[HIDE]==0 and h:logged('标签变化')==1)
end)
test('a missing AbilityUtils object is reported instead of a silent failure',function()
    local h=fixture();h.options.find=function()return nil end;h.mod=Body.new(h.options)
    assert(h:run().ok and h.counts[HATE]==1 and h:logged('写入=找不到AbilityUtils')==1)
end)
test('player and wrong-world identities fail closed',function()
    local h=fixture();h.player=h.actor;assert(not h:run().ok and #h.writes==0)
    h=fixture();h.actor.outer=object('Other world');assert(not h:run().ok and #h.writes==0)
end)
test('identity or world changes during birth prevent any write',function()
    local h=fixture();h.duringBirth=function()h.actor.label='Replacement actor'end
    assert(not h:run().ok and #h.writes==0)
    h=fixture();h.duringBirth=function()h.world=object('new world')end
    assert(not h:run().ok and #h.writes==0)
    h=fixture();h.duringBirth=function()h.mod:cancel()end
    assert(not h:run().ok and #h.writes==0)
end)
test('an instance replaced between the read and the write is not written',function()
    local h=fixture();h.onRead=function()h.actor.label='Replacement actor'end
    assert(h:run().ok and #h.writes==0 and h.counts[HATE]==1 and h:logged(HATE..' 1→1（写入=实例已变化）；'..HIDE..' 1→1（写入=实例已变化）')==1)
end)
test('a body still hidden after the tags read zero is shown once',function()
    local h=fixture();assert(h:run().ok);h.actor.bHidden=true;h:tick(1);assert(h.shown==nil)
    h:tick(1);assert(h.shown==1 and h.actor.bHidden==false and h:logged('解除隐藏')==1)
    h.actor.bHidden=true;h:tick(5);assert(h.shown==1,'the game hiding it again is left alone')
end)
test('the look probe lists the body and the player once per request and writes nothing',function()
    local h=fixture()
    -- The player carries a head with its own animation class, hung on the body mesh at a socket.
    local body=h.components.SkeletalMeshComponent[1]
    local head=object('Comp /Game/Map.Player:Hun_pic_head',h.player);head.SkeletalMeshAsset=object('Mesh /Game/Hun.SK_Head');head.bHiddenInGame=false;head.ForcedLodModel=0
    head.AnimClass=object('Class /Game/Hun.ABP_Head_C')
    local headClass=object('Class /Script/Engine.SkeletalMeshComponent');function headClass:GetFName()return {ToString=function()return 'SkeletalMeshComponent'end}end
    local animClass=object('Class /Game/Hun.ABP_Head_C');function animClass:GetFName()return {ToString=function()return 'ABP_Head_C'end}end
    local instance=object('Anim instance',head);function instance:GetClass()return animClass end
    function head:GetOwner()return h.player end
    function head:GetClass()return headClass end
    function head:IsVisible()return true end
    function head:GetAttachParent()return body end
    function head:GetAttachSocketName()return {ToString=function()return 'head'end}end
    function head:GetAnimInstance()return instance end
    table.insert(h.components.SkeletalMeshComponent,head)
    h.actor['Actor Config']['Default Linked Animation Layers']={object('Class /Game/Hun.ABP_Item_Hun_Summon_C')}
    h.actor.CharacterMovement=object('Movement',h.actor);h.actor.CharacterMovement.Velocity={X=300,Y=400,Z=0};h.actor.CharacterMovement.MovementMode=1;h.actor.CharacterMovement.MaxWalkSpeed=600
    assert(h:run().ok);h:tick(4)
    assert(h.scans==10,'five component classes (cloth included) for the body and five for the player: '..h.scans)
    assert(h:logged('外观部件：魂 NPC Hun 1；共3个')==1 and h:logged('外观部件：主角 Player；共1个')==1)
    assert(h:logged('SkeletalMeshComponent Body 资源=SK_Body')==1 and h:logged('StaticMeshComponent Head 资源=SM_Head')==1)
    assert(h:logged('StaticMeshComponent Mesh（挂件:Hat actor） 资源=SM_Hat')==1 and h:logged('SK_Other')==0)
    assert(h:logged('SkeletalMeshComponent Hun_pic_head 资源=SK_Head 挂在=Body@head 可见=true 游戏内隐藏=false 强制LOD=0 动画实例=ABP_Head_C 动画类=ABP_Head_C')==1)
    assert(h:logged('动画与移动：魂；配置=ActorC_Monster_Hun；默认动画层=ABP_Item_Hun_Summon_C；移动模式=1；水平速度=500；最大行走速度=600')==1)
    assert(h:logged('动画与移动：主角')==1)
    assert(#h.writes==2,'only the two tag writes of the birth itself')
    h:tick(12);assert(h:logged('动画与移动：魂（第6次复查）')==1 and h:logged('动画与移动：魂（第14次复查）')==1)
    assert(h.scans==10,'later cycles read the movement only')
end)
test('a failing component read cannot interrupt the support cycle',function()
    local h=fixture();h.options.findAll=function()error('native fixture failure')end;h.mod=Body.new(h.options)
    assert(h:run().ok);h:tick(3);assert(h:logged('本体初始化读回')==1 and h:logged('共0个')==2)
    h=fixture();h.options.player=function()error('player lookup failure')end
    local broken=Body.new(h.options);h.mod=broken
    assert(not h:run().ok,'an unreadable player fails the identity check closed')
end)
test('the watch ends after its fixed number of cycles',function()
    local h=fixture();assert(h:run().ok);h:tick(20);local reads=h.reads
    assert(h:logged('复查结束')==1 and h.mod:status().message:find('持续为0',1,true))
    h.counts[HIDE]=1;h:tick(10);assert(h.reads==reads and h.counts[HIDE]==1)
end)
test('a body that left the arena is forgotten',function()
    local h=fixture();assert(h:run().ok);h.mod:tick({});local reads=h.reads
    h:tick(3);assert(h.reads==reads)
end)
test('failed spawn does not leak a request context into normal summons',function()
    local h=fixture();local r=h.mod:spawn({spawn=function()error('native fixture failure')end},'blue',1,'1')
    assert(not r.ok and r.uncertain)
    h.mod:capture(h.actor,Body.path);assert(h.mod:prepare(h.actor)and h.mod:finished(h.actor)and #h.writes==0 and #h.logs==0)
end)
test('all existing batch sizes remain accepted and unload prevents new work',function()
    local h=fixture();local counts={}
    local arena={spawn=function(_,_,_,c)counts[#counts+1]=c;return {ok=true,message='fixture'}end}
    for _,c in ipairs({1,2,4,50,100})do assert(h.mod:spawn(arena,'red',c,'1').ok)end
    assert(not h.mod:spawn(arena,'red',101,'1').ok and #counts==5)
    h.mod:silence();assert(not h.mod:spawn(arena,'red',1,'1').ok)
end)
test('idle body support does not scan or read game state',function()
    local h=fixture();h.options.world=function()error('idle world lookup')end
    for _=1,2000 do h.mod:tick({})end
    assert(h.scans==0 and h.reads==0)
end)
-- A profile for the next tests: two attribute values and two accessory effects.
local function loadoutFixture(accessories)
    local h=fixture();h.effects={};h.applied={}
    local function effect(label)local c=object('Class /Game/GE.'..label);h.effects['/Game/GE.'..label..'_C']=c;return {path='/Game/GE.'..label..'_C',level=1,label=label}end
    h.loadout={revision=9,count=2,attributes={Health_Max=5000,Attack=77},accessories=accessories,effects={effect('Loot'),effect('Guard')}}
    function h.asc:GetGameplayEffectCount(cls)return h.applied[cls]or 0 end
    function h.asc:BP_ApplyGameplayEffectToSelf(cls,level)assert(level==1);if not h.refuse then h.applied[cls]=(h.applied[cls]or 0)+1 end end
    h.options.loadout=function()return h.loadout end
    h.options.loadClass=function(path)return h.effects[path]end
    h.mod=Body.new(h.options)
    return h
end
test('each body keeps the attribute values of the profile it was summoned with',function()
    local h=loadoutFixture(false);assert(h:run().ok)
    local values=h.mod:attributes(h.actor);assert(values.Health_Max==5000 and values.Attack==77)
    assert(h:logged('方案版本=9（请求=1）')==1)
    h.loadout={revision=10,count=1,attributes={Attack=1},accessories=false,effects={}}
    assert(h.mod:attributes(h.actor).Attack==77,'a later save does not reach a body already summoned')
    assert(h.mod:attributes(h.other)==nil)
    local plain=fixture();assert(plain:run().ok and plain.mod:attributes(plain.actor)==nil,'no profile file: nothing to write')
    local empty=loadoutFixture(false);empty.loadout.attributes={};assert(empty:run().ok and empty.mod:attributes(empty.actor)==nil)
end)
test('accessory effects stay off unless the profile turns the trial on',function()
    local h=loadoutFixture(false);assert(h:run().ok);h:tick(3)
    assert(next(h.applied)==nil and h:logged('饰品效果')==0)
end)
test('with the trial on every enabled effect is applied once and read back',function()
    local h=loadoutFixture(true);assert(h:run().ok);assert(next(h.applied)==nil,'not before the first support cycle')
    h:tick(5)
    local total=0;for _,count in pairs(h.applied)do total=total+count end
    assert(total==2 and h:logged('方案启用2条；读回生效2条')==1)
end)
test('an effect the game does not take or a class that does not load is named in the log',function()
    local h=loadoutFixture(true);h.refuse=true;assert(h:run().ok);h:tick(2)
    assert(h:logged('读回生效0条')==1 and h:logged('Loot（调用=true 层数0→0）')==1)
    h=loadoutFixture(true);h.effects['/Game/GE.Guard_C']=nil;assert(h:run().ok);h:tick(2)
    assert(h:logged('读回生效1条')==1 and h:logged('Guard（效果类没载入）')==1)
end)
test('a profile reader that fails does not stop the summon',function()
    local h=fixture();h.options.loadout=function()error('fixture read failure')end;h.mod=Body.new(h.options)
    assert(h:run().ok and h.mod:attributes(h.actor)==nil)
end)
-- The probes and the look step, with a look stand-in that records when it runs.
local function probeFixture(lookApply)
    local h=fixture();h.t=0;h.hpValue=100;h.order={}
    h.options.clock=function()return h.t end
    h.options.hp=function()return h.hpValue end
    h.options.look={apply=function(_,r,still)h.order[#h.order+1]=#h.logs;h.lookStill=still;if lookApply then return lookApply(r,still)end;return {}end,
        recheck=function(_,r)h.rechecked=(h.rechecked or 0)+1 end}
    h.mod=Body.new(h.options)
    return h
end
test('the body is probed before and after the look step, the player once per request, each kind a few lines',function()
    local h=probeFixture();assert(h:run().ok)
    local before=h:logged('动画实例：魂 NPC Hun 1 改前')
    assert(before==1 and h:logged('帽子与材质：魂 NPC Hun 1 改前')==1 and h:logged('骨架：魂 NPC Hun 1 改前')==1)
    assert(h:logged('技能与标签：魂 NPC Hun 1 改前')==1 and h:logged('资源属性：魂 NPC Hun 1 改前')==1)
    assert(h:logged('组件：魂 NPC Hun 1 改前；ExecutionComponent')==1 and h:logged('组件：魂 NPC Hun 1 改前；DeflectComponent')==1)
    assert(h:logged('动画实例：主角（只读）')==1)
    local lastBefore=0;for i,line in ipairs(h.logs)do if line:find('改前',1,true)then lastBefore=i end end
    assert(#h.order==1 and h.order[1]>=lastBefore,'the look step runs after every 改前 probe line')
    assert(h:logged('改后')==0);h:tick(1)
    assert(h:logged('动画实例：魂 NPC Hun 1 改后')==1 and h.rechecked==1 and h:logged('动画实例：主角（只读）')==1)
    h:tick(5);assert(h:logged('改后')==h:logged('NPC Hun 1 改后'),'later cycles do not probe again')
    assert(#h.writes==2,'probes write nothing')
end)
test('a second body of the same request is not probed; a new request probes its first body',function()
    local h=probeFixture()
    h.mod:spawn({spawn=function()
        h.mod:capture(h.actor,Body.path);assert(h.mod:prepare(h.actor) and h.mod:finished(h.actor))
        local other=h.actor;h.actor=object('NPC Hun 2',h.world);h.actor['Actor Config']=h.source;h.actor.AbilitySystemComponent=h.asc
        function h.actor:GetClass()return h.cls end
        h.mod:capture(h.actor,Body.path);assert(h.mod:prepare(h.actor) and h.mod:finished(h.actor))
        h.second=h.actor;h.actor=other
        return {ok=true}
    end},'blue',2,'1')
    assert(h:logged('NPC Hun 1 改前')>0 and h:logged('NPC Hun 2 改前')==0 and #h.order==2,'both bodies get the look step')
    assert(h:logged('动画实例：主角（只读）')==1)
    local before=h:logged('NPC Hun 1 改前')
    assert(h:run().ok and h:logged('NPC Hun 1 改前')>before and h:logged('动画实例：主角（只读）')==2,'a new request probes again')
end)
test('a look step that fails or throws does not hold the birth back',function()
    local h=probeFixture(function()error('native fixture failure')end)
    local r=h:run();assert(r.ok and h:logged('外观与动画中断：实例=NPC Hun 1')==1)
    assert(h.lookStill()==true,'the identity check given to the look step is live')
    h.actor.label='Replacement actor';assert(h.lookStill()==false)
end)
test('a probe that throws writes 探查中断 and the rest still runs',function()
    local h=probeFixture()
    h.options.fname=function(s)if s=='MMGraph'then error('fname fixture failure')end;return s end
    h.mod=Body.new(h.options)
    assert(h:run().ok and #h.order==1)
    assert(h:logged('探查中断：动画实例 原因=')==2,'the body and the player probe each stop once')
    assert(h:logged('技能与标签：魂 NPC Hun 1 改前')==1 and h:logged('资源属性：魂 NPC Hun 1 改前')==1)
end)
test('switching the probe off leaves only the look step',function()
    local h=probeFixture();h.options.steps={probe=false,deathWatch=true};h.mod=Body.new(h.options)
    assert(h:run().ok);h:tick(2)
    assert(h:logged('改前')==0 and h:logged('改后')==0 and #h.order==1)
end)
test('death is read back once a second for at most 15 seconds and only read',function()
    local h=probeFixture();assert(h:run().ok);h:tick(1)
    h.counts['CharacterState.Dead']=1
    function h.actor:IsActorBeingDestroyed()return h.destroying==true end
    h.hpValue=0;h:tick(1)
    assert(h:logged('死亡读回开始：实例=NPC Hun 1')==1 and h:logged('第0秒 HP=0 Dead=1 销毁中=false 有效=true')==1)
    h.t=0.5;h:tick(1);assert(h:logged('死亡读回：')==1,'one line a second')
    h.t=1;h.destroying=true;h:tick(1);assert(h:logged('第1秒 HP=0 Dead=1 销毁中=true 有效=true')==1)
    -- It leaves the arena's list while it dissolves: still read back, without the record.
    h.t=2;h.mod:tick({});assert(h:logged('第2秒')==1)
    h.actor.valid=false;h.t=3;h.mod:tick({});assert(h:logged('第3秒 已无效=true，停止读回')==1)
    h.t=4;h.mod:tick({});assert(h:logged('死亡读回：')==4)
    local writes=#h.writes;assert(writes==2,'nothing written for the death readback')
    local long=probeFixture();assert(long:run().ok);long:tick(1);long.hpValue=0
    for i=0,30 do long.t=i;long:tick(1)end
    assert(long:logged('死亡读回：')==15,'at most 15 lines: '..long:logged('死亡读回：'))
end)
test('the deflect-frame sampler reads ReceiveFrames and the player cooldown, then stops when the body leaves',function()
    local h=probeFixture();local loops,cancelled={},{}
    h.options.loop=function(ms,fn)assert(ms==100);loops[#loops+1]=fn;return #loops end
    h.options.cancel=function(handle)cancelled[handle]=true end
    h.options.now=function()return 10 end
    h.mod=Body.new(h.options)
    local frames={}
    h.actor['Deflect Component']=object('Deflect',h.actor)
    h.actor['Deflect Component'].ReceiveFrames={ForEach=function(_,fn)for k,v in pairs(frames)do fn(k,v)end end}
    local cooldown=0
    local wc=object('PlayerWeapons',h.player);function wc:GetCurrentChangeWeaponCooldown(slot)assert(slot.TagName=='Weapon.Slot.Main');return cooldown end
    h.player['Character Weapons Component']=wc
    assert(h:run().ok);assert(#loops==0,'not before the first support cycle');h:tick(1);assert(#loops==1)
    loops[1]();assert(h:logged('预告：')==0,'no line for an empty sample before the heartbeat')
    frames[7]={HitGameTime=10.25,IsDodge=false,CounterAbility=object('Class /Game/GA_Counter_C')}
    h.t=1;loops[1]();assert(h:logged('预告：魂 NPC Hun 1；条数=1；已采样2次 有预告1次；距命中=0.25 闪避=false')==1)
    h.t=1.5;loops[1]();assert(h:logged('预告：')==1,'one line a second')
    cooldown=15;h.t=2;loops[1]();assert(h:logged('只读玩家 换武器冷却=15')==1)
    h.t=3;loops[1]();assert(h:logged('只读玩家 换武器冷却')==1,'the same value is not logged again')
    h.mod:tick({});assert(cancelled[1] and h:logged('预告采样结束：实例离场')==1)
end)
test('statsFor: a Hun body takes its profile or the game numbers, never the arena or companion set',function()
    local known={Health_Max=true,Attack=true}
    local arenaSet,hunSet={name='arena'},{name='hun'}
    local s,dropped,source=Body.statsFor(false,{Attack=5},known,arenaSet,hunSet)
    assert(s==arenaSet and dropped==0 and source==nil,'other units keep the arena set')
    s,dropped,source=Body.statsFor(true,nil,known,arenaSet,hunSet)
    assert(s==Body.KEEP_STATS and source=='游戏原值' and s:onSpawn().ok and s:onSummon().ok,'an empty profile keeps the game numbers')
    s,dropped,source=Body.statsFor(true,{},known,arenaSet,hunSet);assert(s==Body.KEEP_STATS)
    s,dropped,source=Body.statsFor(true,{Unknown=3},known,arenaSet,hunSet);assert(s==Body.KEEP_STATS and dropped==1)
    s,dropped,source=Body.statsFor(true,{Attack=77,Unknown=1},known,arenaSet,hunSet)
    assert(s==hunSet and hunSet.mode=='custom' and hunSet.custom.Attack==77 and hunSet.custom.Unknown==nil and dropped==1 and source=='方案')
end)
test('owns: only bodies this module summoned and still follows',function()
    local h=fixture();assert(h:run().ok)
    assert(h.mod:owns(h.actor) and not h.mod:owns(h.other) and not h.mod:owns(nil))
    h.mod:tick({});assert(not h.mod:owns(h.actor))
end)
print('hun body: PASS '..n..' scoped-instance/tag/lifecycle/profile checks; native gameplay remains unverified')
