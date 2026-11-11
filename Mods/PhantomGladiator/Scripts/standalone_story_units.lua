-- These story combat classes look up their partner by class. A direct arena summon skips
-- those lookups for its own instance, including the death handlers that update the partner.
local U=require('ue_observe')
local Retry=require('lookup_retry')
local Standalone={}
local LOOKUP='/Script/Engine.GameplayStatics:GetActorOfClass'
local ABILITY_UTILS='/Script/SGameUtils.Default__AbilityUtils'
local AI_LIBRARY='/Script/SGameAI.Default__SGameAIFunctionLibrary'
local HATRED_BLOCK='AI.Hatred.CanNotBeHatred'
local ASSIGNED_ACTOR='AI.BlackboardKey.Object.AssignActor1'
local MOBS='/PBZCombatAsset/ActorData/Mobs/'
local function generated(package)
    return package..'.'..package:match('[^/]+$')..'_C'
end
local GUI_CHAI=generated(MOBS..'060_GuiChai_Yellow/BP_Monster_GuiChai_Yellow_MoDao_LengTu')
local PARTNERS={
    [generated(MOBS..'079_XuKong/BP_Monster_XuKong')]={
        teamBossName='虚空', paths={generated(MOBS..'078_MengHua/BP_Monster_MengHua')}},
    [generated(MOBS..'071_XianZhe/BP_Monster_XianZhe')]={
        teamBossName='弦者', paths={generated(MOBS..'065_ChiLian_P2/BP_Monster_ChiLian_P2')}},
    -- These six LengTu helpers use DelayUntilNextTick before the partner lookup.
    [generated(MOBS..'044_PengMeng/BP_Monster_PengMeng_Axe_NPC')]={
        nextTick=true, paths={generated(MOBS..'043_Scavenger/BP_Monster_Scavenger_LengTu')}},
    [generated(MOBS..'034_EMei/BP_Monster_EMei_Sword_NPC')]={nextTick=true, paths={GUI_CHAI}},
    [generated(MOBS..'035_HuaShan/BP_Monster_HuaShan_Blue_NPC')]={nextTick=true, paths={GUI_CHAI}},
    [generated(MOBS..'FengXueDaoKe/BP_Monster_FengXueDaoKe_NPC')]={
        nextTick=true, paths={
            generated(MOBS..'YuDing_00/BP_Monster_FemaleVessel_YuDing_LengTu'),
            generated(MOBS..'YuBi/BP_Monster_YuBi_LengTu')}},
    [generated('/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_LionDancer_P2_NPC')]={
        nextTick=true, paths={generated(MOBS..'FemaleDoll/BP_Monster_FemaleDoll_Golden_LengTu')}},
    [generated(MOBS..'047_LeiDang/BP_Monster_LeiDang_NPC')]={
        nextTick=true, paths={generated(MOBS..'077_LengTu/BP_Monster_LengTu')}},
}
local SHORT={}
for path in pairs(PARTNERS)do SHORT[path:match('%.([^%.]+)$')]=true end

local function fullName(object)
    if not U.valid(object) then return nil end
    local ok,name=pcall(function()return object:GetFullName()end)
    return ok and type(name)=='string' and name or nil
end

local function call(object,method,...)
    if not U.valid(object) then return false end
    local ok,value=pcall(function(...)return object[method](object,...)end,...)
    return ok,ok and U.unwrap(value) or nil
end

local function tag_name(value)
    local name=U.struct(value,'TagName')
    if type(name)=='string' then return name end
    local ok,text=pcall(function()return name:ToString()end)
    return ok and type(text)=='string' and text or nil
end

