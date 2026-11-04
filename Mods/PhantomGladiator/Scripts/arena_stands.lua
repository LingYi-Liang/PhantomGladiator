-- Skill participants keep CharacterType.Stand across their Niagara fade. bHidden is not their active state.
-- Diagnostics observe blueprint post callbacks; they never replace a result or send a gameplay event.
local U=require('ue_observe')
local Retry=require('lookup_retry')
local Stands={}
local KNOWN={BP_Monster_Yuu_Stand_C=true,BP_Monster_TieGui_Stand_C=true,BP_Monster_ZuoShang_P2_Stand_C=true}
local ACTION='/PBZCombatAsset/Prototypes/Actions/GAA_AllOutAttack.GAA_AllOutAttack_C:'
local PASSIVE='/PBZCombatAsset/ActorData/Mobs/064_MuXiaoKui_P2/Ability/Abilities/Passive/GA_Stand_Passive.GA_Stand_Passive_C:'
Stands.paths={find=ACTION..'FindIdleSummonParticipant',idle=ACTION..'IsSummonPoolCandidateIdle',
    grow=ACTION..'TryGrowSummonParticipantPool',enable=PASSIVE..'TryEnable',disable=PASSIVE..'TryDisable',
    event=PASSIVE..'EventReceived_2F6FA8C24106A5A2D58E33B4C61E48C4'}
local ORDER={'find','idle','grow','enable','disable','event'}
local LIMIT,PER_KIND,SECONDS=240,12,5
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local ok,value=pcall(function(...)return object[method](object,...)end,...)
    if ok then return U.unwrap(value) end
end
local function name(value)
    if type(value)=='string' then return value end
    local ok,text=pcall(function()return value:ToString()end)
    return ok and type(text)=='string' and text or '?'
end
local function booleanResult(value)
    local kind=U.kind(value)
    if kind=='RemoteUnrealParam' or kind=='LocalUnrealParam' then
        local ok,result=pcall(function()return value:get()end)
        if ok then return result end
    else return value end
end
local function label(object)
    if not U.valid(object) then return '无效' end
    return name(call(object,'GetFName'))..'@'..tostring(U.key(object))
end
local function tagCount(actor,tag)
    local asc=U.field(actor,'AbilitySystemComponent')
    if not U.valid(asc) or type(FName)~='function' then return nil end
    local value=call(asc,'GetGameplayTagCount',{TagName=FName(tag)})
    return type(value)=='number' and value or nil
end
-- Leaf class name -> the known class it is or inherits, or false. The walk is done once per class.
local known={}
local function knownClass(actor)
    local cls=call(actor,'GetClass')
    if not U.valid(cls) then return false end
    local leaf=name(call(cls,'GetFName'))
    if known[leaf]==nil then
        known[leaf]=false
        for _=1,16 do
            if not U.valid(cls) then break end
            local class=name(call(cls,'GetFName'))
            if KNOWN[class] then known[leaf]=class;break end
            cls=call(cls,'GetSuperStruct')
        end
    end
    return known[leaf]
end
function Stands.isStand(actor)
    if not U.valid(actor) then return false end
    local count=tagCount(actor,'CharacterType.Stand')
    if count and count>0 then return true,'CharacterType.Stand='..count end
    -- These three classes carry AIScript_Stand even before its startup task grants the tag.
    local class=knownClass(actor)
    if class then return true,'类='..class end
    return false
end

