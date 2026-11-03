-- Read-only difficulty probe. Logs the difficulty the game reports, the mob modifiers of every
-- /PBZCombatAsset/Config/GlobalConfig_Combat_<difficulty> asset (ProjectPBZ.hpp, PBZCombatAsset.hpp,
-- PDA_GlobalCombatConfig.hpp, SGameUtils.hpp), and which config/difficulty fields the app's units carry.
-- It writes nothing to game objects; the only side effect is loading the four other small config assets.
local U=require('ue_observe')
local Probe={}
local DIFFICULTIES={'Handicapped','Easy','Normal','Hard','Nightmare'}
local LIBRARY='/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary'
local SCALARS={'Global Mob Level Offset','Mob Break Duration','Mob Break Damage Multiplier','Player Break Damage Multiplier'}
local function assetPath(name)return '/PBZCombatAsset/Config/GlobalConfig_Combat_'..name..'.GlobalConfig_Combat_'..name end

local function text(v)
    v=U.unwrap(v)
    if v==nil then return 'nil' end
    if type(v)=='number' or type(v)=='boolean' or type(v)=='string' then return tostring(v) end
    local ok,s=pcall(function()return v:ToString()end)
    if ok and type(s)=='string' then return s end
    return U.kind(v)
end
local function tagName(tag)
    local name=U.struct(tag,'TagName')
    return name~=nil and text(name) or text(tag)
end
local function attributeName(attribute)
    local name=U.struct(attribute,'AttributeName')
    return name~=nil and text(name) or text(attribute)
end
-- TMap:ForEach with a cap; returns readable,total.
local function eachMap(map,limit,fn)
    map=U.unwrap(map)
    if map==nil then return false,0 end
    local count=0
    local ok=pcall(function()
        map:ForEach(function(key,value)
            count=count+1
            if count<=limit then fn(U.unwrap(key),U.unwrap(value)) end
        end)
    end)
    return ok,count
end
local function modifiers(map)
    local parts={}
    local ok,count=eachMap(map,60,function(attribute,data)
        parts[#parts+1]=attributeName(attribute)..'='..text(U.struct(data,'Type'))..':'..text(U.struct(data,'Value'))
    end)
    if not ok then return 'unreadable' end
    return '{'..table.concat(parts,', ')..'} count='..count
end

function Probe.new(options)
    local self={done=false}
    local log=options.log or function()end
    local function say(message)log('[DifficultyProbe] '..message)end

    local function currentDifficulty()
        local library=StaticFindObject(LIBRARY)
        local world=options.getWorld and options.getWorld()
        if not U.valid(library) or not U.valid(world) then say('函数库或World无效，未读取当前难度');return end
        for _,name in ipairs({'GetDiffcultMode','GetDifficulty'})do
            local ok,value=pcall(function()return library[name](library,world)end)
            say(name..' 调用='..tostring(ok)..' 读回='..(ok and text(value) or tostring(value)))
        end
    end

    local function dumpConfig(name)
        local path=assetPath(name)
        local config=StaticFindObject(path)
        local resident=U.valid(config)
        if not resident and options.load then
            local ok,value=pcall(LoadAsset,path)
            config=ok and value or nil
        end
        say(name..' 已在内存='..tostring(resident)..' 本次加载='..tostring(not resident and U.valid(config))..' 可读='..tostring(U.valid(config)))
        if not U.valid(config) then return end
        for _,field in ipairs(SCALARS)do say(name..' '..field..'='..text(U.field(config,field)))end
        say(name..' Global Mob Attribute Modifiers='..modifiers(U.field(config,'Global Mob Attribute Modifiers')))
        say(name..' Global Player Attribute Modifiers='..modifiers(U.field(config,'Global Player Attribute Modifiers')))
        local ok,count=eachMap(U.field(config,'Difficulty Settings By Mob Type'),40,function(tag,settings)
            local _,skills=eachMap(U.struct(settings,'SkillTypeDataSetMultipliers'),0,function()end)
            say(name..' 怪物类型 '..tagName(tag)..' AttributeModifiers='..modifiers(U.struct(settings,'AttributeModifiers'))..' SkillTypeDataSetMultipliers='..skills)
        end)
        say(name..' Difficulty Settings By Mob Type 可读='..tostring(ok)..' 条目='..count)
    end

    -- Which reflected fields tie a unit to its config and difficulty tag; names only, values for tags.
    local function dumpUnits()
        local members=options.members and options.members() or {}
        say('当前登记单位='..#members)
        for index,entry in ipairs(members)do
            if index>4 then break end
            local actor=entry.actor
            if U.valid(actor) then
                local found={}
                local okClass,class=pcall(function()return actor:GetClass()end)
                for _=1,12 do
                    if not okClass or not U.valid(class) then break end
                    pcall(function()
                        class:ForEachProperty(function(property)
                            local okName,name=pcall(function()return property:GetFName():ToString()end)
                            if okName and type(name)=='string' and (name:find('Config') or name:find('Difficult')) and #found<24 then
                                found[#found+1]=name
                            end
                        end)
                    end)
                    okClass,class=pcall(function()return class:GetSuperStruct()end)
                end
                say('单位 '..tostring(entry.class_path)..' 含Config/Difficult的字段='..(#found>0 and table.concat(found,',') or '无'))
                for _,name in ipairs(found)do
                    local value=U.field(actor,name)
                    if U.valid(value) then
                        local tag=U.field(value,'Difficulty Tag')
                        say('  '..name..'='..text(value)..(tag~=nil and (' Difficulty Tag='..tagName(tag)) or ''))
                    end
                end
            end
        end
    end

    function self:run()
        say('开始只读探查：当前难度和5个GlobalConfig_Combat资产；不写任何游戏对象')
        currentDifficulty()
        for _,name in ipairs(DIFFICULTIES)do
            local ok,err=pcall(dumpConfig,name)
            if not ok then say(name..' 读取异常='..tostring(err))end
        end
    end

    -- Configs once per Lua lifetime after the player is in a map; unit fields once the app has
    -- summoned something. A mod reload runs both again.
    function self:tick()
        if not options.ready() then return end
        if not self.done then
            self.done=true
            local ok,err=pcall(function()self:run()end)
            say('配置探查完成='..tostring(ok)..(ok and '' or ' 错误='..tostring(err)))
        end
        if not self.unitsDone and options.members and #options.members()>0 then
            self.unitsDone=true
            local ok,err=pcall(dumpUnits)
            say('单位字段探查完成='..tostring(ok)..(ok and '' or ' 错误='..tostring(err)))
        end
    end
    return self
end
return Probe
