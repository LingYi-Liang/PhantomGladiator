package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Grabs=require('arena_grabs')
local ROOT='/PBZCombatAsset/ActorData/Mobs/'
local GE='/PBZCombatAsset/Prototypes/GameplayEffects/Inflictions/GE_GrabHit.GE_GrabHit_C'
local EVENT='/SGameExecution/Bullet/Events/BP_BulletEvent_Grab.BP_BulletEvent_Grab_C'
local function harness()
    local h={objects={},files={},events={},logs={},scans=0};local serial=100
    function h:object(path,fields,kind)
        serial=serial+1;local o=fields or {};o.alive=true;o.path=path;o.key=serial;o.kind=kind or 'Object'
        function o:IsValid()return self.alive end
        function o:GetAddress()assert(self.alive);return self.key end
        function o:GetFullName()assert(self.alive);return self.kind..' '..self.path end
        function o:IsAnyClass()assert(self.alive);return self.kind=='Class' end
        h.objects[path]=o;return o
    end
    h.eventClass=h:object(EVENT,nil,'Class');h.original=h:object(GE,nil,'Class')
    h.emptyClass=h:object('/NullClass',nil,'Class');h.emptyClass.alive=false
    function h.emptyClass:type()return 'UClass' end
    h.cdo=h:object(EVENT..'.Default',{NonPlayerGE=h.emptyClass})
    function h.eventClass:GetCDO()return h.cdo end
    function h:event(name,root,original)
        local o=self:object(root..'Ability/BD_'..name..'.BD_'..name..':BP_BulletEvent_Grab_C_0')
        local data={NonPlayerGE=original or self.emptyClass}
        setmetatable(o,{__index=data,__newindex=function(t,k,v)
            if k=='NonPlayerGE' then assert(v~=nil,'ClassProperty requires an object wrapper');data[k]=v else rawset(t,k,v)end
        end})
        function o:GetClass()assert(self.alive);return h.eventClass end
        self.events[#self.events+1]=o;return o
    end
    h.own=h:event('Grab',ROOT..'Alpha/',h.original)
    h.other=h:event('Grab',ROOT..'Beta/',h.original)
    h.player=h:event('Grab','/PBZCombatAsset/ActorData/Players/Hun/',h.original)
    h.nativeNpc=h:event('ToNpc',ROOT..'Alpha/',nil)
    h.blue=h:object('/Game/World:Blue',{hp=100})
    h.red=h:object('/Game/World:Red',{hp=100})
    h.members={{actor=h.blue,team='blue',class_path=ROOT..'Alpha/BP_Blue.BP_Blue_C'},
        {actor=h.red,team='red',class_path=ROOT..'Alpha/BP_Red.BP_Red_C'}}
    local fs={open=function(name,mode)
        if mode=='w' and h.failWrite then return nil end
        if mode=='r' and not h.files[name] then return nil end
        local text=h.files[name] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[name]=text end;return true end}
    end}
    StaticFindObject=function(name)return h.objects[name]end
    LoadAsset=function(name)assert(name==GE);h.original=h:object(GE,nil,'Class');return h.original end
    h.options={path='memory',io=fs,ready=function()return true end,hp=function(o)assert(o.alive);return o.hp end,
        findEvents=function()h.scans=h.scans+1;return h.events end,log=function(s)h.logs[#h.logs+1]=s end}
    function h:new()return Grabs.new(self.options)end
    h.grabs=h:new();return h
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('only confirmed fallback on participating NPC asset families is changed and restored',function()
    local h=harness();assert(h.grabs:sync(h.members,true,true))
    assert(h.own.NonPlayerGE==h.emptyClass and h.other.NonPlayerGE==h.original and h.player.NonPlayerGE==h.original)
    assert(h.nativeNpc.NonPlayerGE==h.emptyClass and h.grabs:status().events==1)
    assert(h.files['memory/npc-grab-policy.tsv']:find(h.own.path,1,true),'restore identity must be persisted')
    assert(h.grabs:restore() and h.own.NonPlayerGE==h.original and h.grabs:status().events==0)
    assert(h.files['memory/npc-grab-policy.tsv']=='NPCGrabPolicyV1\n')
end)
test('a companion out of any fight gets full grabs on map enemies until it is dismissed',function()
    local h=harness()
    local companion={{actor=h.blue,team='companion',class_path=ROOT..'Alpha/BP_Blue.BP_Blue_C'}}
    assert(h.grabs:sync(companion,false,true))
    assert(h.own.NonPlayerGE==h.emptyClass and h.other.NonPlayerGE==h.original and h.player.NonPlayerGE==h.original)
    assert(h.grabs:sync({},false) and h.own.NonPlayerGE==h.original,'dismissed: the shared event is restored')
    h.members[2].team='neutral'
    assert(h.grabs:sync(h.members,true,true) and h.own.NonPlayerGE==h.original,'a lone Blue unit without Red still enables nothing')
end)
test('inactive battle, neutral actors and missing live opponents do not enable grabs',function()
    local h=harness();h.grabs:sync(h.members,false,true);assert(h.scans==0)
    h.members[2].team='neutral';h.grabs:sync(h.members,true,true);assert(h.scans==0)
    h.members[2].team='red';h.red.hp=0;h.grabs:sync(h.members,true,true);assert(h.scans==0)
end)
test('journal write failure prevents a shared asset mutation',function()
    local h=harness();h.failWrite=true;h.grabs:sync(h.members,true,true)
    assert(h.own.NonPlayerGE==h.original and h.grabs:status().events==0)
end)
test('hot reload restores saved asset values before permitting new work',function()
    local h=harness();h.grabs:sync(h.members,true,true)
    local reloaded=h:new();assert(reloaded:status().restore_pending)
    assert(reloaded:sync({},false) and h.own.NonPlayerGE==h.original and not reloaded:status().restore_pending)
end)
test('replaced asset instance is never overwritten by an old journal',function()
    local h=harness();h.grabs:sync(h.members,true,true);h.own.alive=false
    local replacement=h:event('Grab',ROOT..'Alpha/',nil)
    assert(h.grabs:restore() and replacement.NonPlayerGE==h.emptyClass)
end)
test('roster change restores families no longer in the battle',function()
    local h=harness();h.grabs:sync(h.members,true,true)
    for _,member in ipairs(h.members)do member.class_path=member.class_path:gsub('/Alpha/','/Beta/')end
    h.grabs:sync(h.members,true)
    assert(h.own.NonPlayerGE==h.original and h.other.NonPlayerGE==h.emptyClass)
end)
test('no per-frame discovery and no repeated writes to already empty fields',function()
    local h=harness();h.grabs:sync(h.members,true,true)
    local file=h.files['memory/npc-grab-policy.tsv']
    for _=1,8 do h.grabs:sync(h.members,true)end
    assert(h.scans==1 and h.files['memory/npc-grab-policy.tsv']==file)
end)
test('only actual active native handles on two owned actors count as a paired execution',function()
    local h=harness()
    local function component(actor,isTarget,ownHandle)
        local asc=h:object(actor.path..'.ASC',{ActivatableAbilities={Items={{Handle={Handle=ownHandle},ActiveCount=1}}}})
        local c=h:object(actor.path..'.Execution',{AbilitySystem=asc,CurrentExecutionInfo={Executor=h.blue,Target=h.red,
            IsTarget=isTarget,ExecutionHandle={Handle=7},ExecutedHandle={Handle=8}}})
        function c:GetOwner()return actor end
        actor['Execution Component']=c;return asc
    end
    local a,b=component(h.blue,false,7),component(h.red,true,8)
    h.grabs:sync(h.members,true,true);assert(h.grabs:status().observed_pairs==1)
    a.ActivatableAbilities.Items[1].ActiveCount=0;b.ActivatableAbilities.Items[1].ActiveCount=0
    h.grabs:sync(h.members,true)
    assert(table.concat(h.logs,'\n'):find('active_count=0',1,true),'native completion must be observable')
    assert(h.blue.hp==100 and h.red.hp==100,'the mod must not synthesize grab damage')
end)
print('arena_grabs: PASS ('..count..' scope, native observation and restoration regressions)')
