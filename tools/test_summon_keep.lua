package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Keep=require('summon_keep')
local n,passed=0,0
local function object(fields)
    n=n+1;local key=n
    local o=fields or {};o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()assert(o.alive);return key end
    return o
end
-- The code under test wraps its calls in pcall, so an error alone would go unnoticed: each access is counted. In the
-- game such an access is a native crash that pcall does not stop.
local illegal=0
local function dead()
    return setmetatable({IsValid=function()return false end,type=function()return 'UObject' end},
        {__index=function(_,key)illegal=illegal+1;error('invalid dereference: '..key)end})
end
local function class(name)
    return object({GetFName=function()return {ToString=function()return name end}end})
end
local function actor(name)
    local cls=class(name)
    return object({GetClass=function()return cls end})
end
-- As in the game: FName is callable but is not a Lua function.
FName=setmetatable({},{__call=function(_,s)return s end})
local function test(name,fn)fn();passed=passed+1;print('ok - '..name)end

-- The passive as its blueprint behaves (GA_SummonPassive_MonsterBase, ExecuteUbergraph):
-- combat 0x0110: a wait is started unless WaitOffCombatTask is still valid; idle 0x001d: the summons are destroyed.
local function passive(owner,board)
    local stands={actor('BP_Monster_Yuu_Stand_C'),actor('BP_Monster_TieGui_Stand_C')}
    local a=object({GetAvatarActorFromActorInfo=function()return owner end,
        SpawnedSummonInstances={{Pawn=stands[1],bPawnPending=false},{Pawn=stands[2],bPawnPending=false}}})
    a.ai=object({CurrentStateTag={TagName='AI.State.Idle'},BlackboardComponent=object({GetValueAsObject=function(_,key)
        return key=='AssignActor1' and stands[1] or key=='AssignActor2' and stands[2] or nil end})})
    owner.ai=a.ai
    function a:combat()
        self.ai.CurrentStateTag={TagName='AI.State.Combat'}
        if self.WaitOffCombatTask and self.WaitOffCombatTask:IsValid() then return end
        local task=object({})
        task.EndTask=function(t)t.ended=(t.ended or 0)+1;t.alive=false end
        self.WaitOffCombatTask=task
    end
    function a:idle()
        self.ai.CurrentStateTag={TagName='AI.State.Idle'}
        local task=self.WaitOffCombatTask
        if task and task:IsValid() then
            self.WaitOffCombatTask=nil
            for _,row in ipairs(self.SpawnedSummonInstances)do row.Pawn.alive=false end
            self.destroyed=true
        end
    end
    return a
