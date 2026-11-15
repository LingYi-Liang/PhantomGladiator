package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local U=require('ue_observe')
local file=assert(io.open(arg[1] or 'Mods/PhantomGladiator/Scripts/main.lua','r'));local text=file:read('*a');file:close()
local start=assert(text:find('function arenaSupport:viewportWorld()',1,true))
local finish=assert(text:find('local function GetLocation',start,true))
local function object(id)
    return {valid=true,IsValid=function(s)return s.valid end,GetAddress=function()return id end}
end
local world,world2=object(1),object(2)
local player,oldPlayer=object(3),object(4)
local cls=object(5);cls.GetFullName=function()return 'Class /Script/Test.PlayerController'end
local pc,stale=object(6),object(7)
pc.GetClass=function()return cls end;stale.GetClass=pc.GetClass
pc.Player=player;player.PlayerController=pc;stale.Player=oldPlayer;oldPlayer.PlayerController=stale
pc.GetWorld=function()return world end;stale.GetWorld=pc.GetWorld
local instance,viewport=object(8),object(9)
instance.LocalPlayers={player};viewport.World=world;viewport.GameInstance=instance
local calls,list=0,{pc}
local env=setmetatable({arenaSupport={},UEObserve=U,safeValid=U.valid,summonActorLive=U.valid,
    objectName=function(v)return v:GetFullName()end,UEHelpers={GetGameViewportClient=function()return viewport end},
    FindAllOf=function(name)assert(name=='PlayerController');calls=calls+1;return list end},{__index=_G})
local get=assert(load(text:sub(start,finish-1)..'\nreturn GetRealPlayerController','production controller lookup','t',env))()
for _=1,100 do assert(get()==pc,'viewport local player must take precedence over stale controllers')end
print('100 production controller lookups: global scans='..calls)
assert(calls==0,'authoritative local-player lookup must avoid global scans')
list={stale,pc};assert(get()==pc,'viewport local player must take precedence over stale controllers')
local newer=object(10);newer.GetClass=pc.GetClass;newer.GetWorld=pc.GetWorld;newer.Player=player;player.PlayerController=newer
assert(get()==newer,'controller changes must be observed immediately without cached objects')
viewport.World=world2;newer.GetWorld=function()return world2 end
assert(get()==newer,'world changes must not reuse a stale controller')
newer.valid=false;assert(get()==nil,'invalid current controller cannot fall back to a different world')
viewport.World=world;viewport.GameInstance=nil;list={stale,pc};player.PlayerController=pc
assert(get()==nil,'known viewport with unavailable local players is not permission to reuse retired players')
local viewportGetter=env.UEHelpers.GetGameViewportClient;env.UEHelpers.GetGameViewportClient=nil
assert(get()==stale,'without viewport support retain the validated legacy fallback')
assert(calls==1)
env.UEHelpers.GetGameViewportClient=viewportGetter
viewport.World=nil;viewport.GameInstance=instance
assert(get()==nil,'a known viewport with no world is loading, not permission to reuse an old controller world')
print('controller_discovery: PASS (100 lookups, global scans 100 -> 0; local-player/world changes and fallback)')
