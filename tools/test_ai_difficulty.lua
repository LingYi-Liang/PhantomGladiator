package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local AI=dofile('Mods/PhantomGladiator/Scripts/ai_difficulty.lua')
-- Fixture objects refuse writes: the override may only answer through hook return values.
local address=0
local function object(fields,name,outer,class)
    address=address+1;local a=address
    fields.IsValid=function()return true end
    fields.GetAddress=function()return a end
    fields.GetOuter=function()return outer end
    fields.GetFName=function()return {ToString=function()return name end}end
    fields.GetClass=function()return class end
    return setmetatable(fields,{__newindex=function(_,k)error('override wrote '..tostring(k))end})
end
local function class(name)return object({},name)end
local world=object({},'World',nil,class('World'))
local pawn=object({},'MoTian',world,class('BP_Monster_MoTian_C'))
local mob=object({},'MapMob',world,class('BP_Monster_MoTian_C'))
local controller=object({K2_GetPawn=function()return pawn end},'Controller',world,class('BP_PBZAIController_C'))
rawset(pawn,'Controller',controller) -- the index holds the unit and its controller
local mobController=object({K2_GetPawn=function()return mob end},'MobController',world,class('BP_PBZAIController_C'))

-- Simulated UE4SS: /Script/ hooks get pre and post callbacks, blueprint hooks one callback after the
-- function; a non-nil return replaces the result (the later one wins).
-- Hooks come off by id, as in UE4SS. failUnhook[id]: that removal raises, and the hook stops running all the same
-- (v0.38.2 in game: the GetDifficulty pre callback never ran again after a failed removal).
local hooks,registered,unregistered,failUnhook={},0,0,{}
RegisterHook=function(path,first,second)registered=registered+1;hooks[path]={first=first,second=second,id=registered*2};return registered*2,registered*2+1 end
UnregisterHook=function(path,pre)
    unregistered=unregistered+1
    if failUnhook[pre] then
        if hooks[path] and hooks[path].id==pre then hooks[path]=nil end
        error(failUnhook[pre])
    end
    if hooks[path] and hooks[path].id==pre then hooks[path]=nil end
end
local function wrap(v)return {type=function()return 'RemoteUnrealParam' end,get=function()return v end}end
local GAME=1 -- Easy
local function getDifficulty(context)
    local hook=hooks['/Script/ProjectPBZ.PBZBlueprintFunctionLibrary:GetDifficulty']
    local result=GAME
    if hook then
        local pre=hook.first(nil,wrap(context));if pre~=nil then result=pre end
        local post=hook.second(nil,wrap(context));if post~=nil then result=post end
    end
    return result
end
local CONDITION='/PBZCombatAsset/Prototypes/AI/AICondition_AboveDifficulty.AICondition_AboveDifficulty_C:EvaluateCondition'
local DECORATOR='/PBZCombatAsset/Prototypes/AI/BTDecorator_AboveDifficulty.BTDecorator_AboveDifficulty_C:PerformConditionCheckAI'
local function blueprint(path,node,...)
    local result=getDifficulty(node)>=node.Difficulty
    local hook=hooks[path]
    if hook then local r=hook.first(wrap(node),...);if r~=nil then result=r end end
    return result
end
local pool=object({},'AbilityPool_Normal',nil,class('Pool'))
local condition=object({Difficulty=3,EvaluateCondition=function(self,c)return blueprint(CONDITION,self,wrap(c))end},'Condition',pool,class('AICondition_AboveDifficulty_C'))
local btComponent=object({},'BTComponent',controller,class('BTComp'))
local decorator=object({Difficulty=3,PerformConditionCheckAI=function(self,c,p)return blueprint(DECORATOR,self,wrap(c),wrap(p))end},'Decorator',btComponent,class('BTDecorator_AboveDifficulty_C'))
local library=object({GetDifficulty=function(_,c)return getDifficulty(c)end},'Default__PBZBlueprintFunctionLibrary')
local loaded={}
StaticFindObject=function(path)
    if path=='/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary' then return library end
    if path:find('PBZBlueprintFunctionLibrary:',1,true) then return object({},'fn') end
    return loaded[path]
