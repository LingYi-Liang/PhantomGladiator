-- Rules set on a unit's card in the app (set_unit_rule), per class, saved in Runtime/unit-rules.tsv. Only what differs from
-- the default is kept.
--   lock:    how a unit on its death lock ends. execute (default): an opponent executes it, as far as it has an execution.
--            kill: it dies on the lock (arena_executions.lua).
--   phantom: 琴女's 虚化 in fights of blue, red and companions. off (default): taken away when summoned, since nothing an NPC
--            does can break it (phantom_break.lua). keep: as in the game.
local Rules={}
local HEADER='UnitRulesV1'
Rules.VALUES={lock={execute=true,kill=true},phantom={off=true,keep=true}}
Rules.DEFAULTS={lock='execute',phantom='off'}
local LABELS={lock={execute='锁血后处决',kill='锁血后打死'},phantom={off='虚化解除（下次召唤生效）',keep='虚化保持原版（下次召唤生效）'}}

local function validId(id)return type(id)=='string' and #id<=128 and id:match('^BP_[%w_]+$')~=nil end

function Rules.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local file=options.path..'/unit-rules.tsv'
    local self={}
    local rules={}   -- unit id -> {rule=value}
    local function readFile()
        local f=fs.open(file,'r');if not f then return nil end
        local value=f:read('*a');f:close();return value
    end
    local function render(from)
        local ids={}
        for id in pairs(from)do ids[#ids+1]=id end
        table.sort(ids)
        local out={HEADER}
        for _,id in ipairs(ids)do
            local names={}
            for rule in pairs(from[id])do names[#names+1]=rule end
            table.sort(names)
            for _,rule in ipairs(names)do out[#out+1]=id..'\t'..rule..'\t'..from[id][rule] end
        end
        return table.concat(out,'\n')..'\n'
    end
    do
        local saved=readFile()
        if type(saved)=='string' and saved:sub(1,#HEADER+1)==HEADER..'\n' then
            for id,rule,value in saved:gmatch('\n([^\t\r\n]+)\t([^\t\r\n]+)\t([^\t\r\n]+)')do
                if validId(id) and Rules.VALUES[rule] and Rules.VALUES[rule][value] and value~=Rules.DEFAULTS[rule] then
                    rules[id]=rules[id] or {};rules[id][rule]=value
                end
            end
        end
    end
    function self:set(id,rule,value)
        if not validId(id) then return {ok=false,message='单位规则：单位编号不对',spawned_count=0} end
        if not Rules.VALUES[rule] or not Rules.VALUES[rule][value] then return {ok=false,message='单位规则：规则或取值不对',spawned_count=0} end
        local copy={}
        for unit,row in pairs(rules)do
            copy[unit]={}
            for name,current in pairs(row)do copy[unit][name]=current end
        end
        copy[id]=copy[id] or {}
        copy[id][rule]=value~=Rules.DEFAULTS[rule] and value or nil
        if not next(copy[id]) then copy[id]=nil end
        local text=render(copy)
        local f=fs.open(file,'w')
        local wrote=f and f:write(text)
        local closed=f and f:close()
        local saved=f~=nil and wrote~=nil and wrote~=false and closed~=false and readFile()==text
        if saved then rules=copy end
        log(string.format('[UnitRules] 设置 单位=%s %s=%s 保存读回=%s',id,rule,value,tostring(saved)))
        return {ok=saved,spawned_count=0,message=saved and LABELS[rule][value] or '单位规则没有保存'}
    end
    -- The rule for a unit id or an actor's class.
    function self:get(unit,rule)
        if not next(rules) then return Rules.DEFAULTS[rule] end
        local id=unit
        if type(unit)~='string' then
            local ok,name=pcall(function()return unit:GetClass():GetFName():ToString()end)
            id=ok and type(name)=='string' and name:gsub('_C$','') or nil
        end
        return id and rules[id] and rules[id][rule] or Rules.DEFAULTS[rule]
    end
    -- For the app: BP_Monster_MoTian:lock=kill;BP_Monster_FemaleDoll_QinNv:phantom=keep
    function self:status()
        local parts={}
        for id,row in pairs(rules)do
            for rule,value in pairs(row)do parts[#parts+1]=id..':'..rule..'='..value end
        end
        table.sort(parts)
        return {text=table.concat(parts,';')}
    end
    return self
end
return Rules
