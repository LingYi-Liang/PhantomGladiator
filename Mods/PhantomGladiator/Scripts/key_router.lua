-- One native callback per chord, shared by function and per-unit bindings.
-- Unassigned/retired callbacks are inert; no undocumented unregister API is used.
local Router={}
local names={[8]='Backspace',[9]='Tab',[13]='Enter',[19]='Pause',[20]='CapsLock',[32]='Space',
    [33]='PageUp',[34]='PageDown',[35]='End',[36]='Home',[37]='Left',[38]='Up',[39]='Right',[40]='Down',
    [45]='Insert',[46]='Delete',[106]='Num*',[107]='Num+',[109]='Num-',[110]='Num.',[111]='Num/',
    [144]='NumLock',[145]='ScrollLock',[186]=';',[187]='=',[188]=',',[189]='-',[190]='.',[191]='/',
    [192]='`',[219]='[',[220]='\\',[221]=']',[222]="'"}
local function integer(v,min,max)return type(v)=='number' and v%1==0 and v>=min and v<=max end
function Router.valid(vk,mask)
    return integer(vk,0,255) and integer(mask,0,7) and (vk==0 or names[vk]~=nil
        or (vk>=48 and vk<=57) or (vk>=65 and vk<=90) or (vk>=96 and vk<=135))
end
function Router.label(vk,mask)
    if vk==0 then return '未绑定' end
    local base=names[vk] or (vk>=65 and vk<=90 and string.char(vk)) or (vk>=48 and vk<=57 and string.char(vk))
        or (vk>=96 and vk<=105 and 'Num'..(vk-96)) or (vk>=112 and vk<=135 and 'F'..(vk-111)) or ('VK'..vk)
    local result={}
    for i,name in ipairs({'Ctrl','Alt','Shift'})do if math.floor(mask/2^(i-1))%2==1 then result[#result+1]=name end end
    result[#result+1]=base;return table.concat(result,'+')
end
function Router.reserved(vk,mask)
    if vk==121 or vk==192 then return '游戏控制台' end
    if vk==91 or vk==92 then return 'Windows系统键' end
    if vk==82 and mask%2==1 then return 'UE4SS重载Mod（Ctrl+R）' end
    if math.floor(mask/2)%2==1 and vk==115 then return '关闭窗口（Alt+F4）' end
    if math.floor(mask/2)%2==1 and vk==9 then return '切换窗口（Alt+Tab）' end
    if vk==46 and mask%4==3 then return 'Windows安全界面（Ctrl+Alt+Delete）' end
end
function Router.token(binding)
    return binding.key_code==0 and 'UNBOUND' or ('VK_'..binding.key_code..'_MOD_'..binding.modifiers)
end
function Router.parse(value)
    if value=='' or value=='UNBOUND' then return {key_code=0,modifiers=0} end
    if type(value)~='string' then return nil end
    local vk,mask=value:match('^VK_(%d+)_MOD_(%d+)$');vk,mask=tonumber(vk),tonumber(mask)
    if not vk then
        local fn=tonumber(value:match('^F(%d+)$'))
        local digits={ZERO=0,ONE=1,TWO=2,THREE=3,FOUR=4,FIVE=5,SIX=6,SEVEN=7,EIGHT=8,NINE=9}
        local num=digits[value:match('^NUM_(%u+)$')]
        vk=fn and fn>=1 and fn<=24 and (111+fn) or (num and 96+num)
        if not vk and value:match('^[A-Z0-9]$') then vk=value:byte()end
        mask=0
    end
    if not Router.valid(vk,mask) then return nil end
    return {key_code=vk,modifiers=vk==0 and 0 or mask}
end
function Router.new(options)
    options=options or {}
    local self={installed={},alive=true,dispatch=nil}
    local keys=options.keys or Key or {};local mods=options.modifiers or ModifierKey or {}
    local register=options.register or RegisterKeyBind;local occupied=options.occupied or IsKeyBindRegistered
    local supported={};for _,vk in pairs(keys)do if integer(vk,1,255)then supported[vk]=true end end
    for code=65,90 do local vk=keys[string.char(code)];if integer(vk,1,255)then supported[vk]=true end end
    for n=1,24 do local vk=keys['F'..n];if integer(vk,1,255)then supported[vk]=true end end
    local function modifiers(mask)
        local out={}
        for i,name in ipairs({'CONTROL','ALT','SHIFT'})do if math.floor(mask/2^(i-1))%2==1 then
            if mods[name]==nil then return nil end;out[#out+1]=mods[name]
        end end
        return out
    end
    local function taken(vk,mask)
        local values=modifiers(mask);if not values then return nil end
        local ok,value=pcall(function()if #values==0 then return occupied(vk)else return occupied(vk,values)end end)
        return ok and value==true,ok
    end
    function self:ensure(vk,mask)
        if not Router.valid(vk,mask) or vk==0 then return false,'不支持这个按键' end
        local blocked=Router.reserved(vk,mask)
        if blocked then return false,Router.label(vk,mask)..' 已被「'..blocked..'」占用' end
        if not supported[vk] then return false,'当前UE4SS未提供 '..Router.label(vk,mask) end
        if type(register)~='function' or type(occupied)~='function' then return false,'按键注册接口不可用' end
        for otherMask=0,7 do
            if modifiers(otherMask) then
                local used,read=taken(vk,otherMask)
                if not read then return false,'无法读取按键占用状态' end
                if used and not self.installed[vk..':'..otherMask] then return false,Router.label(vk,otherMask)..' 已被其它Mod或UE4SS占用' end
            end
        end
        local slot=vk..':'..mask;local values=modifiers(mask)
        if not values then return false,'当前修饰键不可用' end
        if self.installed[slot] then local used,read=taken(vk,mask);return read and used,'按键注册读回未确认' end
        local callback=function()if self.alive and self.dispatch then self.dispatch(vk,mask)end end
        local called,why=pcall(function()if #values==0 then register(vk,callback)else register(vk,values,callback)end end)
        if not called then return false,tostring(why)end
        self.installed[slot]=callback
        local used,read=taken(vk,mask)
        return read and used,'按键注册读回未确认'
    end
    function self:silence()self.alive=false end
    return self
end
return Router
