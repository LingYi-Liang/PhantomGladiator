local State=dofile('Mods/PhantomGladiator/Scripts/engine_object_state.lua')
local function object(engine)
    return {engine=engine,IsValid=function()return true end,type=function()return 'UObject' end}
end
local lib=object(true)
local calls=0
local fn=setmetatable(object(true),{__call=function(_,context,actor)
    assert(context==lib);calls=calls+1;return actor.engine
end})
local state=State.new({find=function(path)if path:find('Default__',1,true)then return lib end;return fn end})
assert(state:check(object(true))==true)
assert(state:check(object(false))==false,'allocated wrapper must not keep an engine-invalid actor alive')
assert(calls==2)
assert(state:check(nil)==false)
local unavailable=State.new({find=function()return nil end})
assert(unavailable:check(object(true))==nil,'missing native check is unknown, never a fabricated destruction')
print('engine_object_state: PASS (exact native function/context, pending destruction, unknown API)')
