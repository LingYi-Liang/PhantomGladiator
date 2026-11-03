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
CancelDelayedAction=function() end
ExecuteInGameThreadWithDelay=function() error("no delayed UE work expected during empty-world boot") end
FindAllOf=function() assert(inGame,"UObject lookup outside game thread"); return {} end
FindObjects=function() assert(inGame); return {} end
local known=cfg.KnownMonsterClasses[1]
local base={IsValid=function() return true end,GetFullName=function() return actorMode and 'Class /Script/Engine.Actor' or "Class /Script/ProjectPBZ.PBZCharacter_NPC" end}
local cls={IsValid=function() return true end,IsAnyClass=function() return true end,
    GetFullName=function() return "BlueprintGeneratedClass "..known end,GetSuperStruct=function() return base end}
local loaded=false
local genericCalls={}
local genericActor={IsValid=function()return true end,IsActorBeingDestroyed=function()return false end,GetFullName=function()return 'BP_SequenceActor /Test/World.Actor' end}
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
local pc={IsValid=function() return true end,Pawn=player}
package.loaded.UEHelpers={GetPlayerController=function() return pc end,GetWorld=function() return world end}
local arenaOptions,statMatchInstance,spectatorOptions,runtimeInstance
local Arena=require('arena_controller');local realArenaNew=Arena.new
Arena.new=function(options)arenaOptions=options;return realArenaNew(options)end
local Match=require('stat_match');local realMatchNew=Match.new
Match.new=function(options)statMatchInstance=realMatchNew(options);return statMatchInstance end
local Spectator=require('spectator_mode');local realSpectatorNew=Spectator.new
Spectator.new=function(options)spectatorOptions=options;return realSpectatorNew(options)end
local Runtime=require('panel_runtime');local realRuntimeNew=Runtime.new
Runtime.new=function(options)runtimeInstance=realRuntimeNew(options);return runtimeInstance end
assert(loadfile(scripts.."main.lua"))()
assert(next(keys)==nil,'fresh installation must not register fixed or developer shortcuts')
assert(#loops==1,"boot should only install bounded panel polling")
local configured={spawn='F9',start='F3',stop='F4',refresh_catalog='F1',toggle_camera='F6',exit_camera='F7',cycle_team='F2',toggle_spectator='F8'}
inGame=true;assert(runtimeInstance:configure(configured).ok);inGame=false
keys['113:0']();assert(#queue==1 and #loads==0)
inGame=true;table.remove(queue,1)();inGame=false
assert(#loads==0 and table.concat(logs,'\n'):find('blue -> red',1,true),'F2 must only cycle next-spawn settings')
keys['120:0']()
assert(#loads==0 and #queue==1,"hotkey must dispatch to game thread")
inGame=true
table.remove(queue,1)()
inGame=false
assert(#loads==0,"startup without a player must not load assets")
player.alive=true
keys['120:0'](); inGame=true; table.remove(queue,1)(); inGame=false
assert(#loads==1 and loads[1]==known,"ready world with zero NPC instances must resolve only the approved path")
inGame=true
local beforeCameraQueue=#queue
local cameraResult=runtimeInstance:dispatch('toggle_camera',{})
assert(type(cameraResult)=='table' and cameraResult.ok==false and #queue==beforeCameraQueue,
    'camera ACK must reflect the synchronous attempt, not a second queued callback')
inGame=false
local output=table.concat(logs,"\n")
assert(output:find(arg[3] or 'v0.38.4-boss-stages',1,true),"new build must load")
if actorMode then
    assert(#genericCalls==2 and genericCalls[2]=='finish','generic Actor must use separate deferred/finalize calls')
    assert(output:find('通用Actor初始化完成',1,true),'generic Actor must not run PBZ ActivateAI')
else assert(output:find("找不到函数库",1,true),"class resolution must reach the explicit mocked spawn boundary") end
-- Exercise the real main.lua activation callback, not a replacement callback.
local originalFind=StaticFindObject
local aiLib={IsValid=function()return true end,ActivateAI=function()end}
StaticFindObject=function(path)
    if path=='/SGameAI/BP_SGameAIFunctionLibrary.Default__BP_SGameAIFunctionLibrary_C' then return aiLib end
    return originalFind(path)
end
local npc={IsValid=function()return true end,GetFullName=function()return 'NPC /Test/World.Unit' end,
    Controller={IsValid=function()return true end,SGameAIComponent={IsValid=function()return true end}},
    AttributeSetBase={IsValid=function()return true end,Health={CurrentValue=12000}}}
local result={ok=false,rollback_verified=true,message='数值统一失败；回滚读回=true'}
statMatchInstance.onSpawn=function(_,actor,path)assert(actor==npc and path==known);return result end
inGame=true
local activated,_,warning=arenaOptions.activate(npc,known)
assert(activated==true and warning and warning:find('保留原生数值',1,true),
    'verified stat rollback must preserve successful activation, HUD eligibility and combat')
result.rollback_verified=false
assert(arenaOptions.activate(npc,known)==false,'unverified rollback still requires cleanup')
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
local queuedBefore=#queue
ModRef.OnUnload()
keys['120:0']()
assert(#queue==queuedBefore,"unloaded input must stay inert")
print=originalPrint
print("main_boot: PASS (all modules, no startup asset load, ready no-NPC approved resolution, camera bindings, game-thread dispatch, unload)")
