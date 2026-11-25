-- Reflection helpers for studio-owned objects and exact-instance recovery.
local U=require('ue_observe')
local Native={}
function Native.call(obj,method,...)
    if not U.valid(obj) then return nil,false end
    local ok,v=pcall(function(...)return obj[method](obj,...)end,...)
    if not ok then return nil,false end
    return U.unwrap(v),true
end
function Native.need(obj,method,...)
    local v,ok=Native.call(obj,method,...)
    assert(ok,method..' failed')
    return v
end
function Native.path(obj)
    local v=Native.call(obj,'GetFullName')
    return type(v)=='string' and not v:find('%c') and v:match('^%S+ (/.+)$') or nil
end
function Native.same(a,b)
    local k=U.key(a)
    return k~=nil and k==U.key(b)
end
function Native.limit(v,a,b)return math.max(a,math.min(b,v))end
function Native.number(v)return type(v)=='number' and v==v and math.abs(v)<1e8 end
function Native.vec(v)
    local x,y,z=U.struct(v,'X'),U.struct(v,'Y'),U.struct(v,'Z')
    if Native.number(x) and Native.number(y) and Native.number(z) then return {X=x,Y=y,Z=z} end
end
function Native.textName(v)
    if type(v)=='string' then return v end
    if not v then return end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string' and s or nil
end
return Native