function Stands.new(options)
    local self={alive=true}
    local clock=options.clock or os.clock
    local hooks,counts,lines,owned,parents,passives={},{},{},{},{},{}
    local total,nextAt,summaryAt=0,0,0
    local function say(text)
        if total>=LIMIT then return end
        total=total+1
        if options.log then options.log('[StandWatch] '..text) end
    end
    local function note(kind,text)
        counts[kind]=(counts[kind] or 0)+1
        lines[kind]=(lines[kind] or 0)+1
        if lines[kind]<=PER_KIND then say('只读 '..kind..' '..text) end
    end
    local retry=Retry.new({clock=clock,log=say})
    local function snapshot(actor,passive)
        if not U.valid(actor) then return '无效' end
        local ai=options.aiOf and options.aiOf(actor)
        local state=U.field(ai,'CurrentStateTag')
        passive=passive or passives[U.key(actor)]
        local fade=U.field(passive,'NormalFade')
        local hp=U.field(U.field(actor,'AttributeSetBase'),'Health')
        return string.format('%s Dead=%s Action=%s StandEnable=%s bHidden=%s AI=%s bAIStarted=%s HP=%s Enabled=%s EnableCount=%s OwnerBreak=%s ActivateAI=%s NormalFadeValid=%s NormalFade=%s',
            label(actor),tostring(tagCount(actor,'CharacterState.Dead')),tostring(tagCount(actor,'Ability.Action')),
            tostring(tagCount(actor,'CharacterType.Stand.Enable')),tostring((U.field(actor,'bHidden'))),name(U.struct(state,'TagName')),
            tostring((U.field(ai,'bAIStarted'))),tostring((U.struct(hp,'CurrentValue'))),tostring((U.field(passive,'Enabled'))),
            tostring((U.field(passive,'EnableCount'))),tostring((U.field(passive,'IsOwnerBreak'))),tostring((U.field(passive,'ActivateAI'))),
            tostring(U.valid(fade)),tostring(call(fade,'IsActive')))
    end
    local function caster(context)
        local action=U.unwrap(context)
        local actor=call(action,'GetAvatarActor')
        return action,actor,parents[U.key(actor) or '']
    end
    local callbacks={}
    callbacks.find=function(context,original,selected)
        if not self.alive then return end
        local action,actor,children=caster(context)
        if not children then return end
        local result=U.valid(U.unwrap(selected)) and 'selected' or 'empty'
        counts[result]=(counts[result] or 0)+1
        counts.find=(counts.find or 0)+1
        local parts={}
        for i,child in ipairs(children)do if i<=6 then parts[#parts+1]=snapshot(child) end end
        note('find:'..result,'施法者='..label(actor)..' 动作='..label(action)..' UseIdleSummonPool='..tostring((U.field(action,'UseIdleSummonPool')))
            ..' 原参数='..label(U.unwrap(original))..' 选中='..label(U.unwrap(selected))..' 候选=['..table.concat(parts,'；')..']')
    end
    callbacks.idle=function(context,candidate,reference,result)
        if not self.alive then return end
        local _,_,children=caster(context)
        if children then note('idle','参考='..label(U.unwrap(reference))..' 结果='..tostring(booleanResult(result))..' 候选='..snapshot(U.unwrap(candidate))) end
    end
    callbacks.grow=function(context,summoner,reference,result)
        if not self.alive then return end
        local _,_,children=caster(context)
        if not children then return end
        summoner=U.unwrap(summoner)
        local rows=U.array(U.field(summoner,'SpawnedSummonInstances'))
        note('grow','MaxSummonCount='..tostring((U.field(summoner,'MaxSummonCount')))..' 实例记录数='..tostring(rows and #rows)
            ..' 参考='..label(U.unwrap(reference))..' 结果='..label(U.unwrap(result)))
    end
    for _,kind in ipairs({'enable','disable','event'})do
        callbacks[kind]=function(context,payload)
            if not self.alive then return end
            local passive=U.unwrap(context)
            local actor=call(passive,'GetAvatarActorFromActorInfo')
            local key=U.key(actor)
            if not key or not owned[key] then return end
            passives[key]=passive
            local event=kind=='event' and name(U.struct(U.struct(U.unwrap(payload),'EventTag'),'TagName')) or kind
            note(kind,'事件='..event..' 读回='..snapshot(actor,passive))
        end
    end
    local function uninstall()
        for kind,hook in pairs(hooks)do
            local ok=pcall(UnregisterHook,Stands.paths[kind],hook[1],hook[2])
            say('摘除只读钩子 '..kind..' 调用读回='..tostring(ok))
            if ok then hooks[kind]=nil end
        end
    end
    local function needed(kind)return next(owned)~=nil and not hooks[kind]end
    local function register(kind)
        if not needed(kind) or not retry:ready(Stands.paths[kind]) then return end
        local found,fn=pcall(StaticFindObject,Stands.paths[kind])
        retry:result(Stands.paths[kind],found and U.valid(fn))
        if found and U.valid(fn) then
            local ok,pre,post=pcall(RegisterHook,Stands.paths[kind],callbacks[kind],function()end)
            if ok and type(pre)=='number' and type(post)=='number' then
                hooks[kind]={pre,post};say('注册只读钩子 '..kind..' ID读回='..pre..'/'..post)
            else retry:result(Stands.paths[kind]..':register',false,tostring(pre)) end
        end
    end
    function self:tick()
        if not self.alive then return end
        local previous=owned
        owned,parents={},{}
        for _,member in ipairs(options.members() or {})do
            if member.stand and (member.team=='blue' or member.team=='red') then
                local key,parent=U.key(member.actor),U.key(member.summoner)
                if key then
                    owned[key]=member.actor
                    if parent then local list=parents[parent] or {};parents[parent]=list;list[#list+1]=member.actor end
                end
            end
        end
        local added=false
        for key in pairs(owned)do
            if not U.valid(previous[key]) then added=true;passives[key]=nil end
        end
        for key in pairs(passives)do if not owned[key] then passives[key]=nil end end
        if added then retry:reset();nextAt=0 end
        if not next(owned) then uninstall();passives={};return end
        local now=clock()
        if type(StaticFindObject)=='function' and type(RegisterHook)=='function' and type(UnregisterHook)=='function' then
            for _,kind in ipairs(ORDER)do register(kind) end
        end
        local needPassive=false
        for key in pairs(owned)do if not U.valid(passives[key]) then needPassive=true end end
        if needPassive and retry:ready('GA_Stand_Passive_C') then
            local ok,abilities=pcall(function()return FindAllOf('GA_Stand_Passive_C')end)
            local found=0
            for _,ability in ipairs(ok and U.array(abilities) or {})do
                local actor=call(ability,'GetAvatarActorFromActorInfo')
                local key=U.key(actor)
                if key and owned[key] then passives[key]=ability;found=found+1 end
            end
            retry:result('GA_Stand_Passive_C',found>0,'归属匹配='..found)
        end
        if now<nextAt then return end
        nextAt=now+SECONDS
        if now>=summaryAt then
            summaryAt=now+15
            local parts={}
            for _,kind in ipairs(ORDER)do parts[#parts+1]=kind..'='..(counts[kind] or 0) end
            parts[#parts+1]='selected='..(counts.selected or 0);parts[#parts+1]='empty='..(counts.empty or 0)
            say('累计回调读回 '..table.concat(parts,' ')..'；每类详单上限='..PER_KIND..' 总日志上限='..LIMIT)
            for key,actor in pairs(owned)do note('sample:'..key,'状态读回='..snapshot(actor)) end
        end
    end
    function self:silence()self.alive=false;uninstall()end
    return self
end
return Stands
