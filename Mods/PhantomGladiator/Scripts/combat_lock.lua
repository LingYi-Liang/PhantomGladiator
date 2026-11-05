-- 不死不休: blue and red keep fighting until one side is out (docs/REVERSE_ENGINEERING.md v0.37.2-v0.37.8).
-- Without help a unit left the fight about every 10 s and walked back to where it spawned:
--   * after every action the AI asks BP_SGameAIComponent_C.ShouldExitCombatAfterAction;
--   * the hatred manager refuses another monster as a target (CheckCanHatredTarget/CheckActorCanBeHatred);
--   * the state machine itself calls CallTransition(AI.Transition.CombatToIdle), which empties the
--     hatred list; that one cannot be refused, the callback only runs after it.
-- While a fight runs, these hooks answer for this mod's blue and red units only: no to leaving combat,
-- yes to hating a unit of the other side, and on CombatToIdle the unit is sent straight back at its
-- target on the next game-thread tick (options.onDropped); after a perception event the unit's fallback target goes
-- back to its opponent (options.onSensed). A blueprint hook's callback runs after the
-- function and a non-nil return becomes its result, the way the AI difficulty checks are answered
-- (ai_difficulty.lua, verified in v0.33.1); every other AI keeps the game's answers. The hooks exist
-- only while a fight runs and are removed a little after it ends. Hooks that were only there to find
-- the exit path, and the attack token condition (never asked for these units in v0.37.8), are gone.
-- A corpse stays an actor for about 10 s (BP_RenewalNPC DestroyDelay). The game takes a dead unit off the lists of those in
-- its BeHatredList (OnDead), but an entry written straight into a HatredList is not in there, and AIScript_TargetSelector
-- picks the nearest actor of the HatredList: a unit went on standing over the corpse. So a dead unit is not hatable by this
-- fight's units, and comes off their lists the moment it is seen dead.
-- A rider's mount (options.vehicles) is an AI of its own that carries the rider: it gets the same answers as a hater, stays
-- in combat and is sent back, but it is nobody's target, so its rider is what the other side goes for.
local U=require('ue_observe')
local Lock={}
local AI='/SGameAI/BP_SGameAIComponent.BP_SGameAIComponent_C:'
local HATRED='/SGameAI/Tools/Hatred/BP_SGameHatredManagerComponent.BP_SGameHatredManagerComponent_C:'
Lock.path=AI..'ShouldExitCombatAfterAction'
Lock.paths={exit=Lock.path,canHate=HATRED..'CheckCanHatredTarget',canBeHated=HATRED..'CheckActorCanBeHatred',
    transition=AI..'CallTransition',sensed=AI..'OnTargetPerceptionUpdated',sensedInfo=AI..'OnTargetPerceptionInfoUpdated'}
local ORDER={'exit','canHate','canBeHated','transition','sensed','sensedInfo'}
local LABEL={exit='留在战斗中',canHate='允许仇恨',canBeHated='允许被仇恨',transition='脱战后拉回',sensed='感知后改回对手',
    sensedInfo='感知后改回对手(信息)'}
local UNHOOK_SECONDS,LINES,SUMMARY_SECONDS=10,8,10
local DROP='AI.Transition.CombatToIdle'
local DROP_SECONDS=0.5   -- at most one send-back per unit in this time, so a quick re-drop cannot loop

local function tagName(value)
    local name=U.struct(U.unwrap(value),'TagName')
    if name==nil then return nil end
    if type(name)=='string' then return name end
    local ok,text=pcall(function()return name:ToString()end)
    return ok and type(text)=='string' and text or nil
end

local function addr(object)
    if object==nil then return nil end
    local ok,key=pcall(function()return object:GetAddress()end)
    return ok and key~=nil and tostring(key) or nil
end

