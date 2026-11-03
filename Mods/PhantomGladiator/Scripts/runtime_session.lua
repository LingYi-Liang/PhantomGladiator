-- 会话标识只保存字符串；不跨热重载保存UObject指针。
local Session = {}
function Session.new(options)
    local token
    if ModRef then
        local ok,value=pcall(function() return ModRef:GetSharedVariable("PhantomGladiator.session.v1") end)
        if ok and type(value)=="string" and value:match("^[%w_%-]+$") then token=value end
    end
    if not token then
        token="pg-"..os.time().."-"..tostring({}):gsub("[^%w]","")
        if ModRef then pcall(function() ModRef:SetSharedVariable("PhantomGladiator.session.v1",token) end) end
    end
    -- Lua重载会丢失参赛者所有权，因此同一游戏进程内的旧排队指令也必须失效。
    local generation=1
    if ModRef then
        local ok,value=pcall(function() return ModRef:GetSharedVariable("PhantomGladiator.session_generation.v1") end)
        local number=ok and type(value)=="string" and tonumber(value) or nil
        if number and number>=0 and number<1000000000 and number%1==0 then generation=number+1 end
        pcall(function() ModRef:SetSharedVariable("PhantomGladiator.session_generation.v1",string.format("%.0f",generation)) end)
    end
    token=token.."-mod"..string.format("%.0f",generation)
    local function valid(obj)
        if obj==nil then return false end
        local ok,value=pcall(options.valid,obj)
        return ok and value==true
    end
    local instance={}
    function instance:status()
        local result={game_session=token.."-no-world",game_ready=false,game_ready_reason="尚未进入可控制的游戏场景"}
        local okWorld,world=pcall(options.getWorld)
        if not okWorld or not valid(world) then return result end
        local okAddress,address=pcall(function() return world:GetAddress() end)
        if not okAddress or (type(address)~="number" and type(address)~="string") then return result end
        result.game_session=token.."-"..tostring(address):gsub("[^%w]","")
        local okPlayer,player=pcall(options.getPlayer)
        if not okPlayer or not valid(player) then return result end
        local okDestroy,destroying=pcall(options.isDestroying,player)
        if not okDestroy or destroying~=false then result.game_ready_reason="玩家正在销毁或状态不可读"; return result end
        local okHP,hp=pcall(options.hp,player)
        if not okHP or type(hp)~="number" or hp~=hp or hp<=0 then result.game_ready_reason="玩家生命状态尚未就绪"; return result end
        result.game_ready=true
        result.game_ready_reason="玩家与当前世界已就绪"
        return result
    end
    return instance
end
return Session
