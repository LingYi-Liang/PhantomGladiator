-- A UE4SS loop may reject registration, invoke the callback synchronously, or fail to cancel.
-- Only a callback whose returned handle belongs to the current registration may touch game state.
local Timer={}
function Timer.new(ms,register,cancel,clock,log)
    local self={}
    local slot,failedAt,delay
    local function release(handle)
        if handle and cancel then pcall(cancel,handle) end
    end
    function self:stop()
        local old=slot
        slot,failedAt,delay=nil,nil,nil
        if old then release(old.handle) end
    end
    function self:ensure(tick)
        if slot then return slot.handle~=nil end
        if type(register)~='function' then return false end
        local now=clock() or os.clock()
        if failedAt and now>=failedAt and now-failedAt<delay then return false end
        local token={}
        slot=token
        local function dispatch()
            if slot~=token or not token.handle or token.running then return end
            token.running=true
            local ok,err=pcall(tick)
            token.running=false
            if not ok and not token.warned then
                token.warned=true
                log('战斗计时回调异常 '..ms..'ms：'..tostring(err))
            elseif ok then token.warned=nil end
        end
        local ok,handle=pcall(register,ms,dispatch)
        if slot~=token then
            if ok and (not slot or slot.handle~=handle) then release(handle) end
            return false
        end
        if ok and handle then
            token.handle=handle
            if failedAt then log('战斗计时恢复 '..ms..'ms') end
            failedAt,delay=nil,nil
            return true
        end
        slot=nil
        if not failedAt then log('战斗计时登记失败 '..ms..'ms：'..tostring(handle)) end
        failedAt=now;delay=math.min(4,(delay or .25)*2)
        return false
    end
    return self
end
return Timer
