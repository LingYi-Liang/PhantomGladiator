package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local U=require('ue_observe')
local Arena=require('arena_controller')
local Entourage=require('boss_entourage')
local env=setmetatable({arg={'fixture'}},{__index=_G})
local h=assert(loadfile('tools/test_huashan_formation.lua','t',env))()
local f=h.manage
local root='/PBZCombatAsset/ActorData/Mobs/035_HuaShan/'
local function path(id)return root..id..'.'..id..'_C'end
local blue=path('BP_Monster_HuaShan_Blue')
local red=path('BP_Monster_HuaShan_RedTroop_BigBro')
local catalog={selectedPath=blue}
function catalog:registerPath(s)return {path=s,isNPC=true}end
function catalog:select(s)self.selectedPath=s;return self:registerPath(s)end
function catalog:selected()return self:registerPath(self.selectedPath)end
function catalog:resolveSelected()return h.tree(self.selectedPath)end
function catalog:resolvePath(s)return h.tree(s),nil,self:registerPath(s)end
local player=h.actor('/Test/Player.Player_C',{X=1400,Y=200,Z=100})
local enabled=true
local time=0
local function tick(v)time=v;h.setTime(v);f:tick()end
local opts={catalog=catalog,log=function()end,canSpawn=function()return true end,valid=U.valid,
    name=function(a)return a:GetFullName()end,actorKey=function(a)return a:GetAddress()end,
    hp=h.options.hp,now=function()return time end,combatReady=function(a)return a.active==true end,
    getPlayer=function()return player end,getWorld=function()return h.world end,
    getLocation=function(a)return a.at end,getForward=function()return {X=1,Y=0,Z=0}end,
    formationEnabled=function()return enabled end,retireFormation=Entourage.retireFormation,
    escortsFor=function(s,on)return on and Entourage.parties[Entourage.id(s)] or nil end,
    resolveEscort=function(s)return catalog:resolvePath(s)end,
    spawnClass=function(c,t)return h.actor(c:GetFullName():match('^Class (.+)'),t.Translation)end,
    finishSpawn=function(a)
        if enabled then assert(a.Spawner and a.MobGroup and #a.MobGroup:GetMemberInterfaces()==7)end
        a.finished=true;return true
    end,
    activate=function(a)
        if a.MobGroup then for _,sp in ipairs(a.MobGroup.Members)do assert(sp:GetPawn().finished)end end
        a.active=true;return true
    end,
    prepareFormation=function(...)return f:prepare(...)end,formationReady=function(token)return f:ready(token)end,
    formationActivated=function(token)return f:activated(token)end,abortFormation=function(token)return f:abort(token)end,
    onUnitsChanged=function(rows)f:roster(rows)end,formationLifeChanged=function(...)f:lifeChanged(...)end,
    setRelation=function()return true end,
    forceAttack=function(a,target)assert(f:beforeAttack(a,target));h.foes[a]=target;return true end,
    onAssigned=function(a,target)f:assigned(a,target)end,
    restore=function()return true end,destroy=function(a)a:K2_DestroyActor()end}
local arena=Arena.new(opts)
local first=arena:spawn(blue,'blue',1);assert(first.ok and first.escort_count==6,first.message)
assert(arena:spawn(blue,'blue',1).ok)
assert(arena:spawn(red,'red',1).ok)
assert(#h.created==24 and #h.intro==0 and #h.events==0)
enabled=false
assert(arena:spawn(red,'red',1).ok)
local units=arena:members()
assert(#units==22 and #h.created==24 and not units[22].actor.MobGroup)
assert(arena:start().ok)
tick(1);tick(2)
assert(#h.intro==1 and h.intro[1]==units[15].actor)
assert(#h.events==2)
local function slots(actor)
    local found={}
    for i,sp in ipairs(actor:GetAISpawner():GetOtherAliveMembersInGroup())do
        local pawn=sp:GetPawn();assert(pawn:GetMobGroup()==actor:GetMobGroup() and not found[pawn]);found[pawn]=i
    end
    return found
end
local a,b=units[1].actor,units[8].actor
local one,two=slots(a),slots(b)
for i=2,7 do assert(one[units[i].actor] and not two[units[i].actor])end
local down=units[3].actor;down.hp=0;down.tags['CharacterState.Dead']=1
arena:status();tick(3)
assert(not slots(a)[down] and #down:GetMobGroup().Members==7)
down.hp=55;down.tags['CharacterState.Dead']=0;arena:status();tick(4);assert(slots(a)[down])
if arg[1]=='fixture' then return {engine=h,manager=f,arena=arena,units=units,tick=tick,blue=blue,red=red}end
a.hp=0;assert(arena:status().blue_count==13 and units[2].actor.MobGroup==a.MobGroup)
tick(5);assert(#h.intro==1 and #h.events==2)
assert(arena:stop().ok and #arena:members()==0)
for _,helper in ipairs(h.created)do assert(not helper.live)end
-- A refused first destroy can succeed during synchronous rollback, before the arena returns to the caller.
enabled=true
local statics=h.options.statics()
local begin=statics.BeginDeferredActorSpawnFromClass
local attempts=0
function statics:BeginDeferredActorSpawnFromClass(...)
    local helper=begin(self,...)
    local cls,destroy=helper.GetClass,helper.K2_DestroyActor
    function helper:GetClass()self.GetClass=cls;return nil end
    function helper:K2_DestroyActor()
        attempts=attempts+1
        if attempts>1 then destroy(self)end
    end
    return helper
end
local failed=arena:spawn(blue,'blue',1)
assert(not failed.ok and failed.remaining_count==0 and #arena:members()==0 and attempts==2)
for _,helper in ipairs(h.created)do assert(not helper.live)end
print('PASS arena spawn/start/death/revival/stop, 3 independent formations plus solo, 18 original teammates, 3 openings, all helpers retired')
