package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local before,only=arg[1],arg[2]
local function fixtures(path,module)
    local save=arg;arg={before and(before..'/'..module..'.lua')or nil,'fixture'}
    local a,b=assert(loadfile(path))();arg=save;return a,b
end
local make,obj=fixtures('tools/test_combat_continuity.lua','combat_continuity')
local setup,count=fixtures('tools/test_battle_intent.lua','arena_controller')
local n=0
local function test(id,fn)if only and only~=id then return end;fn();n=n+1;print('PASS '..id)end
test('pause_read_failure',function()
    local h=make();h:block();local brain=h.actor.Controller.BrainComponent
    function brain:IsPaused()if h.failRead then error('temporary read')end;return self.paused end
    local native=h.lib.PauseLogic
    function h.lib:PauseLogic(b,r)native(self,b,r);h.failRead=true end
    h.c:wait(h.actor,h.boss);assert(brain.paused)
    assert(h.c:status().pending>0,'a pause with an unreadable result must retain restoration responsibility')
    h.failRead=false;for _,restore in pairs(h.journal)do assert(restore())end
    assert(not brain.paused,'cleanup must restore a partially confirmed native pause')
end)
test('stop_during_repair',function()
    local h=make();h.hates=false
    h.options.addHatred=function()h.hates=true;h.c:beginTick({},false);return true end
    h.c:maintain(h.actor,h.boss)
    assert(h.held==nil and h.engage==0,'native callbacks after stop cannot write a target or force combat')
end)
test('death_during_repair',function()
    local h=make();h.hates=false
    h.options.addHatred=function()h.hates=true;h.boss.hp=0;return true end
    h.c:maintain(h.actor,h.boss);assert(h.held==nil and h.engage==0,'a just-dead target cannot be used after a callback')
end)
test('protection_changes',function()
    local h=make();assert(h.c:protected(h.boss)==false)
    h.boss.hm.CanBeHatredNow=false;h.hates=false
    h.c:maintain(h.actor,h.boss)
    assert(h.add==0 and h.engage==0 and not h.held,'the write path must recheck live protection rather than a prior false snapshot')
end)
test('casting_during_pause',function()
    local h=make();h:block();local native=h.lib.PauseLogic
    function h.lib:PauseLogic(b,r)native(self,b,r);h.actor.casting=true end
    h.c:wait(h.actor,h.boss)
    assert(h.stop==0 and not h.actor.Controller.BrainComponent.paused,'an action starting during pause acquisition must retain control')
end)
test('stop_during_pause',function()
    local h=make();h:block();local native=h.lib.PauseLogic
    function h.lib:PauseLogic(b,r)native(self,b,r);h.c:beginTick({},false)end
    h.c:wait(h.actor,h.boss)
    assert(h.stop==0 and not h.actor.Controller.BrainComponent.paused,'stop must not leave a late-acquired pause after cleanup')
end)
test('world_transfer',function()
    local h=make();h:block();assert(h.c:wait(h.actor,h.boss))
    h.world=obj('Destination');h.actor.outer=h.world;h.actor.Controller.outer=h.world
    h.c:beginTick({},false)
    assert(not h.actor.Controller.BrainComponent.paused,'a verified same actor/brain now in the current world must recover its owned pause')
end)
local function switching()
    local h=setup();h.boss.protected=true;h.f.arena:tickReinforcements()
    assert(h.f.arena:spawn(nil,'red',1).ok)
    local calls=0;h.f.options.forceAttack=function(a)
        for i=1,50 do if a==h.f.actors[i]then calls=calls+1;break end end
        return true
    end
    return h,function()return calls end
