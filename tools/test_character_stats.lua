package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Stats=require('character_stats')
local function object(id,data)
    local o=data or {};o.alive=true
    function o:IsValid()return self.alive end
    function o:GetAddress()assert(self.alive);return id end
    return o
end
local actor=object(1);local foreign=object(2)
local cls=object(3)
local attributes=object(4)
function attributes:GetOuter()assert(self.alive);return actor end
function attributes:GetClass()assert(self.alive);return cls end
actor.AttributeSetBase=attributes
-- UE4SS hands struct fields out as UScriptStruct objects that write through to the set.
local function struct(value)return {BaseValue=value,CurrentValue=value,type=function()return 'UScriptStruct' end}end
for _,field in ipairs(Stats.allFields)do attributes[field]=struct(1)end
attributes.Health=struct(100);attributes.Health_Max=struct(100)
attributes.Shachi=struct(80);attributes.Shachi_Max=struct(80)
attributes.Health_Min=struct(0)
local calls=0
local effects={};local effectFields={}
for _,field in ipairs(Stats.allFields)do if not Stats.direct[field] then effectFields[#effectFields+1]=field end end
for index,field in ipairs(effectFields)do
    local name='GE_MA_'..field..'_1_Override'
    local path='/PBZCombatAsset/Config/AttributesModifyEffect/'..name..'.'..name
    local attr={AttributeName={ToString=function()return field end},AttributeOwner=cls,realName=field,native=true}
    local effect=object(100+index,{Modifiers={{Attribute=attr}}})
    function effect:GetFullName()return 'GameplayEffect '..path end
    effects[path]=effect
end
local native=object(6)
function native:ModifyCharacterAttributeValue(target,attribute,op,value)
    assert(target==actor and actor.alive and attributes.alive and op==3)
    calls=calls+1;local data=attributes[attribute.realName];data.BaseValue=value;data.CurrentValue=value
end
function native:GetCharacterAttributeValue(target,attribute)assert(target==actor);return attributes[attribute.realName].CurrentValue end
local abilities=object(7)
function abilities:GetDebugStringFromGameplayAttribute(attribute)return 'BasicAttributeSet.'..attribute.realName end
local check=object(8)
setmetatable(check,{__call=function(_,context,attr)assert(context==abilities);return attr.realName~=nil and attr.native==true end})
StaticFindObject=function(path)
    if effects[path] then return effects[path] end
    if path=='/Script/SGameAttributes.Default__AttributeUtils' then return native end
    if path=='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary' then return abilities end
    if path=='/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:IsValid' then return check end
end
local adapter=Stats.new();assert(adapter:snapshot(actor))
assert(adapter:writeBase(actor,'Attack',70) and adapter:nativeValue(actor,'Attack')==70 and calls==1)
assert(adapter:writeBase(actor,'Health_Min',100) and adapter:nativeValue(actor,'Health_Min')==100 and attributes.Health_Min.BaseValue==100)
for _,field in ipairs(Stats.fields)do assert(field~='Health_Min','matching NPCs must never copy the observer health floor')end
-- Every attribute of the set is writable: 209 through the native effect, the 14 without one on the field.
local all,direct,matched={},0,{}
for _,field in ipairs(Stats.allFields)do assert(not all[field],'duplicate '..field);all[field]=true;if Stats.direct[field] then direct=direct+1 end end
for field in pairs(Stats.direct)do assert(all[field],'direct field not in the set: '..field)end
for _,field in ipairs(Stats.fields)do assert(all[field],'matched field not in the set: '..field);matched[field]=true end
assert(#Stats.allFields==223 and direct==14 and #Stats.fields==107)
local before=calls
for index,field in ipairs(Stats.allFields)do
    local value=1000+index
    assert(adapter:writeBase(actor,field,value),field)
    assert(adapter:nativeValue(actor,field)==value and adapter:read(actor,field).base==value,field)
    assert(adapter:via(field)==(Stats.direct[field] and 'field' or 'effect'))
end
assert(calls-before==209,'only attributes with an effect call the native writer: '..(calls-before))
-- A struct handed out as a copy: the in-place write does not stick, so the whole field is assigned.
local copy={BaseValue=5,CurrentValue=5}
attributes.Resistance_ShachiWeaponShachi=setmetatable({type=function()return 'UScriptStruct' end},{__index=copy,__newindex=function()end})
assert(adapter:writeBase(actor,'Resistance_ShachiWeaponShachi',0.25) and adapter:nativeValue(actor,'Resistance_ShachiWeaponShachi')==0.25)
assert(not adapter:writeBase(actor,'NotAnAttribute',1),'unknown attributes are refused')
function attributes:GetOuter()return foreign end
local settled=calls
assert(not adapter:snapshot(actor) and not adapter:writeBase(actor,'Attack',12) and calls==settled,'foreign-owned attribute sets are read-only to this adapter')
attributes.alive=false
function attributes:GetOuter()error('invalid object dereference')end
assert(not adapter:writeBase(actor,'Attack',12) and calls==settled)
print('character_stats: PASS (instance ownership, descriptor readback, native Override=3, invalid-object gate)')
