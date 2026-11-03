local Guard=dofile('Mods/PhantomGladiator/Scripts/spawn_guard.lua')
local value=nil
local options={get=function() return value end,set=function(v) assert(type(v)=='string');value=v end}
local first=Guard.new(options)
assert(not first:reason() and first:begin())
assert(first:reason() and not first:begin())
local reloaded=Guard.new(options)
assert(reloaded:reason(),'hot reload must retain unconfirmed native-spawn protection')
assert(first:complete() and not first:reason() and not reloaded:reason())
assert(first:begin() and first:complete())
local broken=Guard.new({get=function() error('unavailable') end,set=function() error('must not write') end})
assert(broken:reason() and not broken:begin())
local silent=Guard.new({get=function() return nil end,set=function() end})
assert(not silent:begin() and silent:reason(),'write must be read back before native work')
value='native_spawn_pending'
local fails=Guard.new({get=options.get,set=function() error('write failed') end})
assert(not fails:complete() and fails:reason(),'unconfirmed clear cannot permit a new spawn')
print('spawn_guard: PASS (string-only hot-reload persistence, begin/readback, confirmed ownership, I/O failures)')
