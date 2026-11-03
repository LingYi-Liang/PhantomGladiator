-- Read-only probe of how a monster's numbers are built, run after a summon on the summoned unit and on
-- the map NPC its level came from. Nothing is written.
--   1. The actor config's level values (PDA_ActorConfig "Attribute Data": ULevelValue_Plain base/Grow or
--      ULevelValue_ScaledCurve base/CurveScale/NormalizedCurve, SGameCombatSystem.hpp), asked for their
--      value at several levels through ULevelValueBase.GetValue, next to the curve's own values, and
--      which simple formula reproduces GetValue at every level asked.
--   2. The difficulty config the unit uses (PDA_GlobalCombatConfig: Global Mob Level Offset, Global Mob
--      Attribute Modifiers, Difficulty Settings By Mob Type for the unit's Difficulty Tag).
--   3. The value predicted from 1 and 2 next to the unit's attribute and its _Lv1 attribute.
local U=require('ue_observe')
local Stats=require('character_stats')
local Probe={}
-- Level value field in "Attribute Data" -> the attribute it initialises.
Probe.stats={{'MaxHealth','Health_Max'},{'MaxShachi','Shachi_Max'},{'Attack','Attack'},{'ShachiAttack','ShachiAttack'}}
local LEVELS={0,1,2,5,10,15,18,20,25,30,40}
local CURVE_POINTS=40
-- EGenericValueModifyType (SGameUtils_enums.hpp).
local MODIFY={[0]='加',[1]='乘',[2]='加倍率',[3]='覆盖',[4]='取大',[5]='取小'}
local function configPath(name)return '/PBZCombatAsset/Config/GlobalConfig_Combat_'..name..'.GlobalConfig_Combat_'..name end

local function num(v)v=U.unwrap(v);return type(v)=='number' and v==v and v or nil end
local function text(v)
    v=U.unwrap(v)
    if v==nil then return 'nil' end
    if type(v)~='userdata' and type(v)~='table' then return tostring(v) end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string' and s or U.kind(v)
end
local function name(obj)
    if not U.valid(obj) then return 'nil' end
    local ok,n=pcall(function()return obj:GetFName():ToString()end)
    return ok and type(n)=='string' and n or '?'
end
local function className(obj)
    if not U.valid(obj) then return 'nil' end
    local ok,cls=pcall(function()return obj:GetClass()end)
    return ok and name(cls) or '?'
end
local function tagName(tag)
    local n=U.struct(tag,'TagName')
    return n~=nil and text(n) or text(tag)
end
local function attributeName(attribute)
    local n=U.struct(attribute,'AttributeName')
    return n~=nil and text(n) or text(attribute)
end
local function fmt(v)
    if not v then return 'nil' end
    local s=string.format('%.4f',v):gsub('0+$','')
    return (s:gsub('%.$',''))
end
local function close(a,b)return a and b and math.abs(a-b)<=math.max(0.01,math.abs(b)*1e-4) end
local function eachMap(map,fn)
    map=U.unwrap(map)
    if map==nil then return false end
    return pcall(function()map:ForEach(function(k,v)fn(U.unwrap(k),U.unwrap(v))end)end)
end

-- Candidate formulas for a level value; the probe reports those that match GetValue at every level.
function Probe.formulas(kind,f)
    if kind=='LevelValue_ScaledCurve' then
        return {
            {'base×(1+scale×curve)',function(c,_)return f.base*(1+f.scale*c)end},
            {'base×scale×curve',function(c,_)return f.base*f.scale*c end},
            {'base×curve',function(c,_)return f.base*c end},
            {'base+scale×curve',function(c,_)return f.base+f.scale*c end},
            {'base×(1+scale×(curve-1))',function(c,_)return f.base*(1+f.scale*(c-1))end},
        }
    elseif kind=='LevelValue_Plain' then
        return {
            {'base+grow×L',function(_,l)return f.base+f.grow*l end},
            {'base×(1+grow×L)',function(_,l)return f.base*(1+f.grow*l)end},
            {'base×(1+grow)^L',function(_,l)return f.base*(1+f.grow)^l end},
            {'base+grow×(L-1)',function(_,l)return f.base+f.grow*(l-1)end},
        }
    end
    return {}
end
function Probe.matching(kind,f,samples)
    local found={}
    for _,candidate in ipairs(Probe.formulas(kind,f))do
        local all=#samples>0
        for _,s in ipairs(samples)do
            if not close(candidate[2](s.curve or 0,s.level),s.value) then all=false;break end
        end
        if all then found[#found+1]=candidate[1] end
    end
    return found
end

function Probe.new(options)
    local log=options.log or function()end
    local stats=options.attributes or Stats.new()
    local self={}
    local curvesLogged={}
    local function say(m)log('[StatFormula] '..m)end
    local function getValue(levelValue,level)
        if not U.valid(levelValue) then return nil end
        local ok,v=pcall(function()return levelValue:GetValue(level)end)
        return ok and num(v) or nil
    end
    local function curveAt(curve,t)
        if not U.valid(curve) then return nil end
        local ok,v=pcall(function()return curve:GetFloatValue(t)end)
        return ok and num(v) or nil
    end
    local function logCurve(curve)
        local key=U.key(curve)
        if not key or curvesLogged[key] then return end
        curvesLogged[key]=true
        local values={}
        for t=0,CURVE_POINTS do values[#values+1]=fmt(curveAt(curve,t)) end
        say('曲线 '..name(curve)..' 0..'..CURVE_POINTS..'级=['..table.concat(values,',')..']')
    end
    -- {kind, base, grow|scale, curve, samples={level,value,curve}} for one level value.
    local function readLevelValue(levelValue)
        local kind=className(levelValue)
        local f={kind=kind,base=num(U.field(levelValue,'base')),grow=num(U.field(levelValue,'Grow')),
            scale=num(U.field(levelValue,'CurveScale')),curve=U.field(levelValue,'NormalizedCurve')}
        f.samples={}
        for _,level in ipairs(LEVELS)do
            local value=getValue(levelValue,level)
            if value then f.samples[#f.samples+1]={level=level,value=value,curve=curveAt(f.curve,level)} end
        end
        if U.valid(f.curve) then logCurve(f.curve) end
        return f
    end
    -- The modifiers for one attribute: global first, then the unit's mob type.
    local function modifiersFor(config,difficultyTag,attribute)
        local found={}
        eachMap(U.field(config,'Global Mob Attribute Modifiers'),function(attr,data)
            if attributeName(attr)==attribute then
                found[#found+1]={from='全局',type=num(U.struct(data,'Type')),value=num(U.struct(data,'Value'))}
            end
        end)
        eachMap(U.field(config,'Difficulty Settings By Mob Type'),function(tag,settings)
            if tagName(tag)==difficultyTag then
                eachMap(U.struct(settings,'AttributeModifiers'),function(attr,data)
                    if attributeName(attr)==attribute then
                        found[#found+1]={from='类型',type=num(U.struct(data,'Type')),value=num(U.struct(data,'Value'))}
                    end
                end)
            end
        end)
        return found
    end
    local function apply(value,modifiers)
        if not value then return nil end
        for _,m in ipairs(modifiers)do
            if m.type==0 then value=value+(m.value or 0)
            elseif m.type==1 then value=value*(m.value or 1)
            elseif m.type==3 then value=m.value or value end
        end
        return value
    end
    local function describe(modifiers)
        local parts={}
        for _,m in ipairs(modifiers)do parts[#parts+1]=m.from..(MODIFY[m.type] or tostring(m.type))..fmt(m.value) end
        return #parts>0 and table.concat(parts,' ') or '无'
    end

    -- label: '召唤' or '地图怪'; difficulty: the difficulty whose config the unit uses ('Easy', 'Nightmare'...).
    function self:unit(actor,label,difficulty)
        if not U.valid(actor) then return end
        local actorConfig=U.field(actor,'Actor Config')
        local difficultyTag=tagName(U.field(actorConfig,'Difficulty Tag'))
        local level=num(U.field(actor,'Level'))
        local okCombat,combat=pcall(function()return actor:GetCombatLevel()end)
        combat=okCombat and num(combat) or nil
        local config=difficulty and StaticFindObject(configPath(difficulty))
        local offset=U.valid(config) and num(U.field(config,'Global Mob Level Offset')) or nil
        say(string.format('%s %s 配置=%s 类型=%s 难度=%s 等级字段=%s 战斗等级=%s 难度等级偏移=%s',label,className(actor),name(actorConfig),
            difficultyTag,tostring(difficulty),fmt(level),fmt(combat),fmt(offset)))
        local data=U.field(actorConfig,'Attribute Data')
        local at=combat or level or 0
        for _,pair in ipairs(Probe.stats)do
            local levelValue=U.struct(data,pair[1])
            local f=readLevelValue(levelValue)
            local values={}
            for _,s in ipairs(f.samples)do values[#values+1]=s.level..':'..fmt(s.value) end
            local formulas=Probe.matching(f.kind,{base=f.base or 0,grow=f.grow or 0,scale=f.scale or 0},f.samples)
            local modifiers=U.valid(config) and modifiersFor(config,difficultyTag,pair[2]) or {}
            local predicted=apply(getValue(levelValue,at),modifiers)
            local actual=stats:read(actor,pair[2])
            local lv1=stats:read(actor,pair[2]..'_Lv1')
            say(string.format('  %s 取值=%s 基础=%s 增长=%s 缩放=%s 曲线=%s 各级=[%s] 公式=%s',pair[1],f.kind,fmt(f.base),fmt(f.grow),fmt(f.scale),
                name(f.curve),table.concat(values,' '),#formulas>0 and table.concat(formulas,'|') or '未匹配'))
            say(string.format('  %s 难度系数=%s 预测(%s级)=%s 实际=%s 比值=%s _Lv1=%s',pair[2],describe(modifiers),fmt(at),fmt(predicted),
                actual and fmt(actual.current) or 'nil',(predicted and actual and predicted~=0) and fmt(actual.current/predicted) or 'nil',
                lv1 and fmt(lv1.current) or 'nil'))
        end
    end
    return self
end
return Probe
