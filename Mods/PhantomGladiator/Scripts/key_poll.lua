-- Hotkeys read in the game thread.
-- UE4SS runs RegisterKeyBind callbacks on a thread of its own, while this mod's timers and hooks run in the game
-- thread. A key press and a game-thread callback then ran this mod's Lua at the same moment and corrupted the Lua
-- state: each of four crash dumps of 2026-11-11 has two threads inside the interpreter, one of them without any game
-- code on its stack. So a key press runs no Lua here. Once a frame, in the game thread, the bound keys are read from
-- the player controller (as free_camera.lua reads its movement keys) and a press is dispatched there.
-- register and occupied take the arguments of RegisterKeyBind and IsKeyBindRegistered, for key_router.lua.
-- A key the engine has no name for (F13-F24) cannot be read this way. It stays a UE4SS key bind whose callback only
-- sets a flag in a table made beforehand, and the frame loop acts on the flag.
local U=require('ue_observe')
local Poll={}
local NAMES={[8]='BackSpace',[9]='Tab',[13]='Enter',[19]='Pause',[20]='CapsLock',[32]='SpaceBar',[33]='PageUp',
    [34]='PageDown',[35]='End',[36]='Home',[37]='Left',[38]='Up',[39]='Right',[40]='Down',[45]='Insert',[46]='Delete',
    [106]='Multiply',[107]='Add',[109]='Subtract',[110]='Decimal',[111]='Divide',[144]='NumLock',[145]='ScrollLock',
    [186]='Semicolon',[187]='Equals',[188]='Comma',[189]='Hyphen',[190]='Period',[191]='Slash',[192]='Tilde',
    [219]='LeftBracket',[220]='Backslash',[221]='RightBracket',[222]='Apostrophe'}
local DIGITS={'Zero','One','Two','Three','Four','Five','Six','Seven','Eight','Nine'}
local MODIFIERS={{'CONTROL',1,'LeftControl','RightControl'},{'ALT',2,'LeftAlt','RightAlt'},{'SHIFT',4,'LeftShift','RightShift'}}
local RESOLVE_SECONDS=0.5

-- The engine's name (EKeys) for a Windows virtual key, or nil when it has none.
function Poll.keyName(vk)
    if type(vk)~='number' then return nil end
    if NAMES[vk] then return NAMES[vk] end
    if vk>=48 and vk<=57 then return DIGITS[vk-47] end
    if vk>=65 and vk<=90 then return string.char(vk) end
    if vk>=96 and vk<=105 then return 'NumPad'..DIGITS[vk-95] end
    if vk>=112 and vk<=123 then return 'F'..(vk-111) end
end

