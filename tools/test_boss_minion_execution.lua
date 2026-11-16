local saved=arg;arg={'fixture'};local make=assert(loadfile('tools/test_arena_executions.lua'))();arg=saved
local function fixture(setting,rank,hp,floor,count)
    local h=make();local source=h.enemy({X=100,Y=0,Z=0},{class='BP_Source'})
    function source:GetFullName()return 'BP_Source actor'end
    local template=h.boss('BP_Config',500,0,{rank='UltimateBoss'})
    source['Actor Config']=template['Actor Config']
    h.members={{actor=source,team='red',class_path='/Game/BP_Source.BP_Source_C'}};h.targets={}
    for i=1,(count or 1)do
        local t=h.boss('BP_Target'..i,hp or 20,floor or 0,{rank=rank or'Mob'})
        function t:GetFullName()return 'BP_Target actor '..i end
        h.attrs[t].Health_Max=100;h.targets[i]=t
        h.tags[t]={['CharacterState.CanWeakExecute.LowHealth']=1}
        h.members[#h.members+1]={actor=t,team='blue',class_path='/Game/BP_Target.BP_Target_C'}
    end
    h.setting=setting
    h.e=h.new({executionPolicyConfigured=function()return true end,executionPolicy=function()return h.setting end})
    return h
end
local function plays(h)local n=0;for _,v in ipairs(h.calls)do if v:match('^play ')then n=n+1 end end;return n end
do
    local h=fixture('off_50');h.e:tick();h.clock=2;h.e:tick()
    assert(plays(h)==0 and h.attrs[h.targets[1]].Health==20,'disabled finishers cannot change ordinary minion health')
end
do
    local h=fixture('on_100');h.e:tick();assert(plays(h)==1,'default must preserve automatic finisher')
    h.setting='off_100';h.e:tick();assert(h.e:status().started==1,'a settings change cannot abort an already-started native action')
end
do
    local h=fixture('off_0','UltimateBoss');h.e:tick();assert(plays(h)==1,'boss phase finishers are outside this rule')
end
do
    local h=fixture('on_0','Mob',1,1,5);h.e:tick();h.clock=2;h.e:tick()
    local dead=0;for _,t in ipairs(h.targets)do if h.attrs[t].Health==0 then dead=dead+1 end end
    assert(plays(h)==0 and dead==1,'final locked minions must be releasable with a one-per-tick native write budget')
end
print('boss minion execution: PASS 4 production-entry scope, animation and final-floor checks; no game accessed')
