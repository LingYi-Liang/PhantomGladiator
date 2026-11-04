-- 连携技: 铁鬼 and 玉妖 attack together through GA_TieGui_AllOutAttack / GA_Yuu_AllOutAttack (class GA_AutoComboGroup). Their mob
-- group decides it, and summoned units have none. A real group cannot be given to them: a valid MobGroup makes the AI call
-- iface(group.MobDomain).GetActorsInMobDomain and IsActorInMobDomain, and a group that is not owned by a BP_MobDomain ends in
-- a fatal "Failed to find function" (AIScript_UpdateAwareness, Condition_TargetInMobDomain). So MobGroup and Spawner stay empty
-- and the two places that ask for the group are done from here, while two such units of one team fight:
-- * K2_CanActivateAbility wants GetMobGroup().GetInCombatMembers() above 1: answered true while the partner lives.
-- * The picked trees start by waiting on the partner in the blackboard key Vehicle (BTTask_WaitGameplayTagRemoveFromActor): with
--   the key empty that task never finishes and has no timeout, so the unit circles for good. Each gets the other there, read
--   back; a dead partner is taken out again, since AIScript_TargetSelector copies the target from whoever is in that key.
--   That wait is also given a timeout on these trees, or a partner dying with the awaited tag would hold the survivor as well.
-- * The picked tree's BTTask_AssignBehaviorTreesToGroupMember finds nobody, and ends with FinishExecute(AlwaysSuccess). Its
--   copies on this pair's trees get AlwaysSuccess, so the caster goes on with its part. Right after, the partner gets what the
--   task would have given it: the blackboard's assign keys and the event CustomState carrying its tree. Other trees that use the
--   same two task classes are left alone: they keep stopping or going on as the game set them.
local U=require('ue_observe')
local Combos={}
local HEADER='BossCombosV1'
local ASSIGN_CLASS='BTTask_AssignBehaviorTreesToGroupMember_C'
local WAIT_CLASS='BTTask_WaitGameplayTagRemoveFromActor_C'
local WAIT_SECONDS=8
local EVENT='GameplayEvent.AI.EventTransition.CustomState'
local NOT_ASSIGNED='AI.Assignment.CanNotBeAssigned'
local PARTNER_KEY='AI.BlackboardKey.Object.Vehicle'
local AI_LIB='/Script/SGameAI.Default__SGameAIFunctionLibrary'
local BB_LIB='/Script/AIModule.Default__AIBlueprintHelperLibrary'
local ABILITY_LIB='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
Combos.PAIRS={{name='铁鬼+玉妖',classes={'BP_Monster_TieGui_C','BP_Monster_Yuu_C'}}}
Combos.paths={
    gateTieGui='/PBZCombatAsset/ActorData/Mobs/LuanShi/Ability/TieGui/Abilities/GA_TieGui_AllOutAttack.GA_TieGui_AllOutAttack_C:K2_CanActivateAbility',
    gateYuu='/PBZCombatAsset/ActorData/Mobs/046_Yuu/Abilities/GA_Yuu_AllOutAttack.GA_Yuu_AllOutAttack_C:K2_CanActivateAbility',
    assign='/SGameAI/BehaviorTree/Task/BTTask_AssignBehaviorTreesToGroupMember.BTTask_AssignBehaviorTreesToGroupMember_C:ExecuteInternal',
}
-- What each caster's tree assigns (AssignToTransformAndBehaviorTree, read offline); all use this offset from the caster.
local YUU='/PBZCombatAsset/ActorData/Mobs/046_Yuu/BehaviorTree/AllOutAttack/'
local TIEGUI='/PBZCombatAsset/ActorData/Mobs/LuanShi/BehaviorTree/TieGui/'
Combos.TREES={
    BT_Yuu_AllOutAttack_01=YUU..'01/BT_Yuu_AllOutAttack_01_TieGui.BT_Yuu_AllOutAttack_01_TieGui',
    BT_Yuu_AllOutAttack_02=YUU..'BT_Yuu_AllOutAttack_02_TieGui.BT_Yuu_AllOutAttack_02_TieGui',
    BT_Yuu_AllOutAttack_03=YUU..'BT_Yuu_AllOutAttack_03_TieGui.BT_Yuu_AllOutAttack_03_TieGui',
    BT_TieGui_AllOutAttack_01=TIEGUI..'BT_TieGui_AllOutAttack_01_Yuu.BT_TieGui_AllOutAttack_01_Yuu',
    BT_TieGui_AllOutAttack_02=TIEGUI..'BT_TieGui_AllOutAttack_02_Yuu.BT_TieGui_AllOutAttack_02_Yuu',
}
-- Every tree of the pair that opens by waiting on the partner (Timeout -1).
Combos.WAITING={BT_TieGui_Troop_01=true,BT_TieGui_Troop_02=true}
for name in pairs(Combos.TREES)do Combos.WAITING[name]=true end
local OFFSET={X=150,Y=-150}
local LINES=48

