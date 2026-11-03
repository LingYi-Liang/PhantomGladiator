-- Per-unit keys. Saved data contains class paths and numeric keys, never Lua code.
-- V2 rows also keep the unit's own team and count; a V1 row (or an empty field) follows the
-- current panel selection, as every key did before.
local Keys={}
local KeyRouter=require('key_router')
local RESERVED={[121]=true,[192]=true,[91]=true,[92]=true}
local TEAMS={blue=true,red=true,neutral=true,companion=true}
local function integer(v,min,max)return type(v)=='number' and v==v and v%1==0 and v>=min and v<=max end
local function teamOK(t)return t==nil or TEAMS[t]==true end
local function countOK(c)return c==nil or integer(c,1,100) end   -- arena_controller.lua MAX_BATCH
local function pathOK(p)return type(p)=='string' and #p<=512 and p:match('^/[%w_/%-%.]+%.[%w_%-]+_C$') and not p:find('..',1,true) and not p:find('//',1,true) end
local function clean(s)return tostring(s or ''):gsub('[\t\r\n]',' ')end
local function read(path)
    local f=io.open(path,'rb');if not f then return nil end
    local s=f:read(2097153);f:close();return s and #s<=2097152 and s or nil
end
local function write(path,data)
    local f,e=io.open(path,'wb');if not f then return false,e end
    local ok=f:write(data);local flushed=f:flush();local closed=f:close()
    return ok~=nil and flushed~=nil and closed~=nil and read(path)==data
