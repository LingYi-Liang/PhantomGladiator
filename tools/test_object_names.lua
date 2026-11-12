package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local U=require('ue_observe')
local reads=0
local cls={IsValid=function()return true end,GetFName=function()
    reads=reads+1;return {ToString=function()return 'BP_Unit_C' end}
end}
local actor={IsValid=function()return true end,GetClass=function()return cls end}
assert(U.className(actor)=='BP_Unit_C' and reads==1)
cls.IsValid=function()return false end
assert(U.className(actor)==nil and reads==1,'a stale class must not reach GetFName')
cls.IsValid=function()return true end
U.setEngineValidator(function(value)return value~=cls end)
assert(U.className(actor)==nil and reads==1,'engine-invalid classes remain unreadable when the wrapper is valid')
U.setEngineValidator(nil)
actor.GetClass=function()return nil end
assert(U.className(actor)==nil)
actor.IsValid=function()return false end
actor.GetClass=function()error('invalid actors must not reach GetClass')end
assert(U.className(actor)==nil)
for i=1,100 do
    local current={IsValid=function()return true end,GetFName=function()
        return {ToString=function()return 'BP_Unit_'..i..'_C' end}
    end}
    local recycled={IsValid=function()return true end,GetAddress=function()return 42 end,GetClass=function()return current end}
    assert(U.className(recycled)=='BP_Unit_'..i..'_C','class names must not inherit an address cache')
end
print('object_names: PASS (valid, missing, stale and engine-invalid classes; recycled actors)')
