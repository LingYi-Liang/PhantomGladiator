package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
if arg[1]then package.loaded.arena_executions=assert(loadfile(arg[1]))()end
local saved=arg;arg={'fixture'};local make=assert(loadfile('tools/test_arena_executions.lua'))();arg=saved
local function fixture(mode)
    local h=make();local target=h.boss('BP_FinalTarget',1,1,{rank='NormalBoss',pairs={}})
    h.identity='BP_FinalTarget_0'
    function target:GetFullName()if h.unknownIdentity then error('identity unreadable')end;return h.identity end
    h.world={IsValid=function()return true end,GetAddress=function()return 77 end}
    h.attrs[target].Health_Max=300;h.target=target;h.attempts=0;h.allow=false;h.phase=false
    local native=target.AbilitySystemComponent.BP_ApplyGameplayEffectToSelf
    target.AbilitySystemComponent.BP_ApplyGameplayEffectToSelf=function(self,...)
        h.attempts=h.attempts+1
        if h.unknown then h.attrs[target].Health=nil elseif h.allow then return native(self,...)end
    end
    h.members={{actor=target,team='red'}}
    h.e=h.new({killOnLock=mode=='card'and function()return true end or nil,phaseBusy=function()return h.phase end,getWorld=function()return h.world end,
        staticFind=function(path)
            if path:find('GE_Kill',1,true)and h.onLookup then h.onLookup()end
            return h.found[path]
        end})
    h.e:tick();if mode=='stuck'then h.clock=21;h.e:tick()end
    return h
end
local count=0
for _,mode in ipairs({'card','stuck'})do
    local h=fixture(mode);assert(h.attempts==1 and h.attrs[h.target].Health_Min==0)
    assert(h.e:status().kills==0,mode..': accepted call without HP zero must not count as death')
    local start=h.clock;for i=1,10 do h.clock=start+i*.05;h.e:tick()end
    assert(h.attempts==1,mode..': failed final death cannot retry every frame')
    h.allow=true;h.clock=start+1.1;h.e:tick()
    assert(h.attempts==2 and h.attrs[h.target].Health==0 and h.e:status().kills==1,mode..': removing the floor cannot lose the pending death retry')
    h.clock=start+5;h.e:tick();assert(h.attempts==2 and h.e:status().kills==1)
    count=count+1;print('PASS '..mode..' confirmed final death after paced retry')
end
do
    local h=fixture('card');h.unknown=true;h.clock=1.1;h.e:tick();assert(h.e:status().kills==0 and h.attempts==2)
    h.clock=5;h.e:tick();assert(h.attempts==2,'unknown HP cannot authorize a new lethal call')
    h.unknown=false;h.allow=true;h.attrs[h.target].Health=1;h.clock=6;h.e:tick();assert(h.e:status().kills==1)
    count=count+1;print('PASS unknown HP preserves pending retry without new native writes')
end
for _,mode in ipairs({'card','stuck'})do
    local h=fixture(mode);local start=h.clock;h.allow=true;h.phase=true;h.clock=start+2;h.e:tick();assert(h.attempts==1)
    h.phase=false;h.attrs[h.target].Health=123;h.attrs[h.target].Health_Min=123;h.clock=start+3;h.e:tick()
    assert(h.attempts==1 and h.e:status().kills==0,'a later phase floor must cancel the old final-death request')
    count=count+1;print('PASS '..mode..' native phase/healing supersedes pending final death')
end
for _,change in ipairs({'identity','world','stop','immortal'})do
    local h=fixture('card');h.allow=true
    if change=='identity'then h.identity='Replacement actor'
    elseif change=='world'then h.world={IsValid=function()return true end,GetAddress=function()return 88 end}
    elseif change=='stop'then h.e:stop('cancel test')
    else h.immortal.red=true end
    h.clock=2;h.e:tick();assert(h.attempts==1 and h.e:status().kills==0,change..' cannot authorize a stale final-death retry')
    count=count+1;print('PASS '..change..' cancels or blocks pending death')
end
do
    local h=fixture('card');h.allow=true;h.unknownIdentity=true;h.clock=2;h.e:tick();assert(h.attempts==1)
    h.unknownIdentity=false;h.clock=3;h.e:tick();assert(h.attempts==2 and h.e:status().kills==1)
    count=count+1;print('PASS unread identity defers without losing completion responsibility')
end
for _,mode in ipairs({'card','stuck'})do
    for _,change in ipairs({'stop','leave','phase','heal','floor','immortal','world','identity'})do
        local h=fixture(mode);local start=h.clock;h.allow=true
        h.onLookup=function()
            if change=='stop'then h.e:stop('reentrant stop')
            elseif change=='leave'then h.members={}
            elseif change=='phase'then h.phase=true
            elseif change=='heal'then h.attrs[h.target].Health=100
            elseif change=='floor'then h.attrs[h.target].Health_Min=100
            elseif change=='immortal'then h.immortal.red=true
            elseif change=='world'then h.world={IsValid=function()return true end,GetAddress=function()return 88 end}
            else h.identity='Replacement actor'end
        end
        h.clock=start+2;h.e:tick()
        assert(h.attempts==1,mode..' '..change..': callback before lethal call must invalidate the request')
        count=count+1;print('PASS '..mode..' '..change..' during native lookup aborts stale lethal call')
    end
end
print('execution final retry: PASS '..count..' real-entry readback/retry/phase checks; no game accessed')
