-- RegisterHook / UnregisterHook for blueprint functions whose class can leave with its map.
-- UE4SS finds the function by name. With the class gone UnregisterHook throws after a search of every object (26-37 ms
-- measured), and each module that kept its ids tried again: one of them 108 times a minute after a teleport, 27 ms each,
-- until the next summon. A module that gives up and registers again instead leaves two callbacks on the function.
-- The entry itself stays with UE4SS under the function's name and comes off once the class is loaded again (seen in a
-- player's log: registered before a reload, removed after the next registration of the same path). So such a hook
-- its callbacks are disabled immediately. Their ids are parked until UE4SS can remove the entry.
-- Native /Script/ functions are never unloaded: they pass straight through.
local Registry={}
local GONE='no UFunction with the specified name was found'
local RECENT=1          -- s: after one miss, the other functions of that class are not searched for again
local LINES=20

function Registry.new(options)
    local self={parked=0,cleared=0}
    local register,unregister=options.register,options.unregister
    local clock=options.clock or os.clock
    local parked,missing,registered,lines={},{},{},0
    local function say(text)
        if lines>=LINES then return end
        lines=lines+1
        local log=self.log or options.log
        if log then log('[Hooks] '..text) end
    end
    local function blueprint(path)return type(path)=='string' and path:sub(1,8)~='/Script/' end
    local function owner(path)return path:match('^(.*):') or path end
    local function disable(path,pre,post)
        local hooks=registered[path]
        local state=hooks and hooks[pre]
        if state and state.post==post then
            state.enabled=false
            hooks[pre]=nil
            if not next(hooks) then registered[path]=nil end
        end
    end
    local function park(path,pre,post)
        disable(path,pre,post)
        local list=parked[path]
        if not list then list={};parked[path]=list end
        for _,ids in ipairs(list)do if ids[1]==pre and ids[2]==post then return true end end
        list[#list+1]={pre,post}
        self.parked=self.parked+1
        say('蓝图已随地图卸载，挂钩等它再次加载时摘除 '..path..' pre='..tostring(pre)..' post='..tostring(post))
        return true
    end
    function self.unregister(path,pre,post)
        if not blueprint(path) then return unregister(path,pre,post) end
        local class,now=owner(path),clock()
        local at=missing[class]
        if at and now>=at and now-at<RECENT then return park(path,pre,post) end
        local ok,result=pcall(unregister,path,pre,post)
        if ok then
            missing[class]=nil
            if result~=false then disable(path,pre,post) end
            return result
        end
        if type(result)=='string' and result:find(GONE,1,true) then
            missing[class]=now
            return park(path,pre,post)
        end
        error(result,0)
    end
    function self.register(path,...)
        if not blueprint(path) then return register(path,...) end
        local state={enabled=true}
        local args=table.pack(...)
        for i=1,math.min(2,args.n)do
            local callback=args[i]
            if type(callback)=='function' then
                args[i]=function(...)
                    if state.enabled then return callback(...) end
                end
            end
        end
        local result=table.pack(register(path,table.unpack(args,1,args.n)))
        local pre,post=result[1],result[2]
        if type(pre)~='number' or type(post)~='number' then
            state.enabled=false
            return table.unpack(result,1,result.n)
        end
        missing[owner(path)]=nil
        local hooks=registered[path] or {}
        if hooks[pre] then hooks[pre].enabled=false end
        hooks[pre]=state;registered[path]=hooks;state.post=post
        local list=parked[path]
        if list then
            parked[path]=nil;missing[owner(path)]=nil
            local kept={}
            for _,ids in ipairs(list)do
                -- The callback that was just installed must never be taken for an old one.
                if ids[1]~=result[1] or ids[2]~=result[2] then
                    local ok,value=pcall(unregister,path,ids[1],ids[2])
                    if ok and value~=false then self.cleared=self.cleared+1
                    else kept[#kept+1]=ids;say('旧挂钩仍未摘除 '..path..' pre='..tostring(ids[1])..'：'..tostring(value)) end
                end
                self.parked=self.parked-1
            end
            if #kept>0 then parked[path]=kept;self.parked=self.parked+#kept end
        end
        return table.unpack(result,1,result.n)
    end
    function self:status()return {parked=self.parked,cleared=self.cleared} end
    return self
end
-- Over the given table's RegisterHook and UnregisterHook; nothing is replaced when either is missing.
function Registry.install(globals,options)
    if type(globals.RegisterHook)~='function' or type(globals.UnregisterHook)~='function' then return nil end
    options=options or {}
    local registry=Registry.new({register=globals.RegisterHook,unregister=globals.UnregisterHook,clock=options.clock,log=options.log})
    globals.RegisterHook,globals.UnregisterHook=registry.register,registry.unregister
    return registry
end
return Registry
