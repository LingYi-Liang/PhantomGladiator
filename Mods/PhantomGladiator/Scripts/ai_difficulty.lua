-- Per-unit AI difficulty. The game's AI asks "is the difficulty at least X" through two blueprint
-- checks, both `GetDifficulty() >= self.Difficulty` (docs/REVERSE_ENGINEERING.md v0.32.1/v0.33.0):
--   AICondition_AboveDifficulty_C.EvaluateCondition(AIController)  shared ability-pool condition
--   BTDecorator_AboveDifficulty_C.PerformConditionCheckAI(OwnerController, ControlledPawn)
-- Both call UPBZBlueprintFunctionLibrary.GetDifficulty(ContextObject).
-- For a unit this app summoned at a chosen difficulty, the hooks answer with that unit's level:
-- the checks return `level >= Difficulty`, and GetDifficulty returns the level when its context
-- belongs to the unit. UE4SS turns a callback's non-nil return value into the function's return value;
-- nil keeps the game's answer. The player, map enemies and the world keep the game's difficulty.
-- Verified in game (v0.33.1): a value returned from the GetDifficulty *pre* callback becomes the result;
-- the post callback runs too but never sees a usable context, so it stays empty. Nothing is written.
-- Every map NPC asks too, so the hooks are hot: they exist only while a leveled unit does (installed
-- right before such a unit finishes spawning, removed 10 s after the last one leaves), and attribution
-- is a lookup in a per-tick index of the units' and their controllers' addresses (v0.35.3; the
-- earlier outer-chain walk with engine validity calls made the game stutter).
local U=require('ue_observe')
local AI={}
local LIBRARY='/Script/ProjectPBZ.PBZBlueprintFunctionLibrary'
local DEFAULT='/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary'
-- GetDiffcultMode was only ever asked with the World as context (v0.32.1–v0.35 logs), never by a unit.
local FUNCTIONS={'GetDifficulty'}
local UNHOOK_SECONDS=10
-- A hook UE4SS would not remove is tried again this often, not every tick (v0.38.2 logged 150 lines in 78 s).
local STALE_RETRY=10
-- The blueprint checks are looked up every 15 s for a minute after a leveled unit is summoned, then no more
-- until the next one: a lookup that misses costs 50–60 ms (v0.37.6 log), a stutter every 15 s otherwise.
local CHECK_EVERY,CHECK_WINDOW=15,60
local VALUES={Handicapped=0,Easy=1,Normal=2,Hard=3,Nightmare=4} -- EDifficultMode
-- Blueprint checks: the hook's single callback runs after the function; `subject` picks the argument
-- that names the AI being checked.
local CHECKS={
    {name='EvaluateCondition',path='/PBZCombatAsset/Prototypes/AI/AICondition_AboveDifficulty.AICondition_AboveDifficulty_C:EvaluateCondition',
        subject=function(controller)return controller end,call=function(node,controller)return node:EvaluateCondition(controller)end},
    {name='PerformConditionCheckAI',path='/PBZCombatAsset/Prototypes/AI/BTDecorator_AboveDifficulty.BTDecorator_AboveDifficulty_C:PerformConditionCheckAI',
        subject=function(controller,pawn)return pawn or controller end,call=function(node,controller,pawn)return node:PerformConditionCheckAI(controller,pawn)end},
}
local MAX_LINES=50
AI.values=VALUES
AI.checks=CHECKS

