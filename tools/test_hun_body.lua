package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Body=require('hun_body')
local index=0
local function object(label,outer)
    index=index+1;local id=index;local a={label=label,outer=outer,valid=true}
    function a:IsValid()return self.valid end
    function a:GetFullName()assert(self.valid);return self.label end
    function a:GetOuter()assert(self.valid);return self.outer end
    function a:GetAddress()assert(self.valid);return id end
    return a
end
local function fixture()
    local h={logs={}}
    FName=function(s)return s end
    h.world=object('World');h.player=object('Player',h.world)
    h.native=object('Class /Script/ProjectPBZ.PBZCharacter_NPC');function h.native:GetSuperStruct()return nil end
    h.cls=object('BlueprintGeneratedClass '..Body.path);function h.cls:GetSuperStruct()return h.native end
    h.cfgClass=object('Class Config');function h.cfgClass:IsAnyClass()return true end
    h.source=object('Config /PBZCombatAsset/ActorData/Mobs/000_Hun/ActorConfig/ActorC_Monster_Hun.ActorC_Monster_Hun')
    h.source.InitialTags={GameplayTags={{TagName='AI.Hatred.CanNotBeHatred'},{TagName='CharacterState.Unselectable.Force.Hide'},{TagName='CharacterType.AI.Boss'}},ParentTags={}}
    function h.source:GetClass()return h.cfgClass end
    h.actor=object('NPC Hun 1',h.world);h.actor['Actor Config']=h.source
    function h.actor:GetClass()return h.cls end
    h.options={world=function()return h.world end,player=function()return h.player end,log=function(s)h.logs[#h.logs+1]=s end,
        hp=function()return 100 end,aiOf=function()return object('AI')end,
        construct=function(cls,actor,n,a,b,c,d,template)
            local copy=object('Config Private',actor);function copy:GetClass()return cls end
            local tags={};for _,t in ipairs(template.InitialTags.GameplayTags)do tags[#tags+1]={TagName=t.TagName}end
            copy.InitialTags={GameplayTags=tags,ParentTags={}};h.private=copy
            if h.shared then copy.InitialTags=template.InitialTags end
            if h.afterCopy then h.afterCopy()end
            return copy
        end,container=function(values)return {GameplayTags=values,ParentTags={}}end}
    h.mod=Body.new(h.options)
    function h:run()
        return self.mod:spawn({spawn=function(_,path,team,count)
            assert(path==Body.path);self.mod:capture(self.actor,path)
            local ok,why=self.mod:prepare(self.actor)
            if ok then ok,why=self.mod:finished(self.actor)end
            return {ok=ok,message=why or'',spawned_count=1}
        end},'blue',1,'1')
    end
    return h
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end
test('only scoped body requests receive a private config',function()
    local h=fixture();h.mod:capture(h.actor,Body.path);assert(h.mod:prepare(h.actor));assert(h.actor['Actor Config']==h.source)
    local r=h:run();assert(r.ok);assert(h.actor['Actor Config']==h.private and #h.private.InitialTags.GameplayTags==1)
    assert(#h.source.InitialTags.GameplayTags==3 and h.private.InitialTags.GameplayTags[1].TagName=='CharacterType.AI.Boss')
    assert(h.mod:status().full_ready==false)
end)
test('shared native arrays fail before mutating templates',function()
    local h=fixture();h.shared=true;assert(not h:run().ok);assert(h.actor['Actor Config']==h.source and #h.source.InitialTags.GameplayTags==3)
end)
test('player and wrong-world identities fail closed',function()
    local h=fixture();h.player=h.actor;assert(not h:run().ok and h.actor['Actor Config']==h.source)
    h=fixture();h.actor.outer=object('Other world');assert(not h:run().ok)
end)
test('identity changes during construction prevent config binding',function()
    local h=fixture();h.afterCopy=function()h.actor.label='Replacement actor'end
    assert(not h:run().ok and h.actor['Actor Config']==h.source)
end)
test('world change during construction cannot affect new scene',function()
    local h=fixture();h.afterCopy=function()h.world=object('new world')end
    assert(not h:run().ok and h.actor['Actor Config']==h.source)
end)
test('stop during construction cancels deferred configuration',function()
    local h=fixture();h.afterCopy=function()h.mod:cancel()end
    assert(not h:run().ok and h.actor['Actor Config']==h.source)
end)
test('unconfirmed finish refuses success and retains ownership responsibility',function()
    local h=fixture();assert(h:run().ok);h.actor['Actor Config']=h.source
    assert(not h.mod:finished(h.actor))
end)
test('failed spawn does not leak a request context into normal summons',function()
    local h=fixture();local r=h.mod:spawn({spawn=function()error('native fixture failure')end},'blue',1,'1')
    assert(not r.ok and r.uncertain)
    h.mod:capture(h.actor,Body.path);assert(h.mod:prepare(h.actor)and h.actor['Actor Config']==h.source)
end)
test('all existing batch sizes remain accepted and unload prevents new work',function()
    local h=fixture();local counts={}
    local arena={spawn=function(_,_,_,c)counts[#counts+1]=c;return {ok=true,message='fixture'}end}
    for _,c in ipairs({1,2,4,50,100})do assert(h.mod:spawn(arena,'red',c,'1').ok)end
    assert(not h.mod:spawn(arena,'red',101,'1').ok and #counts==5)
    h.mod:silence();assert(not h.mod:spawn(arena,'red',1,'1').ok)
end)
test('idle body support does not scan or mutate game state',function()
    local h=fixture();h.options.world=function()error('idle world lookup')end
    for _=1,2000 do h.mod:tick({})end
end)
print('hun body: PASS '..n..' scoped-instance/config/lifecycle checks; native gameplay remains unverified')
