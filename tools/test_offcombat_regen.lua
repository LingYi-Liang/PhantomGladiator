package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Regen=require('offcombat_regen')
local EMPTY='/Script/GameplayAbilities.GameplayEffect'
local serial=0
local function object(full)
    serial=serial+1
    local out={valid=true,key=serial,full=full}
    function out:IsValid()return self.valid end
    function out:GetAddress()assert(self.valid,'invalid address access');return self.key end
    function out:GetFullName()assert(self.valid,'invalid name access');return self.full end
    return out
end
local function param(value,deny)
    return {value=value,type=function()return 'RemoteUnrealParam'end,get=function(s)return s.value end,
        set=function(s,v)if not deny then s.value=v end end}
end
local function harness()
    local h={now=0,files={},finds=0,counts=0,removes=0,registered=0,unregistered=0,logs={},ready=true}
    h.empty=object('Class '..EMPTY)
    h.defaults=object('GameplayEffect /Script/GameplayAbilities.Default__GameplayEffect')
    h.defaults.DurationPolicy=0
    for _,field in ipairs({'Modifiers','Executions','ApplicationRequirements','ConditionalGameplayEffects','OverflowEffects'})do h.defaults[field]={} end
    h.empty.GetCDO=function()return h.defaults end;h.empty.IsAnyClass=function()return true end
    h.classes={[EMPTY]=h.empty}
    for _,path in ipairs(Regen.effects)do
        h.classes[path]=object('BlueprintGeneratedClass '..path);h.classes[path].IsAnyClass=function()return true end
    end
    h.fn=object('Function '..Regen.path)
    h.actor=object('BP_Test_C /World/Test_1');h.actor.hp=321
    h.asc=object('AbilitySystemComponent /World/Test_1.ASC');h.asc.AvatarActor=h.actor;h.asc.effects={}
    h.actor.AbilitySystemComponent=h.asc
    h.asc.GetGameplayEffectCount=function(s,c)
        assert(s.valid and c.valid,'invalid effect call');h.counts=h.counts+1;return h.badCount and nil or s.effects[c.full] or 0
    end
    h.asc.RemoveActiveGameplayEffectBySourceEffect=function(s,c)
        assert(s.valid and c.valid,'invalid remove');h.removes=h.removes+1;if not h.failRemove then s.effects[c.full]=0 end
    end
    h.members={{actor=h.actor,team='blue'}}
    h.fs={open=function(path,mode)
        if mode=='r' then
            if not h.files[path] then return nil end
            return {read=function()return h.files[path]end,close=function()return true end}
        end
        if h.failWrite then return nil end
        return {write=function(_,text)h.files[path]=text;return true end,close=function()return not h.failClose end}
    end}
    function h:new()
        return Regen.new({path='fixture',io=self.fs,clock=function()return self.now end,
            customActive=function()return self.customActive end,custom=function(a)return self.custom==a end,
            find=function(path)self.finds=self.finds+1;return path==Regen.path and self.fn or self.classes[path]end,
            register=function(_,pre,post)self.registered=self.registered+1;if self.failRegister then error('denied')end;self.pre=pre;self.post=post;return 1,2 end,
            unregister=function()self.unregistered=self.unregistered+1;if self.failUnregister then return false end;self.pre=nil;return true end,
            inGameThread=function()return self.inGame~=false end,
            ready=function()return self.ready end,members=function()self.rosterReads=(self.rosterReads or 0)+1;return self.members end,
            actorOf=self.index and function(key)return self.index[key]end,
            log=function(line)self.logs[#self.logs+1]=line end})
    end
    function h:apply(asc,cls,deny)
        local p=param(cls,deny)
        if self.pre then self.pre(param(asc),p,0,{})end
        if p.value~=self.empty then asc.AvatarActor.hp=asc.AvatarActor.hp+100 end
        if self.post then self.post()end
        return p.value
    end
    h.feature=h:new()
    return h
end
local tests=0
local function check(name,fn)fn();tests=tests+1;print('PASS '..name)end
check('default-off makes no native lookup or health write',function()
    local h=harness();for _=1,20 do h.feature:tick()end
    assert(not h.feature:status().on and h.finds==0 and h.actor.hp==321)
end)
check('both native heals replaced before execution; skill heal and damage remain',function()
    local h=harness();assert(h.feature:set('ON').ok)
    for _,path in ipairs(Regen.effects)do assert(h:apply(h.asc,h.classes[path])==h.empty)end
    assert(h.actor.hp==321 and h.feature:status().blocked==2)
    local skill=object('BlueprintGeneratedClass /Game/GE_SkillHeal.GE_SkillHeal_C')
    assert(h:apply(h.asc,skill)==skill and h.actor.hp==421)
    h.actor.hp=55;h.feature:tick();assert(h.actor.hp==55,'no health lock')
end)
check('native NPC and another owner ASC are untouched',function()
    local h=harness();assert(h.feature:set('ON').ok)
    h.members={};assert(h:apply(h.asc,h.classes[Regen.effects[1]])~=h.empty and h.actor.hp==421)
    h.members={{actor=h.actor}};h.actor.AbilitySystemComponent=object('ASC /Other')
    assert(h:apply(h.asc,h.classes[Regen.effects[1]])~=h.empty)
end)
check('newly owned actor is covered without a battle or previous capture',function()
    local h=harness();assert(h.feature:set('ON').ok)
    h.actor.full='BP_Test_C /World/New_2';h.actor.key=h.actor.key+1000
    assert(h:apply(h.asc,h.classes[Regen.effects[2]])==h.empty)
end)
check('enable removes and verifies an already-running heal',function()
    local h=harness();h.asc.effects[h.classes[Regen.effects[1]].full]=1
    assert(h.feature:set('ON').ok and h.removes==1 and h.feature:status().cleared==1 and h.feature:status().state=='on')
end)
check('unconfirmed removal is paced and retried',function()
    local h=harness();h.asc.effects[h.classes[Regen.effects[1]].full]=1;h.failRemove=true
    assert(h.feature:set('ON').ok and h.feature:status().state=='failed')
    local reads=h.counts;for _=1,20 do h.feature:tick()end;assert(h.counts==reads)
    h.now=0.6;h.failRemove=false;h.feature:tick();assert(h.feature:status().state=='on' and h.removes==2)
end)
check('disable immediately passes even if unhook fails; no catch-up heal',function()
    local h=harness();assert(h.feature:set('ON').ok);h.failUnregister=true
    assert(h.feature:set('OFF').ok and h.actor.hp==321)
    assert(h:apply(h.asc,h.classes[Regen.effects[1]])~=h.empty and h.actor.hp==421)
    local calls=h.unregistered;h.feature:tick();assert(h.unregistered==calls)
    h.now=2;h.failUnregister=false;h.feature:tick();assert(h.feature:status().hooks==0)
end)
check('saved setting reloads; retired callback cannot modify anything',function()
    local h=harness();assert(h.feature:set('ON').ok);local old=h.pre;h.failUnregister=true;h.feature:silence()
    local p=param(h.classes[Regen.effects[1]]);old(param(h.asc),p);assert(p.value~=h.empty)
    h.failUnregister=false;h.feature=h:new();assert(h.feature:status().on);h.feature:tick()
    assert(h:apply(h.asc,h.classes[Regen.effects[1]])==h.empty)
end)
check('write/close failures keep the prior selection',function()
    local h=harness();h.failWrite=true;assert(not h.feature:set('ON').ok and not h.feature.on)
    h.failWrite=false;h.failClose=true;assert(not h.feature:set('ON').ok and not h.feature.on)
    h.failClose=false;assert(h.feature:set('ON').ok);h.failWrite=true;assert(not h.feature:set('OFF').ok and h.feature.on)
    assert(not h.feature:set('MAYBE').ok and h.feature.on)
end)
check('invalid objects and non-game-thread callbacks are never dereferenced',function()
    local h=harness();assert(h.feature:set('ON').ok)
    local cls=h.classes[Regen.effects[1]];h.inGame=false;assert(h:apply(h.asc,cls)==cls)
    h.inGame=true;h.actor.valid=false;assert(h:apply(h.asc,cls)==cls)
    h.actor.valid=true;h.asc.valid=false;assert(h:apply(h.asc,cls)==cls)
    h.asc.valid=true;cls.valid=false;local p=param(cls);h.pre(param(h.asc),p);assert(p.value==cls)
end)
check('nonempty or invalid base defaults fail safely instead of replacing a heal',function()
    local h=harness();h.defaults.Modifiers={1};assert(h.feature:set('ON').ok)
    assert(h.feature:status().state=='failed' and h.registered==0)
    h.defaults.Modifiers={};h.now=2;h.feature:tick();assert(h.feature:status().state=='on')
    h.empty.valid=false;local cls=h.classes[Regen.effects[1]];assert(h:apply(h.asc,cls)==cls)
end)
check('a rejected parameter write is reported and remains failed until a successful interception',function()
    local h=harness();assert(h.feature:set('ON').ok);local cls=h.classes[Regen.effects[1]]
    assert(h:apply(h.asc,cls,true)==cls and h.feature:status().state=='failed')
    h.feature:tick();assert(h.feature:status().state=='failed')
    assert(h:apply(h.asc,cls)==h.empty);h.feature:tick();assert(h.feature:status().state=='on')
end)
check('hook registration failures have a retry deadline',function()
    local h=harness();h.failRegister=true;assert(h.feature:set('ON').ok and h.feature:status().state=='failed')
    for _=1,20 do h.feature:tick()end;assert(h.registered==1)
    h.now=2;h.failRegister=false;h.feature:tick();assert(h.registered==2 and h.feature:status().hooks==1)
end)
check('leaving the world disarms immediately and retains the saved choice',function()
    local h=harness();assert(h.feature:set('ON').ok);h.ready=false;h.feature:tick()
    assert(h.feature:status().on and h.feature:status().state=='waiting' and h.feature:status().hooks==0)
    h.now=2;h.ready=true;h.feature:tick();assert(h.feature:status().state=='on')
end)
check('one custom-healing companion leaves ordinary arena members out of native clearance checks',function()
    local h=harness();h.members[1].team='companion';h.customActive=true;h.custom=h.actor
    local reads=0
    for i=1,100 do
        local npc=object('NPC /Arena.'..i)
        npc.GetFullName=function(a)reads=reads+1;return a.full end
        h.members[#h.members+1]={actor=npc,team='red'}
    end
    for i=1,10 do h.now=i;h.feature:tick() end
    print('MEASURE unrelated opponent name reads during 10 custom-heal ticks='..reads)
    assert(reads==0 and h.feature:canCustomHeal(h.actor))
end)
check('burst of native heals uses the current indexed owner and rejects a recycled address',function()
    local h=harness();h.index={[tostring(h.actor.key)]=h.actor};h.feature=h:new()
    assert(h.feature:set('ON').ok);h.rosterReads=0
    for _=1,200 do assert(h:apply(h.asc,h.classes[Regen.effects[1]])==h.empty) end
    print('MEASURE 200 healing effects: full roster queries='..h.rosterReads)
    assert(h.rosterReads==0)
    local foreign=object('NPC /World/Foreign');foreign.key=h.actor.key
    h.index[tostring(h.actor.key)]=foreign
    assert(h:apply(h.asc,h.classes[Regen.effects[1]])~=h.empty)
end)
print('offcombat_regen: '..tests..' checks passed')