local function nameOf(object)
    local ok,name=pcall(function()return object:GetFName():ToString()end)
    return ok and type(name)=='string' and name or nil
end
local function className(object)
    local ok,name=pcall(function()return object:GetClass():GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end
local function find(path)
    local ok,object=pcall(StaticFindObject,path)
    return ok and U.valid(object) and object or nil
end

function Combos.new(options)
    local log=options.log or function()end
    local self={alive=true,enabled=false,linked=0,gates=0,assigned=0,failures=0}
    local links,members,hooks={},{},{}   -- pair key -> link; unit address -> {link,partner}; path -> hook ids
    local seenGate,lines,dispatched={},0,{}
    local function say(text)log('[Combos] '..text)end
    local function sayOften(text)
        if lines<LINES then lines=lines+1;say(text) end
    end
    local file=options.path and options.path..'/boss-combos.tsv'
    if file then
        local f=io.open(file,'r')
        if f then
            local text=f:read('*a');f:close()
            self.enabled=text==HEADER..'\tON\n'
        end
    end
    local function save()
        if not file then return true end
        local f=io.open(file,'w');if not f then return false end
        local wrote=f:write(HEADER..'\t'..(self.enabled and 'ON' or 'OFF')..'\n');f:close()
        return wrote~=nil and wrote~=false
    end

    local function alive(actor)
        if not U.valid(actor) then return false end
        local ok,value=pcall(function()return actor:IsAlive()end)
        return not ok or value==nil or U.unwrap(value)~=false
    end
    -- The tree a task object belongs to: the tree manager's copies and a brain's instances name it in TreeAsset, the asset's own
    -- node has it as outer.
    local function treeOf(task)
        local tree=U.field(task,'TreeAsset')
        if U.valid(tree) then return nameOf(tree) end
        local ok,outer=pcall(function()return task:GetOuter()end)
        outer=ok and U.unwrap(outer) or nil
        return U.valid(outer) and nameOf(outer) or nil
    end
    local function writeOnTrees(class,trees,field,value)
        local ok,list=pcall(FindAllOf,class)
        local set,mine,others=0,0,0
        if ok and type(list)=='table' then
            for _,task in ipairs(list)do
                if U.valid(task) then
                    if trees[treeOf(task) or ''] then
                        mine=mine+1
                        if pcall(function()task[field]=value end) and U.field(task,field)==value then set=set+1 end
                    else others=others+1 end
                end
            end
        end
        return string.format('%d/%d（别的树 %d 个没动）',set,mine,others)
    end
    local function prepareTrees()
        return '分派任务 AlwaysSuccess 读回='..writeOnTrees(ASSIGN_CLASS,Combos.TREES,'AlwaysSuccess',true)
            ..'；等搭档超时 读回='..writeOnTrees(WAIT_CLASS,Combos.WAITING,'Timeout',WAIT_SECONDS)
    end
    -- K2_CanActivateAbility runs on the class default object, so the caster comes from its actor info.
    local function avatarOf(context,info)
        local struct=U.unwrap(info)
        local weak=struct and U.struct(struct,'AvatarActor')
        if weak then
            local ok,actor=pcall(function()return weak:Get()end)
            if ok and U.valid(actor) then return actor end
        end
    end
    function self.onGate(context,info)
        if not self.alive or not self.enabled or not next(members) then return nil end
        local actor=avatarOf(context,info)
        local entry=actor and members[U.key(actor)]
        if not entry or not alive(entry.partner) then return nil end
        -- Never before the partner key reads back: the picked tree would wait on the empty key for good.
        if entry.link.partnerSet[U.key(actor)]~=true then return nil end
        self.gates=self.gates+1
        local ability=U.unwrap(context)
        local where=U.valid(ability) and className(ability) or '?'
        if not seenGate[where] then
            seenGate[where]=true
            -- The ability is loaded by now and with it its trees, which may not have been there when the pair linked.
            say(string.format('组合技放行 招式=%s 单位=%s 搭档=%s；%s',where,className(actor),className(entry.partner),prepareTrees()))
        end
        return true
    end

    local function tag(name)return {TagName=FName(name)} end
    -- The offset in the caster's facing, as the task composes it from its base transform.
    local function assignSpot(caster)
        local okAt,at=pcall(function()return caster:K2_GetActorLocation()end)
        if not okAt or not at then return nil end
        local okRot,rot=pcall(function()return caster:K2_GetActorRotation()end)
        local x,y,z,yaw=at.X,at.Y,at.Z,okRot and rot and rot.Yaw or 0
        if type(x)~='number' then return nil end
        local c,s=math.cos(math.rad(yaw)),math.sin(math.rad(yaw))
        return {X=x+OFFSET.X*c-OFFSET.Y*s,Y=y+OFFSET.X*s+OFFSET.Y*c,Z=z},{X=x,Y=y,Z=z},{Pitch=0,Yaw=yaw,Roll=0}
    end
    local function assign(caster,partner,treeName)
        local path=Combos.TREES[treeName or '']
        local tree=path and find(path)
        if not tree then self.failures=self.failures+1;sayOften('组合技分派失败 行为树='..tostring(treeName)..' 没找到搭档的树');return end
        local asc=U.field(partner,'AbilitySystemComponent')
        if U.valid(asc) then
            local ok,count=pcall(function()return asc:GetGameplayTagCount(tag(NOT_ASSIGNED))end)
            if ok and U.unwrap(count)~=0 and U.unwrap(count)~=nil then sayOften('搭档现在不接受分派 '..className(partner));return end
        end
        local spot,base,rotation=assignSpot(caster)
        local bbLib,aiLib,abilityLib=find(BB_LIB),find(AI_LIB),find(ABILITY_LIB)
        if not spot or not bbLib or not aiLib or not abilityLib then self.failures=self.failures+1;sayOften('组合技分派失败：缺位置或函数库');return end
        local okBoard,board=pcall(function()return bbLib:GetBlackboard(partner)end)
        board=okBoard and U.unwrap(board) or nil
        local wrote=U.valid(board) and pcall(function()
            aiLib:SetValueAsVectorByTag(board,tag('AI.BlackboardKey.Vector.AssignLocation'),spot)
            aiLib:SetValueAsRotatorByTag(board,tag('AI.BlackboardKey.Rotator.AssignRotation'),rotation)
            aiLib:SetValueAsVectorByTag(board,tag('AI.BlackboardKey.Vector.AssignBaseLocation'),base)
            aiLib:SetValueAsObjectByTag(board,tag('AI.BlackboardKey.Object.AssignBaseActor'),caster)
        end)
        local event=tag(EVENT)
        local sent=pcall(function()abilityLib:SendGameplayEventToActor(partner,event,{EventTag=event,Instigator=caster,OptionalObject=tree})end)
        if sent then
            self.assigned=self.assigned+1
            dispatched[U.key(partner) or partner]={actor=partner,want=nameOf(tree) or '?'}
        else self.failures=self.failures+1 end
        sayOften(string.format('组合技分派 单位=%s 树=%s -> 搭档=%s 树=%s 黑板写入=%s 发事件=%s',className(caster),treeName,className(partner),nameOf(tree) or '?',tostring(wrote==true),tostring(sent)))
    end
    function self.onAssign(context)
        if not self.alive or not self.enabled then return nil end
        local task=U.unwrap(context)
        if not U.valid(task) then return nil end
        local pawn=U.field(task,'ControlledPawn')
        local entry=U.valid(pawn) and members[U.key(pawn)]
        if not entry or not alive(entry.partner) then return nil end
        local tree=U.field(task,'TreeAsset')
        assign(pawn,entry.partner,U.valid(tree) and nameOf(tree) or nil)
        return nil
    end

    -- Writes the partner key of one unit and reads it back; nil partner empties it.
    local function setPartner(actor,partner)
        local bbLib,aiLib=find(BB_LIB),find(AI_LIB)
        if not bbLib or not aiLib or not U.valid(actor) then return false,'缺函数库' end
        local okBoard,board=pcall(function()return bbLib:GetBlackboard(actor)end)
        board=okBoard and U.unwrap(board) or nil
        if not U.valid(board) then return false,'还没有黑板' end
        local wrote=pcall(function()aiLib:SetValueAsObjectByTag(board,tag(PARTNER_KEY),partner)end)
        local okBack,back=pcall(function()return aiLib:GetValueAsObjectByTag(board,tag(PARTNER_KEY))end)
        back=okBack and U.unwrap(back) or nil
        local same=(partner==nil and not U.valid(back)) or (partner~=nil and U.key(back)==U.key(partner))
        return wrote and same,'写入='..tostring(wrote)..' 读回='..tostring(same)
    end
    -- What a linked unit is doing: the tree its brain runs, named when it changes, so a stuck tree shows in the log.
    local function runningTree(actor)
        local okC,controller=pcall(function()return actor:GetController()end)
        controller=okC and U.unwrap(controller) or nil
        local aiLib=find(AI_LIB)
        if not U.valid(controller) or not aiLib then return nil end
        local ok,tree=pcall(function()return aiLib:GetRunningBehaviorTree(controller)end)
        tree=ok and U.unwrap(tree) or nil
        return U.valid(tree) and nameOf(tree) or nil
    end
    local function watchTrees(record)
        for _,actor in ipairs({record.a,record.b})do
            local key=U.key(actor)
            if key and U.valid(actor) then
                local name=runningTree(actor)
                if name and record.trees[key]~=name then
                    record.trees[key]=name
                    if name:find('AllOutAttack',1,true) or name:find('Troop',1,true) then sayOften('行为树 单位='..className(actor)..' -> '..name) end
                end
            end
        end
    end
    -- What the partner runs on the tick after it got its tree: a tree that ends at once would otherwise not show at all.
    local function checkDispatched()
        for key,check in pairs(dispatched)do
            dispatched[key]=nil
            if U.valid(check.actor) then
                sayOften(string.format('分派后 搭档=%s 要跑=%s 实际在跑=%s',className(check.actor),check.want,tostring(runningTree(check.actor))))
            end
        end
    end
    local function holdPartners(record)
        for _,pair in ipairs({{record.a,record.b},{record.b,record.a}})do
            local actor,partner=pair[1],pair[2]
            local key=U.key(actor)
            if key and U.valid(actor) then
                local living=alive(partner)
                local state=record.partnerSet[key]
                if living and state~=true then
                    local ok,note=setPartner(actor,partner)
                    if ok then record.partnerSet[key]=true end
                    if ok or state==nil then say('搭档键 单位='..className(actor)..' 搭档='..className(partner)..' '..note) end
                    if not ok then record.partnerSet[key]=false end
                elseif not living and state==true then
                    local _,note=setPartner(actor,nil)
                    record.partnerSet[key]=nil
                    say('搭档不在了，清空搭档键 单位='..className(actor)..' '..note)
                end
            end
        end
    end

    -- A blueprint that is not loaded yet comes in with the unit's AI, so this runs again on every tick of a linked pair.
    local missing,refused={},{}
    local function installHooks()
        for name,path in pairs(Combos.paths)do
            if not hooks[path] and not refused[path] then
                if find(path) then
                    missing[name]=nil
                    local handler=name=='assign' and self.onAssign or self.onGate
                    local ok,pre,post=pcall(RegisterHook,path,handler,function()end)
                    if ok and type(pre)=='number' then hooks[path]={pre=pre,post=post};say('挂钩注册ID读回 '..name..' pre='..pre)
                    else refused[path]=true;say('挂钩注册失败 '..name..'：'..tostring(pre)) end
                elseif not missing[name] then
                    missing[name]=true
                    say('还没找到函数，稍后再试 '..name)
                end
            end
        end
    end
    local function removeHooks()
        for path,hook in pairs(hooks)do pcall(UnregisterHook,path,hook.pre,hook.post);hooks[path]=nil end
        missing,refused={},{}
    end

    local function link(pair,team,a,b,key)
        links[key]={key=key,pair=pair,a=a,b=b,partnerSet={},trees={}}
        seenGate={}
        members[U.key(a)]={link=links[key],partner=b};members[U.key(b)]={link=links[key],partner=a}
        self.linked=self.linked+1
        installHooks()
        holdPartners(links[key])
        say(string.format('连携 %s 队伍=%s：%s + %s；%s',pair.name,team,className(a),className(b),prepareTrees()))
    end
    local function unlink(key,reason)
        local record=links[key]
        if not record then return end
        for address,entry in pairs(members)do if entry.link==record then members[address]=nil end end
        for _,actor in ipairs({record.a,record.b})do
            local address=U.key(actor)
            if address and record.partnerSet[address] and U.valid(actor) then
                local _,note=setPartner(actor,nil)
                say('解除时清空搭档键 单位='..className(actor)..' '..note)
            end
        end
        links[key]=nil
        say(string.format('解除连携 %s（%s）放行=%d 分派=%d',record.pair.name,reason,self.gates,self.assigned))
    end

    function self:tick()
        if not self.alive then return end
        local keep={}
        if self.enabled and options.fighting() then
            local byTeam={}
            for _,member in ipairs(options.members())do
                if (member.team=='blue' or member.team=='red') and not member.reserve and U.valid(member.actor) then
                    local team=byTeam[member.team] or {}
                    byTeam[member.team]=team
                    local name=className(member.actor)
                    if not team[name] or (not alive(team[name]) and alive(member.actor)) then team[name]=member.actor end
                end
            end
            for teamName,team in pairs(byTeam)do
                for _,pair in ipairs(Combos.PAIRS)do
                    local a,b=team[pair.classes[1]],team[pair.classes[2]]
                    if a and b then
                        local key=tostring(U.key(a))..':'..tostring(U.key(b))
                        keep[key]=true
                        if not links[key] then link(pair,teamName,a,b,key)
                        else installHooks();holdPartners(links[key]);checkDispatched();watchTrees(links[key]) end
                    end
                end
            end
        end
        for key in pairs(links)do if not keep[key] then unlink(key,self.enabled and '战斗结束或单位离场' or '开关已关') end end
        if not next(links) and next(hooks) then removeHooks() end
    end
    function self:set(value)
        self.enabled=value==true
        local saved=save()
        say('开关 '..(self.enabled and '开' or '关')..' 保存='..tostring(saved))
        self:tick()
        local state=self.enabled and '连携技已开启' or '连携技已关闭'
        return {ok=saved,message=saved and state or state..'，但没保存下来，下次启动会变回去',spawned_count=0}
    end
    function self:status()return {enabled=self.enabled,links=self.linked,gates=self.gates,assigned=self.assigned,failures=self.failures}end
    function self:silence()removeHooks();self.alive=false end
    return self
end
return Combos