end
function Keys.new(options)
    local self={options=options,entries={},active={},installed={},errors={},revision=0,alive=true,event=0,lastUnit='',message=''}
    self.epoch='unitkeys-'..os.time()..'-'..tostring({}):gsub('[^%w]','')
    local keyTable=options.keys or Key or {};local modifierTable=options.modifiers or ModifierKey or {}
    local register=options.register or RegisterKeyBind;local occupied=options.occupied or IsKeyBindRegistered
    local queue=options.queue or ExecuteInGameThread;local log=options.log or function()end
    local supported={};for _,value in pairs(keyTable)do if integer(value,1,255)then supported[value]=true end end
    -- Also support enum tables exposed through __index rather than pairs().
    for code=65,90 do local value=keyTable[string.char(code)];if integer(value,1,255)then supported[value]=true end end
    for n=1,24 do local value=keyTable['F'..n];if integer(value,1,255)then supported[value]=true end end
    local filename=options.path..'/unit-keybinds.tsv';local statefile=options.path..'/unit-keybinds-state.tsv'
    local function modifiers(mask)
        local out={}
        for i,name in ipairs({'CONTROL','ALT','SHIFT'})do
            if math.floor(mask/2^(i-1))%2==1 then
                if modifierTable[name]==nil then return nil end
                out[#out+1]=modifierTable[name]
            end
        end
        return out
    end
    function self:isBound(vk)return self.active[vk]~=nil end
    function self:owner(vk)
        for unit,e in pairs(self.entries)do if e.key_code==vk then return unit end end
    end
    function self:dispatch(vk,mask)
        if not self.alive then return end
        local binding=self.active[vk]
        if not binding or binding.modifiers~=mask then return end
        local revision=self.revision;local unit=binding.unit_id
        queue(function()
            if not self.alive or revision~=self.revision or not self.active[vk] or self.active[vk].unit_id~=unit then return end
            self.event=self.event+1;self.lastUnit=unit
            local ok,ready,reason=pcall(options.ready)
            if not ok or ready~=true then self.message='未召唤：'..tostring(reason or '游戏未就绪');log('[UnitKeys] '..self.message);return end
            local current=self.active[vk]
            local called,result=pcall(options.spawn,unit,current.team,current.count)
            self.message=called and type(result)=='table' and tostring(result.message) or '召唤返回未确认'
            log('[UnitKeys] 单位快捷键 vk='..vk..' modifiers='..mask..' unit='..unit..' team='..tostring(current.team or '跟随当前')
                ..' count='..tostring(current.count or '跟随当前')..'；读回='..self.message)
        end)
    end
    local function ensure(binding)
        local vk,mask=binding.key_code,binding.modifiers
        if not supported[vk] then return false,'当前UE4SS未提供这个按键' end
        local reserved=options.reserved and options.reserved(vk,mask)
        local system=KeyRouter.reserved(vk,mask)
        if RESERVED[vk] or system then return false,'该键已被「'..(system or '系统')..'」占用' end
        if reserved then return false,'该键已被功能「'..tostring(reserved)..'」占用' end
        if options.router then return options.router:ensure(vk,mask)end
        local mods=modifiers(mask);if not mods then return false,'当前修饰键不可用' end
        if type(register)~='function' or type(occupied)~='function' then return false,'按键注册接口不可用' end
        local slot=vk..':'..mask
        local shared=options.shared and options.shared(vk)
        for otherMask=0,7 do
            local otherMods=modifiers(otherMask)
            if otherMods then
                local checked,taken=pcall(function()if #otherMods==0 then return occupied(vk) else return occupied(vk,otherMods) end end)
                if not checked then return false,'无法读回按键是否已占用' end
                if taken and not self.installed[vk..':'..otherMask] and not (shared and otherMask==0) then return false,'这个主键已被其它Mod或功能占用' end
            end
        end
        if shared and mask==0 then return true end
        local checked,taken=pcall(function()if #mods==0 then return occupied(vk) else return occupied(vk,mods) end end)
        if not checked then return false,'无法读回按键是否已占用' end
        if self.installed[slot] then return taken==true,taken and nil or '按键注册未读回' end
        if taken then return false,'按键已被其它Mod或功能占用' end
        local callback=function()self:dispatch(vk,mask)end
        local ok,err=pcall(function()if #mods==0 then register(vk,callback) else register(vk,mods,callback) end end)
        if not ok then return false,tostring(err) end
        self.installed[slot]=callback
        local readback,value=pcall(function()if #mods==0 then return occupied(vk) else return occupied(vk,mods) end end)
        return readback and value==true,'按键注册没有得到确认'
    end
    local function publish()
        local lines={'UnitKeyStateV1\t'..self.revision..'\t'..self.epoch};local paths={}
        for unit in pairs(self.entries)do paths[#paths+1]=unit end;table.sort(paths)
        for _,unit in ipairs(paths)do
            local entry=self.entries[unit];local active=self.active[entry.key_code]
            local ok=active and active.unit_id==unit and active.modifiers==entry.modifiers
            lines[#lines+1]=unit..'\t'..(ok and '1' or '0')..'\t'..clean(self.errors[unit])
        end
        return write(statefile,table.concat(lines,'\n')..'\n')
    end
    local function rebuild()
        self.active,self.errors={},{}
        for unit,entry in pairs(self.entries)do
            local ok,reason=ensure(entry)
            if ok then self.active[entry.key_code]={unit_id=unit,key_code=entry.key_code,modifiers=entry.modifiers,team=entry.team,count=entry.count}
            else self.errors[unit]=reason end
        end
        publish()
    end
    function self:refresh()rebuild()end
    function self:start()
        local data=read(filename)
        if data then
            local version,rev=data:match('^UnitKeysV([12])\t(%d+)\r?\n');local parsed,seen={},{}
            local valid=integer(tonumber(rev),0,2147483646)
            for line in data:gmatch('[^\r\n]+')do
                if not line:match('^UnitKeysV[12]\t')then
                    local unit,key,mask,team,count
                    if version=='2' then unit,key,mask,team,count=line:match('^([^\t]+)\t(%d+)\t(%d+)\t(%a*)\t(%d*)$')
                    else unit,key,mask=line:match('^([^\t]+)\t(%d+)\t(%d+)$') end
                    key,mask=tonumber(key),tonumber(mask)
                    if team=='' then team=nil end
                    count=tonumber(count)
                    if not pathOK(unit) or not integer(key,1,255) or not integer(mask,0,7) or not teamOK(team) or not countOK(count)
                        or parsed[unit] or seen[key] then valid=false;break end
                    parsed[unit]={key_code=key,modifiers=mask,team=team,count=count};seen[key]=true
                end
            end
            if valid then self.entries=parsed;self.revision=tonumber(rev)
            else self.message='单位快捷键文件格式无效，未启用任何条目';log('[UnitKeys] '..self.message) end
        end
        rebuild();local total=0;for _ in pairs(supported)do total=total+1 end
        log('[UnitKeys] 已读取独立单位快捷键；默认无绑定；revision='..self.revision..' supported_keys='..total)
    end
    function self:configure(unit,vk,mask,team,count)
        if not pathOK(unit) or not integer(vk,0,255) or not integer(mask,0,7) then return {ok=false,message='单位路径或按键格式无效',spawned_count=0} end
        if not teamOK(team) or not countOK(count) then return {ok=false,message='单位快捷键的队伍或数量无效',spawned_count=0} end
        local proposal={};for path,entry in pairs(self.entries)do proposal[path]=entry end
        proposal[unit]=nil
        if vk>0 then
            for path,entry in pairs(proposal)do
                if entry.key_code==vk then
                    local name=(path:match('%.([^%.]+)$') or path):gsub('_C$','')
                    return {ok=false,message='这个主键已被单位「'..name..'」占用，请先解除该单位的绑定',spawned_count=0}
                end
            end
            local entry={key_code=vk,modifiers=mask,team=team,count=count};local ok,reason=ensure(entry)
            if not ok then return {ok=false,message=reason,spawned_count=0} end
            proposal[unit]=entry
        end
        local revision=self.revision+1;local lines={'UnitKeysV2\t'..revision};local paths={}
        for path in pairs(proposal)do paths[#paths+1]=path end;table.sort(paths)
        for _,path in ipairs(paths)do
            local e=proposal[path]
            lines[#lines+1]=path..'\t'..e.key_code..'\t'..e.modifiers..'\t'..(e.team or '')..'\t'..(e.count and tostring(e.count) or '')
        end
        local saved=write(filename,table.concat(lines,'\n')..'\n')
        if not saved then return {ok=false,message='快捷键保存未读回，旧绑定保留',spawned_count=0} end
        self.entries,self.revision=proposal,revision;rebuild()
        log('[UnitKeys] 保存并读回 unit='..unit..' key='..vk..' modifiers='..mask..' team='..tostring(team or '跟随当前')
            ..' count='..tostring(count or '跟随当前')..' revision='..revision)
        return {ok=true,message=vk==0 and '已解除该单位快捷键' or '单位快捷键已注册并保存；在游戏内生效',spawned_count=0}
    end
    function self:status()return {epoch=self.epoch,revision=self.revision,event=self.event,unit=self.lastUnit,message=self.message}end
    function self:silence()self.alive=false end
    return self
end
return Keys