end

local lines,levels,members,now={}, {}, {}, 0
local ai=AI.new({log=function(s)lines[#lines+1]=s end,ready=function()return true end,getWorld=function()return world end,
    members=function()return members end,levelOf=function(actor)return levels[actor:GetAddress()]end,clock=function()return now end})
local function all()return table.concat(lines,'\n')end

members={{actor=pawn},{actor=mob}};ai:tick()
assert(registered==0 and getDifficulty(pawn)==1,'units that follow the game install nothing')
-- The spawn path calls ensure before FinishSpawn: hooked and answering for the new unit right away.
ai:ensure(pawn,'Nightmare')
assert(registered==1,'only GetDifficulty is hooked; GetDiffcultMode was only ever asked by the World')
assert(getDifficulty(pawn)==4,'start-up questions are answered before the unit is a member')
levels[pawn:GetAddress()]='Nightmare';ai:tick()
assert(all():find('读回 GetDifficulty 单位=BP_Monster_MoTian_C 期望=Nightmare(4) 返回=4 World返回=1 结果=true 前回调计数=3',1,true),
    'Lua readback proves the override, leaves the world alone and says which callbacks ran')
assert(getDifficulty(controller)==4 and getDifficulty(mob)==1 and getDifficulty(world)==1)

-- The blueprint checks hook once their class is loaded; the game says Easy (1) < 3.
loaded[CONDITION]=object({},'fn');loaded[DECORATOR]=object({},'fn')
ai:tick();assert(registered==1,'an unloaded check class is looked up at most every 15 s')
now=15;ai:tick()
assert(registered==3,'both blueprint checks are hooked once loaded')
assert(condition:EvaluateCondition(controller)==true,'the shared ability-pool check answers for the unit it evaluates')
assert(condition:EvaluateCondition(mobController)==false,'a map enemy using the same pool keeps the game answer')
assert(decorator:PerformConditionCheckAI(controller,pawn)==true)
assert(all():find('检查节点参数 EvaluateCondition 节点=AICondition_AboveDifficulty_C 1=RemoteUnrealParam:Controller',1,true))
assert(all():find('改写 EvaluateCondition 单位=BP_PBZAIController_C/Nightmare 门槛=3 → true',1,true))
ai:tick()
assert(all():find('读回 EvaluateCondition 门槛=3 单位难度=Nightmare 期望=true 返回=true 游戏难度下应为=false（可区分）结果=true',1,true))
assert(all():find('读回 PerformConditionCheckAI 门槛=3',1,true))

levels[pawn:GetAddress()]=nil;now=16;ai:tick()
assert(getDifficulty(pawn)==1 and condition:EvaluateCondition(controller)==false,'a unit that left the arena gets the game answer after the next tick')
assert(unregistered==0,'hooks stay for a while in case another unit comes')
now=27;ai:tick()
assert(unregistered==3 and next(hooks)==nil and ai:status().state=='idle','ten seconds without leveled units: every hook is removed')
assert(all():find('摘除挂钩 reason=召唤单位已全部离场 摘除=3 失败=0',1,true))

-- Checks that never load (an AI that does not use them) are looked up every 15 s for a minute after a summon,
-- then not again until the next summon: each miss costs 50–60 ms in game.
loaded[CONDITION]=nil;loaded[DECORATOR]=nil
local lookups,find=0,StaticFindObject
StaticFindObject=function(path)if path==CONDITION or path==DECORATOR then lookups=lookups+1 end;return find(path)end
now=100;ai:ensure(pawn,'Nightmare');levels[pawn:GetAddress()]='Nightmare'
for t=100,250,5 do now=t;ai:tick()end
assert(lookups==2*5,'looked up at 0, 15, 30, 45 and 60 s after the summon, then no more: '..lookups)
now=300;ai:ensure(pawn,'Nightmare')
for t=300,320,5 do now=t;ai:tick()end
assert(lookups==2*7,'a new summon looks again: '..lookups)
StaticFindObject=find

-- v0.38.2: the GetDifficulty hook would not come off when the field emptied. The module stayed
-- 'running' with a hook that no longer ran, and units summoned next got the game's AI difficulty.
local DIFFICULTY='/Script/ProjectPBZ.PBZBlueprintFunctionLibrary:GetDifficulty'
local function unit(name)
    local actor=object({},name,world,class('BP_Monster_'..name..'_C'))
    rawset(actor,'Controller',object({},name..'Controller',world,class('BP_PBZAIController_C')))
    return actor
end
levels[pawn:GetAddress()]=nil;members={{actor=mob}};now=400;ai:tick()
local stuck=hooks[DIFFICULTY].id;failUnhook[stuck]='hook busy'
now=411;ai:tick()
assert(ai:status().state=='idle','a hook that would not come off does not keep the module running')
assert(all():find('摘除=0 失败=1（GetDifficulty：',1,true) and all():find('hook busy',1,true),'the failure and its reason are logged')
now=412;ai:tick()
local attempts=unregistered
for t=413,419 do now=t;ai:tick()end
assert(unregistered==attempts,'a stuck hook is retried every 10 s, not every tick')
local biyuan=unit('BiYuan')
now=415;ai:ensure(biyuan,'Hard');levels[biyuan:GetAddress()]='Hard';members={{actor=biyuan},{actor=mob}}
assert(hooks[DIFFICULTY] and hooks[DIFFICULTY].id~=stuck and getDifficulty(biyuan)==3,'the next summon hooks afresh')
now=416;ai:tick()
assert(all():find('读回 GetDifficulty 单位=BP_Monster_BiYuan_C 期望=Hard(3) 返回=3',1,true))
failUnhook[stuck]=nil;now=422;ai:tick()
assert(all():find('补摘挂钩 1 个，剩 0 个',1,true) and getDifficulty(biyuan)==3,'the stuck hook comes off later; the new one stays')

-- A hook can also stop running while the module counts it as in place: a readback whose Lua call never reached the
-- pre callback hooks GetDifficulty again and asks once more.
local heihei=unit('HeiHei');levels[heihei:GetAddress()]='Hard';members={{actor=biyuan},{actor=heihei}}
hooks[DIFFICULTY]=nil;now=430;ai:tick()
assert(all():find('读回 GetDifficulty 单位=BP_Monster_HeiHei_C 期望=Hard(3) 返回=3',1,true)
    and all():find('挂钩没有被调用，重新挂钩后再读回=3',1,true),'a dead hook is replaced and the unit read again')
assert(getDifficulty(heihei)==3 and getDifficulty(mob)==1)

-- The app's warning follows the units on the field: a unit whose readback still fails counts while it is out;
-- once it leaves, the warning goes, and the total stays in the log.
local haha=unit('HaHa');levels[haha:GetAddress()]='Hard';members={{actor=biyuan},{actor=heihei},{actor=haha}}
local register=RegisterHook;RegisterHook=function()return nil end
hooks[DIFFICULTY]=nil;now=440;ai:tick();RegisterHook=register
assert(ai:status().failed==1 and ai:status().failed_total>=1,'a failed unit on the field is reported')
levels[haha:GetAddress()]=nil;members={{actor=biyuan},{actor=heihei}};now=441;ai:tick()
assert(ai:status().failed==0 and ai:status().failed_total>=1,'the warning goes with the unit; the total stays for the log')
print('ai_difficulty: PASS (no hook without a leveled unit, hooked before spawn finishes, address index for unit/controller/node, readbacks, map and world untouched, removed when units leave, check lookups only after a summon, stuck and dead hooks, warning for units on the field)')
