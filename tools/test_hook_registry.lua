-- Hooks on blueprint functions whose class leaves with its map: one miss, no retries, no doubled callback afterwards.
package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Registry=require('hook_registry')
local GONE="Tried to unregister a hook with Lua function 'UnregisterHook' but no UFunction with the specified name was found."
-- UE4SS as the logs show it: entries are kept by name, removing needs the function to be loaded.
local function engine()
    local e={loaded={},hooks={},next=1,slow=0,calls=0,now=0}
    function e.register(path,callback,post)
        if not e.loaded[path] then error('Tried to register a hook but no UFunction was found') end
        local id=e.next;e.next=id+1
        e.hooks[path]=e.hooks[path] or {}
        e.hooks[path][id]=callback
        return id,id,'extra'
    end
    function e.unregister(path,pre,post)
        e.calls=e.calls+1
        if not e.loaded[path] then e.slow=e.slow+1;error(GONE) end
        if e.fail then error('busy') end
        if e.refuse then return false end
        assert(e.hooks[path] and e.hooks[path][pre],'unknown id '..tostring(pre))
        e.hooks[path][pre]=nil
        return nil
    end
    function e.fire(path)
        local n=0
        for _,callback in pairs(e.hooks[path] or {})do callback();n=n+1 end
        return n
    end
    function e.count(path)local n=0;for _ in pairs(e.hooks[path] or {})do n=n+1 end;return n end
    e.logs={}
    e.registry=Registry.new({register=e.register,unregister=e.unregister,clock=function()return e.now end,log=function(s)e.logs[#e.logs+1]=s end})
    return e
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end
local A='/Game/A.A_C:Run'

test('a loaded blueprint function is registered and removed as before, results included',function()
    local e=engine();e.loaded[A]=true
    local pre,post,extra=e.registry.register(A,function()end);assert(pre==1 and post==1 and extra=='extra')
    assert(e.registry.unregister(A,pre,post)==nil and e.count(A)==0 and e.calls==1)
    e.refuse=true;pre,post=e.registry.register(A,function()end);assert(e.registry.unregister(A,pre,post)==false,'a refusal is the caller\'s')
    e.refuse,e.fail=nil,true;local ok,why=pcall(e.registry.unregister,A,pre,post);assert(not ok and why:find('busy'))
    ok,why=pcall(e.registry.register,'/Game/B.B_C:Run',function()end);assert(not ok and why:find('no UFunction was found'))
end)
test('a function whose class left counts as removed after one search',function()
    local e=engine();e.loaded[A]=true;local pre,post=e.registry.register(A,function()end)
    e.loaded[A]=nil
    assert(e.registry.unregister(A,pre,post)==true and e.slow==1 and e.registry:status().parked==1)
    assert(#e.logs==1 and e.logs[1]:find('pre=1',1,true))
end)
test('the old entry comes off when the path is hooked again, and one callback is left',function()
    local e=engine();local fired={old=0,new=0}
    e.loaded[A]=true;local pre,post=e.registry.register(A,function()fired.old=fired.old+1 end)
    e.loaded[A]=nil;e.registry.unregister(A,pre,post)
    e.loaded[A]=true;assert(e.count(A)==1,'UE4SS still has the entry')
    local again=e.registry.register(A,function()fired.new=fired.new+1 end)
    assert(again==2 and e.count(A)==1 and e.registry:status().parked==0 and e.registry:status().cleared==1)
    assert(e.fire(A)==1 and fired.old==0 and fired.new==1)
    assert(e.registry.unregister(A,again,again)==nil and e.count(A)==0)
end)
test('several visits leave one callback, however often the map changed without a fight',function()
    local e=engine();local fired=0
    for visit=1,6 do
        e.loaded[A]=true;local id=e.registry.register(A,function()fired=fired+1 end)
        fired=0;assert(e.fire(A)==1 and fired==1,'visit '..visit)
        e.loaded[A]=nil;e.now=e.now+30;e.registry.unregister(A,id,id)
    end
    assert(e.slow==6 and e.registry:status().parked==1 and e.registry:status().cleared==5)
    for _,line in ipairs(e.logs)do assert(not line:find('旧挂钩仍未摘除',1,true),'an entry is taken off once') end
end)
test('the functions of one class are searched for once, other classes and later times again',function()
    local e=engine();local B,C='/Game/A.A_C:Stop','/Game/C.C_C:Run'
    for _,p in ipairs({A,B,C})do e.loaded[p]=true end
    local ids={};for _,p in ipairs({A,B,C})do ids[p]=e.registry.register(p,function()end)end
    for _,p in ipairs({A,B,C})do e.loaded[p]=nil end
    for _,p in ipairs({A,B,C})do assert(e.registry.unregister(p,ids[p],ids[p])==true) end
    assert(e.slow==2,'A_C once, C_C once')
    local D='/Game/A.A_C:Late';e.loaded[D]=true;local d=e.registry.register(D,function()end)
    e.now=.5;assert(e.registry.unregister(D,d,d)==nil and e.count(D)==0 and e.slow==2,
        'a successful registration confirms that the class is loaded again')
    e.loaded[D]=true;d=e.registry.register(D,function()end);assert(e.count(D)==1)
    e.now=2;assert(e.registry.unregister(D,d,d)==nil and e.count(D)==0,'later it is really removed')
end)
test('a clock that went back does not hide a loaded class',function()
    local e=engine();e.now=100;e.loaded[A]=true;local id=e.registry.register(A,function()end);e.loaded[A]=nil
    local B='/Game/A.A_C:Stop';e.loaded[B]=true;local b=e.registry.register(B,function()end)
    e.registry.unregister(A,id,id);e.now=3
    assert(e.registry.unregister(B,b,b)==nil and e.count(B)==0)
end)
test('a parked entry that still refuses is kept for the next time and never mistaken for the new one',function()
    local e=engine();e.loaded[A]=true;local id=e.registry.register(A,function()end)
    e.loaded[A]=nil;e.registry.unregister(A,id,id);e.loaded[A]=true
    e.refuse=true;local two=e.registry.register(A,function()end);assert(e.registry:status().parked==1 and e.count(A)==2)
    e.refuse=nil;local three=e.registry.register(A,function()end)
    assert(e.registry:status().parked==0 and e.hooks[A][id]==nil and e.hooks[A][two] and e.hooks[A][three])
    local s=engine();s.loaded[A]=true;local x=s.registry.register(A,function()end);s.loaded[A]=nil;s.registry.unregister(A,x,x)
    s.loaded[A]=true;s.next=x;assert(s.registry.register(A,function()end)==x and s.count(A)==1,'the same ids are the live hook')
end)
test('a parked callback stays inert while its function reloads or removal is refused',function()
    local e=engine();local fired=0
    local other='/Game/A.A_C:Other'
    e.loaded[A]=true;e.loaded[other]=true
    local a=e.registry.register(A,function()end)
    local b=e.registry.register(other,function()fired=fired+1 end)
    e.loaded[A]=nil
    assert(e.registry.unregister(A,a,a)==true)
    -- A miss in one path can briefly park the still-loaded sibling.
    assert(e.registry.unregister(other,b,b)==true and e.count(other)==1)
    e.fire(other);assert(fired==0,'the parked callback must be inert even before re-registration')
    e.refuse=true
    e.registry.register(other,function()fired=fired+10 end)
    e.fire(other);assert(fired==10,'a failed engine removal may leave two handles but only one live callback')
end)
test('native functions pass straight through, errors included',function()
    local e=engine();local N='/Script/Engine.GameplayStatics:GetPlayerPawn'
    e.loaded[N]=true;local id=e.registry.register(N,function()end);e.loaded[N]=nil
    local ok,why=pcall(e.registry.unregister,N,id,id);assert(not ok and why:find('no UFunction',1,true) and e.registry:status().parked==0)
    ok=pcall(e.registry.unregister,N,id,id);assert(not ok and e.slow==2)
    ok=pcall(e.registry.unregister,nil,1,1);assert(not ok)
end)
test('installed over a table it replaces both functions, and nothing when one is missing',function()
    local e=engine();local g={RegisterHook=e.register,UnregisterHook=e.unregister}
    local r=Registry.install(g,{clock=function()return e.now end});assert(r and g.RegisterHook==r.register and g.UnregisterHook==r.unregister)
    e.loaded[A]=true;local id=g.RegisterHook(A,function()end);e.loaded[A]=nil;assert(g.UnregisterHook(A,id,id)==true)
    local seen={};r.log=function(s)seen[#seen+1]=s end
    e.loaded[A]=true;id=g.RegisterHook(A,function()end);e.loaded[A]=nil;e.now=5;g.UnregisterHook(A,id,id);assert(#seen==1)
    local half={RegisterHook=e.register};assert(Registry.install(half)==nil and half.RegisterHook==e.register)
end)
-- The modules the player logs and the replay named: an idle minute after the map that held their blueprint is gone.
local function idleMinute(tick,e)
    local t0=e.now
    while e.now-t0<60 do e.now=e.now+.55;tick() end
end
test('the summon keeper searches once after a reload and hooks again at the next summon',function()
    local e=engine();local Keep=require('summon_keep');local P=Keep.path
    local live=true
    local function object(fields)
        local a=fields or {};a.valid=true;function a:IsValid()return self.valid end;function a:GetAddress()return a end
        function a:GetClass()return {IsValid=function()return true end,GetFName=function()return {ToString=function()return 'X'end}end}end
        return a
    end
    local actor=object();local ability=object();function ability:GetAvatarActorFromActorInfo()return actor end
    ability.SpawnedSummonInstances={}
    _G.RegisterHook,_G.UnregisterHook=e.registry.register,e.registry.unregister
    _G.StaticFindObject=function(path)return e.loaded[path] and object() or nil end
    _G.FName=function(s)return s end
    e.loaded[P]=true
    local members={{actor=actor}}
    local keep=Keep.new({members=function()return members end,clock=function()return e.now end,log=function()end,aiOf=function()end})
    keep:tick();keep:passive(ability);assert(e.count(P)==1)
    e.loaded[P]=nil;members={};ability.valid=false
    idleMinute(function()keep:tick()end,e)
    assert(e.slow==1,'searched '..e.slow..' times in an idle minute')
    e.loaded[P]=true;members={{actor=actor}};ability=object();function ability:GetAvatarActorFromActorInfo()return actor end
    ability.SpawnedSummonInstances={};e.now=e.now+30
    keep:tick();keep:passive(ability);assert(e.count(P)==1,'hooked again, once')
    _G.RegisterHook,_G.UnregisterHook,_G.StaticFindObject,_G.FName=nil,nil,nil,nil
end)
test('the main program installs it before any other module can register a hook',function()
    local file=assert(io.open('Mods/PhantomGladiator/Scripts/main.lua','rb'));local text=file:read('*a');file:close()
    local at=assert(text:find('require("hook_registry").install(_G)',1,true))
    local second=assert(text:find('require("UEHelpers")',1,true));assert(at<second)
    assert(text:find('hookRegistry.log=log',1,true))
end)
print(n..' tests passed')
