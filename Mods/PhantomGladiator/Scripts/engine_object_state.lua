-- Engine validity differs from a UE4SS wrapper still pointing at allocated memory.
-- Use the exact UFunction to avoid the Lua UObject:IsValid name shadowing it.
local State={}
local function rawValid(value)
    if value==nil then return false end
    local ok,valid=pcall(function() return value:IsValid() end)
    return ok and valid==true
end
function State.new(options)
    options=options or {};local self={library=nil,fn=nil,lastError=nil}
    local find=options.find or StaticFindObject
    local log=options.log or function() end
    function self:check(object)
        if not rawValid(object) then return false end
        local typed,kind=pcall(function() return object:type() end)
        if typed and kind=='UScriptStruct' then return nil end
        if type(IsInGameThread)=='function' and not IsInGameThread() then return nil end
        if not rawValid(self.library) or not rawValid(self.fn) then
            local ok,lib,fn=pcall(function()
                return find('/Script/Engine.Default__KismetSystemLibrary'),find('/Script/Engine.KismetSystemLibrary:IsValid')
            end)
            if ok then self.library,self.fn=lib,fn end
        end
        if not rawValid(self.library) or not rawValid(self.fn) then
            if self.lastError~='missing' then log('[EngineValidity] 引擎IsValid接口未找到；保持原有效性判断，未把未知当销毁');self.lastError='missing' end
            return nil
        end
        local ok,value=pcall(self.fn,self.library,object)
        if not ok or type(value)~='boolean' then
            local err=tostring(value)
            if self.lastError~=err then log('[EngineValidity] 引擎有效性未读回：'..err);self.lastError=err end
            return nil
        end
        if not self.ready then log('[EngineValidity] 已通过原生Kismet IsValid读取布尔结果；包装器有效不再等同于引擎对象仍存活');self.ready=true end
        self.lastError=nil
        return value
    end
    return self
end
return State
