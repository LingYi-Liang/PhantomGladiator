-- Arena and challenge instances use the ordinary humanoid decision tree. The clone's summon tree has
-- a different Idle goal. Leave native companion preparation in charge of the companion role.
local U=require('ue_observe')
local Role={}
local BASE='/PBZCombatAsset/Prototypes/AI/Template/StateConfig/StateTreeConfig_Humaniod'
local NORMAL=BASE..'.StateTreeConfig_Humaniod'
local SUMMON=BASE..'_Summon.StateTreeConfig_Humaniod_Summon'
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
        local player=o.player()
        if not U.key(player) or U.key(player)==U.key(r.actor) then return end
        local faction=U.field(r.actor,'Faction Component')
        local ok,relation=call(faction,'GetFactionRelation',player)
        if ok and relation==2 then
            o.log('[HunRole] 即将设置本体对玩家单向中立 '..r.name)
            call(faction,'SetFactionRelationOverride',player,1,false)
            local _,back=call(faction,'GetFactionRelation',player)
            if back==1 then r.neutralPlayer=player;r.neutralFaction=faction end
            o.log('[HunRole] 玩家关系读回='..tostring(back))
        end
        local hm=U.field(r.actor,'BP_PBZHatredManagerComponent')
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
        if not o.current(r) then return end
        if U.valid(r.roleAI) and U.key(U.field(r.roleAI,'Pawn'))==U.key(r.actor)
            and U.key(U.field(r.roleAI,'OverrideStateTreeConfig'))==U.key(standard) then
            pcall(function()r.roleAI.OverrideStateTreeConfig=r.previousTree end)
            o.log('[HunRole] 决策树覆盖还原 读回='..tostring(U.key(U.field(r.roleAI,'OverrideStateTreeConfig'))==U.key(r.previousTree)))
        end
        local p,fc=r.neutralPlayer,r.neutralFaction
        if U.key(p) and U.key(p)==U.key(o.player()) and not (o.keepNeutral and o.keepNeutral()) and
            U.key(fc)==U.key(U.field(r.actor,'Faction Component')) then
            local _,live=call(fc,'GetFactionRelation',p)
            if live==1 then
                call(fc,'SetFactionRelationOverride',p,2,false)
                local _,back=call(fc,'GetFactionRelation',p)
                o.log('[HunRole] 玩家关系还原 读回='..tostring(back))
            end
        end
        r.roleAI,r.previousTree,r.neutralPlayer,r.neutralFaction=nil,nil,nil,nil
    end
    return self
end
return Role
