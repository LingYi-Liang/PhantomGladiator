-- Missing objects use 1, 2, 4, 8, 16, 30, 60 second delays. Loaded objects are validated before reuse.
-- Roster resets can restart the schedule at most once every ten seconds.
local U=require('ue_observe')
local Retry={}
function Retry.new(options)
    options=options or {}
    local clock=options.clock or os.clock
    local states,objects={},{}
    local resetAt
    local lines=0
    local self={}
    local function say(text)
        if lines>=96 then return end
        lines=lines+1
        if options.log then options.log(text) end
    end
    function self:reset()
        local now=clock()
        if resetAt and now-resetAt<10 then return false end
        resetAt=now
        local count=0
        for _,state in pairs(states)do state.at=0;state.delay=1;count=count+1 end
        if count>0 then say('重置查询退避 待检查记录='..count..' 下次间隔=1秒') end
        return true
    end
    function self:ready(key)
        local state=states[key]
        if not state then state={at=0,delay=1};states[key]=state end
        local now=clock()
        if now<state.at then return false end
        state.at=now+state.delay
        state.delay=state.delay<16 and state.delay*2 or state.delay==16 and 30 or 60
        return true
    end
    function self:result(key,ok,detail)
        local state=states[key]
        if not state then state={at=0,delay=1};states[key]=state end
        local kind=ok and 'found' or 'missing'
        if not state[kind] then
            state[kind]=true
            say('查询 '..key..' 读回='..(ok and '找到' or '未找到，退避重试')..(detail and ' '..detail or ''))
        end
    end
    function self:find(path,finder)
        if U.valid(objects[path]) then return objects[path] end
        if not self:ready(path) then return nil end
        local ok,value=pcall(finder or StaticFindObject,path)
        local found=ok and U.valid(value)
        self:result(path,found)
        objects[path]=found and value or nil
        return objects[path]
    end
    return self
end
return Retry