end
local function fixture()
    local f={now=0,logs={},hooks={},ids=0,finds=0,members={},loaded=true}
    StaticFindObject=function(path)
        assert(path==Keep.path,path)
        f.finds=f.finds+1
        return f.loaded and object({}) or nil
    end
    RegisterHook=function(path,callback)f.ids=f.ids+1;f.hooks[path]=callback;return f.ids,f.ids+100 end
    UnregisterHook=function(path)f.hooks[path]=nil end
    f.boss=actor('BP_Monster_MuXiaoKui_P2_C')
    f.members={{actor=f.boss,team='companion'}}
    f.ability=passive(f.boss)
    f.keep=Keep.new({members=function()return f.members end,clock=function()return f.now end,
        aiOf=function(a)return a.ai end,log=function(s)f.logs[#f.logs+1]=s end})
    f.keep:tick()
    function f.all()return table.concat(f.logs,'\n')end
    function f.hook(ability)return f.hooks[Keep.path](ability)end
    return f
end
local function param(value)
    return {type=function()return 'RemoteUnrealParam' end,get=function()return value end,
        set=function()error('this hook must not alter parameters')end}
end

test('the summons of a unit of this mod outlive the end of a fight, however many fights it has',function()
    local f=fixture()
    f.keep:passive(f.ability)
    assert(f.hooks[Keep.path],'hooked once a passive of ours is seen')
    for fight=1,3 do
        f.ability:combat();assert(f.hook(param(f.ability))==nil,'no result is replaced')
        local task=f.ability.WaitOffCombatTask
        assert(task.ended==1,'fight '..fight..': the wait is ended as it starts')
        f.ability:idle()
        assert(not f.ability.destroyed,'fight '..fight..': the summons are still there')
        f.keep:passive(f.ability)
    end
    assert(f.keep.ended==3)
    assert(f.all():find('结束脱战销毁召唤物的等待（进入战斗时） 单位=BP_Monster_MuXiaoKui_P2_C 调用=true 读回等待仍有效=false 召唤物=2',1,true),f.all())
end)
test('a unit of the map is left as the game made it',function()
    local f=fixture();f.keep:passive(f.ability)
    local mapBoss=actor('BP_Monster_MuXiaoKui_P2_C')
    local other=passive(mapBoss)
    other:combat();f.hook(param(other))
    assert(other.WaitOffCombatTask.ended==nil,'its wait stays')
    other:idle();assert(other.destroyed,'and its summons go when it leaves combat')
    -- A unit joins at the next tick.
    local joined=actor('BP_Monster_ZuoShang_P2_C')
    local mine=passive(joined)
    f.members[#f.members+1]={actor=joined,team='blue'};f.keep:tick()
    mine:combat();f.hook(mine)
    assert(mine.WaitOffCombatTask.ended==1)
end)
test('combat that started before the hook is in place is caught by the regular check',function()
    local f=fixture()
    f.ability:combat()
    f.keep:passive(f.ability)
    assert(f.ability.WaitOffCombatTask.ended==1)
    f.ability:idle();assert(not f.ability.destroyed)
    assert(f.all():find('（定时检查）',1,true),f.all())
end)
test('an ended task still in its variable is not reported again',function()
    local f=fixture();f.keep:passive(f.ability)
    f.ability:combat();f.hook(f.ability)
    local task=f.ability.WaitOffCombatTask
    task.alive=true -- the collector has not got to it, and the validity check still says yes
    local before=f.keep.ended
    for _=1,5 do f.keep:passive(f.ability) end
    assert(f.keep.ended==before,'one report for one task')
    assert(select(2,f.all():gsub('结束脱战销毁召唤物的等待',''))==1)
end)
test('a state change reads back the summons and the keys the boss\'s moves look them up by',function()
    local f=fixture();f.keep:passive(f.ability)
    assert(f.all():find('状态 nil -> AI.State.Idle 单位=BP_Monster_MuXiaoKui_P2_C 召唤物读回=2 AssignActor1=BP_Monster_Yuu_Stand_C AssignActor2=BP_Monster_TieGui_Stand_C',1,true),f.all())
    f.ability:combat();f.keep:passive(f.ability)
    assert(f.all():find('状态 AI.State.Idle -> AI.State.Combat',1,true))
    local lines=#f.logs
    f.keep:passive(f.ability);assert(#f.logs==lines,'nothing new, nothing logged')
end)
test('the blueprint not being loaded is asked again with growing gaps',function()
    local f=fixture();f.loaded=false
    for i=0,300 do f.now=i;f.keep:passive(f.ability) end
    assert(next(f.hooks)==nil and f.finds<=10,'lookups in five minutes: '..f.finds)
    f.loaded=true
    for i=301,400 do f.now=i;f.keep:passive(f.ability) end
    assert(f.hooks[Keep.path],'found once it is loaded')
end)
test('invalid objects are never dereferenced',function()
    local f=fixture()
    f.members[#f.members+1]={actor=dead(),team='blue'};f.keep:tick();f.members[#f.members]=nil
    f.keep:passive(dead())
    f.keep:passive(f.ability)
    f.hook(dead())
    f.hook(param(dead()))
    f.ability.WaitOffCombatTask=dead();f.keep:passive(f.ability)
    f.ability.WaitOffCombatTask=nil
    local noOwner=passive(actor('X'));noOwner.GetAvatarActorFromActorInfo=function()return dead()end
    f.hook(noOwner);f.keep:passive(noOwner)
    noOwner.SpawnedSummonInstances={{Pawn=dead()}};f.keep:passive(noOwner)
    assert(illegal==0,'accessed an invalid object '..illegal..' times')
end)
test('no units and unload remove the hook; a saved callback does nothing',function()
    local f=fixture();f.keep:passive(f.ability)
    local list=f.members
    f.members={};f.keep:tick();assert(next(f.hooks)==nil,'nobody left')
    f.members=list;f.now=20;f.keep:tick();f.keep:passive(f.ability)
    local saved=f.hooks[Keep.path];assert(saved)
    f.keep:silence();assert(next(f.hooks)==nil)
    f.ability:combat();assert(saved(f.ability)==nil and f.ability.WaitOffCombatTask.ended==nil)
    local lines=#f.logs
    f.keep:passive(f.ability);f.keep:tick();assert(#f.logs==lines)
end)
print('summon_keep: '..passed..' tests passed')