function Standalone.new(options)
    local find=options.staticFind or StaticFindObject
    local register=options.registerHook or RegisterHook
    local createInvalid=options.createInvalidObject or CreateInvalidObject
    local inGameThread=options.inGameThread or IsInGameThread
    local fname=options.fname or FName
    local owned={}
    local alive,installed=true,false
    local nullActor
    local self={}
    local function say(message)options.log('[StoryUnit] '..message)end
    local retry=Retry.new({log=say})

    local function entryFor(actor)
        local key=U.key(actor)
        local entry=key and owned[key]
        if entry and fullName(actor)==entry.name then return entry,key end
    end

    local function lookup(_,context,actorClass)
        if not alive or not next(owned) or (type(inGameThread)=='function' and not inGameThread()) then return end
        local actor=U.unwrap(context)
        local entry=entryFor(actor)
        if not entry then return end
        local name=fullName(U.unwrap(actorClass))
        local path=name and name:match('^%S+ (/.+)$')
        local partnerKey=path and path:lower()
        if not partnerKey or not entry.partners[partnerKey] then return end
        entry.lookups=entry.lookups+1
        local delayedReadback=entry.delayedReadback
        if delayedReadback and not delayedReadback[partnerKey] then
            delayedReadback[partnerKey]=true
            pcall(say,'延迟剧情查找回调读回 '..entry.name..' 搭档='..path..' 回传空Actor')
        end
        return nullActor
    end

    function self:matches(name)
        return SHORT[name:match('^(%S+) ')]==true
    end

    function self:prepare(actor)
        local config=alive and PARTNERS[U.npcPath(actor)]
        if not config then return nil,'剧情战斗类未读回' end
        local paths=config.paths
        local key,name=U.key(actor),fullName(actor)
        if not key or not name then return nil,'剧情单位对象未读回' end
        local statics=options.statics()
        if not U.valid(statics) then return nil,'剧情拆分的原生查找接口不可读' end
        local targets,partners={},{}
        for _,path in ipairs(paths)do
            local found,cls=pcall(find,path)
            if not found or not U.valid(cls) then
                say('独立初始化未确认，剧情搭档类不可读 '..path)
                return nil,'无法验证剧情单位的独立生成'
            end
            targets[#targets+1]=cls
            partners[path:lower()]=true
        end
        if not installed then
            local created,empty=pcall(createInvalid)
            if not created or empty==nil or U.valid(empty) then
                say('空 Actor 回传对象未读回')
                return nil,'剧情拆分需要 UE4SS 的空 Actor 回传接口'
            end
            nullActor=empty
            local registered,pre,post=pcall(register,LOOKUP,lookup)
            installed=registered and type(pre)=='number' and type(post)=='number'
            say('查找挂钩注册读回='..tostring(installed)..(installed and ' ID='..pre..'/'..post or ''))
            if not installed then return nil,'剧情拆分挂钩注册未确认' end
        end
        local entry={name=name,partners=partners,lookups=0,nextTick=config.nextTick,
            teamBossName=config.teamBossName}
        owned[key]=entry
        -- Verify each return slot for the deferred actor before its BeginPlay runs.
        for i,cls in ipairs(targets)do
            local before=entry.lookups
            local called,result=pcall(function()return statics:GetActorOfClass(actor,cls)end)
            local returnedActor=called and U.valid(U.unwrap(result))
            local confirmed=called and not returnedActor and entry.lookups==before+1
            say('拆分探测 '..name..' 搭档='..paths[i]..' 调用='..tostring(called)..' 返回演员='..tostring(returnedActor)
                ..' 回调次数='..(entry.lookups-before)..' 确认='..tostring(confirmed))
            if not confirmed then
                owned[key]=nil
                return nil,'剧情拆分读回未确认'
            end
        end
        entry.lookups=0
        return entry
    end

    function self:verify(entry)
        if entry.nextTick and entry.lookups==0 then
            -- prepare proved the hook's return slot for each partner. BeginPlay will
            -- use that same guard on the next tick, after FinishSpawn has returned.
            entry.delayedReadback={}
            say('独立生成预检确认 '..entry.name..' 原生剧情查找待读回')
            return true
        end
        say('独立生成读回 '..entry.name..' 剧情查找被拦截次数='..entry.lookups)
        return entry.lookups>0
    end

    function self:teamBossName(actor)
        if not next(owned) then return nil end
        local entry=entryFor(actor)
        return entry and entry.teamBossName
    end

    function self:isTeamActor(actor)
        return self:teamBossName(actor)~=nil
    end

    local function actorLive(actor)
        return U.valid(actor) and (not options.live or options.live(actor)==true)
    end

    local function actorGone(actor,entry)
        if entryFor(actor)~=entry then return true end
        if not options.isDestroying then return false end
        local ok,destroying=pcall(options.isDestroying,actor)
        return ok and destroying==true
    end

    local function teamState(actor,blockTag)
        if not actorLive(actor) then return nil end
        local faction=U.field(actor,'Faction Component')
        local asc=U.field(actor,'AbilitySystemComponent')
        local gotFaction,currentFaction=call(faction,'GetCurrnetFaction')
        local gotCount,currentCount=call(asc,'GetGameplayTagCount',blockTag)
        return gotFaction and tag_name(currentFaction) or nil,
            gotCount and type(currentCount)=='number' and currentCount or nil
    end

    local function applyTeamState(actor,blockTag,factionName,tagCount)
        local beforeFaction,beforeCount=teamState(actor,blockTag)
        if not beforeFaction or beforeCount==nil then return false,beforeFaction,beforeCount end
        local changedFaction=beforeFaction~=factionName
        local changedTag=beforeCount~=tagCount
        local lib=changedTag and retry:find(ABILITY_UTILS,find) or nil
        if changedTag and not U.valid(lib) then return false,beforeFaction,beforeCount end
        local wrote=true
        if changedFaction then
            wrote=call(U.field(actor,'Faction Component'),'SetFaction',{TagName=fname(factionName)})
        end
        if wrote and changedTag and actorLive(actor) then
            wrote=call(lib,'SetLooseGameplayTagCount',actor,blockTag,tagCount)
        end
        local afterFaction,afterCount=teamState(actor,blockTag)
        return wrote and afterFaction==factionName and afterCount==tagCount,afterFaction,afterCount
    end

    function self:prepareTeamActor(actor)
        local entry,key=entryFor(actor)
        if not entry or not entry.teamBossName then return false end
        if type(options.remember)~='function' then return false end
        local made,tagName=pcall(fname,HATRED_BLOCK)
        local blockTag={TagName=made and tagName or nil}
        if tag_name(blockTag)~=HATRED_BLOCK then
            say('剧情援军仇恨标签名称未读回 '..entry.name..' 构造调用='..tostring(made))
            return false
        end
        local originalFaction,originalCount=teamState(actor,blockTag)
        if not originalFaction or (originalCount~=0 and originalCount~=1) then
            say('剧情援军阵营或初始仇恨标签不可确认 '..entry.name
                ..' 阵营='..tostring(originalFaction)..' 标签数='..tostring(originalCount))
            return false
        end
        local wantedFaction=originalFaction=='Faction.Player' and 'Faction.Enemy' or originalFaction
        if originalFaction==wantedFaction and originalCount==0 then
            entry.teamPrepared=true
            return true
        end
        options.remember('story-team:'..key..':'..entry.name,function()
            if actorGone(actor,entry) then return true,'剧情援军已离场' end
            local restored,afterFaction,afterCount=applyTeamState(actor,blockTag,originalFaction,originalCount)
            if restored then entry.teamPrepared=false end
            return restored,'阵营读回='..tostring(afterFaction)..' 初始仇恨标签读回='..tostring(afterCount)
        end)
        local confirmed,afterFaction,afterCount=applyTeamState(actor,blockTag,wantedFaction,0)
        entry.teamPrepared=confirmed
        say('剧情援军参战准备 '..entry.name..' 阵营='..originalFaction..' -> '..tostring(afterFaction)
            ..' 初始仇恨阻止标签='..originalCount..' -> '..tostring(afterCount)..' 确认='..tostring(confirmed))
        if not confirmed then
            local restored=applyTeamState(actor,blockTag,originalFaction,originalCount)
            say('剧情援军参战准备失败，恢复读回='..tostring(restored))
        end
        return confirmed
    end

    function self:assignOpponent(actor,opponent)
        local entry,key=entryFor(actor)
        if not entry or not entry.teamBossName then return true end
        if not entry.teamPrepared then return opponent==nil end
        if not actorLive(actor) or (opponent~=nil and not actorLive(opponent)) then return false end
        if type(options.boardOf)~='function' then return false end
        local board=options.boardOf(actor)
        local boardKey=U.key(board)
        if not boardKey then return false end
        local library=retry:find(AI_LIBRARY,find)
        if not U.valid(library) then return false end
        local tag={TagName=fname(ASSIGNED_ACTOR)}
        local ok,original=call(library,'GetValueAsObjectByTag',board,tag)
        if not ok then return false end
        local expected=U.key(opponent)
        if opponent~=nil and not expected then return false end
        if U.key(original)==expected then return true end

        local function apply(target)
            local targetKey=U.key(target)
            if not U.valid(board) or (target~=nil and not targetKey) then return false end
            local wrote=call(library,'SetValueAsObjectByTag',board,tag,targetKey and target or nullActor)
            local read,actual=call(library,'GetValueAsObjectByTag',board,tag)
            return wrote and read and U.key(actual)==targetKey
        end

        local originalName=fullName(original)
        options.remember('story-aim:'..key..':'..entry.name..':'..boardKey,function()
            if actorGone(actor,entry) then return true,'剧情援军已离场' end
            if not actorLive(actor) then return false,'剧情援军状态不可读' end
            if not U.valid(board) then return true,'剧情援军原黑板已失效' end
            local activeBoard=U.key(options.boardOf(actor))
            if not activeBoard then return false,'剧情援军当前黑板状态不可读' end
            if activeBoard~=boardKey then return true,'剧情援军原黑板已不在用' end
            local target=originalName and fullName(original)==originalName and original or nil
            local restored=apply(target)
            return restored,'原指派对象恢复读回='..tostring(restored)
        end)
        local assigned=apply(opponent)
        say('剧情援军指派目标 '..entry.name..' -> '..(fullName(opponent) or '空')
            ..' 黑板读回='..tostring(assigned))
        return assigned
    end

    function self:prune(units)
        if not next(owned) then return end
        local retained={}
        for _,unit in ipairs(units)do
            if PARTNERS[unit.class_path] then
                local key=U.key(unit.actor)
                local entry=key and owned[key]
                if entry and fullName(unit.actor)==entry.name then retained[key]=entry end
            end
        end
        owned=retained
    end

    function self:silence()
        alive=false
        owned={}
    end
    return self
end

return Standalone
