-- Only a string crosses Lua reloads. An unconfirmed native spawn requires a new
-- game process: reloading the Mod cannot prove an unowned Actor disappeared.
local Guard={}
local KEY='PhantomGladiator.spawn_pending.v1'
function Guard.new(options)
    options=options or {}
    local get=options.get or function() return ModRef:GetSharedVariable(KEY) end
    local set=options.set or function(value) ModRef:SetSharedVariable(KEY,value) end
    local localPending=false
    local instance={}
    function instance:reason()
        local ok,value=pcall(get)
        if not ok or (value~=nil and type(value)~='string') then
            return '生成保护状态不可读，未继续生成或开战'
        end
        if localPending or (value~=nil and value~='') then
            return '上次生成结果未确认；请退出并重新启动游戏，仅重载Mod不能确认未知对象已清除'
        end
    end
    function instance:begin()
        local reason=self:reason()
        if reason then return false,reason end
        localPending=true
        local ok=pcall(set,'native_spawn_pending')
        local readOk,value=pcall(get)
        if not ok or not readOk or value~='native_spawn_pending' then
            return false,'生成保护标记未读回，未调用原生生成'
        end
        return true
    end
    function instance:complete()
        local ok=pcall(set,'')
        local readOk,value=pcall(get)
        if not ok or not readOk or value~='' then return false,'生成所有权保护标记未确认清除' end
        localPending=false
        return true
    end
    return instance
end
return Guard
