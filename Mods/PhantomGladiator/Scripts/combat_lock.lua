-- 不死不休: blue and red keep fighting until one side is out (docs/REVERSE_ENGINEERING.md v0.37.2-v0.37.8).
-- Without help a unit left the fight about every 10 s and walked back to where it spawned:
--   * after every action the AI asks BP_SGameAIComponent_C.ShouldExitCombatAfterAction;
--   * the hatred manager refuses another monster as a target (CheckCanHatredTarget/CheckActorCanBeHatred);
--   * the state machine itself calls CallTransition(AI.Transition.CombatToIdle), which empties the
--     hatred list. The per-instance Idle guard is evaluated before this post-hook.
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
    transition=AI..'CallTransition',sensed=AI..'OnTargetPerceptionUpdated',sensedInfo=AI..'OnTargetPerceptionInfoUpdated',
    removed=HATRED..'RemoveActorFromHatredList',cleared=HATRED..'RemoveAllActorsFromHatredList'}
local ORDER={'exit','canHate','canBeHated','transition','sensed','sensedInfo'}
local LABEL={exit='留在战斗中',canHate='允许仇恨',canBeHated='允许被仇恨',transition='脱战后拉回',sensed='感知后改回对手',
    sensedInfo='感知后改回对手(信息)',removed='处决或无敌时补回条目',cleared='处决或无敌时整表清除后补回'}
local UNHOOK_SECONDS,LINES,SUMMARY_SECONDS=10,8,10
local DROP='AI.Transition.CombatToIdle'
local DROP_SECONDS=0.5   -- at most one send-back per unit in this time, so a quick re-drop cannot loop
local FORGET_SECONDS=0.5 -- failed/unreadable corpse removals retry without rescanning every support tick

local function tagName(value)
    local name=U.struct(U.unwrap(value),'TagName')
    if name==nil then return nil end
    if type(name)=='string' then return name end
    local ok,text=pcall(function()return name:ToString()end)
    return ok and type(text)=='string' and text or nil
end

local function addr(object)
    return U.key(object)
end
local function identity(actor)
    if not U.valid(actor) then return nil end
    local ok,name=pcall(function()return actor:GetFullName()end)
    return ok and type(name)=='string' and name or nil
end

