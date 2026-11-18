-- Arena and challenge instances use the ordinary humanoid decision tree. The clone's summon tree has
-- a different Idle goal. Leave native companion preparation in charge of the companion role.
local U=require('ue_observe')
local Role={}
local BASE='/PBZCombatAsset/Prototypes/AI/Template/StateConfig/StateTreeConfig_Humaniod'
local NORMAL=BASE..'.StateTreeConfig_Humaniod'
local SUMMON=BASE..'_Summon.StateTreeConfig_Humaniod_Summon'
local CAN_HATE='/SGameAI/Tools/Hatred/BP_SGameHatredManagerComponent.BP_SGameHatredManagerComponent_C:CheckCanHatredTarget'
local HIT='/Script/ProjectPBZ.PBZCharacter:OnDamage'
local BULLET_HIT='/Script/SGameCombatSystem.BulletAttackModule:DealDamageToAvatar'
local CHECK_TARGET='/Script/SGameCombatSystem.BulletAttackModule:IsValidTarget'
local function call(object,method,...)
    if not U.valid(object) then return false end
    local args=table.pack(...)
    local ok,result=pcall(function()return object[method](object,table.unpack(args,1,args.n))end)
    return ok,U.unwrap(result)
end
local function title(obj)
    local _,name=call(obj,'GetFullName')
    return type(name)=='string' and name:match('^%S+ (/.+)$') or nil
