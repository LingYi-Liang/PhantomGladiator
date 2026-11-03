package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Probe=require('stat_formula_probe')
local address=0
local function object(name,fields)
    address=address+1;local a=address
    fields=fields or {}
    fields.IsValid=function()return true end
    fields.GetAddress=function()return a end
    fields.GetFName=function()return {ToString=function()return name end}end
    fields.GetClass=function()return {IsValid=function()return true end,GetFName=function()return {ToString=function()return name end}end}end
    return fields
end
local function map(entries)
    return {ForEach=function(_,fn)for _,e in ipairs(entries)do fn(e[1],e[2])end end}
end
local function attribute(name)return {AttributeName=name}end
local function tag(name)return {TagName=name}end
local writes=0

-- A normalized curve: 1 at level 0, +0.5 per level.
local curve=object('C_Health',{GetFloatValue=function(_,t)return 1+0.5*t end})
local function scaled(name,base,scale)
    return object('LevelValue_ScaledCurve',{base=base,CurveScale=scale,NormalizedCurve=curve,
        GetValue=function(_,l)return base*(1+scale*(1+0.5*l))end})
end
local plain=object('LevelValue_Plain',{base=100,Grow=10,GetValue=function(_,l)return 100+10*l end})
local actorConfig=object('ActorC_Test',{['Difficulty Tag']=tag('CharacterType.Difficulty.Standard'),
    ['Attribute Data']={MaxHealth=scaled('h',800,1),MaxShachi=scaled('s',200,0.5),Attack=plain,ShachiAttack=plain}})
local actor=object('BP_Test_C',{['Actor Config']=actorConfig,Level=18,GetCombatLevel=function()return 18 end})
local config=object('GlobalConfig_Combat_Easy',{['Global Mob Level Offset']=0,
    ['Global Mob Attribute Modifiers']=map({{attribute('Attack'),{Type=1,Value=0.7}}}),
    ['Difficulty Settings By Mob Type']=map({
        {tag('CharacterType.Difficulty.Standard'),{AttributeModifiers=map({{attribute('Health_Max'),{Type=1,Value=0.8}}})}},
        {tag('CharacterType.Difficulty.MiniBoss'),{AttributeModifiers=map({{attribute('Health_Max'),{Type=1,Value=9}}})}}})})
StaticFindObject=function(path)
    if path=='/PBZCombatAsset/Config/GlobalConfig_Combat_Easy.GlobalConfig_Combat_Easy' then return config end
end
-- Final attributes as the game would make them; nothing may be written.
local health=800*(1+1*(1+0.5*18))*0.8
local attrs={Health_Max=health,Health_Max_Lv1=800,Attack=(100+180)*0.7,Shachi_Max=200*(1+0.5*(1+9)),ShachiAttack=280}
local stats={read=function(_,_,field)local v=attrs[field];return v and {base=v,current=v} or nil end,
    writeBase=function()writes=writes+1 end}
local lines={}
local probe=Probe.new({log=function(s)lines[#lines+1]=s end,attributes=stats})
probe:unit(actor,'召唤','Easy')
local all=table.concat(lines,'\n')
assert(all:find('召唤 BP_Test_C 配置=ActorC_Test 类型=CharacterType.Difficulty.Standard 难度=Easy 等级字段=18 战斗等级=18 难度等级偏移=0',1,true),all)
assert(all:find('MaxHealth 取值=LevelValue_ScaledCurve 基础=800 增长=nil 缩放=1 曲线=C_Health',1,true),all)
assert(all:find('公式=base×(1+scale×curve)',1,true),all)
assert(all:find('Health_Max 难度系数=类型乘0.8 预测(18级)=7040 实际=7040 比值=1 _Lv1=800',1,true),all)
assert(all:find('Attack 取值=LevelValue_Plain 基础=100 增长=10',1,true) and all:find('公式=base+grow×L',1,true),all)
assert(all:find('Attack 难度系数=全局乘0.7 预测(18级)=196 实际=196 比值=1',1,true),all)
-- The curve is logged once with its values from level 0.
local _,curves=all:gsub('曲线 C_Health 0%.%.40级=%[1,1%.5,2,','')
assert(curves==1,all)
assert(writes==0,'the probe never writes')

-- Matching on its own: only formulas that hold at every sample are reported.
local found=Probe.matching('LevelValue_Plain',{base=100,grow=10,scale=0},{{level=0,value=100},{level=2,value=120}})
assert(#found==1 and found[1]=='base+grow×L',table.concat(found,','))
assert(#Probe.matching('LevelValue_Plain',{base=100,grow=10,scale=0},{{level=2,value=999}})==0)
print('stat_formula_probe ok')
