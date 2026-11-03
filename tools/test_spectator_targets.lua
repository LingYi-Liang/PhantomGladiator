package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Targets=require('spectator_targets')
local function object(id,properties)
    local o=properties or {};o.alive=true
    function o:IsValid()return self.alive end
    function o:GetAddress()assert(self.alive);return id end
    return o
end
local player,opponent=object(1),object(2)
local bb=object(3,{target=player,sensed=player,other=opponent})
function bb:GetValueAsObject(key)assert(self.alive);return self[key]end
function bb:ClearValue(key)assert(self.alive);self[key]=nil end
local ai=object(4,{BlackboardComponent=bb})
local ctrl=object(5,{SGameAIComponent=ai,focus=player})
function ctrl:GetFocusActor()assert(self.alive);return self.focus end
function ctrl:K2_ClearFocus()assert(self.alive);self.focus=nil end
local npc=object(6,{Controller=ctrl})
local handler=object(7,{Blackboard=bb,['Target Key']='target',LastSensedActorKey='sensed'})
local unrelated=object(8,{target=player})
function unrelated:GetValueAsObject(key)return self[key]end
function unrelated:ClearValue()error('unrelated AI must not be changed')end
local anotherHandler=object(9,{Blackboard=unrelated,['Target Key']='target'})
local scans=0
FindAllOf=function(name)assert(name=='PBZ_TargetingHandler_AI_C');scans=scans+1;return {handler,anotherHandler}end
local targets=Targets.new({});targets:refresh()
assert(targets:release(npc,player) and bb.target==nil and bb.sensed==nil and ctrl.focus==nil)
assert(bb.other==opponent and unrelated.target==player)
bb.target,bb.sensed,ctrl.focus=opponent,opponent,opponent
assert(targets:release(npc,player) and bb.target==opponent and bb.sensed==opponent and ctrl.focus==opponent)
for _=1,8 do targets:refresh();targets:release(npc,player)end
assert(scans==1,'target discovery must not perform a global scan per NPC')
bb.alive=false;assert(targets:release(npc,player),'invalid target components must be skipped')
print('spectator_targets: PASS (player-only target/focus, NPC combat preserved, bounded discovery, invalid object protection)')
