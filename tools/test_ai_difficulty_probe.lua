package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Probe=dofile('Mods/PhantomGladiator/Scripts/ai_difficulty_probe.lua')
-- Fixture objects refuse writes, so a probe that changed anything would fail here.
local address=0
local function object(fields,name,outer)
    address=address+1;local a=address
    fields.IsValid=function()return true end
    fields.GetAddress=function()return a end
    fields.GetFullName=function()return 'Object '..name end
    fields.GetOuter=function()return outer end
    return setmetatable(fields,{__newindex=function(_,k)error('probe wrote '..tostring(k))end})
end
local function map(entries)
    return object({type=function()return 'TMap' end,ForEach=function(_,fn)for _,e in ipairs(entries)do fn(e[1],e[2])end end},'map')
end
local function class(names)
    local c=object({ForEachProperty=function(_,fn)for _,n in ipairs(names)do fn({GetFName=function()return {ToString=function()return n end}end})end end,
        GetSuperStruct=function()return nil end,GetFName=function()return {ToString=function()return 'Cfg_C' end}end},'class')
    return c
end
local combatClass=class({'Lie Duration','OverrideAIParameters','Punish'})
local mechanicClass=class({'Damage Calculator'})
local function combat(level,aggression)
    local params={FloatParameters=map(aggression and {{'Aggression',aggression}} or {}),BoolParameters=map({})}
    local punish={type=function()return 'TArray' end,ForEach=function(_,fn)fn(1,aggression and 2 or 1)end}
    return object({GetClass=function()return combatClass end,['Lie Duration']=1.5,OverrideAIParameters=params,Punish=punish},'Combat_'..level)
end
local calculators={Easy=object({},'Calc_Easy'),Hard=object({},'Calc_Hard')}
local function mechanic(level)
    local calc=(level=='Hard' or level=='Nightmare') and calculators.Hard or calculators.Easy
    return object({GetClass=function()return mechanicClass end,['Damage Calculator']=calc},'Mechanic_'..level)
end
local resident={}
for _,level in ipairs({'Handicapped','Easy','Normal','Hard','Nightmare'})do
    local hard=level=='Hard' or level=='Nightmare'
    resident['/PBZCombatAsset/Config/GlobalConfig_Combined_'..level..'.GlobalConfig_Combined_'..level]=
        object({['Combat Config']=combat(level,hard and 0.9 or nil),['Mechanic Config']=mechanic(level)},'Combined_'..level)
end
local functions={}
StaticFindObject=function(path)return resident[path] or functions[path] end
LoadAsset=function()error('nothing should need loading')end
local registered,unregistered={},0
RegisterHook=function(path,pre,post)registered[path]={pre=pre,post=post};return #path,#path+1 end
UnregisterHook=function()unregistered=unregistered+1 end

local lines,active,now={},false,0
local pawn=object({GetClass=function()return combatClass end},'BP_Monster_MoTian_C_1')
local other=object({GetClass=function()return combatClass end},'BP_Map_Mob_C_2')
local members={{actor=pawn,team='red'}}
local probe=Probe.new({log=function(s)lines[#lines+1]=s end,ready=function()return true end,members=function()return members end,
    active=function()return active end,levelOf=function(actor)return actor==pawn and 'Hard' or nil end,clock=function()return now end})
probe:tick()
local all=table.concat(lines,'\n')
assert(all:find('配置对比完成=true',1,true))
assert(all:find('差异 Mechanic Config.Damage Calculator',1,true),'differing references are reported')
assert(all:find('Combat Config 字段相同=1 不同=1 未比较=1（OverrideAIParameters）',1,true),'identical fields are only counted; structs are not guessed')
assert(all:find('差异 Combat Config.Punish：Handicapped=TArray[1]{1=1}',1,true) and all:find('Hard=TArray[1]{1=2}',1,true),'arrays are compared by their entries')
assert(all:find('Hard OverrideAIParameters=FloatParameters[1]{Aggression=0.9}',1,true) and all:find('Easy OverrideAIParameters=全空',1,true))
assert(next(registered)==nil,'no hooks before a fight')

-- Hooks wait for a fight; once installed they only count, with the pawn's owner.
local decorator='/PBZCombatAsset/Prototypes/AI/BTDecorator_SwitchDifficulty.BTDecorator_SwitchDifficulty_C:PerformConditionCheckAI'
functions[decorator]=object({},'fn');functions['/Script/ProjectPBZ.PBZBlueprintFunctionLibrary:GetDiffcultMode']=object({},'fn2')
active=true;probe:tick()
assert(registered[decorator] and registered[decorator].post==nil,'blueprint hook takes the single supported callback')
local node=object({Difficulty=3},'Decorator_1',object({},'BTComponent'))
local wrap=function(v)return {type=function()return 'RemoteUnrealParam' end,get=function()return v end}end
for _=1,5 do registered[decorator].pre(wrap(node),wrap(nil),wrap(pawn))end
registered[decorator].pre(wrap(node),wrap(nil),wrap(other))
registered['/Script/ProjectPBZ.PBZBlueprintFunctionLibrary:GetDiffcultMode'].pre(wrap(nil),wrap(pawn))
all=table.concat(lines,'\n')
assert(all:find('本Mod单位=red/Hard 节点难度=3',1,true) and all:find('本Mod单位=否 节点难度=3',1,true))
assert(select(2,all:gsub('首次 decorator',''))==2,'each caller is logged once')
now=200;probe:tick()
all=table.concat(lines,'\n')
assert(all:find('行为树节点调用=6',1,true) and all:find('GetDiffcultMode调用=1',1,true) and unregistered==2)
local before=#lines;probe:tick();assert(#lines==before,'one window per Lua lifetime')
print('ai_difficulty_probe: PASS (read-only fixtures, config diff, AI parameters, fight-gated hooks, owner labels, bounded window)')