end
function Role.new(o)
    local self={}
    local standard,followKey
    local managers,bodies,hooks={},{},{}
    local register,unregister=o.register or RegisterHook,o.unregister or UnregisterHook
    local gameThread=o.gameThread or IsInGameThread
    local effectLib
    local samples={}
    local pending=0
    local function onGameThread()return type(gameThread)=='function' and gameThread()==true end
    local function canHate(context,other)
        if not onGameThread() then return end
        local r=managers[U.key(U.unwrap(context)) or '']
        if r and o.current(r) and U.key(U.unwrap(other))~=nil and U.key(U.unwrap(other))==U.key(o.player()) then return false end
    end
    local function onDamage(context,amount,_,rawEffect)
        if not onGameThread() or not o.stat or not rawEffect then return end
        local a=U.unwrap(context)
        local r=bodies[U.key(a) or '']
        if not r or (r.playerHitLines or 0)>=28 or not o.current(r) then return end
        local effect=U.unwrap(rawEffect)
        if not effect then return end
        if not U.valid(effectLib) then effectLib=o.find('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary') end
        local player=o.player();local key=U.key(player)
        if not key then return end
        local _,source=call(effectLib,'EffectContextGetOriginalInstigatorActor',effect)
        if U.key(source)~=key then _,source=call(effectLib,'EffectContextGetInstigatorActor',effect) end
        if U.key(source)~=key then _,source=call(effectLib,'EffectContextGetEffectCauser',effect) end
        if U.key(source)~=key then return end
        r.playerHitLines=(r.playerHitLines or 0)+1
        local before=r.lastHudSample or {}
        local _,fromPlayer=call(U.field(player,'Faction Component'),'GetFactionRelation',a)
        local _,toPlayer=call(U.field(a,'Faction Component'),'GetFactionRelation',player)
        o.log('[HunPlayerHit] '..r.team..' '..r.name..' 玩家命中 回调伤害='..tostring(U.unwrap(amount))..
            ' 上次界面采样 HP='..tostring(before.hp)..' 杀气='..tostring(before.shachi)..
            ' 命中回调 HP='..tostring(o.stat(a,'Health'))..' 杀气='..tostring(o.stat(a,'Shachi'))..
            ' 下限='..tostring(o.stat(a,'Shachi_Min'))..' 上限='..tostring(o.stat(a,'Shachi_Max'))..
            ' 受击杀气抗性='..tostring(o.stat(a,'Resistance_ImpactShachi'))..' 玩家对魂/魂对玩家='..
            tostring(fromPlayer)..'/'..tostring(toPlayer))
        r.awaitHitSample=true
    end
    -- This native event has five arguments. Copy only numeric values for player -> registered team Hun hits.
    -- Unlike an area-wide damage trace this does not read combat maps or attach to the player's health functions.
    local function bulletEvent(post,context,...)
        if not onGameThread() or not o.stat then return end
        local n=select('#',...)
        if n~=5 and not (post and n==6) then return end
        local target=U.unwrap(select(n==6 and 2 or 1,...))
        local targetKey=U.key(target)
        local r=bodies[targetKey or '']
        if not r or (r.bulletHitLines or 0)>=24 then return end
        local module=U.unwrap(context);local source=U.field(module,'LastOwnerAvatar')
        local player=o.player();local playerKey=U.key(player)
        local moduleKey=U.key(module)
        if not playerKey or U.key(source)~=playerKey or not moduleKey or not o.current(r) then return end
        local key=moduleKey..'/'..targetKey
        if not post then
            if pending>=32 then return end
            local stack=samples[key] or {};samples[key]=stack
            stack[#stack+1]={hp=o.stat(target,'Health'),shachi=o.stat(target,'Shachi'),r=r,at=os.clock()}
            pending=pending+1
            return
        end
        local stack=samples[key];local old=stack and table.remove(stack)
        if old then pending=pending-1 end
        if stack and #stack==0 then samples[key]=nil end
        if not old or old.r~=r then return end
        r.bulletHitLines=(r.bulletHitLines or 0)+1
        local _,fromPlayer=call(U.field(player,'Faction Component'),'GetFactionRelation',target)
        o.log('[HunPlayerHit] 玩家→'..r.team..' '..r.name..' 原生命中调用前后 HP='..tostring(old.hp)..'→'..tostring(o.stat(target,'Health'))..
            ' 杀气='..tostring(old.shachi)..'→'..tostring(o.stat(target,'Shachi'))..
            ' 下限/上限='..tostring(o.stat(target,'Shachi_Min'))..'/'..tostring(o.stat(target,'Shachi_Max'))..
            ' 玩家对魂关系='..tostring(fromPlayer))
        r.awaitHitSample=true
    end
    local function beforeBullet(...)bulletEvent(false,...)end
    local function afterBullet(...)bulletEvent(true,...)end
    local function rejectedTarget(context,...)
        if not onGameThread() or select('#',...)~=2 then return end
        local result,target=...
        if U.unwrap(result)~=false then return end
        local r=bodies[U.key(U.unwrap(target)) or '']
        if not r or (r.rejectedLines or 0)>=4 or not o.current(r) then return end
        local player=o.player()
        if not U.key(player) or U.key(U.field(U.unwrap(context),'LastOwnerAvatar'))~=U.key(player) then return end
        r.rejectedLines=(r.rejectedLines or 0)+1
        local _,from=call(U.field(player,'Faction Component'),'GetFactionRelation',r.actor)
        local _,to=call(U.field(r.actor,'Faction Component'),'GetFactionRelation',player)
        o.log('[HunPlayerHit] 玩家攻击的原生目标筛选返回 false '..r.team..' '..r.name..' 玩家对魂/魂对玩家='..tostring(from)..'/'..tostring(to))
    end
    local function install(key,fn,post)
        if hooks[key] or type(register)~='function' or type(o.find)~='function' or not U.valid(o.find(key)) then return end
        local ok,pre,after=pcall(register,key,fn,post or function()end)
        if ok and type(pre)=='number' and type(after)=='number' then hooks[key]={pre,after};o.log('[HunRole] 已登记 '..key)end
    end
    function self:prepare(r)
        if not r or r.team=='companion' or not o.current(r) then return end
        local ai=o.aiOf and o.aiOf(r.actor)
        if not U.valid(ai) or U.key(U.field(ai,'Pawn'))~=U.key(r.actor) then return end
        local _,tree=call(ai,'GetStateTreeConfig')
        local previous,read=U.field(ai,'OverrideStateTreeConfig')
        if title(tree)==SUMMON or (not U.valid(tree) and read and not U.valid(previous)) then
            if not U.valid(standard) then
                local ok,asset=pcall(o.load,NORMAL)
                if ok and title(asset)==NORMAL then standard=asset end
            end
            if U.valid(standard) and o.current(r) then
                o.log('[HunRole] 即将切换本体决策树 team='..r.team..' '..r.name)
                local ok=pcall(function()ai.OverrideStateTreeConfig=standard end)
                local _,back=call(ai,'GetStateTreeConfig')
                local accepted=U.key(U.field(ai,'OverrideStateTreeConfig'))==U.key(standard)
                if ok and accepted and not r.roleAI then r.roleAI=ai;r.previousTree=previous end
                o.log('[HunRole] 普通人形决策树 写入='..tostring(ok and accepted)..' 原生选用='..tostring(U.key(back)==U.key(standard)))
            end
        end
    end
    function self:excludePlayer(r)
        if not r or (r.team~='blue' and r.team~='red') or not o.current(r) then return end
        if pending>0 then
            local t=os.clock()
            for key,stack in pairs(samples)do
                if t-stack[#stack].at>2 then pending=pending-#stack;samples[key]=nil end
            end
        end
        local player=o.player()
        if not U.key(player) or U.key(player)==U.key(r.actor) then return end
        local hm=U.field(r.actor,'BP_PBZHatredManagerComponent')
        -- Hatred controls whom the NPC chases. Preserve faction checks used by the player's incoming attacks.
        local hmKey=U.key(hm)
        if hmKey then
            if r.managerKey and r.managerKey~=hmKey then managers[r.managerKey]=nil end
            r.managerKey=hmKey;managers[hmKey]=r
            install(CAN_HATE,canHate)
        end
        r.roleKey=U.key(r.actor);bodies[r.roleKey]=r
        install(HIT,onDamage)
        install(BULLET_HIT,beforeBullet,afterBullet)
        install(CHECK_TARGET,function()end,rejectedTarget)
        local list=U.array(U.field(hm,'HatredList')) or {}
        for _,actor in ipairs(list)do
            if U.key(actor)==U.key(player) then
                o.log('[HunRole] 即将移除本体对玩家的仇恨 '..r.name)
                call(hm,'RemoveActorFromHatredList',player)
                local after=U.array(U.field(hm,'HatredList'))
                local remains=false
                for _,other in ipairs(after or {}) do if U.key(other)==U.key(player) then remains=true end end
                o.log('[HunRole] 仇恨名单移除玩家 读回='..tostring(after~=nil and not remains))
                break
            end
        end
        local ai=o.aiOf and o.aiOf(r.actor)
        local board=U.field(ai,'BlackboardComponent')
        if U.key(U.field(ai,'Pawn'))~=U.key(r.actor) or not U.valid(board) then return end
        -- Only erase a key that actually resolves to the real pawn, never an arena opponent.
        local handler=U.field(U.field(r.actor,'Targeting Component'),'DefaultTargetHandler')
        if not followKey then
            if o.find then
                local found,lib=pcall(o.find,'/Script/SGameAI.Default__SGameAIFunctionLibrary')
                local got,key=call(found and lib,'GetBlackboardKeyNameFromTag',{TagName=o.fname('AI.BlackboardKey.Object.FollowTargetActor')})
                local named,s=pcall(function()return key:ToString()end)
                if got and named and s~='None' and s~='' then followKey=key end
            end
            followKey=followKey or o.fname('FollowTargetActor')
        end
        local keys={followKey}
        if U.key(U.field(handler,'Blackboard'))==U.key(board) then
            keys[#keys+1]=U.field(handler,'Target Key')
            keys[#keys+1]=U.field(handler,'LastSensedActorKey')
        end
        for _,key in ipairs(keys)do
            local got,value=call(board,'GetValueAsObject',key)
            if got and U.key(value)==U.key(player) and o.current(r) then
                call(board,'ClearValue',key)
                local checked,after=call(board,'GetValueAsObject',key)
                o.log('[HunRole] 本体黑板移除玩家 读回='..tostring(checked and not U.valid(after)))
            end
        end
    end
    function self:restore(r)
        if r.managerKey and managers[r.managerKey]==r then managers[r.managerKey]=nil end
        if r.roleKey and bodies[r.roleKey]==r then bodies[r.roleKey]=nil end
        for key,stack in pairs(samples) do if stack[1] and stack[1].r==r then pending=pending-#stack;samples[key]=nil end end
        if not next(bodies) then for key,ids in pairs(hooks)do
            local ok,result=pcall(unregister,key,ids[1],ids[2])
            if ok and result~=false then hooks[key]=nil end
        end end
        if not o.current(r) then return end
        if U.valid(r.roleAI) and U.key(U.field(r.roleAI,'Pawn'))==U.key(r.actor)
            and U.key(U.field(r.roleAI,'OverrideStateTreeConfig'))==U.key(standard) then
            pcall(function()r.roleAI.OverrideStateTreeConfig=r.previousTree end)
            o.log('[HunRole] 决策树覆盖还原 读回='..tostring(U.key(U.field(r.roleAI,'OverrideStateTreeConfig'))==U.key(r.previousTree)))
        end
        r.roleAI,r.previousTree=nil,nil
    end
    return self
end
return Role
