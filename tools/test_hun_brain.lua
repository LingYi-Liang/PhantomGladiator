package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Brain=require('hun_brain')
local Growth=require('hun_growth')
local t,hp,target,busy,casting=0,25,{},false,false
local supplyCalls,shadowCalls={},{}
local threat={}
local protection,shadowTicks={},0
local protectedFoe,seenTarget=nil,nil
local brain=Brain.new({now=function()return t end,hp=function()return hp end,target=function()return target end,
    pairProtected=function(_,foe)seenTarget=foe;return foe==protectedFoe end,
    stat=function(_,field)if field=='UltimateChargeCount' then return 3 end;assert(field=='Health_Max');return 100 end,distance=function()return 450 end,
    tag=function(_,field)return field=='Ability.Executed' and busy and 1 or 0 end,log=function()end,
    supply={tick=function(_,r,ctx)supplyCalls[r]=ctx.busy;return false end},
    shadows={tick=function(_,r,ctx)shadowCalls[r]=ctx.allowShadow;threat[r]=ctx.underThreat;protection[r]=ctx.pairProtected;shadowTicks=shadowTicks+1;return casting end}})
local function body(name)
    local path=require('hun_weapon_catalog').rows[1].path
    return {name=name,actor={},loadout={weapons={{id='sword',path=path,weight=1},{id='axe',path=path,weight=0}},
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
casting=true;t=3;a.intent.incomingUntil=3.2;brain:tick(a);assert(a.intent.busy and threat[a])
a.shadowState={running={hold={},released=false}};a.intent.incomingUntil=3.04;t=3.05
brain:tick(a);assert(not threat[a]);a.shadowState=nil
local ticks=shadowTicks;a.shadowState={running={hold={}}}
for _=1,25 do brain:tick(a) end
assert(shadowTicks==ticks,'the same paused game instant cannot drive a pending release repeatedly')
a.shadowState=nil
t=3.5;brain:tick(a);assert(supplyCalls[a],'medicine waits until the shadow action ends')
casting=false;busy=true;t=4;brain:tick(a);assert(a.intent.busy and not shadowCalls[a])
busy=false;protectedFoe=target;t=4.3;brain:tick(a);assert(seenTarget==target and a.intent.busy and not shadowCalls[a])
assert(protection[a]==true,'an existing charge needs the protected-pair state too')
protectedFoe=nil;t=4.6;brain:tick(a);assert(seenTarget==target and not a.intent.busy and shadowCalls[a])
a.wep={pendingSwitch={}};t=4.8;brain:tick(a)
assert(supplyCalls[a] and not shadowCalls[a] and not a.intent.busy,'a pending draw excludes other inputs but lets its own weapon timer settle')
a.wep.pendingSwitch=nil;t=4.95;brain:tick(a);assert(not supplyCalls[a] and shadowCalls[a])
busy=false;target=nil;t=5;brain:tick(b);assert(b.intent.phaseId==nil and not shadowCalls[b])
do
    local c=body('costs');local balance,cap=1,3
    c.loadout.weapons[2].weight=1
    c.loadout.phases={{id='high',weapon_id='sword',health_below=.5,priority=20,once=true},
        {id='low',weapon_id='axe',health_below=.5,priority=10,once=true}}
    c.wep={artCosts={sword=2,axe=1},phaseRetryAt={},rotation={failures={}}}
    c.loadout.resources={consume_skill_resources=true}
    local idle={tick=function()return false end}
    local g=Brain.new({now=function()return t end,target=function()return {} end,hp=function()return 10 end,
        stat=function(_,f)return ({Health_Max=100,UltimateChargeCount=balance,UltimateChargeCount_Max=cap})[f] end,
        tag=function()return 0 end,distance=function()return 200 end,supply=idle,shadows=idle,log=function()end})
    g:start(c);g:tick(c);assert(c.intent.phaseId=='low')
    balance=0;c.loadout.resources.consume_skill_resources=false;t=6;g:tick(c)
    assert(c.intent.phaseId=='high','free mode can borrow up to the actual capacity')
    cap=1;t=7;g:tick(c);assert(c.intent.phaseId=='low')
    c.wep.phaseRetryAt.axe=10;t=8;g:tick(c);assert(not c.intent.phaseId)
    balance=2;c.wep.rotation.failures.sword=2;t=11;g:tick(c)
    assert(c.intent.phaseId=='low' and not c.usedPhases.high,'do not block a usable rule behind an excluded weapon')
end
local custom=Growth.values({Attack=10})
assert(custom.Health_Max==1360 and custom.Shachi_Max==640 and custom.Attack==10 and custom.ShachiAttack==160)
assert(Growth.values({}).Attack==160 and Growth.values({}).Health_Max_Lv1==850)
assert(custom.UltimateCharge_Max==100 and custom.UltimateChargeCount_Max==3 and custom.UltimateChargeCount==3)
assert(Growth.values({UltimateChargeCount_Max=2}).UltimateChargeCount==2 and Growth.values({UltimateChargeCount=0}).UltimateChargeCount==0)
print('PASS phase priority, isolation, protected actions, target loss, and permanent growth')