function Lock.new(options)
    local order={table.unpack(ORDER)}
    if options.guard and options.guard.onHatredRemoved then
        order[#order+1]='removed';order[#order+1]='cleared'
    end
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local self={alive=true,state='idle',held=0,passed=0,refused=0,message='没有进行中的战斗',counts={},window={}}
    local corpseLines=0
    for _,name in ipairs(order)do self.counts[name]=0;self.window[name]=0 end
    local hooks={}        -- name -> {pre=, post=} while installed
    local components={}   -- AI component address -> team, for this mod's blue and red units in a fight
    local managers={}     -- hatred manager address -> team
    local teams={}        -- unit address -> team
    local corpses={}      -- unit address -> team, a fighting unit with no health left
    local forgotten={}    -- unit address -> true once confirmed, else next retry time
    local mounts={}       -- mount address -> true: hates, is not hated
    local owners={}       -- AI component address -> unit address
    local cache={}        -- unit address -> {ai=, hatred=} component addresses (a unit keeps its components)
    local dropped={}      -- unit address -> clock() of the last send-back
    local pendingSense,pendingDrop={},{}
    local identities={}   -- names only for addresses with corpse or send-back state
    local actorObjects={}
    local objectNames,componentNames={},{}
    local identityLines=0
    local installAt,installDelay,unhookAt,unhookLines=0,1,0,0
    local installWarnings={}
    local lines,quietSince,summaryAt={},nil,nil
    for _,name in ipairs(order)do lines[name]=0 end
    local function say(m)log('[CombatLock] '..m)end
    local function count(name,text)
        self.counts[name]=self.counts[name]+1;self.window[name]=self.window[name]+1
        if lines[name]<LINES then lines[name]=lines[name]+1;say(LABEL[name]..' '..text()..' 累计='..self.counts[name])end
    end
    local function refreshIdentity(key,actor)
        local old=identities[key]
        if old and (forgotten[key] or dropped[key]) then
            local current=identity(actor)
            if current and current~=old then
                forgotten[key],dropped[key],cache[key],identities[key]=nil,nil,nil,nil
                if identityLines<LINES then
                    identityLines=identityLines+1
                    say('演员地址复用 已更新缓存 旧身份='..old..' 新身份读回='..current)
                end
            end
        end
    end
    local function component_cache(key,actor,now)
        local c=cache[key]
        local stale=c and ((c.aiObject and (addr(c.aiObject)~=c.ai or identity(c.aiObject)~=c.aiName))
            or (c.hatredObject and (addr(c.hatredObject)~=c.hatred or identity(c.hatredObject)~=c.hatredName)))
        if not c or stale or now-c.checkedAt>=1 then
            local aiObject=options.aiOf(actor)
            local hatredObject=options.hatredOf and options.hatredOf(actor)
            c={ai=addr(aiObject),hatred=addr(hatredObject),aiObject=aiObject,hatredObject=hatredObject,
                aiName=identity(aiObject),hatredName=identity(hatredObject),checkedAt=now}
        end
        return c
    end
    local function owned_address(object,names)
        local key=addr(object)
        if not key or type(names[key])~='string' or identity(object)~=names[key] then return nil end
        return key
    end
    local function component_address(context)
        local key=owned_address(U.unwrap(context),componentNames)
        local owner=key and owners[key]
        if not owner or not owned_address(actorObjects[owner],objectNames) then return nil end
        if options.phaseBusy then
            local ok,busy=pcall(options.phaseBusy,actorObjects[owner])
            if not ok or busy~=false then return nil end
        end
        return key
    end

    local callbacks={}
    -- AI component: after an action, stay in combat.
    callbacks.exit=function(context)
        if not self.alive or not next(components) then return nil end
        local team=components[component_address(context) or '']
        if not team then self.passed=self.passed+1;return nil end
        self.held=self.held+1
        count('exit',function()return team end)
        return false
    end
    -- Hatred manager (owned by one unit) asked about another actor: allowed when both are ours and on
    -- opposite sides. Either check gets the same answer whichever side it is asked from.
    local function opponents(context,actor)
        local mine=managers[component_address(context) or '']
        if not mine then return nil end
        local theirs=teams[owned_address(U.unwrap(actor),objectNames) or '']
        if theirs and theirs~=mine then return mine,theirs end
    end
    for _,name in ipairs({'canHate','canBeHated'})do
        callbacks[name]=function(context,actor)
            if not self.alive or not next(managers) then return nil end
            local asked=owned_address(U.unwrap(actor),objectNames) or ''
            if managers[component_address(context) or ''] and (corpses[asked] or mounts[asked]) then
                self.refused=self.refused+1
                return false
            end
            local mine,theirs=opponents(context,actor)
            if not mine then return nil end
            count(name,function()return mine..' → '..theirs end)
            return true
        end
    end
    local function schedule(pending,callback,unit,component)
        if not options.defer then pcall(callback,unit);return end
        local token=options.context and options.context()
        if options.context and token==nil then return end
        local actorName,aiName=objectNames[unit],componentNames[component]
        local prior=pending[unit]
        if prior and prior.token==token and prior.actor==actorName and prior.component==component and prior.ai==aiName then return end
        local ticket={token=token,actor=actorName,component=component,ai=aiName}
        pending[unit]=ticket
        local ok,result=pcall(options.defer,function()
            if pending[unit]~=ticket then return end
            pcall(function()
                if self.alive and (not options.context or options.context()==token) and owners[component]==unit
                    and objectNames[unit]==actorName and componentNames[component]==aiName
                    and identity(actorObjects[unit])==actorName and component_address(options.aiOf(actorObjects[unit]))==component then
                    callback(unit)
                end
            end)
            if pending[unit]==ticket then pending[unit]=nil end
        end)
        if (not ok or result==false) and pending[unit]==ticket then pending[unit]=nil end
    end
    -- AI component transition: CombatToIdle on a fighting unit sends it back at its target.
    callbacks.transition=function(context,tag)
        if not self.alive or not next(components) or not options.onDropped then return nil end
        local component=component_address(context) or ''
        local team,unit=components[component],owners[component]
        if not team or not unit or tagName(tag)~=DROP then return nil end
        if options.guard then
            local checked,onThread=pcall(options.inGameThread)
            if checked and onThread==true then
                local read,kept=pcall(options.guard.onDrop,options.guard,actorObjects[unit],U.unwrap(context))
                if read and kept then return nil end
            end
        end
        local now=clock()
        if dropped[unit] and now-dropped[unit]<DROP_SECONDS then return nil end
        dropped[unit]=now
        identities[unit]=identity(actorObjects[unit])
        count('transition',function()return team end)
        schedule(pendingDrop,options.onDropped,unit,component)
        return nil
    end
    -- Perception events (the component's two delegates, before the native sense handlers): the AI's targeting falls
    -- back to the blackboard's Last Sensed Actor, which perception sets to the player, the only actor it senses as
    -- hostile; a fighting unit's is set back to its opponent on the next game-thread tick (options.onSensed).
    for _,name in ipairs({'sensed','sensedInfo'})do
        callbacks[name]=function(context)
            if not self.alive or not next(components) or not options.onSensed then return nil end
            local component=component_address(context) or ''
            local team,unit=components[component],owners[component]
            if not team or not unit then return nil end
            count(name,function()return team end)
            schedule(pendingSense,options.onSensed,unit,component)
            return nil
        end
    end
    for _,name in ipairs({'removed','cleared'}) do
        callbacks[name]=function(context,arg)
            if not self.alive or not next(managers) then return end
            local checked,onThread=pcall(options.inGameThread)
            if not checked or onThread~=true then return end
            local component=component_address(context)
            local unit=component and managers[component] and owners[component]
            if not unit then return end
            local removed=name=='removed' and U.unwrap(arg) or nil
            if name=='removed' and not U.valid(removed) then return end
            local ok,restored=pcall(options.guard.onHatredRemoved,options.guard,actorObjects[unit],removed)
            if ok and restored then count(name,function()return objectNames[unit]end) end
        end
    end

    local function missing_hooks()
        for _,name in ipairs(order)do if not hooks[name] then return true end end
        return false
    end
    local function install()
        if clock()<installAt then return end
        installAt=clock()+installDelay;installDelay=math.min(installDelay*2,8)
        for _,fn in ipairs({'StaticFindObject','RegisterHook','UnregisterHook'})do
            if type(_G[fn])~='function' then
                self.state='failed';self.message='缺少 '..fn
                if not installWarnings[fn] then installWarnings[fn]=true;say(self.message..'；保留限频重试') end
                return
            end
        end
        for _,name in ipairs(order)do
          if not hooks[name] then
            local path=Lock.paths[name]
            local okFind,found=pcall(StaticFindObject,path)
            if not okFind or not U.valid(found) then
                if not installWarnings[path] then installWarnings[path]=true;say('找不到函数 '..path..'；保留限频重试') end
            else
                local ok,pre,post=pcall(RegisterHook,path,callbacks[name])
                if ok and type(pre)=='number' and type(post)=='number' then
                    hooks[name]={pre=pre,post=post};say('挂钩注册ID读回 '..name..' pre='..pre..' post='..post)
                elseif not installWarnings['register:'..path] then
                    installWarnings['register:'..path]=true;say('挂钩注册失败 '..name..'：'..tostring(pre)..'；保留限频重试')
                end
            end
          end
        end
        if next(hooks) then self.state='running';self.message='战斗中，参战单位不中途退出、互相仇恨'
        else self.state='failed';self.message='找不到退出战斗判断函数' end
        if not missing_hooks() then installAt=0;installDelay=1
        elseif next(hooks) then self.message='战斗保护部分挂钩未就绪，保留限频重试' end
    end
    local function uninstall(reason,force)
        if not next(hooks) or not force and clock()<unhookAt then return end
        unhookAt=clock()+1
        local kept={}
        for name,hook in pairs(hooks)do
            local ok,value=pcall(UnregisterHook,Lock.paths[name],hook.pre,hook.post)
            if not ok or value==false then kept[name]=hook end
        end
        local parts={}
        for _,name in ipairs(order)do parts[#parts+1]=LABEL[name]..'='..self.counts[name] end
        if unhookLines<LINES or not next(kept) then
            unhookLines=unhookLines+1
            say('摘除挂钩（'..reason..'） '..table.concat(parts,' ')..' 其他AI照常='..self.passed..' 摘除失败='..tostring(next(kept)~=nil))
        end
        hooks=kept
        if not next(hooks) then self.state='idle';self.message='没有进行中的战斗';unhookAt=0;unhookLines=0 end
    end

    -- True only for a read that says no health is left; a unit whose health cannot be read counts as alive.
    local function dead(actor)
        if not options.hp then return false end
        local ok,hp=pcall(options.hp,actor)
        return ok and type(hp)=='number' and hp<=0
    end
    -- Takes a fresh corpse off the list of every living blue or red unit, through the game's own remove, and reads it
    -- back. Logged only when some list held it, with whether the fight had ended on that tick.
    local function forget(corpse,living,over)
        if not options.hatredOf or not options.hates then return true end
        local held,removed,left,unknown=0,0,0,0
        for _,member in ipairs(living)do
            local manager=options.hatredOf(member.actor)
            if U.valid(manager) and U.valid(corpse) then
                local ok,has=pcall(options.hates,manager,corpse)
                if ok and has==true then
                    held=held+1
                    pcall(function()manager:RemoveActorFromHatredList(corpse)end)
                    local checked,still=false,nil
                    if U.valid(manager) and U.valid(corpse) then checked,still=pcall(options.hates,manager,corpse) end
                    if checked and still==false then removed=removed+1 else left=left+1 end
                elseif not ok or has~=false then unknown=unknown+1 end
            else
                unknown=unknown+1
            end
        end
        if held>0 and corpseLines<LINES then
            corpseLines=corpseLines+1
            say(string.format('尸体移出仇恨表 尸体=%s 表里有它的单位=%d 移出=%d 读回仍在=%d 累计拒绝=%d%s',
                options.label and options.label(corpse) or tostring(U.key(corpse)),held,removed,left,self.refused,over and ' 交战已结束' or ''))
        end
        return left==0 and unknown==0
    end
    -- Support tick: index the fighting units and their components; install while a fight runs.
    -- Corpses come off the lists with or without a fight running: the death of a side's last unit ends the fight on
    -- that same tick, and that corpse stayed on the winners' lists, so they never left combat (the game ends combat
    -- after an action only on an empty list) and went on casting, at a spectating player too for the moves that aim
    -- at the player's position.
    function self:tick()
        if not self.alive then return end
        local now=clock()
        local ai,hatred,units,known,own,bodies,horses={},{},{},{},{},{},{}
        local fresh,living,present,objects,names,boundNames={},{},{},{},{},{}
        local fighting=options.fighting()
        local members=options.members() or {}
        if options.guard then
            local ok,err=pcall(options.guard.sync,options.guard,members,fighting)
            if not ok and not installWarnings.guard then installWarnings.guard=true;say('战斗保持检查中断 '..tostring(err)) end
        end
        for _,member in ipairs(members)do
            -- Stands keep their native AI/hatred answers. A summon held in reserve is not in the fight yet;
            -- a unit out of reach by its own design
            -- (member.untargetable, boss_stages.lua) still hates but keeps the game's answer as a target.
            if (member.team=='blue' or member.team=='red') and not member.reserve and not member.stand then
                local key=U.key(member.actor)
                if key then
                    present[key]=true;objects[key]=member.actor;names[key]=identity(member.actor)
                    refreshIdentity(key,member.actor)
                end
                if key and dead(member.actor) then
                    if fighting then bodies[key]=member.team end
                    if forgotten[key]~=true and (not forgotten[key] or now>=forgotten[key]) then fresh[#fresh+1]=member end
                elseif key then
                    forgotten[key]=nil
                    living[#living+1]=member
                    if fighting then
                        local c=component_cache(key,member.actor,now)
                        known[key]=c
                        if not member.untargetable then units[key]=member.team end
                        if c.ai then ai[c.ai]=member.team;own[c.ai]=key;boundNames[c.ai]=c.aiName end
                        if c.hatred then hatred[c.hatred]=member.team;own[c.hatred]=key;boundNames[c.hatred]=c.hatredName end
                    end
                end
            end
        end
        if fighting then
            for _,vehicle in ipairs(options.vehicles and options.vehicles(members) or {})do
                local key=U.key(vehicle.actor)
                if key then
                    objects[key]=vehicle.actor;names[key]=identity(vehicle.actor);refreshIdentity(key,vehicle.actor)
                    local c=component_cache(key,vehicle.actor,now)
                    known[key]=c
                    horses[key]=true
                    if c.ai then ai[c.ai]=vehicle.team;own[c.ai]=key;boundNames[c.ai]=c.aiName end
                    if c.hatred then hatred[c.hatred]=vehicle.team;own[c.hatred]=key;boundNames[c.hatred]=c.hatredName end
                end
            end
        end
        components,managers,teams,cache,owners,corpses,mounts,actorObjects=ai,hatred,units,known,own,bodies,horses,objects
        objectNames,componentNames=names,boundNames
        -- Departed actors must not retain corpse completion or send-back throttles at a reused address.
        for key in pairs(forgotten)do if not present[key] then forgotten[key]=nil end end
        for key in pairs(dropped)do if not known[key] then dropped[key]=nil end end
        for key in pairs(pendingSense)do if not known[key] then pendingSense[key]=nil end end
        for key in pairs(pendingDrop)do if not known[key] then pendingDrop[key]=nil end end
        for _,member in ipairs(fresh)do
            local confirmed=forget(member.actor,living,not fighting)
            local key=U.key(member.actor)
            if key then
                forgotten[key]=confirmed and true or now+FORGET_SECONDS
                identities[key]=identity(member.actor)
            end
        end
        for key in pairs(identities)do if not forgotten[key] and not dropped[key] then identities[key]=nil end end
        if next(teams) then
            quietSince=nil
            if missing_hooks() then install() end
        elseif next(hooks) then
            quietSince=quietSince or now
            if now-quietSince>=UNHOOK_SECONDS then uninstall('战斗已结束') end
        end
        summaryAt=summaryAt or now
        if now-summaryAt>=SUMMARY_SECONDS then
            if next(hooks) then
                local parts={}
                for _,name in ipairs(order)do parts[#parts+1]=LABEL[name]..'='..self.window[name];self.window[name]=0 end
                if options.guard then parts[#parts+1]='状态与仇恨持续保留累计='..tostring(options.guard.retained) end
                say(string.format('近 %.0f 秒：%s',now-summaryAt,table.concat(parts,' ')))
            end
            summaryAt=now
        end
    end
    function self:status()return {state=self.state,held=self.held,refused=self.refused,message=self.message,counts=self.counts}end
    function self:silence(reason)self.alive=false;uninstall(reason or 'Mod卸载',true) end
    return self
end
return Lock
