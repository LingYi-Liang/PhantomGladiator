package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Probe=dofile('Mods/PhantomGladiator/Scripts/difficulty_probe.lua')
-- Fixture objects refuse writes, so a probe that changed anything would fail here.
local function object(fields)
    fields.IsValid=function()return true end
    return setmetatable(fields,{__newindex=function(_,k)error('probe wrote '..tostring(k))end})
end
local function map(entries)
    return object({ForEach=function(_,fn)for _,e in ipairs(entries)do fn(e[1],e[2])end end})
end
local function config(level,hp)
    return object({['Global Mob Level Offset']=level,['Mob Break Duration']=3,['Mob Break Damage Multiplier']=1.5,['Player Break Damage Multiplier']=1,
        ['Global Mob Attribute Modifiers']=map({{{AttributeName='Health_Max'},{Type=1,Value=hp}}}),
        ['Global Player Attribute Modifiers']=map({}),
        ['Difficulty Settings By Mob Type']=map({{{TagName='Mob.Type.Boss'},{AttributeModifiers=map({{{AttributeName='Attack'},{Type=1,Value=hp/2}}}),SkillTypeDataSetMultipliers=map({{1,2}})}}})})
end
local resident={['/PBZCombatAsset/Config/GlobalConfig_Combat_Normal.GlobalConfig_Combat_Normal']=config(0,1)}
local loaded={}
StaticFindObject=function(path)
    if path=='/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary' then
        return object({GetDiffcultMode=function()return 2 end,GetDifficulty=function()return 'Difficulty.Normal' end})
    end
    return resident[path]
end
LoadAsset=function(path)loaded[#loaded+1]=path;return config(#loaded,#loaded*1.25)end
local lines,ready={},false
local units={}
local probe=Probe.new({log=function(s)lines[#lines+1]=s end,getWorld=function()return object({})end,load=true,
    ready=function()return ready end,members=function()return units end})
probe:tick();assert(#lines==0,'nothing runs before the player is in a map')
ready=true;probe:tick()
local all=table.concat(lines,'\n')
assert(all:find('GetDiffcultMode 调用=true 读回=2',1,true),'current difficulty is read')
assert(all:find('Normal 已在内存=true 本次加载=false',1,true),'the live config is read without loading')
assert(#loaded==4,'the four other difficulty configs are loaded once each')
assert(all:find('Health_Max=1:1',1,true) and all:find('怪物类型 Mob.Type.Boss AttributeModifiers={Attack=1:',1,true),'modifiers and mob types are logged')
assert(all:find('SkillTypeDataSetMultipliers=1',1,true))
assert(all:find('配置探查完成=true',1,true))
local before=#lines;probe:tick();assert(#lines==before,'configs are probed once per Lua lifetime')
units={{actor=object({GetClass=function()return nil end}),class_path='/Game/BP_A.BP_A_C'}}
probe:tick()
assert(table.concat(lines,'\n'):find('单位字段探查完成=true',1,true),'unit fields are probed once units exist')
print('difficulty_probe: PASS (read-only fixtures, current difficulty, resident vs loaded configs, modifiers, once-only)')