function Poll.new(options)
    options=options or {}
    local self={alive=true,mode='',fired=0,native=0}
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local modifierTable=options.modifiers or ModifierKey or {}
    local nativeRegister=options.nativeRegister or RegisterKeyBind
    local nativeOccupied=options.nativeOccupied or IsKeyBindRegistered
    local makeName=options.fname or function(name)return FName(name)end
    local meter=options.meter
    local own={}                    -- 'vk:mask' -> true
    local order,byKey={},{}         -- keys read each frame: {vk=,fkey=,chords={[mask]=callback}}
    local flagged,flags={},{}       -- keys the engine cannot name: {callback=}, and their flags
    local down,held={},{}           -- vk -> down last frame; vk -> "just pressed" was reported last frame
    local fkeys={}
    local justPressed=true          -- WasInputKeyJustPressed answers with a boolean
    local pc,resolveAt=nil,0
    local failures=0

    local function fkey(name)
        if not fkeys[name] then fkeys[name]={KeyName=makeName(name)} end
        return fkeys[name]
    end
    -- mods as RegisterKeyBind takes them: a list of ModifierKey values.
    local function maskOf(mods)
        local mask=0
        for _,value in ipairs(mods or {})do
            local bit
            for _,row in ipairs(MODIFIERS)do if modifierTable[row[1]]==value then bit=row[2] end end
            assert(bit,'unknown modifier key')
            mask=mask|bit
        end
        return mask
    end
    local function split(mods,callback)
        if type(mods)=='function' then return {},mods end
        return mods or {},callback
    end

    function self.register(vk,mods,callback)
        mods,callback=split(mods,callback)
        assert(type(vk)=='number' and type(callback)=='function','key and callback required')
        local mask=maskOf(mods)
        local slot=vk..':'..mask
        assert(not own[slot],'duplicate registration')
        local name=Poll.keyName(vk)
        if name then
            local key=byKey[vk]
            if not key then
                key={vk=vk,fkey=fkey(name),chords={}}
                byKey[vk]=key;order[#order+1]=key
            end
            key.chords[mask]=callback
        else
            assert(type(nativeRegister)=='function','key bind interface unavailable')
            local index=#flagged+1
            flags[index]=false
            -- The only Lua a key press runs: one store into an existing slot.
            local raise=function()flags[index]=true end
            if #mods==0 then nativeRegister(vk,raise) else nativeRegister(vk,mods,raise) end
            flagged[index]={callback=callback}
            self.native=self.native+1
            log('[KeyPoll] 虚拟键 '..vk..' 游戏里读不到，沿用 UE4SS 按键回调，回调只置标记')
        end
        own[slot]=true
    end
    function self.occupied(vk,mods)
        mods=split(mods)
        local ok,mask=pcall(maskOf,mods)
        if ok and own[vk..':'..mask] then return true end
        if type(nativeOccupied)~='function' then return false end
        if #mods==0 then return nativeOccupied(vk)==true end
        return nativeOccupied(vk,mods)==true
    end

    local function fire(callback)
        self.fired=self.fired+1
        local ok,err=xpcall(callback,debug.traceback)
        if not ok and failures<5 then failures=failures+1;log('[KeyPoll] 按键处理失败：'..tostring(err)) end
    end
    local function controller(now)
        if pc and U.valid(pc) then
            if not options.isCurrentController then return pc end
            local ok,current=pcall(options.isCurrentController,pc)
            if ok and current==true then return pc end
        end
        local changed=pc~=nil
        if changed then resolveAt=0 end
        pc=nil
        if now<resolveAt or not options.controller then return nil end
        resolveAt=now+RESOLVE_SECONDS
        local ok,found=pcall(options.controller)
        if ok and U.valid(found) then pc=found end
        if changed then log('[KeyPoll] 控制器缓存已失效或归属已切换；重新解析读回='..tostring(pc~=nil)) end
        return pc
    end
    local function isDown(target,key)
        local ok,value=pcall(function()return target:GetInputAnalogKeyState(key)end)
        return ok and type(value)=='number' and value>0.5
    end
    local function modifierMask(target)
        local mask=0
        for _,row in ipairs(MODIFIERS)do
            if isDown(target,fkey(row[3])) or isDown(target,fkey(row[4])) then mask=mask|row[2] end
        end
        return mask
    end

    function self:tick()
        if not self.alive then return end
        for index=1,#flagged do
            if flags[index] then flags[index]=false;fire(flagged[index].callback) end
        end
        if #order==0 then return end
        local started=clock()
        local target=controller(started)
        if not target then
            for vk in pairs(down)do down[vk]=nil;held[vk]=nil end
            return
        end
        local mask
        for index=1,#order do
            local key=order[index]
            local now=isDown(target,key.fkey)
            local just=false
            if justPressed then
                local ok,value=pcall(function()return target:WasInputKeyJustPressed(key.fkey)end)
                if ok and type(value)=='boolean' then just=value
                else
                    justPressed=false
                    log('[KeyPoll] WasInputKeyJustPressed 读回不是布尔值，只按按下状态判断；读回='..tostring(value))
                end
            end
            -- A press is the engine's "just pressed" (it also catches a press and release inside one frame), or else
            -- the key going from up to down. A key already down when first seen is not a press, and "just pressed"
            -- reported again the next frame is the same press (a paused game does not clear it).
            local pressed
            if just then pressed=not held[key.vk] else pressed=now and down[key.vk]==false and not held[key.vk] end
            down[key.vk]=now;held[key.vk]=just
            if pressed then
                mask=mask or modifierMask(target)
                local callback=key.chords[mask]
                if callback then fire(callback) end
            end
        end
        if meter then meter:add((clock()-started)*1000,started) end
    end

    function self:start()
        if self.handle~=nil then return true end
        local tick=function()self:tick()end
        local ok,handle
        if type(LoopInGameThreadAfterFrames)=='function' then
            ok,handle=pcall(LoopInGameThreadAfterFrames,1,tick);self.mode='frame'
        elseif type(LoopInGameThreadWithDelay)=='function' then
            -- A timer does not run once a frame, so "just pressed" could be seen twice or not at all.
            ok,handle=pcall(LoopInGameThreadWithDelay,16,tick);self.mode='16ms';justPressed=false
        end
        if not ok or handle==nil or handle==false then
            self.mode=''
            log('[KeyPoll] 游戏线程按键循环未注册：'..tostring(handle)..'；快捷键不可用')
            return false
        end
        self.handle=handle
        log('[KeyPoll] 快捷键改在游戏线程读取；循环='..self.mode..'；handle读回='..tostring(handle))
        return true
    end
    function self:status()
        return {mode=self.mode,keys=#order,native=self.native,fired=self.fired,just_pressed=justPressed}
    end
    function self:silence()
        self.alive=false
        if self.handle~=nil and type(CancelDelayedAction)=='function' then pcall(CancelDelayedAction,self.handle) end
        self.handle=nil
    end
    return self
end
return Poll
