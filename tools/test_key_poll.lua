package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Poll=require('key_poll')
local Router=require('key_router')
local MODS={CONTROL=1001,ALT=1002,SHIFT=1003}

-- A player controller as the engine reports keys: `down` names held now, `just` names pressed in this frame.
local function fixture(extra)
    local h={down={},just={},reads=0,logs={},native={},nativeOccupied={},loops={},cancelled={},now=100,finds=0}
    h.pc={alive=true}
    function h.pc:IsValid()return self.alive end
    function h.pc:GetInputAnalogKeyState(key)h.reads=h.reads+1;return h.down[key.KeyName] and 1.0 or 0.0 end
    function h.pc:WasInputKeyJustPressed(key)
        h.reads=h.reads+1
        if h.justKind=='number' then return 1 end
        return h.just[key.KeyName]==true
    end
    local options={log=function(line)h.logs[#h.logs+1]=line end,clock=function()return h.now end,modifiers=MODS,
        fname=function(name)return name end,controller=function()h.finds=h.finds+1;return h.found~=false and h.pc or nil end,
        nativeRegister=function(vk,mods,callback)
            if type(mods)=='function' then callback=mods;mods={} end
            h.native[#h.native+1]={vk=vk,mods=mods,callback=callback}
        end,
        nativeOccupied=function(vk,mods)
            local mask=0
            for _,value in ipairs(mods or {})do mask=mask+(value==MODS.CONTROL and 1 or value==MODS.ALT and 2 or 4) end
            return h.nativeOccupied[vk..':'..mask]==true
        end}
    for key,value in pairs(extra or {})do options[key]=value end
    h.poll=Poll.new(options)
    -- One frame with these keys newly pressed and held.
    function h:press(...)
        for _,name in ipairs({...})do self.down[name]=true;self.just[name]=true end
        self.poll:tick();self.just={}
    end
    function h:release(...)
        for _,name in ipairs({...})do self.down[name]=nil end
        self.poll:tick()
    end
    return h
end
local function counter()
    local c={n=0}
    c.fn=function()c.n=c.n+1 end
    return c
end

-- Engine names for the keys the router accepts; F13 and beyond have none.
assert(Poll.keyName(81)=='Q' and Poll.keyName(48)=='Zero' and Poll.keyName(57)=='Nine' and Poll.keyName(96)=='NumPadZero'
    and Poll.keyName(105)=='NumPadNine' and Poll.keyName(112)=='F1' and Poll.keyName(123)=='F12' and Poll.keyName(32)=='SpaceBar'
    and Poll.keyName(189)=='Hyphen')
assert(Poll.keyName(124)==nil and Poll.keyName(135)==nil and Poll.keyName(0)==nil and Poll.keyName('Q')==nil)

-- The same key under no modifier, Ctrl and Alt is three chords; the modifiers must match exactly.
do
    local h=fixture()
    local plain,ctrl,alt=counter(),counter(),counter()
    h.poll.register(81,plain.fn)
    h.poll.register(81,{MODS.CONTROL},ctrl.fn)
    h.poll.register(81,{MODS.ALT},alt.fn)
    assert(#h.native==0,'a key the engine can name is never a UE4SS key bind')
    h.poll:tick()
    assert(plain.n+ctrl.n+alt.n==0)
    h:press('Q');assert(plain.n==1 and ctrl.n==0 and alt.n==0)
    h.poll:tick();h.poll:tick();assert(plain.n==1,'a held key is one press')
    h:release('Q')
    h.down.LeftControl=true;h:press('Q');assert(ctrl.n==1 and plain.n==1);h:release('Q')
    h.down.LeftControl=nil;h.down.RightAlt=true;h:press('Q');assert(alt.n==1 and ctrl.n==1 and plain.n==1);h:release('Q')
    h.down.LeftControl=true;h:press('Q');assert(plain.n==1 and ctrl.n==1 and alt.n==1,'Ctrl+Alt+Q is not bound');h:release('Q')
    h.down.LeftControl=nil;h.down.RightAlt=nil;h.down.LeftShift=true
    h:press('Q');assert(plain.n==1,'Shift+Q is not plain Q');h:release('Q')
    h.down.LeftShift=nil
    for _=1,5 do h:press('Q');h:release('Q') end
    assert(plain.n==6,'every separate press counts')
    assert(h.poll:status().fired==8 and h.poll:status().keys==1)
end

-- A press and release inside one frame is still seen; "just pressed" reported twice is one press.
do
    local h=fixture()
    local c=counter()
    h.poll.register(120,c.fn)
    h.poll:tick()
    h.just.F9=true;h.poll:tick();assert(c.n==1,'down and up within the frame')
    h.poll:tick();assert(c.n==1,'a stuck report (paused game) is the same press')
    h.just={};h.poll:tick()
    h.just.F9=true;h.poll:tick();assert(c.n==2)
end

-- Without a usable "just pressed" the key going down is the press; a key already down when first seen is not one.
do
    local h=fixture()
    h.justKind='number'
    local c=counter()
    h.poll.register(120,c.fn)
    h.down.F9=true
    h.poll:tick();assert(c.n==0,'held before the first frame')
    local warned=0
    for _,line in ipairs(h.logs)do if line:find('WasInputKeyJustPressed',1,true)then warned=warned+1 end end
    assert(warned==1)
    h.poll:tick();assert(c.n==0)
    h.down.F9=nil;h.poll:tick()
    h.down.F9=true;h.poll:tick();assert(c.n==1)
    h.poll:tick();assert(c.n==1)
    assert(h.poll:status().just_pressed==false)
    for _,line in ipairs(h.logs)do if line:find('WasInputKeyJustPressed',1,true)then warned=warned+1 end end
    assert(warned==2,'said once')
end

-- No controller: nothing is read, it is looked for twice a second, and a key held when it appears is not a press.
do
    local h=fixture()
    h.justKind='number'
    local c=counter()
    h.poll.register(81,c.fn)
    h.found=false
    h.down.Q=true
    for _=1,10 do h.poll:tick() end
    assert(h.reads==0 and h.finds==1,'one lookup, then a wait')
    h.now=h.now+0.6;h.poll:tick();assert(h.finds==2)
    h.found=nil;h.now=h.now+0.6
    h.poll:tick();assert(c.n==0 and h.reads>0)
    h.down.Q=nil;h.poll:tick();h.down.Q=true;h.poll:tick();assert(c.n==1)
    -- The controller goes away (a map change): the next one starts clean.
    h.pc.alive=false;h.poll:tick()
    h.pc.alive=true;h.now=h.now+0.6;h.poll:tick();assert(c.n==1,'still held across the change')
end

-- Nothing bound: the frame costs no engine call at all.
do
    local h=fixture()
    for _=1,100 do h.poll:tick() end
    assert(h.reads==0 and h.finds==0)
end

-- F13 has no engine name: it stays a UE4SS key bind whose callback only raises a flag for the frame loop.
do
    local h=fixture()
    local f13,ctrlF13=counter(),counter()
    h.poll.register(124,f13.fn)
    h.poll.register(124,{MODS.CONTROL},ctrlF13.fn)
    assert(#h.native==2 and h.native[1].vk==124 and #h.native[1].mods==0 and h.native[2].mods[1]==MODS.CONTROL)
    h.native[1].callback();h.native[1].callback()
    assert(f13.n==0,'the UE4SS callback itself runs none of the handler')
    h.poll:tick();assert(f13.n==1 and ctrlF13.n==0,'two flags before a frame are one press')
    h.poll:tick();assert(f13.n==1)
    h.native[2].callback();h.poll:tick();assert(ctrlF13.n==1)
    assert(h.poll:status().native==2 and h.reads==0)
end

-- occupied: this mod's own chords and other mods' UE4SS binds.
do
    local h=fixture()
    h.poll.register(81,{MODS.CONTROL},function()end)
    assert(h.poll.occupied(81,{MODS.CONTROL})==true and h.poll.occupied(81)==false and h.poll.occupied(81,{MODS.ALT})==false)
    h.nativeOccupied['81:2']=true
    assert(h.poll.occupied(81,{MODS.ALT})==true)
    assert(not pcall(h.poll.register,81,{MODS.CONTROL},function()end),'a chord is registered once')
    assert(not pcall(h.poll.register,81,{42},function()end),'unknown modifier')
end

-- One handler failing does not stop the others, and is logged.
do
    local h=fixture()
    local c=counter()
    h.poll.register(81,function()error('boom')end)
    h.poll.register(87,c.fn)
    h:press('Q','W')
    assert(c.n==1)
    local seen=false
    for _,line in ipairs(h.logs)do if line:find('按键处理失败',1,true) and line:find('boom',1,true)then seen=true end end
    assert(seen)
end

-- The loop: once a frame when UE4SS offers it; a timer otherwise, and then "just pressed" is not trusted.
do
    local saved={LoopInGameThreadAfterFrames,LoopInGameThreadWithDelay,CancelDelayedAction}
    local frames,timers,cancelled={},{},{}
    LoopInGameThreadAfterFrames=function(n,fn)assert(n==1);frames[#frames+1]=fn;return 'frame-handle' end
    LoopInGameThreadWithDelay=function(ms,fn)timers[#timers+1]={ms=ms,fn=fn};return 'timer-handle' end
    CancelDelayedAction=function(handle)cancelled[#cancelled+1]=handle;return true end
    local h=fixture()
    local c=counter()
    h.poll.register(81,c.fn)
    assert(h.poll:start()==true and #frames==1 and #timers==0 and h.poll:status().mode=='frame')
    assert(h.poll:start()==true and #frames==1,'started once')
    h.just.Q=true;frames[1]();assert(c.n==1)
    h.poll:silence()
    assert(cancelled[1]=='frame-handle')
    h.just.Q=nil;frames[1]();h.just.Q=true;frames[1]();assert(c.n==1,'inert once silenced')

    LoopInGameThreadAfterFrames=nil
    local t=fixture()
    local d=counter()
    t.poll.register(81,d.fn)
    assert(t.poll:start()==true and #timers==1 and timers[1].ms==16 and t.poll:status().mode=='16ms')
    assert(t.poll:status().just_pressed==false)
    t.just.Q=true;timers[1].fn();assert(d.n==0,'the report alone is not used on a timer')
    t.down.Q=true;timers[1].fn();assert(d.n==1)

    LoopInGameThreadWithDelay=nil
    local n=fixture()
    assert(n.poll:start()==false,'no loop: the caller is told')
    LoopInGameThreadAfterFrames,LoopInGameThreadWithDelay,CancelDelayedAction=saved[1],saved[2],saved[3]
end

-- Through the router: a chord is confirmed without any UE4SS registration and dispatches with its own key and mask.
do
    local h=fixture()
    local keys={}
    for code=65,90 do keys[string.char(code)]=code end
    for n=1,24 do keys['F'..n]=111+n end
    local router=Router.new({keys=keys,modifiers=MODS,register=h.poll.register,occupied=h.poll.occupied})
    local got={}
    router.dispatch=function(vk,mask)got[#got+1]=vk..':'..mask end
    assert(router:ensure(81,1)==true)
    assert(router:ensure(81,2)==true)
    assert(router:ensure(81,1)==true,'asking again confirms the same chord')
    assert(#h.native==0)
    h.nativeOccupied['87:0']=true
    local ok,why=router:ensure(87,4)
    assert(ok==false and why:find('已被其它Mod或UE4SS占用',1,true),'another mod holds W')
    h.down.RightControl=true;h:press('Q');h:release('Q')
    h.down.RightControl=nil;h.down.LeftAlt=true;h:press('Q');h:release('Q')
    assert(table.concat(got,',')=='81:1,81:2')
    router:silence();h:press('Q')
    assert(#got==2)
end

do
    local active
    local h=fixture({isCurrentController=function(controller)return controller==active end})
    active=h.pc
    local c=counter()
    h.poll.register(81,c.fn)
    h.poll:tick();h:press('Q');h:release('Q')
    assert(c.n==1)
    local old=h.pc
    h.pc={alive=true,IsValid=old.IsValid,GetInputAnalogKeyState=old.GetInputAnalogKeyState,WasInputKeyJustPressed=old.WasInputKeyJustPressed}
    active=h.pc
    local staleReads=0
    old.GetInputAnalogKeyState=function()staleReads=staleReads+1;return 0 end
    old.WasInputKeyJustPressed=function()staleReads=staleReads+1;return false end
    h:press('Q')
    assert(c.n==2 and staleReads==0 and h.finds==2,'a valid but unowned cached controller must be replaced before reading input')
end
print('key_poll: PASS (engine key names, exact chords, one press per press, in-frame presses, controller changes, ownership, F13 flag fallback, loop choice, router)')
