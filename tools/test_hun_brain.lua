package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Brain=require('hun_brain')
local Growth=require('hun_growth')
local t,hp,target,busy,casting=0,25,{},false,false
local supplyCalls,shadowCalls={},{}
local brain=Brain.new({now=function()return t end,hp=function()return hp end,target=function()return target end,
    stat=function(_,field)assert(field=='Health_Max');return 100 end,distance=function()return 450 end,
    tag=function(_,field)return field=='Ability.Executed' and busy and 1 or 0 end,log=function()end,
    supply={tick=function(_,r,ctx)supplyCalls[r]=ctx.busy;return false end},
    shadows={tick=function(_,r,ctx)shadowCalls[r]=ctx.allowShadow;return casting end}})
local function body(name)
    return {name=name,actor={},loadout={weapons={{id='sword',weight=1},{id='axe',weight=0}},
        phases={{id='disabled_item',health_below=.6,priority=110,weapon_id='axe'},
                {id='save',health_below=.25,priority=100,once=true,weapon_id='sword'}}}}
end
local a,b=body('first'),body('second')
brain:start(a);brain:start(b);brain:tick(a);brain:tick(b)
assert(a.intent.weapon_id=='sword' and not shadowCalls[a])
assert(b.intent.phaseId=='save' and not a.usedPhases.save)
t=2.2;brain:tick(a);assert(shadowCalls[a],'an unavailable phase cannot indefinitely starve other actions')
a.intent.performedPhase='save';t=2.5;brain:tick(a);brain:tick(b)
assert(a.usedPhases.save and a.intent.phaseId==nil and b.intent.phaseId=='save')
casting=true;t=3;brain:tick(a);assert(a.intent.busy)
t=3.5;brain:tick(a);assert(supplyCalls[a],'medicine waits until the shadow action ends')
casting=false;busy=true;t=4;brain:tick(a);assert(a.intent.busy and not shadowCalls[a])
busy=false;target=nil;t=5;brain:tick(b);assert(b.intent.phaseId==nil and not shadowCalls[b])
local custom=Growth.values({Attack=10})
assert(custom.Health_Max==1360 and custom.Shachi_Max==640 and custom.Attack==10 and custom.ShachiAttack==160)
assert(Growth.values({}).Attack==160 and Growth.values({}).Health_Max_Lv1==850)
assert(custom.UltimateCharge_Max==100 and custom.UltimateChargeCount_Max==3 and custom.UltimateChargeCount==3)
assert(Growth.values({UltimateChargeCount_Max=2}).UltimateChargeCount==2 and Growth.values({UltimateChargeCount=0}).UltimateChargeCount==0)
print('PASS phase priority, isolation, protected actions, target loss, and permanent growth')
