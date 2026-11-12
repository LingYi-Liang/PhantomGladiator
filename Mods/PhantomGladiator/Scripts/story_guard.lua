-- 雷当's story fight in 戏梦山庄 (flow graphs QuestFlowGraph/QingSheDao/BPF_LeiDangOrYuer_*).
--
-- Any phase-one 雷当 (/047_LeiDang/) that runs its phase-end move GA_LeiDang_CA tells the player that 雷当 is killed: 3.55 s
-- into the move a GAA_DurationTags gives it CharacterState.AbilityState.LeiDang.Dead, and on that tag the move sends
-- GameplayEvent.MobGroup.Clear with InstigatorTags [qsd.击杀.雷当] to GetPlayerCharacter. BP_Player_Base adds those tags to the
-- story (EventPipelineManager.AddTags). Which 雷当 it is and which map it is in do not matter. With that tag,
-- BPF_LeiDangOrYuer_Dead plays Seq123-4 and lets phase two out the first time the player comes near, before phase one has
-- been fought; the intro then lets phase one out too.
-- So while one of the mod's units is a phase-one 雷当, that event, sent while one of them has the LeiDang.Dead tag, goes to
-- that unit instead of the player. Only BP_Player_Base listens for it (the native tag object is only referenced where it is
-- defined). A hook on the player's handler shows whether it still got through.
--
-- 雷煌 and 雷鸣 (/Game/RenewalContent/Actors/Mobs/Normal/) run the same AI config and move.
-- The mod no longer summons any of them while the story lacks the tag (story_writes.lua), and the BP_Monster_LeiDang_NPC
-- 冷荼's fifth round calls in is taken out as it comes (main.lua removeHelper); this covers one that was not.
--
-- Once armed (the app's save-repair button, save_repair.lua), a save that already has the tag while phase one's spawner
-- (LeiDang_Seq123-3) would still let it out gets what the game does when Seq123-4 starts (flow node SetSpawnerDespawn):
-- the spawner is told not to spawn, saved and emptied. The tag is read from that spawner's own AIScript_AddTagOnDead, so
-- no Chinese name has to be built here.
local U=require('ue_observe')
local Guard={}
local SEND='/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:SendGameplayEventToActor'
local HEARD='/Game/PBZContent/Blueprint/Character/Player/BP_Player_Base.BP_Player_Base_C:EventReceived_BA05D11E4E68EAF4570C7CB73B67D54D'
local CLEAR='GameplayEvent.MobGroup.Clear'
local DEAD='CharacterState.AbilityState.LeiDang.Dead'
local PHASE_ONE={'/047_LeiDang/','/Mobs/Normal/BP_Monster_LeiHuang.','/Mobs/Normal/BP_Monster_LeiMing.'}
local SPAWNER_ID='LeiDang_Seq123-3'
local TAG_TEXT='qsd.击杀.雷当'
local FIGHT_OVER='qsd.Boss战.结束'   -- BPF_LeiDangOrYuer_Dead's reaction to the tag is blocked once this is there
local TAG_SCRIPT='AIScript_AddTagOnDead_C'
local REPAIR_EVERY=3      -- seconds between looks at phase one's spawner
local HEARD_WINDOW=2      -- seconds after a redirect in which the player's handler running means it got through
local LINES=60

local function text(name)
    if type(name)=='string' then return name end
    local ok,value=pcall(function()return name:ToString()end)
    return ok and type(value)=='string' and value or nil
end
local function className(object)
    if not U.valid(object) then return '?' end
    return U.className(object) or '?'
end

function Guard.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local fname=options.fname or function(value)return FName and FName(value) end
    local register=options.registerHook or function(...)return RegisterHook(...)end
    local unregister=options.unregisterHook or function(...)return UnregisterHook(...)end
    local find=options.find or function(path)return StaticFindObject(path)end
    local self={redirected=0,leaked=0,passed=0,repaired=0,armed=options.repair==true}
    local hooks,pending,lines,repairAt,lastState,waiting=nil,nil,0,0,nil,false
    local function say(message)
        if lines<LINES then lines=lines+1;log('[StoryGuard] '..message) end
    end
    local function label(actor)return options.label and options.label(actor) or className(actor) end
    local function isPhaseOne(path)
        if type(path)~='string' then return false end
        for _,part in ipairs(PHASE_ONE)do if path:find(part,1,true) then return true end end
        return false
    end
    local function phaseOne()
        local list={}
        for _,member in ipairs(options.members and options.members() or {})do
            if isPhaseOne(member.class_path) and U.valid(member.actor) then list[#list+1]=member.actor end
        end
        return list
    end
    local function tagsOf(payload)
        local container=U.struct(U.unwrap(payload),'InstigatorTags')
        local names={}
        for _,tag in ipairs(U.array(U.struct(container,'GameplayTags')) or {})do
            names[#names+1]=text(U.struct(tag,'TagName')) or '?'
        end
        return table.concat(names,',')
    end

    -- Before the call: the event, its target and its tags as the game passes them in.
    local function onSend(_,actor,eventTag,payload)
        if not hooks then return nil end
        if text(U.struct(U.unwrap(eventTag),'TagName'))~=CLEAR then return nil end
        local unit
        for _,candidate in ipairs(phaseOne())do
            local count=options.tagCount and options.tagCount(candidate,DEAD)
            if type(count)=='number' and count>0 then unit=candidate;break end
        end
        local tags=tagsOf(payload)
        if not unit then
            self.passed=self.passed+1
            say('放行 '..CLEAR..' InstigatorTags=['..tags..']：召唤的一阶段雷当都不在转阶段')
            return nil
        end
        local before=U.unwrap(actor)
        local okSet=pcall(function()actor:set(unit)end)
        local after=U.unwrap(actor)
        local how,done='目标改成这只雷当',okSet and U.key(after)~=nil and U.key(after)==U.key(unit)
        if not done then
            local okTag=pcall(function()eventTag:set({TagName=fname('None')})end)
            how='事件标签改成 None'
            done=okTag and text(U.struct(U.unwrap(eventTag),'TagName'))=='None'
        end
        self.redirected=self.redirected+1
        pending={at=clock(),unit=label(unit)}
        say(string.format('召唤的雷当 %s 放完转阶段技能，发给 %s 的 %s InstigatorTags=[%s]：%s 写入=%s 读回=%s 累计=%d',
            label(unit),className(before),CLEAR,tags,how,tostring(okSet),done and '已改' or '没改成',self.redirected))
        return nil
    end
    -- After BP_Player_Base handled one: right after a redirect it means the story got the tags anyway.
    local function onHeard(_,payload)
        if not hooks then return nil end
        local tags=tagsOf(payload)
        if pending and clock()-pending.at<HEARD_WINDOW then
            self.leaked=self.leaked+1
            say('拦截没生效：玩家仍收到 '..CLEAR..' InstigatorTags=['..tags..']，来自 '..pending.unit..'，剧情可能已记下 累计='..self.leaked)
            pending=nil
        else
            say('玩家收到 '..CLEAR..' InstigatorTags=['..tags..']（不是召唤的雷当发的）')
        end
        return nil
    end

    local function hook()
        hooks={}
        for _,spec in ipairs({{SEND,onSend,'发事件'},{HEARD,onHeard,'玩家收事件'}})do
            local okFind,found=pcall(find,spec[1])
            if okFind and U.valid(found) then
                local ok,pre,post=pcall(register,spec[1],spec[2],function()end)
                if ok and type(pre)=='number' and type(post)=='number' then
                    hooks[#hooks+1]={path=spec[1],pre=pre,post=post}
                    say('挂钩 '..spec[3]..' 注册ID读回 pre='..pre..' post='..post)
                else say('挂钩 '..spec[3]..' 注册失败：'..tostring(pre)) end
            else say('挂钩 '..spec[3]..' 找不到函数 '..spec[1]) end
        end
    end
    local function unhook(reason)
        local removed,failed=0,0
        for _,h in ipairs(hooks or {})do
            if pcall(unregister,h.path,h.pre,h.post) then removed=removed+1 else failed=failed+1 end
        end
        hooks=nil;pending=nil
        say('摘除挂钩 reason='..reason..' 摘除='..removed..' 失败='..failed)
    end

    -- The tag phase one's death script would add: [qsd.击杀.雷当] read from the spawner, else built from text.
    local function deathTag(spawner)
        local info=U.field(spawner,'SpawnInfo')
        for _,script in ipairs(U.array(U.struct(info,'ExtraScripts')) or {})do
            if U.valid(script) and className(script)==TAG_SCRIPT then
                local tags=U.array(U.struct(U.field(script,'EventTag'),'GameplayTags'))
                local name=tags and tags[1] and U.struct(tags[1],'TagName')
                if name~=nil then return name,'刷怪点脚本' end
            end
        end
        local ok,name=pcall(fname,TAG_TEXT)
        return ok and name or nil,'按名字'
    end
    local function call(object,name,...)
        local args=table.pack(...)
        local ok,value=pcall(function()return object[name](object,table.unpack(args,1,args.n))end)
        return ok,ok and U.unwrap(value) or value
    end
    local function repair()
        local sub=options.aiSubsystem and options.aiSubsystem()
        if not U.valid(sub) then return end
        local okFind,spawner=call(sub,'GetSpawner',fname(SPAWNER_ID))
        if not okFind or not U.valid(spawner) then return end
        local should=U.field(spawner,'ShouldSpawn')
        local present=U.valid((U.field(spawner,'SpawnedAI')))
        local okWould,would=call(spawner,'IsShouldToSpawn')
        if not okWould then would=nil end
        local tag,source=deathTag(spawner)
        local has
        local pipeline=options.pipeline and options.pipeline()
        if tag~=nil and U.valid(pipeline) then
            local okHas,value=call(pipeline,'HasTagWithOutSource',{TagName=tag})
            if okHas and type(value)=='boolean' then has=value end
        end
        local state=string.format('一阶段刷怪点 %s ShouldSpawn=%s 会刷出=%s 在场=%s 剧情标记[%s]（%s）=%s',SPAWNER_ID,tostring(should),
            tostring(would),tostring(present),tostring(text(tag) or '?'),source,tostring(has))
        if state~=lastState then lastState=state;say(state) end
        if has~=true or not (present or (should==true and would==true)) then waiting=false;return end
        if not self.armed then
            if not waiting then say('剧情里一阶段已算打过，它的刷怪点却还会放它出来：助手里点"修复存档"后照 Seq123-4 开始时的做法关掉') end
            waiting=true
            return
        end
        local okOff=pcall(function()spawner.ShouldSpawn=false end)
        local okSave=call(spawner,'Save')
        local okGone=call(spawner,'Despawn')
        self.repaired=self.repaired+1
        local _,wouldAfter=call(spawner,'IsShouldToSpawn')
        say(string.format('剧情里一阶段已算打过，它的刷怪点却还会放它出来：照 Seq123-4 开始时的做法关掉。写 ShouldSpawn=false=%s 保存=%s 移除=%s；读回 ShouldSpawn=%s 会刷出=%s 在场=%s 累计=%d',
            tostring(okOff),tostring(okSave),tostring(okGone),tostring((U.field(spawner,'ShouldSpawn'))),tostring(wouldAfter),
            tostring(U.valid((U.field(spawner,'SpawnedAI')))),self.repaired))
        lastState=nil
    end

    function self:tick()
        local now=clock()
        local want=#phaseOne()>0
        if want and not hooks then hook()
        elseif not want and hooks then unhook('召唤的一阶段雷当都已离场') end
        if pending and now-pending.at>=HEARD_WINDOW then
            say('确认：玩家没收到 '..pending.unit..' 的剧情事件')
            pending=nil
        end
        if now>=repairAt then
            repairAt=now+REPAIR_EVERY
            repair()
        end
    end
    -- From the save-repair button: phase one's spawner may be turned off from now on; looked at again right away.
    function self:arm()self.armed=true;repairAt=0 end
    -- For the save-repair report: true when there is nothing to do (false when there is, nil when unread) and a short
    -- line. has(text) answers whether the story holds a mark (true/false/nil).
    function self:diagnose(has)
        local killed=has and has(TAG_TEXT)
        if killed==nil then return nil,'雷当' end
        if killed==false then return true,'雷当' end
        local over=has(FIGHT_OVER)
        if over==true then return true,'雷当' end
        if self.repaired>0 then return false,'雷当：已关掉一阶段刷怪点，只打二阶段' end
        return false,'雷当：已被记成打过'..(over==nil and '（读不到这一战打完没有）' or '')..'，到戏梦山庄时关掉一阶段，只打二阶段'
    end
    function self:status()
        return {hooked=hooks~=nil,redirected=self.redirected,leaked=self.leaked,passed=self.passed,repaired=self.repaired,armed=self.armed}
    end
    return self
end
return Guard
