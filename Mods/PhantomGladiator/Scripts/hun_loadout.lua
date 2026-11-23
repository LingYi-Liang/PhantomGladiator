-- The Hun profile as the local panel last saved it, in the form the game side reads: how many to summon,
-- the attribute values to write on each new body, and the effect classes of the enabled accessories.
-- Read-only here; the panel owns the file.
local Loadout={}
local MAX_BYTES=262144
local MAX_ROWS=1024

local function finite(value)return type(value)=='number'and value==value and value~=math.huge and value~=-math.huge end

local function number(raw,low,high,integer)
    local n=tonumber(raw)
    if finite(n) and n>=low and n<=high and (not integer or n%1==0) then return n end
end
local function flag(raw)
    if raw=='on' then return true end
    if raw=='off' then return false end
end
local function choices(...)
    local values={};for _,v in ipairs({...})do values[v]=v end
    return function(v)return values[v]end
end
local function chance(v)return number(v,0,1)end
local SETTINGS={
    ai={deflect_chance=chance,red_dodge_chance=chance,counter_chance=chance,late_weapon_bias=flag,
        repeat_policy=choices('soft','none'),combo_limit=function(v)return number(v,0,100,true)end},
    resources={medicine_count=function(v)return v=='native_max' and v or number(v,0,10000,true)end,
        consume_medicine=flag,consume_skill_resources=flag,cooldown_scale=function(v)return number(v,0,10)end,
        rebirth=choices('native')},
    survival={grab=choices('native','immune'),execution=choices('native','immune'),lethal=choices('native','immune')}
}
local KITS={weapon={'weapons','main_weapon',33},shadow={'shadows','shadow_armament',28},variant={'variants','resource_armament',17}}
local function itemId(id,prefix)
    local tail=id and id:match('^'..prefix..'_(%x+)$')
    return tail and #tail==16
end
local function parseItem(kind,rest)
    local id,native,path,rawLevel,rawSoul,rawWeight,rawRank,label=rest:match('^([^\t]+)\t([%w_]*)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$')
    local rule=KITS[kind]
    if not itemId(id,rule[2]) or not path:match('^/PBZCombatAsset/ActorData/Players/Hun/[%w_/]+%.[%w_]+$')
        or #path>512 or #native>100 or #label>200 or label:find('%c') then return nil end
    local level=rawLevel=='max' and 'max' or number(rawLevel,1,60,true)
    local soul,weight,rank=flag(rawSoul),number(rawWeight,0,1000),number(rawRank,1,rule[3],true)
    if level and soul~=nil and weight and rank then
        return {id=id,native_id=native,path=path,level=level,soul=soul,weight=weight,rank=rank,label=label}
    end
end

