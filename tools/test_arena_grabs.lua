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
test('a living companion opens grabs from a team NPC before an arena fight',function()
    local h=harness()
    local companion=h.members[2]
    companion.team='companion'
    companion.class_path=ROOT..'Beta/BP_Companion.BP_Companion_C'
    assert(h.grabs:sync(h.members,false,true))
    assert(h.own.NonPlayerGE==h.emptyClass and h.other.NonPlayerGE==h.emptyClass)
    assert(h.player.NonPlayerGE==h.original,'unrelated player assets stay untouched')
    h.red.hp=0
    assert(h.grabs:sync(h.members,false,true))
    assert(h.own.NonPlayerGE==h.original and h.other.NonPlayerGE==h.original)
    h.red.hp=100
    companion.stand=true
    assert(h.grabs:sync(h.members,false,true) and h.own.NonPlayerGE==h.original,
        'a visual stand is not a live companion target')
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
local RENEWAL='/Game/RenewalContent/Actors/Mobs/Normal/'
-- Abilities granted to a unit, as its ability system lists them.
local function grant(h,actor,root)
    local ability=h:object(root..'Ability/GA_X.Default__GA_X_C')
    actor.AbilitySystemComponent=h:object(actor.path..'.ASC',{ActivatableAbilities={Items={{Ability=ability}}}})
end
test('an opponent whose class is outside the data folders still opens the grabber events',function()
    local h=harness();h.members[2].class_path=RENEWAL..'BP_Monster_MBoss.BP_Monster_MBoss_C'
    assert(h.grabs:sync(h.members,true,true))
    assert(h.own.NonPlayerGE==h.emptyClass,'魔渊 against 荒行子: the fight runs, so 魔渊 grabs')
    assert(h.other.NonPlayerGE==h.original)
end)
test('a unit whose class is outside the data folders is found through its abilities',function()
    local h=harness();local gamma=h:event('Grab',ROOT..'Gamma/',h.original)
    h.members[1].class_path=RENEWAL..'BP_Monster_PowerMan.BP_Monster_PowerMan_C';grant(h,h.blue,ROOT..'Gamma/')
    assert(h.grabs:sync(h.members,true,true))
    assert(gamma.NonPlayerGE==h.emptyClass and h.own.NonPlayerGE==h.emptyClass,'力者 grabs, and so does the other side')
    assert(h.grabs:restore() and gamma.NonPlayerGE==h.original)
end)
test('abilities granted after the first look are read again',function()
    local h=harness();local gamma=h:event('Grab',ROOT..'Gamma/',h.original)
    h.members[1].class_path=RENEWAL..'BP_Monster_PowerMan.BP_Monster_PowerMan_C'
    h.grabs:sync(h.members,true,true);assert(gamma.NonPlayerGE==h.original)
    grant(h,h.blue,ROOT..'Gamma/')
    for _=1,10 do h.grabs:sync(h.members,true)end
    assert(gamma.NonPlayerGE==h.emptyClass,'read again while nothing was found')
end)
test('units coming and going within the same folders neither restore nor rescan',function()
    local h=harness();h.grabs:sync(h.members,true,true)
    local scans,logs=h.scans,#h.logs
    local summon=h:object('/Game/World:Summon',{hp=100})
    h.members[3]={actor=summon,team='red',class_path=ROOT..'Alpha/BP_Summon.BP_Summon_C'}
    h.grabs:sync(h.members,true);summon.hp=0;h.grabs:sync(h.members,true);h.members[3]=nil;h.grabs:sync(h.members,true)
    assert(h.scans==scans and #h.logs==logs and h.own.NonPlayerGE==h.emptyClass,table.concat(h.logs,'\n',logs+1))
end)
-- 1-5: 毕峰, 彭猛 and 火流星 grab through GetPlayerCharacter(0) for their QTE. Facing a Hun body they keep NonPlayerGE.
local function qteCase(familyFolder)
    local h=harness()
    local qte=h:event('Grab',ROOT..familyFolder,h.original)
    h.hun=h:object('/Game/World:Hun',{hp=100})
    h.members={{actor=h.hun,team='blue',class_path='/PBZCombatAsset/ActorData/Mobs/000_Hun/BP_Monster_Hun.BP_Monster_Hun_C'},
        {actor=h.red,team='red',class_path=ROOT..familyFolder..'BP_Boss.BP_Boss_C'},
        {actor=h.blue,team='blue',class_path=ROOT..'Alpha/BP_Blue.BP_Blue_C'}}
    h.options.isHun=function(actor)return actor==h.hun end
    h.grabs=h:new()
    return h,qte
end
test('a QTE family facing a Hun body keeps its NonPlayerGE; other families are still opened',function()
    for _,folder in ipairs({'008_GreatBladeMan/','044_PengMeng/','069_GuiChai_Red/','075_GuiChai_Red_P2/'})do
        local h,qte=qteCase(folder)
        assert(h.grabs:sync(h.members,true,true))
        assert(qte.NonPlayerGE==h.original,'held: '..folder)
        assert(h.own.NonPlayerGE==h.emptyClass,'the Hun\'s teammates and their family are opened as before')
        local logged=0;for _,line in ipairs(h.logs)do if line:find('[NPCGrab] QTE 族对魂暂不完整抓取：',1,true) and line:find(ROOT..folder,1,true)then logged=logged+1 end end
        assert(logged==1,'logged once: '..table.concat(h.logs,'\n'))
        h.grabs:sync(h.members,true);h.grabs:sync(h.members,true)
        logged=0;for _,line in ipairs(h.logs)do if line:find('QTE 族',1,true)then logged=logged+1 end end
        assert(logged==1,'not logged again while nothing changes')
    end
end)
test('the gate opens when the Hun body is gone, and the family is cleared then; without a Hun nothing changes',function()
    local h,qte=qteCase('008_GreatBladeMan/')
    assert(h.grabs:sync(h.members,true,true) and qte.NonPlayerGE==h.original)
    h.hun.hp=0
    assert(h.grabs:sync(h.members,true))
    assert(qte.NonPlayerGE==h.emptyClass,'no Hun left: the 毕峰 events are opened as for any NPC')
    local opened=false;for _,line in ipairs(h.logs)do if line:find('QTE 族闸解除',1,true)then opened=true end end;assert(opened)
    h.hun.hp=100
    assert(h.grabs:sync(h.members,true) and qte.NonPlayerGE==h.original,'a Hun back: the event is restored before the rescan')
    local plain,qte2=qteCase('044_PengMeng/');plain.options.isHun=nil;plain.grabs=plain:new()
    assert(plain.grabs:sync(plain.members,true,true) and qte2.NonPlayerGE==plain.emptyClass)
    for _,line in ipairs(plain.logs)do assert(not line:find('QTE 族',1,true),line)end
end)
test('a QTE family on the Hun body\'s own side is not held, and the switch off holds nothing',function()
    local h,qte=qteCase('044_PengMeng/')
    h.members[2].class_path=ROOT..'Alpha/BP_Red.BP_Red_C'
    h.members[3].class_path=ROOT..'044_PengMeng/BP_PengMeng.BP_PengMeng_C'
    assert(h.grabs:sync(h.members,true,true) and qte.NonPlayerGE==h.emptyClass,'彭猛 with the Hun grabs the other side as before')
    local steps=require('hun_look').STEPS;steps.qteGate=false
    local off,qte3=qteCase('008_GreatBladeMan/')
    local ok=off.grabs:sync(off.members,true,true);steps.qteGate=true
    assert(ok and qte3.NonPlayerGE==off.emptyClass)
end)
test('Yu Ding chooses the native nonlethal branch only against living protected arena victims',function()
    local h=harness();local world=h:object('/Map');local player=h:object('/Map/Player')
    local jadeRoot=ROOT..'YuDing_00/'
    local sourcePath=jadeRoot..'BP_Monster_FemaleVessel_YuDing.BP_Monster_FemaleVessel_YuDing_C'
    local hooks={};local inThread=true;local floor,max=6400,8000
    h.options.staticFind=function(path)return h:object(path)end
    h.options.registerHook=function(path,cb)hooks[path]=cb;return 21,22 end
    h.options.unregisterHook=function(path)hooks[path]=nil;return true end
    h.options.inGameThread=function()return inThread end;h.options.world=function()return world end
    h.options.player=function()return player end
    local attrs=h:object('/Map/Blue.Attrs',{GetOuter=function()return h.blue end})
    h.blue.AttributeSetBase=setmetatable(attrs,{__index=function(_,field)
        local value=field=='Health_Max' and max or field=='Health_Min' and floor
        if type(value)=='number' then return {BaseValue=value,CurrentValue=value} end
    end})
    local function typed(obj,path)
        local cls=h:object(path,nil,'LegoAbilityBlueprintGeneratedClass');obj.GetClass=function()return cls end
        obj.GetOuter=function()return world end
    end
    local event=h:event('Jade',jadeRoot,h.original)
    for _,spec in ipairs({{'054_ZuoShang','BP_Monster_ZuoShang',8000,6400},{'078_MengHua','BP_Monster_MengHua',871200,357192}})do
        max,floor=spec[3],spec[4];h.blue.hp=max
        local targetPath=ROOT..spec[1]..'/'..spec[2]..'.'..spec[2]..'_C'
        typed(h.red,sourcePath);typed(h.blue,targetPath);h.members[1].class_path=targetPath;h.members[2].class_path=sourcePath
        h.grabs=h:new();assert(h.grabs:sync(h.members,true,true));assert(event.NonPlayerGE==h.emptyClass)
        local paths=require('jade_grab_guard').paths
        for ix=1,2 do
            local ka=paths[ix]:match('^(.*):IsKill$');local target=h.blue
            local ability=h:object('grab'..ix,{bIsActive=true,GetAvatarActorFromActorInfo=function()return h.red end,
                ['Lock Target']={Component=h:object('Root',{GetOwner=function()return target end})},
                ['Execution Info']={Executor=h.red,Target=h.blue}});typed(ability,ka)
            local out={value=true,type=function()return 'RemoteUnrealParam'end,get=function(self)return self.value end,set=function(self,v)self.value=v end}
            if ix==2 then
                local component=ability['Lock Target'].Component
                ability['Lock Target'].Component={type=function()return 'TWeakObjectPtr' end,Get=function()return component end}
            end
            local callback=assert(hooks[paths[ix]])
            callback(ability,out);assert(out.value==false,'use the native nonlethal branch even above the protected floor')
            target=player;out.value=true;callback(ability,out);assert(out.value,'real player remains native')
            target=h.blue;floor=1;callback(ability,out);assert(out.value,'the ordinary final floor is not a phase lock')
            floor=spec[4];inThread=false;callback(ability,out);assert(out.value);inThread=true
        end
        local victim=h:object('receiver',{bIsActive=true,GetAvatarActorFromActorInfo=function()return h.blue end,
            ['Execution Info']={Executor=h.red,Target=h.blue}})
        typed(victim,jadeRoot..'Ability/Abilities/Grab/GA_YuDing_GEd_01.GA_YuDing_GEd_01_C')
        local owner=h.blue;local stops=0
        local slow=h:object('slow',{Multiplier=0.01,['Slomo ID']='Ability',GetAbility=function()return victim end,
            Handles={ForEach=function(_,visit)visit(owner,{})end},['Stop Slomo Handles']=function()stops=stops+1 end})
        typed(slow,paths[3]:match('^(.*):'))
        local cb=assert(hooks[paths[3]]);cb(slow);assert(stops==1)
        owner=player;cb(slow);assert(stops==1,'other slow handles never touched')
        owner=h.blue;slow.Multiplier=0.5;cb(slow);assert(stops==1,'other hit stops remain native')
        slow.Multiplier=0.01;h.blue.hp=0;cb(slow);assert(stops==1,'a genuinely dead victim keeps the native finale')
        h.blue.hp=max;assert(h.grabs:restore());cb(slow);assert(stops==1,'retained callbacks are inert after stop')
        assert(h.grabs:sync(h.members,true,true));cb(slow);assert(stops==1,'a retired callback cannot act in the next fight')
        assert(h.grabs:restore())
    end
    h.options.registerHook=function()return nil,nil end
    h.grabs=h:new();assert(h.grabs:sync(h.members,true,true))
    for _,event in ipairs(h.events)do if event.path:find(jadeRoot,1,true) then assert(event.NonPlayerGE==h.original) end end
end)
print('arena_grabs: PASS ('..count..' scope, native observation and restoration regressions)')
