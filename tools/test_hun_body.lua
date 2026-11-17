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
test('mesh components are listed once per request and only for this body',function()
    local h=fixture();assert(h:run().ok);h:tick(4)
    assert(h.scans==3 and h:logged('网格组件：实例=NPC Hun 1；共3个')==1)
    assert(h:logged('SkeletalMeshComponent Body 资源=SK_Body 可见=true')==1 and h:logged('StaticMeshComponent Head 资源=SM_Head')==1)
    assert(h:logged('StaticMeshComponent Mesh（挂件） 资源=SM_Hat')==1 and h:logged('SK_Other')==0)
end)
test('a failing component read cannot interrupt the support cycle',function()
    local h=fixture();h.options.findAll=function()error('native fixture failure')end;h.mod=Body.new(h.options)
    assert(h:run().ok);h:tick(3);assert(h:logged('本体初始化读回')==1 and h:logged('共0个')==1)
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
print('hun body: PASS '..n..' scoped-instance/tag/lifecycle checks; native gameplay remains unverified')
