-- 真正加载当前主程序及全部Lua模块；只替换引擎入口，不接触游戏进程。
local root=assert(arg[1],"pass an isolated existing Runtime directory")
local scripts="Mods/PhantomGladiator/Scripts/"
package.path=scripts.."?.lua;"..package.path
local cfg=assert(loadfile(scripts.."config.lua"))()
local actorMode=arg[2]=='actor'
if actorMode then cfg.KnownMonsterClasses={'/Test/BP_SequenceActor.BP_SequenceActor_C'} end
cfg.RuntimePath=root
cfg.CatalogPath=root.."/known-classes.tsv"
package.loaded.config=cfg
local logs,keys,queue,loops,loads={},{},{},{},{}
local originalPrint=print
print=function(message) logs[#logs+1]=tostring(message) end
Key={};for i=1,24 do Key['F'..i]=111+i end;for i=65,90 do Key[string.char(i)]=i end
ModifierKey={CONTROL=1,ALT=2,SHIFT=4}
local shared={}
ModRef={GetSharedVariable=function(_,key) return shared[key] end,
    SetSharedVariable=function(_,key,value) shared[key]=value end}
local inGame=false
IsInGameThread=function() return inGame end
local function keySlot(key,mods)local mask=0;for _,value in ipairs(mods or {})do mask=mask+value end;return key..':'..mask end
IsKeyBindRegistered=function(key,modifiers) return keys[keySlot(key,modifiers)]~=nil end
RegisterKeyBind=function(key,second,third)keys[keySlot(key,third and second or nil)]=third or second end
ExecuteInGameThread=function(callback) queue[#queue+1]=callback end
LoopInGameThreadWithDelay=function(_,callback) loops[#loops+1]=callback; return #loops end
-- The hotkeys' frame loop (key_poll.lua), kept apart from the timers.
local frameLoops={}
LoopInGameThreadAfterFrames=function(frames,callback) assert(frames==1);frameLoops[#frameLoops+1]=callback;return 'frame'..#frameLoops end
CancelDelayedAction=function() end
ExecuteInGameThreadWithDelay=function() error("no delayed UE work expected during empty-world boot") end
-- Filled in below: the player controller the hotkeys are read from.
local controllers={}
FindAllOf=function(name) assert(inGame,"UObject lookup outside game thread"); return name=='PlayerController' and controllers or {} end
FindObjects=function() assert(inGame); return {} end
local known=cfg.KnownMonsterClasses[1]
local base={IsValid=function() return true end,GetFullName=function() return actorMode and 'Class /Script/Engine.Actor' or "Class /Script/ProjectPBZ.PBZCharacter_NPC" end}
local cls={IsValid=function() return true end,IsAnyClass=function() return true end,
    GetFullName=function() return "BlueprintGeneratedClass "..known end,GetSuperStruct=function() return base end}
local loaded=false
local genericCalls={}
local genericActor={IsValid=function()return true end,IsActorBeingDestroyed=function()return false end,GetFullName=function()return 'BP_SequenceActor /Test/World.Actor' end,
    GetAddress=function()return 77 end}
local gameplay={IsValid=function()return true end,
    BeginDeferredActorSpawnFromClass=function(_,w,c,t,collision,owner,scale)
        assert(inGame and c==cls and collision==1 and owner==nil and scale==1)
        genericCalls[#genericCalls+1]='begin';return genericActor
    end,
    FinishSpawningActor=function(_,actor,t,scale)
        assert(inGame and actor==genericActor and scale==1 and genericCalls[1]=='begin')
        genericCalls[#genericCalls+1]='finish';return actor
    end}
StaticFindObject=function(path) assert(inGame); if path==known and loaded then return cls end
    if actorMode and path=='/Script/Engine.Default__GameplayStatics' then return gameplay end end
LoadAsset=function(path) assert(inGame); loads[#loads+1]=path; loaded=true; return cls,true,true end
local player={alive=false,AttributeSetBase={IsValid=function() return true end,Health={CurrentValue=100}}}
function player:IsValid() return self.alive end
function player:GetAddress()return 101 end
function player:IsActorBeingDestroyed() return false end
function player:K2_GetActorLocation() return {X=0,Y=0,Z=100} end
function player:GetActorForwardVector() return {X=1,Y=0,Z=0} end
local world={IsValid=function() return true end,GetAddress=function() return 100 end}
function player:GetWorld()return world end
local pc={IsValid=function() return true end,Pawn=player}
-- Keys as the engine reports them: `pressed` holds the names down in this frame.
local pressed={}
FName=FName or function(name)return {ToString=function()return name end}end
local controllerClass={IsValid=function()return true end,GetFullName=function()return 'Class /Script/ProjectPBZ.PBZPlayerController' end,
    GetFName=function()return {ToString=function()return 'PBZPlayerController' end}end}
local keyController={IsValid=function()return true end,GetClass=function()return controllerClass end,
    GetFullName=function()return 'PBZPlayerController /Test/World.Controller' end,
    Player={IsValid=function()return true end},Pawn=player,
    GetInputAnalogKeyState=function(_,key)assert(inGame,'key read outside game thread');return pressed[key.KeyName:ToString()] and 1.0 or 0.0 end,
    WasInputKeyJustPressed=function(_,key)assert(inGame,'key read outside game thread');return pressed[key.KeyName:ToString()]==true end}
controllers[1]=keyController
function keyController:GetAddress()return 201 end
function keyController:GetWorld()return world end
function keyController.Player:GetAddress()return 202 end
keyController.Player.PlayerController=keyController
-- One frame with the keys down, then one with them up.
local function press(...)
    for _,name in ipairs({...})do pressed[name]=true end
    inGame=true;frameLoops[1]();pressed={};frameLoops[1]();inGame=false
end
package.loaded.UEHelpers={GetPlayerController=function() return pc end,GetWorld=function() return world end,
    GetGameViewportClient=function()return {IsValid=function()return true end,World=world}end}
local arenaOptions,statMatchInstance,companionStatsInstance,spectatorOptions,runtimeInstance
local Arena=require('arena_controller');local realArenaNew=Arena.new
Arena.new=function(options)arenaOptions=options;return realArenaNew(options)end
local Match=require('stat_match');local realMatchNew=Match.new
Match.new=function(options)
    local made=realMatchNew(options)
    if options.customOnly then companionStatsInstance=made else statMatchInstance=made end
    return made
end
local Spectator=require('spectator_mode');local realSpectatorNew=Spectator.new
Spectator.new=function(options)spectatorOptions=options;return realSpectatorNew(options)end
local Runtime=require('panel_runtime');local realRuntimeNew=Runtime.new
local supportLoop
Runtime.new=function(options)supportLoop=options.support;runtimeInstance=realRuntimeNew(options);return runtimeInstance end
local StandKeep=require('stand_keep');local realKeepNew=StandKeep.new
local keepOptions,keepTicks=nil,0
StandKeep.new=function(options)
    keepOptions=options
    local made=realKeepNew(options)
    local tick=made.tick
    made.tick=function(self)keepTicks=keepTicks+1;return tick(self)end
    return made
end
-- What the summon scan finds goes to the arena with its side (arena_summon_links.lua opposing -> 'opposing').
local adoptCalls,fakeLinks={},{}
local arenaInstance,unitKeyOptions
local UnitKeys=require('unit_keybinds')
local realUnitKeysNew=UnitKeys.new
UnitKeys.new=function(options)unitKeyOptions=options;return realUnitKeysNew(options)end
local wrappedArenaNew=Arena.new
Arena.new=function(options)
    local made=wrappedArenaNew(options)
    arenaInstance=made
    local adopt=made.adoptSummon
    made.adoptSummon=function(self,...)adoptCalls[#adoptCalls+1]=table.pack(...);return adopt(self,...)end
    return made
end
local Links=require('arena_summon_links');local realLinksNew=Links.new
Links.new=function(options)
    local made=realLinksNew(options)
    local scan=made.scan
    made.scan=function(self,members,onPassive)if #fakeLinks>0 then return fakeLinks end;return scan(self,members,onPassive)end
    return made
end
-- Finishers ask story_writes before a move that writes story progress; the 龙柱 check runs in the support loop.
local execOptions
local Execs=require('arena_executions');local realExecsNew=Execs.new
Execs.new=function(options)execOptions=options;return realExecsNew(options)end
local Writes=require('story_writes');local realWritesNew=Writes.new
local writesOptions,writesAsked
Writes.new=function(options)
    writesOptions=options
    local made=realWritesNew(options)
    local allows=made.allows
    made.allows=function(self,ability)writesAsked=ability;return allows(self,ability)end
    return made
end
local LongZhu=require('longzhu_check');local realLongZhuNew=LongZhu.new
local longzhuOptions,longzhuTicks,longzhuInstance=nil,0,nil
LongZhu.new=function(options)
    longzhuOptions=options
    local made=realLongZhuNew(options)
    longzhuInstance=made
    local tick=made.tick
    made.tick=function(self)longzhuTicks=longzhuTicks+1;return tick(self)end
    return made
end
local StoryGuard=require('story_guard');local realGuardNew=StoryGuard.new
local guardOptions,guardTicks,guardInstance=nil,0,nil
StoryGuard.new=function(options)
    guardOptions=options
    local made=realGuardNew(options)
    guardInstance=made
    local tick=made.tick
    made.tick=function(self)guardTicks=guardTicks+1;return tick(self)end
    return made
end
assert(loadfile(scripts.."main.lua"))()
assert(keepOptions and keepOptions.members and keepOptions.location and keepOptions.camera and keepOptions.ground and keepOptions.ground.park,'stands are kept on the ground')
assert(next(keys)==nil,'fresh installation must not register fixed or developer shortcuts')
assert(#loops==1,"boot should only install bounded panel polling")
assert(#frameLoops==1,'the hotkeys are read by one frame loop')
local configured={spawn='F9',start='F3',stop='F4',refresh_catalog='F1',toggle_camera='F6',exit_camera='F7',cycle_team='F2',toggle_spectator='F8'}
inGame=true;assert(runtimeInstance:configure(configured).ok);inGame=false
assert(next(keys)==nil,'configured shortcuts are read in the game thread, never registered as UE4SS key binds')
press('F2');assert(#queue==1 and #loads==0)
inGame=true;table.remove(queue,1)();inGame=false
assert(#loads==0 and table.concat(logs,'\n'):find('blue -> red',1,true),'F2 must only cycle next-spawn settings')
press('F9')
assert(#loads==0 and #queue==1,"hotkey must dispatch to game thread")
inGame=true
table.remove(queue,1)()
inGame=false
assert(#loads==0,"startup without a player must not load assets")
player.alive=true
press('F9'); inGame=true; table.remove(queue,1)(); inGame=false
assert(#loads==1 and loads[1]==known,"ready world with zero NPC instances must resolve only the approved path")
inGame=true
local beforeCameraQueue=#queue
local cameraResult=runtimeInstance:dispatch('toggle_camera',{})
assert(type(cameraResult)=='table' and cameraResult.ok==false and #queue==beforeCameraQueue,
    'camera ACK must reflect the synchronous attempt, not a second queued callback')
inGame=false
local output=table.concat(logs,"\n")
assert(output:find(arg[3] or 'v0.40.11-beta-5',1,true),"new build must load")
if actorMode then
    assert(#genericCalls==2 and genericCalls[2]=='finish','generic Actor must use separate deferred/finalize calls')
    assert(output:find('通用Actor初始化完成',1,true),'generic Actor must not run PBZ ActivateAI')
else assert(output:find("找不到函数库",1,true),"class resolution must reach the explicit mocked spawn boundary") end
do
    inGame=true
    runtimeInstance.bridge:_writeStatus()
    inGame=false
    local statusFile=assert(io.open(root..'/status.tsv','rb'))
    local wire=statusFile:read('*a');statusFile:close()
    assert(wire:find('summon_queue_enabled\tfalse',1,true))
    assert(wire:find('summon_queue_epoch\tSQ_0',1,true))
    assert(wire:find('summon_queue_waiting\t0',1,true))
    assert(wire:find('spawn_cycle\t0',1,true))
    inGame=true
    assert(runtimeInstance:dispatch('set_spawn_level',{key_spawn='CYCLE',key_start='7'}).ok)
    runtimeInstance.bridge:_writeStatus()
    inGame=false
    statusFile=assert(io.open(root..'/status.tsv','rb'))
    wire=statusFile:read('*a');statusFile:close()
    assert(wire:find('spawn_cycle\t7',1,true) and wire:find('spawn_level_mode\tHOME',1,true))
    originalPrint('summon cycle status readback: 0 -> 7, level mode HOME')
    originalPrint('summon queue status readback: off, epoch SQ_0, waiting 0')
end

-- The production callback must forward a legacy key's unset team/count to Arena
-- rather than sampling all combatants just to look up selection defaults.
do
    local sampled,requests=0,{}
    local status,spawn=arenaInstance.status,arenaInstance.spawn
    arenaInstance.status=function(self)sampled=sampled+1;return status(self)end
    arenaInstance.spawn=function(_,path,team,count)
        requests[#requests+1]=table.pack(path,team,count)
        return {ok=true,spawned_count=1}
    end
    inGame=true
    unitKeyOptions.spawn(known,nil,nil)
    unitKeyOptions.spawn(known,'red',3)
    inGame=false
    arenaInstance.status,arenaInstance.spawn=status,spawn
    originalPrint('unit-key dispatch readback: whole-roster status calls='..sampled)
    assert(sampled==0,'a unit key must not sample the entire roster before summoning')
    assert(#requests==2 and requests[1].n==3 and requests[1][1]==known and requests[1][2]==nil and requests[1][3]==nil)
    assert(requests[2][1]==known and requests[2][2]=='red' and requests[2][3]==3)
end
-- Exercise the real main.lua activation callback, not a replacement callback.
local originalFind=StaticFindObject
local originalFindObject=FindObject
local aiLib={IsValid=function()return true end,ActivateAI=function()end}
StaticFindObject=function(path)
    if path=='/SGameAI/BP_SGameAIFunctionLibrary.Default__BP_SGameAIFunctionLibrary_C' then return aiLib end
    return originalFind(path)
end
local diagnosticQueries=0
local effectClass={IsValid=function()return true end}
FindObject=function(kind,name,...)
    if kind=='BlueprintGeneratedClass' and name=='GE_IgnoreAllDamage_C' then return effectClass end
    if originalFindObject then return originalFindObject(kind,name,...) end
end
local npc={IsValid=function()return true end,GetFullName=function()return 'NPC /Test/World.Unit' end,
    Controller={IsValid=function()return true end,SGameAIComponent={IsValid=function()return true end}},
    AbilitySystemComponent={IsValid=function()return true end,GetGameplayEffectCount=function()
        diagnosticQueries=diagnosticQueries+1
        return 0
    end},
    AttributeSetBase={IsValid=function()return true end,Health={CurrentValue=12000}}}
function npc:IsActorBeingDestroyed()return false end
local result={ok=false,rollback_verified=true,message='数值统一失败；回滚读回=true'}
statMatchInstance.onSpawn=function(_,actor,path)assert(actor==npc and path==known);return result end
inGame=true
local activated,_,warning=arenaOptions.activate(npc,known)
FindObject=originalFindObject
assert(diagnosticQueries==0,'normal spawn must not query gameplay effect classes for diagnostics')
assert(activated==true and warning and warning:find('保留原生数值',1,true),
    'verified stat rollback must preserve successful activation, HUD eligibility and combat')
result.rollback_verified=false
assert(arenaOptions.activate(npc,known)==false,'unverified rollback still requires cleanup')
-- A companion takes its own set and never the arena's; an escort takes neither.
local whose={}
statMatchInstance.onSpawn=function()whose[#whose+1]='arena';return {ok=true}end
companionStatsInstance.onSpawn=function(_,actor,path)assert(actor==npc and path==known);whose[#whose+1]='companion';return {ok=true}end
statMatchInstance.onSummon=function(_,actor,path)assert(actor==npc and path==known);whose[#whose+1]='arena-brought';return {ok=true}end
companionStatsInstance.onSummon=function(_,actor,path)assert(actor==npc and path==known);whose[#whose+1]='companion-brought';return {ok=true}end
arenaOptions.activate(npc,known,'blue')
arenaOptions.activate(npc,known,'companion')
arenaOptions.activate(npc,known,'companion',true)
arenaOptions.activate(npc,known,'red',true)
assert(table.concat(whose,',')=='arena,companion,companion-brought,arena-brought',table.concat(whose,','))
-- What a unit summons in a fight takes the set of its side.
whose={}
arenaOptions.summonAdopted(npc,known,'companion')
arenaOptions.summonAdopted(npc,known,'blue')
arenaOptions.summonAdopted(npc,known,'red')
arenaOptions.summonAdopted(npc,known,'neutral')
assert(table.concat(whose,',')=='companion-brought,arena-brought,arena-brought,arena-brought',table.concat(whose,','))
-- A companion whose numbers the game refused is treated like an arena unit's: rolled back it stays and fights.
companionStatsInstance.onSpawn=function()return {ok=false,rollback_verified=true,message='fixture'}end
local stays,_,why=arenaOptions.activate(npc,known,'companion')
assert(stays==true and why and why:find('保留原生数值',1,true))
function npc:GetAddress()return 2001 end
function npc:GetOuter()return world end
function npc:IsActorBeingDestroyed()return false end
local template={IsValid=function()return true end,GetAddress=function()return 2002 end,
    GetOuter=function()return cls end,GetFullName=function()return 'NPC /Test.Default__NPC' end,
    IsActorBeingDestroyed=function()return false end}
FindAllOf=function(name)assert(inGame);return name=='PBZCharacter_NPC' and {npc,template} or {}end
local scanned=spectatorOptions.getNPCs()
assert(#scanned==1 and scanned[1]==npc,'spectator must ignore class templates/out-of-world objects')
inGame=false
-- A helper sent to fight its own summoner's side (冷荼's 彭猛 and the rest) is taken out as it comes; one that cannot
-- be taken out joins the other side; an ordinary summon is adopted as before.
-- Native activation or FinishSpawn can destroy an actor while its Lua wrapper stays valid.
local function expiringActor()
    local actor={destroying=false,afterDestroyReads=0,
        IsValid=function()return true end,
        GetFullName=function()return 'NPC /Test/World.Expiring' end,
        IsActorBeingDestroyed=function(self)return self.destroying end,
        GetAddress=function()return 2003 end}
    return setmetatable(actor,{__index=function(self,key)
        if self.destroying and (key=='CapsuleComponent' or key=='Mesh' or key=='Controller' or key=='AttributeSetBase'
            or key=='AbilitySystemComponent' or key=='K2_GetActorLocation') then
            self.afterDestroyReads=self.afterDestroyReads+1
            error('fixture: property read after native destruction: '..key)
        end
    end})
end
inGame=true
local lostOnActivate=expiringActor()
local normalActivation=aiLib.ActivateAI
aiLib.ActivateAI=function(_,actor)assert(actor==lostOnActivate);actor.destroying=true end
local activationResult=arenaOptions.activate(lostOnActivate,known,'blue')
aiLib.ActivateAI=normalActivation
local finishResult=false
local afterFinishReads=0
if not actorMode then
    local lostOnFinish=expiringActor()
    aiLib.SpawnAIDefered=function()return lostOnFinish end
    aiLib.FinishSpawnAIDefered=function(_,actor)assert(actor==lostOnFinish);actor.destroying=true end
    local transform={Translation={X=0,Y=0,Z=100},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
    local owned=arenaOptions.spawnClass(cls,transform,world,{path=known,isNPC=true})
    assert(owned==lostOnFinish,'the real deferred-spawn path must register the fixture')
    finishResult=arenaOptions.finishSpawn(owned,transform,world)
    afterFinishReads=lostOnFinish.afterDestroyReads
end
originalPrint('spawn lifecycle readback: activate='..tostring(activationResult)..' reads='..lostOnActivate.afterDestroyReads
    ..' finish='..tostring(finishResult)..' reads='..afterFinishReads)
assert(activationResult==false and lostOnActivate.afterDestroyReads==0,'never read pawn fields after native activation starts destruction')
assert(finishResult==false and afterFinishReads==0,'never continue from FinishSpawn once destruction starts')
inGame=false

local function helper(name,throws)
    local h={name=name,destroyed=false}
    h.IsValid=function()return true end
    h.GetFullName=function()return 'BP_Helper_NPC_C /Test/World.'..name end
    h.K2_DestroyActor=function(self)if throws then error('refused') end;self.destroyed=true end
    h.IsActorBeingDestroyed=function(self)return self.destroyed end
    return h
end
local gone,stuck=helper('helper'),helper('stuck',true)
fakeLinks={{actor=gone,parent={name='boss'},class_path='/Test/BP_Helper_NPC.BP_Helper_NPC_C',evidence='fixture；SummonCombatTargetMode=EncounterSummons',opposing=true},
    {actor=stuck,parent={name='boss'},class_path='/Test/BP_Helper_NPC.BP_Helper_NPC_C',evidence='fixture',opposing=true},
    {actor={name='minion'},parent={name='boss'},class_path='/Test/BP_Minion.BP_Minion_C',evidence='fixture',opposing=false}}
inGame=true;supportLoop:tick();inGame=false
assert(gone.destroyed and supportLoop.helpersRemoved==1,'the helper is taken out')
assert(#adoptCalls==2 and adoptCalls[1][1]==stuck and adoptCalls[1][5]=='opposing' and adoptCalls[2][5]==nil,
    'not adopted once gone; one that stays joins the other side; an ordinary summon is adopted')
assert(table.concat(logs,'|'):find('移除剧情帮手 BP_Helper_NPC_C /Test/World.helper（召唤者',1,true)
    and table.concat(logs,'|'):find('SummonCombatTargetMode=EncounterSummons；原版是来帮玩家打召唤者的）调用=true 读回 正在销毁=true 累计=1',1,true),'logged with its read-back')
fakeLinks={}
assert(keepTicks==1,'the support loop looks after the stands')
assert(guardTicks==1,'the support loop runs the story guard')
assert(guardOptions.aiSubsystem and guardOptions.pipeline and guardOptions.tagCount and guardOptions.members,'story guard wired')
inGame=true;assert(guardOptions.aiSubsystem()==nil and guardOptions.pipeline()==nil,'no subsystem in the empty test world');inGame=false
assert(longzhuTicks==1 and longzhuOptions.pipeline and writesOptions.pipeline,'the 龙柱 check runs in the support loop; both read the story system')
assert(longzhuOptions.repair==nil and longzhuInstance.armed==false and guardInstance.armed==false,'nothing is repaired before the save-repair button')
assert(runtimeInstance.handlers.repair_save,'the save-repair button reaches the game')
do -- The button arms both repairs and reports; in the empty test world nothing can be read.
    inGame=true
    local report=supportLoop.saveRepair:run()
    inGame=false
    assert(report.ok==true and longzhuInstance.armed==true and guardInstance.armed==true,'the button arms the 龙柱 and 雷当 repairs')
    assert(report.message:find('读不到：龙柱、雷当、冷荼',1,true) and #report.message<=512,report.message)
end
do -- A unit that writes story progress is not summoned while the story cannot say it holds that already.
    local leidang='/PBZCombatAsset/ActorData/Mobs/047_LeiDang/BP_Monster_LeiDang.BP_Monster_LeiDang_C'
    local unit={IsValid=function()return true end,GetFullName=function()return 'BlueprintGeneratedClass '..leidang end}
    inGame=true
    local pawn,why,outcome=arenaOptions.spawnClass(unit,{Translation={X=0,Y=0,Z=0}},world)
    inGame=false
    assert(pawn==nil and outcome=='not_started' and why:find('qsd.击杀.雷当',1,true),tostring(why))
end
assert(execOptions and type(execOptions.storyAllows)=='function','finishers are wired to story_writes')
do
    local probe={IsValid=function()return true end,GetFName=function()return {ToString=function()return 'GA_Hun_BEx_MoYuan_C' end}end}
    inGame=true
    local allowed,why=execOptions.storyAllows(probe)
    inGame=false
    assert(writesAsked==probe and allowed==false and type(why)=='string','a story move with nothing loaded is refused: '..tostring(why))
end
do -- An attack order's restore records: once what they would put back is gone, they do not hold up the cleanup, even
   -- for a unit the arena never registered as its own (an adopted summon is engaged before it is registered).
    local serial,logged=900,#logs
    local function obj(fields)
        serial=serial+1;local o=fields or {};o.alive=true;o.address=serial
        o.IsValid=function(self)return self.alive end
        o.GetAddress=function(self)assert(self.alive,'read of a destroyed object');return self.address end
        o.GetFullName=function(self)return 'Object /Test/World.Object'..self.address end
        return o
    end
    local overrides={}
    local function unit()
        local actor=obj()
        local fc=obj({GetFactionRelation=function(self,other)assert(self.alive and other.alive)
                return (overrides[actor] or {})[other] or 1 end,
            SetFactionRelationOverride=function(self,other,relation,both)assert(self.alive and other.alive)
                overrides[actor]=overrides[actor] or {};overrides[actor][other]=relation
                if both then overrides[other]=overrides[other] or {};overrides[other][actor]=relation end end,
            ClearFactionRelationOverride=function(self,other)assert(self.alive and other.alive)
                if overrides[actor] then overrides[actor][other]=nil end end})
        local hm=obj({HatredList={},AddActorToHatredList=function(self,other)assert(self.alive);table.insert(self.HatredList,other)end,
            RemoveActorFromHatredList=function(self,other)assert(self.alive and other.alive)
                for i=#self.HatredList,1,-1 do if self.HatredList[i]==other then table.remove(self.HatredList,i)end end end})
        local value={}
        local bb=obj({GetValueAsObject=function(self,k)assert(self.alive);return value[k.name] end,
            SetValueAsObject=function(self,k,v)assert(self.alive and v.alive);value[k.name]=v end,
            ClearValue=function(self,k)assert(self.alive);value[k.name]=nil end})
        local ai=obj({BlackboardComponent=bb,ForceIntoCombat=function(self)assert(self.alive)end,CurrentStateTag={TagName='AI.State.Combat'}})
        actor['Faction Component']=fc;actor.BP_PBZHatredManagerComponent=hm;actor.Controller=obj({SGameAIComponent=ai})
        actor.parts={fc,hm,bb,ai,actor.Controller};actor.bb=bb;actor.value=value
        return actor
    end
    local function destroy(actor)actor.alive=false;for _,part in ipairs(actor.parts)do part.alive=false end end
    local key={name='TargetActor',ToString=function()return 'TargetActor' end}
    local summon,victim,old=unit(),unit(),unit()
    summon.value.TargetActor=old
    local handlers={obj({Blackboard=summon.bb,['Target Key']=key})}
    local findAll=FindAllOf
    FindAllOf=function(name)assert(inGame);return name=='PBZ_TargetingHandler_AI_C' and handlers or {} end
    inGame=true
    arenaOptions.forceAttack(summon,victim)
    assert(summon.value.TargetActor==victim and summon.BP_PBZHatredManagerComponent.HatredList[1]==victim,'the order was written')
    destroy(old)
    assert(arenaOptions.restore()==true,'the old target is gone: the blackboard is cleared, the rest put back')
    assert(summon.value.TargetActor==nil and #summon.BP_PBZHatredManagerComponent.HatredList==0 and next(overrides[summon])==nil)
    assert(table.concat(logs,'\n',logged+1):find('原目标已不存在，改为清空',1,true),'the cleared target is logged')
    arenaOptions.forceAttack(summon,victim)
    destroy(summon);destroy(victim)
    assert(arenaOptions.restore()==true,'the units are gone: nothing is left to put back and the cleanup completes')
    assert(arenaOptions.restore()==true,'and nothing is left over for the next one')
    inGame=false
    FindAllOf=findAll
end
local queuedBefore=#queue
ModRef.OnUnload()
press('F9')
assert(#queue==queuedBefore,"unloaded input must stay inert")
print=originalPrint
do
    local previousControllers,previousWorld=controllers,world
    local previousFind=FindAllOf
    local helper=package.loaded.UEHelpers
    local previousViewport=helper.GetGameViewportClient
    local oldWorld={IsValid=function()return true end,GetAddress=function()return 8101 end}
    local currentWorld={IsValid=function()return true end,GetAddress=function()return 8102 end}
    local oldPawn={IsValid=function()return true end,IsActorBeingDestroyed=function()return false end,
        GetAddress=function()return 8103 end,GetWorld=function()return oldWorld end}
    local currentPawn={IsValid=function()return true end,IsActorBeingDestroyed=function()return false end,
        GetAddress=function()return 8104 end,GetWorld=function()return currentWorld end}
    local localPlayer={IsValid=function()return true end,GetAddress=function()return 8105 end}
    local stale={IsValid=function()return true end,GetAddress=function()return 8106 end,
        GetClass=function()return controllerClass end,Player=localPlayer,Pawn=oldPawn,GetWorld=function()return oldWorld end}
    local current={IsValid=function()return true end,GetAddress=function()return 8107 end,
        GetClass=function()return controllerClass end,Player=localPlayer,Pawn=currentPawn,GetWorld=function()return currentWorld end}
    localPlayer.PlayerController=current
    local viewport={IsValid=function()return true end,World=currentWorld}
    helper.GetGameViewportClient=function()return viewport end
    controllers={stale,current};world=oldWorld
    FindAllOf=function(name)
        if name=='PlayerController' then return controllers end
        return previousFind(name)
    end
    inGame=true
    local chosen=arenaOptions.getPlayer()
    local chosenWorld=arenaOptions.getWorld(chosen)
    stale.Player={IsValid=function()return true end,GetAddress=function()return 8110 end,PlayerController=stale}
    local chosenFromDifferentPlayer=arenaOptions.getPlayer()
    current.Pawn=oldPawn
    local mismatchedPawn=arenaOptions.getPlayer()
    current.Pawn=currentPawn
    currentPawn.IsActorBeingDestroyed=function()return true end
    local destroyingPawn=arenaOptions.getPlayer()
    inGame=false
    controllers,world=previousControllers,previousWorld
    FindAllOf=previousFind
    helper.GetGameViewportClient=previousViewport
    print('main_context readback: pawn='..tostring(chosen and chosen:GetAddress())..' active pawn='..tostring(chosen==currentPawn)..' active world='..tostring(chosenWorld==currentWorld))
    assert(chosen==currentPawn,'a still-valid old controller must not select the previous pawn')
    assert(chosenFromDifferentPlayer==currentPawn,'a retained controller from another world must be rejected even with its own player backlink')
    assert(mismatchedPawn==nil and destroyingPawn==nil,'a pawn from another world or entering destruction must not be accepted')
    assert(chosenWorld==currentWorld,'spawns must use the viewport world rather than the first retained controller world')
end
print("main_boot: PASS (all modules, active player/world, no startup asset load, ready no-NPC approved resolution, camera bindings, game-thread dispatch, unload)")
