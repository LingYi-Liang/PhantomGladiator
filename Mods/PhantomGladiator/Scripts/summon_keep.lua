-- A boss's summon passive (GA_SummonPassive_MonsterBase) destroys its summons when the boss leaves combat: entering
-- AI.State.Combat (Added_4602...) starts a one-shot wait for AI.State.Idle, kept in WaitOffCombatTask, and that wait
-- (Added_3B38...) calls DestroyAllSummons. Passives such as GA_SummonPassive_MuXiaoKui_P2 summon and write the boss's
-- blackboard AssignActor1/2 only when they activate, so nothing brings the summons back: GAA_AllOutAttack then finds no
-- Character in those keys, the boss's own move still plays its sound, and the stands' moves never start.
-- For a unit this mod summoned the wait is ended as soon as it starts, so its summons outlive a fight. Units of the map
-- are left as the game made them, and ending the wait changes no asset: without this module the passive works as before.
local U=require('ue_observe')
local Retry=require('lookup_retry')
local Keep={}
Keep.path='/PBZCombatAsset/Prototypes/Abilities/Base/GA_SummonPassive_MonsterBase.GA_SummonPassive_MonsterBase_C:Added_4602B2654F0CA071F910E69E5095CB2E'
local LINES=80

local function text(value)
    if value==nil or type(value)=='string' then return tostring(value) end
    local ok,result=pcall(function()return value:ToString()end)
    return ok and type(result)=='string' and result or '?'
end
local function className(object)
    if not U.valid(object) then return '空' end
    local ok,class=pcall(function()return object:GetClass()end)
    if not ok or not U.valid(class) then return '?' end
    local okName,name=pcall(function()return class:GetFName():ToString()end)
    return okName and type(name)=='string' and name or '?'
end
local function avatarOf(ability)
    if not U.valid(ability) then return nil end
    local ok,actor=pcall(function()return ability:GetAvatarActorFromActorInfo()end)
    actor=ok and U.unwrap(actor) or nil
    return U.valid(actor) and actor or nil
end
local function liveSummons(ability)
    local count=0
    for _,row in ipairs(U.array(U.field(ability,'SpawnedSummonInstances')) or {})do
        if U.valid(U.struct(row,'Pawn')) then count=count+1 end
    end
    return count
end
local function assigned(ai,key)
    local board=U.field(ai,'BlackboardComponent')
    if not U.valid(board) or FName==nil then return '读不到' end
    local ok,value=pcall(function()return board:GetValueAsObject(FName(key))end)
    return ok and className(U.unwrap(value)) or '读不到'
end

function Keep.new(options)
    local self={alive=true,ended=0}
    local passives,owned,hook,lines={},{},nil,0
    local function say(line)
        if lines>=LINES then return end
        lines=lines+1
        if options.log then options.log('[SummonKeep] '..line) end
    end
    local retry=Retry.new({clock=options.clock or os.clock,log=say})
    -- The hook runs inside the game's tag callback, so it reads this list rather than asking the arena, which may tidy up.
    local function ours(actor)
        local key=U.key(actor)
        return key~=nil and owned[key]==true
    end
    local function recordOf(ability)
        local key=U.key(ability)
        if not key then return nil end
        local record=passives[key]
        if not record then record={ability=ability};passives[key]=record end
        return record
    end
    local function endWait(record,why)
        local ability=record.ability
        local task=U.field(ability,'WaitOffCombatTask')
        if not U.valid(task) then return end
        local key=U.key(task)
        local called=pcall(function()task:EndTask()end)
        -- A task that was ended stays in the variable until the collector clears it: only a new one is news.
        if key==record.endedTask then return end
        record.endedTask=key
        self.ended=self.ended+1
        say('结束脱战销毁召唤物的等待（'..why..'） 单位='..className(avatarOf(ability))..' 调用='..tostring(called)
            ..' 读回等待仍有效='..tostring(U.valid(U.field(ability,'WaitOffCombatTask')))..' 召唤物='..liveSummons(ability))
    end
    local function onCombat(context)
        if not self.alive then return end
        local ability=U.unwrap(context)
        if not U.valid(ability) or not ours(avatarOf(ability)) then return end
        local record=recordOf(ability)
        if record then endWait(record,'进入战斗时') end
    end
    local function register()
        if hook or type(RegisterHook)~='function' or type(StaticFindObject)~='function' then return end
        if not retry:ready(Keep.path) then return end
        local found,fn=pcall(StaticFindObject,Keep.path)
        retry:result(Keep.path,found and U.valid(fn))
        if not found or not U.valid(fn) then return end
        local ok,pre,post=pcall(RegisterHook,Keep.path,onCombat,function()end)
        if ok and type(pre)=='number' and type(post)=='number' then
            hook={pre,post};say('挂钩注册ID读回 pre='..pre..' post='..post)
        else retry:result(Keep.path..':register',false,tostring(pre)) end
    end
    local function uninstall()
        if not hook or type(UnregisterHook)~='function' then return end
        local ok=pcall(UnregisterHook,Keep.path,hook[1],hook[2])
        say('摘除挂钩 调用读回='..tostring(ok))
        if ok then hook=nil end
    end
    -- Each support tick, for each summon passive of a unit this mod summoned (arena_summon_links.lua finds them).
    function self:passive(ability)
        if not self.alive or not U.valid(ability) then return end
        local known=passives[U.key(ability)]~=nil
        local record=recordOf(ability)
        if not record then return end
        if not known then retry:reset() end
        register()
        -- Combat that started before the hook was in place.
        endWait(record,'定时检查')
        local actor=avatarOf(ability)
        if not actor then return end
        local ai=options.aiOf and options.aiOf(actor)
        local state=text((U.struct(U.field(ai,'CurrentStateTag'),'TagName')))
        if record.state~=state then
            say('状态 '..tostring(record.state)..' -> '..state..' 单位='..className(actor)..' 召唤物读回='..liveSummons(ability)
                ..' AssignActor1='..assigned(ai,'AssignActor1')..' AssignActor2='..assigned(ai,'AssignActor2'))
            record.state=state
        end
    end
    function self:tick()
        if not self.alive then return end
        for key,record in pairs(passives)do
            if not U.valid(record.ability) then passives[key]=nil end
        end
        owned={}
        for _,member in ipairs(options.members() or {})do
            local key=U.key(member.actor)
            if key then owned[key]=true end
        end
        if not next(owned) then uninstall();passives={} end
    end
    function self:silence()self.alive=false;uninstall()end
    return self
end
return Keep