end
test('controller_stop',function()
    local h,calls=switching();h.f.options.resumeIntent=function()h.f.arena:stop();return true end
    h.now=1;h.f.arena:tickReinforcements()
    assert(calls()==0,'a resume callback that stops the roster must abort before forceAttack')
end)
test('controller_cast',function()
    local h,calls=switching()
    h.f.options.resumeIntent=function(a)a.casting=true;return true end
    h.now=1;h.f.arena:tickReinforcements()
    assert(calls()==0,'an action that starts during resume cannot be interrupted by a later forceAttack')
end)
test('name_cost',function()
    local h=make();local names=0;FName=function(s)names=names+1;return s end
    h.actor.ai.CurrentStateTag={TagName='AI.State.Combat'}
    for i=1,200 do h.c:beginTick(h.members,true);h.c:maintain(h.actor,h.boss)end
    print('MEASURE 200 stable maintain ticks FName constructions='..names)
    assert(names<=8,'stable checks should reuse immutable tag names')
end)
test('idle_retry',function()
    local h=make()
    h.options.engage=function()h.engage=h.engage+1;return false end
    for _=1,200 do h.c:maintain(h.actor,h.boss)end
    print('MEASURE same-time rejected idle combat requests='..h.engage)
    assert(h.engage<=1,'failed or delayed combat re-entry must be paced across immediate callbacks')
end)
test('late_action',function()
    local h=make();h:block();assert(h.c:wait(h.actor,h.boss))
    h.actor.casting=true;h.c:beginTick(h.members,true)
    assert(not h.actor.Controller.BrainComponent.paused,'a later native action must not inherit an idle-return pause')
end)
test('stop_before_pause_write',function()
    local h=make();h:block()
    function h.lib:PauseLogic(b)
        h.c:beginTick({},false)
        b.paused=true
    end
    h.c:wait(h.actor,h.boss)
    assert(not h.actor.Controller.BrainComponent.paused and h.stop==0,'a late native write after stop must be rolled back')
end)
test('live_stop_token',function()
    local h=make();local active=true;h.options.context=function()return active and 1 or nil end;h.hates=false
    h.options.addHatred=function()h.hates=true;active=false;return true end
    h.c:maintain(h.actor,h.boss)
    assert(h.engage==0 and h.held==nil,'live arena stop must abort even before the next beginTick snapshot')
end)
test('mixed_stress',function()
    for i=1,1000 do
        local h=make();h:block();local mode=i%5
        if mode==0 then
            local native=h.lib.PauseLogic
            function h.lib:PauseLogic(b,r)native(self,b,r);h.actor.casting=true end
        elseif mode==1 then
            local native=h.lib.PauseLogic
            function h.lib:PauseLogic(b,r)native(self,b,r);h.c:beginTick({},false)end
        end
        h.c:wait(h.actor,h.boss)
        if mode==2 then h.boss.hp=0 elseif mode==3 then h.actor.casting=true end
        h.c:beginTick(h.members,false)
        for _,restore in pairs(h.journal)do assert(restore())end
        assert(not h.actor.Controller.BrainComponent.paused,'mixed stop/phase/action transitions must not strand an owned pause')
        local engage,stop=h.engage,h.stop;h.c:silence();h.c:maintain(h.actor,h.boss);h.c:wait(h.actor,h.boss)
        assert(h.engage==engage and h.stop==stop)
    end
    print('MEASURE mixed callback/cleanup transitions=1000 stranded pauses=0 late mutations=0')
end)
test('stop_and_unread_pause',function()
    local h=make();h:block();local brain=h.actor.Controller.BrainComponent
    function brain:IsPaused()if h.readFails then error('read interrupted')end;return self.paused end
    function h.lib:PauseLogic(b)
        h.c:beginTick({},false)
        b.paused=true;h.readFails=true
    end
    h.c:wait(h.actor,h.boss);assert(brain.paused and h.c:status().pending>0,'a late unknown pause after stop must remain in recovery')
    h.readFails=false
    for _,restore in pairs(h.journal)do restore()end
    assert(not brain.paused)
end)
test('stable_hold_cost',function()
    local h=make();h.options.deferTargetHold=true;h.actor.ai.CurrentStateTag={TagName='AI.State.Combat'}
    local holds,tags=0,0;h.options.holdTarget=function()holds=holds+1;return true end
    for _,a in ipairs({h.actor,h.boss})do
        local native=a.AbilitySystemComponent.GetGameplayTagCount
        a.AbilitySystemComponent.GetGameplayTagCount=function(self,t)tags=tags+1;return native(self,t)end
        local group=a.AbilitySystemComponent.HasAnyMatchingGameplayTags
        a.AbilitySystemComponent.HasAnyMatchingGameplayTags=function(self,t)tags=tags+1;return group(self,t)end
    end
    for _=1,200 do h.c:beginTick(h.members,true);h.c:maintain(h.actor,h.boss)end
    print('MEASURE 200 stable Combat ticks duplicate module target holds='..holds..' protection tag reads='..tags)
    assert(holds==0 and tags<=1600,'stable combat should leave the existing controller cadence responsible for target holding')
end)
for _,callback in ipairs({'maintainTarget','waitForTarget'})do
    test('controller_late_'..callback,function()
        local h=setup();local stopped,late=false,0
        if callback=='waitForTarget'then h.boss.protected=true end
        h.f.options[callback]=function()
            assert(h.f.arena:stop().ok);stopped=true;return true
        end
        h.f.options.holdTarget=function()if stopped then late=late+1 end;return true end
        h.now=1;h.f.arena:tickReinforcements()
        assert(stopped and late==0,'a stopped maintenance/wait callback cannot fall through to fallback target writes')
    end)
end
for _,event in ipairs({'death','montage','phase'})do
    test('controller_maintenance_'..event,function()
        local h=setup()
        local source=h.f.actors[1]
        local changed,holds,locks=false,0,0
        h.f.options.maintainTarget=function(actor)
            if actor==source then
                if event=='death' then actor.hp=0 elseif event=='montage' then actor.casting=true else actor.phase=true end
                changed=true
            end
            return true
        end
        h.f.options.holdTarget=function(actor)if changed and actor==source then holds=holds+1 end end
        h.f.options.releaseLock=function(actor)if changed and actor==source then locks=locks+1 end end
        h.now=1;h.f.arena:tickReinforcements()
        assert(changed and holds==0 and locks==0,event..' during maintenance: fallback writes='..holds..', lock calls='..locks)
    end)
end
print('intent hardening: PASS '..n..' reentrancy/ownership/performance checks; no game accessed')
