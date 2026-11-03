-- Small read-only reflection helpers. Never dereference an invalid UObject.
local U={}
local engineValidator
function U.setEngineValidator(check) engineValidator=check end
function U.valid(v)
    if v==nil then return false end
    local ok,result=pcall(function() return v:IsValid() end)
    if not ok or result~=true then return false end
    if engineValidator then
        local checked,live=pcall(engineValidator,v)
        if checked and live==false then return false end
    end
    return true
end
function U.kind(v)
    if type(v)~='table' and type(v)~='userdata' then return type(v) end
    local ok,name=pcall(function() return v:type() end)
    return ok and type(name)=='string' and name or type(v)
end
function U.unwrap(v)
    local kind=U.kind(v)
    if kind=='RemoteUnrealParam' or kind=='LocalUnrealParam' then
        local ok,result=pcall(function() return v:get() end);return ok and result or nil
    end
    return v
end
function U.key(v)
    if not U.valid(v) then return nil end
    local ok,key=pcall(function() return v:GetAddress() end)
    return ok and key~=nil and tostring(key) or nil
end
function U.field(v,name)
    if not U.valid(v) then return nil,false end
    local ok,value=pcall(function() return v[name] end)
    if ok then return U.unwrap(value),true end
    return nil,false
end
function U.struct(v,name)
    v=U.unwrap(v);local kind=U.kind(v)
    if kind~='table' and kind~='UScriptStruct' then return nil,false end
    local ok,value=pcall(function() return v[name] end)
    if ok then return U.unwrap(value),true end
    return nil,false
end
function U.array(v)
    v=U.unwrap(v);local kind=U.kind(v);local out={}
    if kind=='table' then
        if #v==0 and next(v)~=nil then return nil end
        for _,item in ipairs(v) do out[#out+1]=U.unwrap(item) end;return out
    end
    if kind~='TArray' then return nil end
    local ok=pcall(function() v:ForEach(function(_,item) out[#out+1]=U.unwrap(item) end) end)
    return ok and out or nil
end
function U.inWorld(actor,world)
    local key=U.key(world);if not key then return false end
    local object=actor
    for _=1,8 do
        if not U.valid(object) then return false end
        if U.key(object)==key then return true end
        local ok,outer=pcall(function() return object:GetOuter() end)
        if not ok then return false end
        object=outer
    end
    return false
end
function U.npcPath(actor)
    if not U.valid(actor) then return nil end
    local ok,cls=pcall(function() return actor:GetClass() end)
    if not ok or not U.valid(cls) then return nil end
    local got,full=pcall(function() return cls:GetFullName() end)
    local path=got and type(full)=='string' and full:match('^%S+ (/.+)$') or nil
    if not path then return nil end
    for _=1,32 do
        if not U.valid(cls) then return nil end
        local named,name=pcall(function() return cls:GetFullName() end)
        if named and name=='Class /Script/ProjectPBZ.PBZCharacter_NPC' then return path end
        local passed,parent=pcall(function() return cls:GetSuperStruct() end)
        if not passed then return nil end
        cls=parent
    end
end
return U