local function fname(object)
    local ok,name=pcall(function()return object:GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end
local function className(object)
    if not U.valid(object) then return 'invalid' end
    local ok,class=pcall(function()return object:GetClass()end)
    return ok and U.valid(class) and fname(class) or '?'
end
local function show(v)
    v=U.unwrap(v)
    if type(v)=='number' then return string.format('%.6g',v) end
    if v==nil or type(v)=='boolean' or type(v)=='string' then return tostring(v) end
    if U.valid(v) then return fname(v) end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string' and s or U.kind(v)
end

function AI.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.time
    local self={state='idle',alive=true,overrides=0,verified=0,failed=0,message='还没有按所选难度召唤的单位',
        calls={},answers={}}
    local hooks,cache,logged,lines,installed,samples={},{},{},0,{},{}
    local index={}
    local nextCheck,retryChecks=nil,{}
    -- stale: hooks whose removal failed, tried again every STALE_RETRY s. results/checkResults: the last readback
    -- of each unit on the field and of each check, so the app warns about what is wrong now, not since load.
    local stale,results,checkResults,currentFailed={},{},{},0
    local summarizedAt,summarizedCount,emptySince,checksAt,checksUntil,staleAt
    local function say(m)log('[AIDifficulty] '..m)end
    -- The message is built only the first time a signature is seen.
    local function note(signature,message)
        if not logged[signature] and lines<MAX_LINES then
            logged[signature]=true;lines=lines+1
            say(type(message)=='function' and message() or message)
        end
    end
    local function bump(t,k)t[k]=(t[k] or 0)+1 end

    local function addr(object)
        if object==nil then return nil end
        local ok,key=pcall(function()if object:IsValid() then return object:GetAddress() end end)
        return ok and key~=nil and tostring(key) or nil
    end
    -- The level of the unit a context object belongs to: the unit or its controller, or an object whose
    -- outer (or the outer's outer, e.g. a behaviour-tree node under the controller's tree component) is
    -- one of them. Guard the wrapper before reading its address or outer; avoid a world lookup on this hot path.
    -- Results, misses included, are cached until the next tick.
    local function resolve(object)
        local key=addr(object)
        if not key then return nil end
        local level=cache[key]
        if level~=nil then return level or nil,key end
        level=index[key]
        local current=object
        for _=1,2 do
            if level then break end
            local ok,outer=pcall(function()return current:GetOuter()end)
            local outerKey=ok and addr(outer)
            if not outerKey then break end
            level=index[outerKey];current=outer
        end
        cache[key]=level or false
        return level,key
    end

    local function difficultyCallback(name,phase)
        local counter=name..'.'..phase
        local seen={}
        return function(_,contextObject)
            if not self.alive or self.state~='running' then return nil end
            bump(self.calls,counter)
            local object=U.unwrap(contextObject)
            local level,key=resolve(object)
            local value=level and VALUES[level]
            if value==nil then return nil end
            self.overrides=self.overrides+1
            if lines<MAX_LINES and seen[key]~=level then
                seen[key]=level
                local signature=counter..'|'..level..'|'..key
                if not logged[signature] then note(signature,'改写 '..name..'('..phase..') 上下文='..className(object)..' → '..level..'('..value..')') end
            end
            return value
        end
    end

    local function checkCallback(spec)
        local argsKey='args|'..spec.name
        return function(context,...)
            if not self.alive or self.state~='running' then return nil end
            bump(self.calls,spec.name)
            local node=U.unwrap(context)
            if lines<MAX_LINES and not logged[argsKey] then
                local args=table.pack(...)
                local kinds={}
                for i=1,args.n do kinds[#kinds+1]=i..'='..U.kind(args[i])..':'..show(args[i])end
                note(argsKey,'检查节点参数 '..spec.name..' 节点='..className(node)..' '..table.concat(kinds,' '))
            end
            local first,second=...
            local controller,pawn=U.unwrap(first),U.unwrap(second)
            local subject=spec.subject(controller,pawn)
            local level=resolve(subject)
            if not level then return nil end
            local rawThreshold=U.field(node,'Difficulty')
            local threshold=tonumber(rawThreshold)
            if not threshold then return nil end
            local answer=VALUES[level]>=threshold
            self.overrides=self.overrides+1
            bump(self.answers,spec.name..' 门槛='..threshold..' → '..tostring(answer))
            if checkResults[spec.name]==nil and not samples[spec.name] then
                samples[spec.name]={node=node,args={controller,pawn},threshold=threshold,level=level}
            end
            if lines<MAX_LINES then note(spec.name..'|'..threshold..'|'..level,function()
                return '改写 '..spec.name..' 单位='..className(subject)..'/'..level..' 门槛='..threshold..' → '..tostring(answer) end) end
            return answer
        end
    end

    -- kind: 'difficulty' for the GetDifficulty hook, 'check' for the blueprint checks.
    local function register(path,label,pre,post,kind)
        local okFind,found=pcall(StaticFindObject,path)
        if not okFind or not U.valid(found) then return false end
        local ok,preId,postId
        local hook={path=path,kind=kind}
        local function dispatch(...)if hook.enabled then return pre(...) end end
        if post then ok,preId,postId=pcall(RegisterHook,path,dispatch,post) else ok,preId,postId=pcall(RegisterHook,path,dispatch) end
        if ok and type(preId)=='number' and type(postId)=='number' then
            hook.pre,hook.post,hook.enabled=preId,postId,true
            hooks[#hooks+1]=hook
            say('挂钩注册ID读回 '..label..' pre='..preId..' post='..postId)
            return true
        end
        say('挂钩注册失败 '..label..'：'..tostring(preId))
        return false,true
    end
    local function registerDifficulty()
        for _,name in ipairs(FUNCTIONS)do
            local path=LIBRARY..':'..name
            if not register(path,name,difficultyCallback(name,'pre'),function()end,'difficulty') then say('函数不可用 '..path)end
        end
    end

    local function install()
        for _,name in ipairs({'StaticFindObject','RegisterHook','UnregisterHook'})do
            if type(_G[name])~='function' then self.state='failed';self.message='缺少 '..name..'，AI难度未启用';say(self.message);return end
        end
        registerDifficulty()
        self.state='running'
        self.message='已挂钩，等待读回'
        checksUntil=clock()+CHECK_WINDOW
    end
    local function unhook(hook)
        hook.enabled=false
        local ok,result=pcall(UnregisterHook,hook.path,hook.pre,hook.post)
        return ok and result~=false,result
    end
    -- A hook that would not come off goes to `stale` and the module goes idle anyway, so the next summon hooks
    -- afresh. v0.38.2 stayed 'running' with a GetDifficulty hook that no longer ran, and the units summoned in
    -- the next ten minutes got the game's AI difficulty with the chosen stats.
    local function uninstall(reason)
        local failed={}
        for _,hook in ipairs(hooks)do
            local ok,err=unhook(hook)
            if not ok then stale[#stale+1]=hook;failed[#failed+1]=hook.path:match('[^:]+$')..'：'..tostring(err) end
        end
        say('摘除挂钩 reason='..reason..' 摘除='..(#hooks-#failed)..' 失败='..#failed
            ..(#failed>0 and '（'..table.concat(failed,'；')..'；每 '..STALE_RETRY..' 秒再试，下次召唤重新挂钩）' or ''))
        hooks={};installed={};checkResults={};samples={};checksAt=nil;nextCheck=nil;retryChecks={}
        self.state='idle'
        self.message='没有按所选难度召唤的单位，挂钩已摘除'
    end
    local function retryStale()
        if #stale==0 or (staleAt and clock()-staleAt<STALE_RETRY) then return end
        staleAt=clock()
        local kept={}
        for _,hook in ipairs(stale)do
            local reused=false
            for _,active in ipairs(hooks)do
                if active.path==hook.path and active.pre==hook.pre and active.post==hook.post then reused=true;break end
            end
            if not reused and not unhook(hook) then kept[#kept+1]=hook end
        end
        if #kept<#stale then say('补摘挂钩 '..(#stale-#kept)..' 个，剩 '..#kept..' 个')end
        stale=kept
    end
    -- The GetDifficulty hook did not run for a Lua call: it is hooked again; the old one goes to `stale`.
    local function rehook()
        local kept={}
        for _,hook in ipairs(hooks)do
            if hook.kind=='difficulty' then hook.enabled=false;stale[#stale+1]=hook else kept[#kept+1]=hook end
        end
        hooks=kept
        registerDifficulty()
    end

    -- Called by the spawn path right before a unit with a chosen level finishes spawning, so its own
    -- start-up questions are already answered with its level.
    function self:ensure(actor,level)
        if not self.alive or not VALUES[level] then return end
        local key=addr(actor)
        if key then index[key]=level;results[key]=nil;cache={} end
        emptySince=nil
        if self.state=='idle' then install() end
        checksUntil=clock()+CHECK_WINDOW
    end

    -- Lua calls go through the same hooks. Asking for a unit's difficulty proves the GetDifficulty
    -- override and asking with the World proves everyone else still gets the game's answer; calling a
    -- recorded check with the unit's arguments proves the check override.
    local library,world
    local function gameValue()
        local okWorld,game=pcall(function()return library:GetDifficulty(world)end)
        return okWorld and tonumber(U.unwrap(game)) or nil
    end
    local function askUnit(actor)
        local okUnit,unit=pcall(function()return library:GetDifficulty(actor)end)
        return okUnit and tonumber(U.unwrap(unit)) or nil
    end
    local function readbackUnit(actor,level)
        local before=self.calls['GetDifficulty.pre'] or 0
        local unit=askUnit(actor)
        local repaired=''
        -- The Lua call goes through the hook; a pre callback that did not run means the hook is dead.
        if unit~=VALUES[level] and (self.calls['GetDifficulty.pre'] or 0)==before then
            rehook()
            unit=askUnit(actor)
            repaired=' 挂钩没有被调用，重新挂钩后再读回='..tostring(unit)
        end
        local game=gameValue()
        local ok=unit==VALUES[level] and game~=nil
        if ok then self.verified=self.verified+1 else self.failed=self.failed+1 end
        local key=U.key(actor)
        if key then results[key]={level=level,ok=ok,retryAt=not ok and clock()+CHECK_EVERY or nil} end
        -- Which of the character's two AI configs its AI ended up with (PDA_ActorConfig: AIConfig  Default /
        -- AIConfig Nightmare); read only.
        local config=U.field(actor,'Actor Config')
        local ai=U.field(U.field(actor,'Controller'),'SGameAIComponent')
        say('读回 GetDifficulty 单位='..className(actor)..' 期望='..level..'('..tostring(VALUES[level])..') 返回='..tostring(unit)
            ..' World返回='..tostring(game)..' 结果='..tostring(ok)..' 前回调计数='..(self.calls['GetDifficulty.pre'] or 0)
            ..' AI配置 默认='..show((U.field(config,'AIConfig  Default')))..' 噩梦='..show((U.field(config,'AIConfig Nightmare')))
            ..' 当前='..show((U.field(ai,'AIConfig')))..repaired)
    end
    local function readbackCheck(spec,sample)
        if not U.valid(sample.node) or not U.valid(sample.args[1]) or (sample.args[2] and not U.valid(sample.args[2]))
            or resolve(spec.subject(sample.args[1],sample.args[2]))~=sample.level then return end
        local threshold=U.field(sample.node,'Difficulty')
        if tonumber(threshold)~=sample.threshold then return end
        local okCall,result=pcall(spec.call,sample.node,sample.args[1],sample.args[2])
        if okCall then result=U.unwrap(result) else result=nil end
        local expected=VALUES[sample.level]>=sample.threshold
        local game=gameValue()
        local gameAnswer=game and game>=sample.threshold
        local ok=result==expected
        if ok then self.verified=self.verified+1 else self.failed=self.failed+1 end
        checkResults[spec.name]=ok
        say('读回 '..spec.name..' 门槛='..sample.threshold..' 单位难度='..sample.level..' 期望='..tostring(expected)..' 返回='..tostring(result)
            ..' 游戏难度下应为='..tostring(gameAnswer)..'（'..(expected~=gameAnswer and '可区分' or '与游戏答案相同，不能区分')..'）结果='..tostring(ok))
    end

    function self:summary(reason)
        local parts={}
        for k,v in pairs(self.calls)do parts[#parts+1]=k..'='..v end
        table.sort(parts)
        local answers={}
        for k,v in pairs(self.answers)do answers[#answers+1]=k..' ×'..v end
        table.sort(answers)
        say('汇总 reason='..reason..' 改写='..self.overrides..' 读回成功='..self.verified..' 失败='..self.failed..' 回调='..table.concat(parts,' '))
        if #answers>0 then say('  检查节点改写：'..table.concat(answers,'；'))end
    end

    -- The app's warning: units on the field whose readback failed, and failed check readbacks while units are out.
    local function countFailed(leveled)
        local kept,bad={},0
        for _,unit in ipairs(leveled)do
            local result=results[unit.key]
            if result then kept[unit.key]=result;if not result.ok then bad=bad+1 end end
        end
        results=kept
        for _,ok in pairs(checkResults)do if ok==false then bad=bad+1 end end
        currentFailed=bad
    end

    function self:tick()
        if not self.alive then return end
        cache={}
        retryStale()
        if options.ready and not options.ready() then
            index={};results={};samples={};checkResults={};currentFailed=0;nextCheck=nil
            return
        end
        local leveled,fresh,pending={},{},false
        for _,entry in ipairs(options.members and options.members() or {})do
            local level=options.levelOf(entry.actor)
            local key=level and VALUES[level] and addr(entry.actor)
            if key then
                fresh[key]=level
                local previous=results[key]
                local needsRead=not previous or previous.level~=level or (previous.retryAt and clock()>=previous.retryAt)
                leveled[#leveled+1]={actor=entry.actor,level=level,key=key,needsRead=needsRead}
                pending=pending or needsRead
                local controllerKey=addr(U.field(entry.actor,'Controller'))
                if controllerKey then fresh[controllerKey]=level end
            end
        end
        index=fresh
        if #leveled==0 then
            results={};samples={};checkResults={};currentFailed=0;nextCheck=nil
            emptySince=emptySince or clock()
            if self.state=='running' and clock()-emptySince>=UNHOOK_SECONDS then uninstall('召唤单位已全部离场') end
            return
        end
        emptySince=nil
        if self.state=='idle' then install() end
        if self.state~='running' then return end
        -- The blueprint checks load with the first AI that uses them.
        -- Looking up a function whose class is not loaded is slow in UE4SS (60–70 ms a tick in v0.35.5
        -- with only 魔渊 out, whose AI does not use these checks), so try every 15 s, and only in the minute
        -- after a leveled unit was summoned.
        local now=clock()
        local discover=checksUntil and now<=checksUntil
        if not nextCheck and (discover or next(retryChecks)) and (not checksAt or now-checksAt>=CHECK_EVERY) then
            checksAt=now;nextCheck=1
        end
        while nextCheck do
            local i=nextCheck
            local spec=CHECKS[i]
            nextCheck=i<#CHECKS and i+1 or nil
            if not installed[spec.name] and ((checksUntil and checksAt<=checksUntil) or retryChecks[spec.name]) then
                local ok,rejected=register(spec.path,spec.name,checkCallback(spec))
                installed[spec.name]=ok;retryChecks[spec.name]=rejected
                break
            end
        end
        if pending or next(samples) then
            local found,lib=pcall(StaticFindObject,DEFAULT)
            library=found and lib
            world=options.getWorld and options.getWorld()
            if U.valid(library) and U.valid(world) then
                for _,unit in ipairs(leveled)do
                    if unit.needsRead then readbackUnit(unit.actor,unit.level) end
                end
                for _,spec in ipairs(CHECKS)do
                    local sample=samples[spec.name]
                    if sample then readbackCheck(spec,sample);samples[spec.name]=nil end
                end
            end
            library,world=nil,nil
        end
        countFailed(leveled)
        -- A running tally once a minute while it changes, so a fight is readable without a reload.
        if not summarizedAt then summarizedAt=clock() end
        if clock()-summarizedAt>=60 and summarizedCount~=self.overrides then
            summarizedAt=clock();summarizedCount=self.overrides;self:summary('每分钟')
        end
    end

    function self:silence(reason)
        if not self.alive then return end
        self.alive=false
        if self.state=='running' then self:summary(reason or 'Mod卸载')end
    end
    function self:status()
        -- failed: what the app warns about (units on the field now); failed_total: every failure since load, for logs.
        return {state=self.state,overrides=self.overrides,verified=self.verified,failed=currentFailed,failed_total=self.failed,
            stale=#stale,message=self.message}
    end
    return self
end
return AI