-- Returns the parsed table, or nil and why the text is not a loadout.
function Loadout.parse(text)
    if type(text)~='string'or #text>MAX_BYTES or text:sub(-1)~='\n'then return nil,'文件为空、过大或没有结尾换行'end
    local revision=tonumber(text:match('^HunLoadoutV1\t(%d+)\n'))
    if not revision or revision>2147483646 then return nil,'文件头无效'end
    local out={revision=revision,count=1,appearance='player',attributes={},effects={},accessories=false}
    local rows,first,seen=0,true,{}
    for line in text:gmatch('([^\n]*)\n')do
        if first then first=false
        else
            rows=rows+1
            if rows>MAX_ROWS then return nil,'条目过多'end
            local kind,rest=line:match('^(%a+)\t(.*)$')
            if kind=='kit' then
                if out.kit or rest~='1' then return nil,'配装版本无效'end
                out.kit=true
                out.weapons,out.shadows,out.variants,out.phases={},{},{},{}
                out.ai,out.ai_parameters,out.resources,out.survival={},{},{},{}
            elseif kind=='appearance' and out.kit then
                if seen.appearance or (rest~='player' and rest~='snapshot' and rest~='default_outfit' and rest~='native' and rest~='clone') then
                    return nil,'外观来源无效'
                end
                seen.appearance=true;out.appearance=rest
            elseif KITS[kind] and out.kit then
                local row=parseItem(kind,rest)
                local target=out[KITS[kind][1]]
                if not row or seen[row.id] or #target>=KITS[kind][3] then return nil,'装备条目无效'end
                seen[row.id]=true;target[#target+1]=row
            elseif SETTINGS[kind] and out.kit then
                local key,raw=rest:match('^([%w_]+)\t([^\t]+)$')
                local parse=SETTINGS[kind][key]
                if not parse or out[kind][key]~=nil then return nil,'策略条目无效'end
                local value=parse(raw)
                if value==nil then return nil,'策略值无效'end
                out[kind][key]=value
            elseif kind=='param' and out.kit then
                local key,raw=rest:match('^([^\t]+)\t([^\t]+)$')
                local value=number(raw,-1e9,1e9)
                if not value or #key>200 or key:find('%c') or not require('ai_params').kind[key] or out.ai_parameters[key]~=nil then return nil,'行为参数无效'end
                out.ai_parameters[key]=value
            elseif kind=='phase' and out.kit then
                local id,hp,weapon,priority,once=rest:match('^([%w_%-]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$')
                hp,priority,once=number(hp,.01,1),number(priority,0,1000,true),flag(once)
                if not id or #id>64 or seen['phase:'..id] or not itemId(weapon,'main_weapon') or not hp or not priority or once==nil or #out.phases>=16 then return nil,'阶段无效'end
                seen['phase:'..id]=true
                out.phases[#out.phases+1]={id=id,health_below=hp,weapon_id=weapon,priority=priority,once=once,enabled=true,action='native_combat_art'}
            elseif kind=='count'then
                local count=tonumber(rest)
                if not count or count%1~=0 or count<1 or count>100 then return nil,'数量无效'end
                out.count=count
            elseif kind=='attr'then
                local field,raw=rest:match('^([%w_]+)\t([^\t]+)$')
                local value=tonumber(raw)
                if not field or #field>64 or not finite(value)or out.attributes[field]~=nil then return nil,'属性条目无效'end
                out.attributes[field]=value
            elseif kind=='accessories'then
                if rest~='on'and rest~='off'then return nil,'饰品开关无效'end
                out.accessories=rest=='on'
            elseif kind=='ge'then
                local path,level,label=rest:match('^(/[%w_/%-%.]+%.[%w_%-]+_C)\t(%d+)\t([^\t]*)$')
                level=tonumber(level)
                if not path or not path:match('^/PBZCombatAsset/Prototypes/GameplayEffects/Accessories/[%w_/]+%.GE_[%w_]+_C$')
                    or #path>512 or path:find('..',1,true)or path:find('//',1,true)or not level or level>100
                    or #label>128 or label:find('%c')or seen[path]then return nil,'饰品效果条目无效'end
                seen[path]=true
                out.effects[#out.effects+1]={path=path,level=level,label=label}
            else return nil,'未知条目'end
        end
    end
    return out
end

function Loadout.new(options)
    local self={revision=nil,value=nil}
    local fs=options.io or io
    local source=options.path..'/hun-loadout.tsv'
    local log=options.log or function()end
    -- The current loadout, re-read only when the file's revision changes; nil while there is no usable file.
    function self:read()
        local file=fs.open(source,'rb')
        if not file then
            if self.revision~=false then self.revision,self.value=false,nil;log('[HunLoadout] 没有方案文件；按默认数量 1、不写属性')end
            return nil
        end
        local header=file:read(64)
        local revision=tonumber((header or''):match('^HunLoadoutV1\t(%d+)\n'))or-1
        -- The panel can migrate an older revision in place without editing the user's profile.
        if revision==self.revision and header==self.header and self.value then file:close();return self.value end
        local text=file:seek('set',0)and file:read(MAX_BYTES+1)or nil
        file:close()
        local value,why=Loadout.parse(text)
        local repeatedFailure=not value and not self.value and self.revision==revision and self.lastError==why
        self.revision,self.value,self.header=revision,value,header
        self.lastError=why
        if repeatedFailure then return nil end
        local attributes,n=0,0
        if value then for _ in pairs(value.attributes)do attributes=attributes+1 end;n=#value.effects end
        log('[HunLoadout] 读取方案 revision='..tostring(revision)..'；读回='..(value and('数量='..value.count..' 属性='..attributes..' 项 饰品效果='..n
            ..' 条 外观='..value.appearance..'（'..(value.accessories and'开'or'关')..'） 主武器='..#(value.weapons or{})..' 影之武装='..#(value.shadows or{})
            ..' 表外='..#(value.variants or{})..' 阶段='..#(value.phases or{}))or('无效：'..tostring(why)..'，未采用')))
        return value
    end
    return self
end
return Loadout