function Lock.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local self={alive=true,state='idle',held=0,passed=0,refused=0,message='没有进行中的战斗',counts={},window={}}
    local corpseLines=0
    for _,name in ipairs(ORDER)do self.counts[name]=0;self.window[name]=0 end
    local hooks={}        -- name -> {pre=, post=} while installed
    local components={}   -- AI component address -> team, for this mod's blue and red units in a fight
    local managers={}     -- hatred manager address -> team
    local teams={}        -- unit address -> team
    local corpses={}      -- unit address -> team, a fighting unit with no health left
    local forgotten={}    -- unit address -> true once it came off the others' lists
    local mounts={}       -- mount address -> true: hates, is not hated
    local owners={}       -- AI component address -> unit address
    local cache={}        -- unit address -> {ai=, hatred=} component addresses (a unit keeps its components)
    local dropped={}      -- unit address -> clock() of the last send-back
    local lines,quietSince,summaryAt={},nil,nil
    for _,name in ipairs(ORDER)do lines[name]=0 end
    local function say(m)log('[CombatLock] '..m)end
    local function count(name,text)
        self.counts[name]=self.counts[name]+1;self.window[name]=self.window[name]+1
        if lines[name]<LINES then lines[name]=lines[name]+1;say(LABEL[name]..' '..text()..' 累计='..self.counts[name])end
    end

    local callbacks={}
    -- AI component: after an action, stay in combat.
    callbacks.exit=function(context)
        if not self.alive then return nil end
        local team=components[addr(U.unwrap(context)) or '']
        if not team then self.passed=self.passed+1;return nil end
        self.held=self.held+1
        count('exit',function()return team end)
        return false
    end
    -- Hatred manager (owned by one unit) asked about another actor: allowed when both are ours and on
    -- opposite sides. Either check gets the same answer whichever side it is asked from.
    local function opponents(context,actor)
        local mine=managers[addr(U.unwrap(context)) or '']
        if not mine then return nil end
        local theirs=teams[addr(U.unwrap(actor)) or '']
        if theirs and theirs~=mine then return mine,theirs end
    end
    for _,name in ipairs({'canHate','canBeHated'})do
        callbacks[name]=function(context,actor)
            if not self.alive then return nil end
            local asked=addr(U.unwrap(actor)) or ''
            if managers[addr(U.unwrap(context)) or ''] and (corpses[asked] or mounts[asked]) then
                self.refused=self.refused+1
                return false
            end
            local mine,theirs=opponents(context,actor)
            if not mine then return nil end
            count(name,function()return mine..' → '..theirs end)
            return true
        end
    end
    -- AI component transition: CombatToIdle on a fighting unit sends it back at its target.
    callbacks.transition=function(context,tag)
        if not self.alive or not options.onDropped then return nil end
        local component=addr(U.unwrap(context)) or ''
        local team,unit=components[component],owners[component]
        if not team or not unit or tagName(tag)~=DROP then return nil end
        local now=clock()
        if dropped[unit] and now-dropped[unit]<DROP_SECONDS then return nil end
        dropped[unit]=now
        count('transition',function()return team end)
        pcall(options.onDropped,unit)
        return nil
    end
    -- Perception events (the component's two delegates, before the native sense handlers): the AI's targeting falls
    -- back to the blackboard's Last Sensed Actor, which perception sets to the player, the only actor it senses as
    -- hostile; a fighting unit's is set back to its opponent on the next game-thread tick (options.onSensed).
    for _,name in ipairs({'sensed','sensedInfo'})do
        callbacks[name]=function(context)
            if not self.alive or not options.onSensed then return nil end
            local component=addr(U.unwrap(context)) or ''
            local team,unit=components[component],owners[component]
            if not team or not unit then return nil end
            count(name,function()return team end)
            pcall(options.onSensed,unit)
            return nil
        end
    end

    local function install()
        for _,fn in ipairs({'StaticFindObject','RegisterHook','UnregisterHook'})do
            if type(_G[fn])~='function' then self.state='failed';self.message='缺少 '..fn;say(self.message);return end
        end
        for _,name in ipairs(ORDER)do
            local path=Lock.paths[name]
            local okFind,found=pcall(StaticFindObject,path)
            if not okFind or not U.valid(found) then say('找不到函数 '..path)
            else
                local ok,pre,post=pcall(RegisterHook,path,callbacks[name])
                if ok and type(pre)=='number' and type(post)=='number' then
                    hooks[name]={pre=pre,post=post};say('挂钩注册ID读回 '..name..' pre='..pre..' post='..post)
                else say('挂钩注册失败 '..name..'：'..tostring(pre))end
            end
        end
        if next(hooks) then self.state='running';self.message='战斗中，参战单位不中途退出、互相仇恨'
        else self.state='failed';self.message='找不到退出战斗判断函数' end
    end
    local function uninstall(reason)
        if not next(hooks) then return end
        local kept={}
        for name,hook in pairs(hooks)do
            if not pcall(UnregisterHook,Lock.paths[name],hook.pre,hook.post) then kept[name]=hook end
        end
        local parts={}
        for _,name in ipairs(ORDER)do parts[#parts+1]=LABEL[name]..'='..self.counts[name] end
        say('摘除挂钩（'..reason..'） '..table.concat(parts,' ')..' 其他AI照常='..self.passed..' 摘除失败='..tostring(next(kept)~=nil))
        hooks=kept
        if not next(hooks) then self.state='idle';self.message='没有进行中的战斗' end
    end

    -- True only for a read that says no health is left; a unit whose health cannot be read counts as alive.
    local function dead(actor)
        if not options.hp then return false end
        local ok,hp=pcall(options.hp,actor)
        return ok and type(hp)=='number' and hp<=0
    end
    -- Takes a fresh corpse off the list of every unit still fighting, through the game's own remove, and reads it back.
    local function forget(corpse,living)
        if not options.hatredOf or not options.hates then return end
        local held,removed,left=0,0,0
        for _,member in ipairs(living)do
            local manager=options.hatredOf(member.actor)
            if U.valid(manager) and U.valid(corpse) and options.hates(manager,corpse)==true then
                held=held+1
                pcall(function()manager:RemoveActorFromHatredList(corpse)end)
                if options.hates(manager,corpse)==false then removed=removed+1 else left=left+1 end
            end
        end
        if corpseLines<LINES then
            corpseLines=corpseLines+1
            say(string.format('尸体移出仇恨表 尸体=%s 表里有它的单位=%d 移出=%d 读回仍在=%d 累计拒绝=%d',
                options.label and options.label(corpse) or tostring(U.key(corpse)),held,removed,left,self.refused))
        end
    end
    -- Support tick: index the fighting units and their components; install while a fight runs.
    function self:tick()
        if not self.alive then return end
        local now=clock()
        local ai,hatred,units,known,own,bodies,horses={},{},{},{},{},{},{}
        local fresh,living={},{}
        if options.fighting() then
            local members=options.members()
            for _,member in ipairs(members)do
                -- Stands keep their native AI/hatred answers. A summon held in reserve is not in the fight yet;
                -- a unit out of reach by its own design
                -- (member.untargetable, boss_stages.lua) still hates but keeps the game's answer as a target.
                if (member.team=='blue' or member.team=='red') and not member.reserve and not member.stand then
                    local key=U.key(member.actor)
                    if key and dead(member.actor) then
                        bodies[key]=member.team
                        if not forgotten[key] then fresh[#fresh+1]=member end
                    elseif key then
                        forgotten[key]=nil
                        living[#living+1]=member
                        local c=cache[key] or {ai=addr(options.aiOf(member.actor)),hatred=options.hatredOf and addr(options.hatredOf(member.actor))}
                        known[key]=c
                        if not member.untargetable then units[key]=member.team end
                        if c.ai then ai[c.ai]=member.team;own[c.ai]=key end
                        if c.hatred then hatred[c.hatred]=member.team end
                    end
                end
            end
            for _,vehicle in ipairs(options.vehicles and options.vehicles(members) or {})do
                local key=U.key(vehicle.actor)
                if key then
                    local c=cache[key] or {ai=addr(options.aiOf(vehicle.actor)),hatred=options.hatredOf and addr(options.hatredOf(vehicle.actor))}
                    known[key]=c
                    horses[key]=true
                    if c.ai then ai[c.ai]=vehicle.team;own[c.ai]=key end
                    if c.hatred then hatred[c.hatred]=vehicle.team end
                end
            end
        end
        components,managers,teams,cache,owners,corpses,mounts=ai,hatred,units,known,own,bodies,horses
        for _,member in ipairs(fresh)do
            forget(member.actor,living)
            local key=U.key(member.actor)
            if key then forgotten[key]=true end
        end
        if next(teams) then
            quietSince=nil
            if not next(hooks) and self.state~='failed' then install() end
        elseif next(hooks) then
            quietSince=quietSince or now
            if now-quietSince>=UNHOOK_SECONDS then uninstall('战斗已结束') end
        end
        summaryAt=summaryAt or now
        if now-summaryAt>=SUMMARY_SECONDS then
            if next(hooks) then
                local parts={}
                for _,name in ipairs(ORDER)do parts[#parts+1]=LABEL[name]..'='..self.window[name];self.window[name]=0 end
                say(string.format('近 %.0f 秒：%s',now-summaryAt,table.concat(parts,' ')))
            end
            summaryAt=now
        end
    end
    function self:status()return {state=self.state,held=self.held,refused=self.refused,message=self.message,counts=self.counts}end
    function self:silence(reason)uninstall(reason or 'Mod卸载');self.alive=false end
    return self
end
return Lock
