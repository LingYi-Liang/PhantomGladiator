package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Lock=require('combat_lock')
local address=0
local function object(name)
    address=address+1;local a=address
    return {IsValid=function()return true end,GetAddress=function()return a end,
        GetFName=function()return {ToString=function()return name end}end}
end
local function harness()
    local h={lines={},hooks={},unhooked={},now=0,fighting=false,members={},ai={},hatred={},ids=0,dropped={},sensed={}}
    local paths={}
    for _,path in pairs(Lock.paths)do paths[path]=true end
    StaticFindObject=function(path)return paths[path] and not (h.missing and h.missing[path]) and object(path) or nil end
    RegisterHook=function(path,callback)
        assert(paths[path]);h.ids=h.ids+1
        h.hooks[path]=callback;return h.ids,100+h.ids
    end
    UnregisterHook=function(path,pre,post)h.unhooked[#h.unhooked+1]={path,pre,post};h.hooks[path]=nil end
    function h.unit(team)
        local actor,component,manager=object('Unit'),object('BP_SGameAIComponent_C'),object('BP_PBZHatredManagerComponent_C')
        h.ai[actor]=component;h.hatred[actor]=manager
        h.members[#h.members+1]={actor=actor,team=team}
        return actor,component,manager
    end
    function h.new(extra)
        local settings={log=function(s)h.lines[#h.lines+1]=s end,clock=function()return h.now end,
            members=function()return h.members end,aiOf=function(actor)return h.ai[actor] end,
            hatredOf=function(actor)return h.hatred[actor] end,fighting=function()return h.fighting end,
            onDropped=function(key)h.dropped[#h.dropped+1]=key end,onSensed=function(key)h.sensed[#h.sensed+1]=key end}
        for key,value in pairs(extra or {})do settings[key]=value end
        return Lock.new(settings)
    end
    -- The game calling a hooked function: what the callback answers.
    function h.call(name,...)local hook=h.hooks[Lock.paths[name]];return hook and hook(...) end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end
local function tag(name)return {TagName=name}end

-- No fight: no hooks. A fight: the four hooks once; blue and red stay in combat, may hate each other,
-- and are sent back on CombatToIdle; everything else keeps the game's answer (nil).
do
    local h=harness()
    local lock=h.new()
    local blueActor,blue,blueHatred=h.unit('blue')
    local redActor,red,redHatred=h.unit('red')
    local blue2=h.unit('blue')
    local soloActor,solo,soloHatred=h.unit('neutral')
    local map,mapAI,mapHatred=object('MapNPC'),object('MapAI'),object('MapHatred')
    lock:tick()
    assert(next(h.hooks)==nil and lock:status().state=='idle','no fight, no hook')
    h.fighting=true;lock:tick();lock:tick()
    assert(h.ids==6 and lock:status().state=='running','six hooks, registered once')
    assert(h.call('exit',blue)==false and h.call('exit',red)==false,'blue and red stay in combat')
    assert(h.call('exit',solo)==nil and h.call('exit',mapAI)==nil,'others keep the game answer')
    assert(h.call('canHate',blueHatred,redActor)==true and h.call('canHate',redHatred,blueActor)==true,'opposite sides may hate each other')
    assert(h.call('canBeHated',redHatred,blueActor)==true)
    assert(h.call('canHate',blueHatred,blue2)==nil,'not their own side')
    assert(h.call('canHate',blueHatred,soloActor)==nil and h.call('canHate',soloHatred,redActor)==nil,'no-team units are left to the game')
    assert(h.call('canHate',mapHatred,blueActor)==nil and h.call('canHate',blueHatred,map)==nil,'map enemies are left to the game')
    -- CombatToIdle sends a fighting unit back, at most once per 0.5 s each; other transitions and units do not.
    assert(h.call('transition',red,tag('AI.Transition.CombatToIdle'))==nil)
    h.call('transition',red,tag('AI.Transition.CombatToIdle'))
    h.call('transition',mapAI,tag('AI.Transition.CombatToIdle'))
    h.call('transition',solo,tag('AI.Transition.CombatToIdle'))
    h.call('transition',blue,tag('AI.Transition.ToCombat'))
    assert(#h.dropped==1 and h.dropped[1]==tostring(redActor.GetAddress()),'red sent back once, nothing else')
    h.now=0.6;h.call('transition',red,tag('AI.Transition.CombatToIdle'))
    assert(#h.dropped==2)
    local counts=lock:status().counts
    assert(counts.exit==2 and counts.canHate==2 and counts.canBeHated==1 and counts.transition==2,h.all())
    assert(h.all():find('允许仇恨 blue → red',1,true) and h.all():find('脱战后拉回 red 累计=1',1,true),h.all())
    -- A summary every 10 s while hooked.
    h.now=10;lock:tick()
    assert(h.all():find('近 10 秒：留在战斗中=2 允许仇恨=2 允许被仇恨=1 脱战后拉回=2',1,true),h.all())
    -- The fight ends: answers go back to the game at once; the hooks go 10 s later.
    h.fighting=false;h.now=11;lock:tick()
    assert(h.call('exit',blue)==nil and h.call('canHate',blueHatred,redActor)==nil,'after the fight the game decides again')
    h.call('transition',red,tag('AI.Transition.CombatToIdle'));assert(#h.dropped==2,'no send-back after the fight')
    h.now=15;lock:tick();assert(#h.unhooked==0)
    h.now=21.5;lock:tick()
    assert(#h.unhooked==6 and lock:status().state=='idle' and h.all():find('摘除挂钩（战斗已结束） 留在战斗中=2',1,true),h.all())
    -- A new fight hooks again.
    h.fighting=true;lock:tick()
    assert(h.ids==12 and h.call('exit',blue)==false)
    lock:silence('test');assert(#h.unhooked==12)
end

-- A unit that leaves the field is no longer answered for.
do
    local h=harness()
    local lock=h.new()
    local actor,blue,blueHatred=h.unit('blue')
    local redActor=h.unit('red')
    h.fighting=true;lock:tick()
    assert(h.call('exit',blue)==false and h.call('canHate',blueHatred,redActor)==true)
    h.members={};lock:tick()
    assert(h.call('exit',blue)==nil and h.call('canHate',blueHatred,redActor)==nil)
end

-- 冷荼 out of reach by her own design: she still hates and stays in combat, but the game answers whether she can
-- be hated. A doll she keeps in reserve is not answered for at all.
do
    local h=harness()
    local lock=h.new()
    local herActor,her,herHatred=h.unit('blue')
    local dollActor,doll,dollHatred=h.unit('blue')
    local redActor,red,redHatred=h.unit('red')
    h.members[1].untargetable=true
    h.members[2].reserve=true
    h.fighting=true;lock:tick()
    assert(h.call('exit',her)==false and h.call('canHate',herHatred,redActor)==true,'she fights')
    assert(h.call('canHate',redHatred,herActor)==nil and h.call('canBeHated',redHatred,herActor)==nil,'the game decides whether she can be hated')
    assert(h.call('exit',doll)==nil and h.call('canHate',dollHatred,redActor)==nil and h.call('canHate',redHatred,dollActor)==nil,'a reserve doll is left to the game')
    h.members[1].untargetable=false;lock:tick()
    assert(h.call('canHate',redHatred,herActor)==true,'once she comes down she may be hated')
end

-- A perception event of a fighting unit asks for its fallback target to go back to its opponent; anyone else's is left alone.
do
    local h=harness()
    local lock=h.new()
    local blueActor,blue=h.unit('blue')
    local redActor,red=h.unit('red')
    local soloActor,solo=h.unit('neutral')
    local mapAI=object('MapAI')
    h.fighting=true;lock:tick()
    assert(h.call('sensed',blue)==nil and h.call('sensedInfo',red)==nil,'the game keeps its own answer')
    h.call('sensed',solo);h.call('sensedInfo',mapAI)
    assert(#h.sensed==2 and h.sensed[1]==tostring(blueActor.GetAddress()) and h.sensed[2]==tostring(redActor.GetAddress()),'fighters only')
    assert(h.all():find('感知后改回对手 blue 累计=1',1,true),h.all())
    h.fighting=false;h.now=1;lock:tick()
    h.call('sensed',blue);assert(#h.sensed==2,'nothing after the fight')
end

-- A missing function is reported; the others still hook. With none found it fails once, not every tick.
do
    local h=harness()
    h.missing={[Lock.paths.transition]=true}
    local lock=h.new();h.unit('blue');h.unit('red');h.fighting=true;lock:tick()
    assert(h.ids==5 and lock:status().state=='running' and h.all():find('找不到函数 '..Lock.paths.transition,1,true))
    local none=harness()
    none.missing={};for _,path in pairs(Lock.paths)do none.missing[path]=true end
    local failed=none.new();none.unit('blue');none.unit('red');none.fighting=true;failed:tick();failed:tick()
    assert(failed:status().state=='failed' and none.ids==0)
    assert(select(2,none.all():gsub('找不到函数 '..Lock.path,''))==1,none.all())
end
do
    local h=harness();local lock=h.new()
    local stand,standAI,standHatred=h.unit('blue')
    local enemy,enemyAI,enemyHatred=h.unit('red')
    h.members[1].stand=true;h.fighting=true;lock:tick()
    assert(h.call('exit',standAI)==nil and h.call('canHate',standHatred,enemy)==nil)
    assert(h.call('canHate',enemyHatred,stand)==nil and h.call('canBeHated',enemyHatred,stand)==nil,
        'the game keeps its unselectable stand answer even when the stand is shown')
    h.call('transition',standAI,tag('AI.Transition.CombatToIdle'));h.call('sensed',standAI)
    assert(#h.dropped==0 and #h.sensed==0)
    assert(h.call('exit',enemyAI)==false,'ordinary combatants keep combat lock')
end
-- A dead unit stops being hatable by this fight's units and comes off their lists once, through the game's remove.
-- Written straight into the array it is not in the corpse's BeHatredList, so the game's OnDead would miss it.
do
    local h=harness()
    local health,lists={},{}
    local lock=h.new({hp=function(actor)return health[actor] end,label=function()return 'Corpse' end,
        hates=function(manager,actor)return lists[manager] and lists[manager][actor]==true end})
    local corpse,corpseAI,corpseHatred=h.unit('red')
    local fighter,fighterAI,fighterHatred=h.unit('blue')
    local other,_,otherHatred=h.unit('blue')
    local mate,_,mateHatred=h.unit('red')
    health[corpse],health[fighter],health[other],health[mate]=100,100,100,100
    lists[fighterHatred]={[corpse]=true}
    lists[otherHatred]={}
    local calls=0
    fighterHatred.RemoveActorFromHatredList=function(_,actor)calls=calls+1;lists[fighterHatred][actor]=nil end
    h.fighting=true;lock:tick()
    assert(h.call('canHate',fighterHatred,corpse)==true,'alive: may be hated')
    health[corpse]=0;lock:tick()
    assert(h.call('canHate',fighterHatred,corpse)==false and h.call('canBeHated',fighterHatred,corpse)==false,'a corpse is refused')
    assert(calls==1 and lists[fighterHatred][corpse]==nil,'taken off the list that held it')
    assert(h.all():find('尸体移出仇恨表 尸体=Corpse 表里有它的单位=1 移出=1 读回仍在=0',1,true),h.all())
    assert(h.call('exit',corpseAI)==nil,'its own AI is left to the game')
    assert(h.call('canHate',fighterHatred,mate)==true,'the living stay hatable')
    lock:tick();assert(calls==1,'only once')
    health[corpse]=50;lock:tick()
    assert(h.call('canHate',fighterHatred,corpse)==true,'up again: hatable again')
    lists[fighterHatred][corpse]=true;health[corpse]=0;lock:tick()
    assert(calls==2,'a second death is forgotten again')
    -- Health that cannot be read counts as alive.
    health[other]=nil;lock:tick()
    assert(h.call('canHate',mateHatred,other)==true)
    assert(lock:status().refused==2,tostring(lock:status().refused))
end
-- The list that keeps a corpse after the remove says so.
do
    local h=harness()
    local health={}
    local lock=h.new({hp=function(actor)return health[actor] end,hates=function()return true end})
    local corpse=h.unit('red');local fighter,_,fighterHatred=h.unit('blue')
    health[corpse],health[fighter]=0,100
    fighterHatred.RemoveActorFromHatredList=function()end
    h.fighting=true;lock:tick()
    assert(h.all():find('移出=0 读回仍在=1',1,true),h.all())
end
-- A mount hates the way its rider does, stays in combat and is sent back, and is never hated itself.
do
    local h=harness()
    local mount,mountAI,mountHatred=object('Horse'),object('HorseAI'),object('HorseHatred')
    h.ai[mount]=mountAI;h.hatred[mount]=mountHatred
    local lock=h.new({vehicles=function()return {{actor=mount,team='blue'}} end})
    local rider=h.unit('blue');local enemy,_,enemyHatred=h.unit('red')
    h.fighting=true;lock:tick()
    assert(h.call('canHate',mountHatred,enemy)==true,'the mount may hate the other side')
    assert(h.call('canHate',mountHatred,rider)==nil,'not its own side')
    assert(h.call('exit',mountAI)==false,'stays in combat')
    assert(h.call('canHate',enemyHatred,mount)==false and h.call('canBeHated',enemyHatred,mount)==false,'nobody targets the mount')
    h.call('transition',mountAI,tag('AI.Transition.CombatToIdle'))
    assert(#h.dropped==1 and h.dropped[1]==tostring(mount.GetAddress()),'sent back by its own address')
    h.fighting=false;lock:tick()
    assert(h.call('canHate',enemyHatred,mount)==nil,'after the fight the game answers again')
end
print('combat_lock: PASS (hooks only in a fight, exit held, hatred allowed for opposite sides only, send-back on CombatToIdle, perception fallback, summary, unhook, rehook, leave, missing functions, stands, corpses, mounts)')
