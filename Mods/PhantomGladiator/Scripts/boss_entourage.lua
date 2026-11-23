-- Supply the original task with the members of this particular summon. The task itself selects
-- positions, checks tags, runs its EQS and dispatches the native behavior trees.
local U=require('ue_observe')
local M={}
local ROOT='/PBZCombatAsset/ActorData/Mobs/035_HuaShan/'
local function mob(id)return ROOT..id..'.'..id..'_C' end
M.parties={
    BP_Monster_HuaShan_Blue={{path=mob('BP_Monster_HuaShan_White'),count=6,formation=true}},
    BP_Monster_HuaShan_RedTroop_BigBro={{path=mob('BP_Monster_HuaShan_RedTroop_Soldier'),count=6,formation=true}},
}
local MASK='/Game/RenewalContent/Actors/Mobs/Normal/'
M.parties.BP_Monster_JadeMaskMan={}
for _,id in ipairs({'BP_Monster_GoldMaskMan','BP_Monster_IronMaskMan'})do
    table.insert(M.parties.BP_Monster_JadeMaskMan,{path=MASK..id..'.'..id..'_C',count=1,formation=true})
end
M.xiao='BP_Monster_XiaoXue'
function M.id(path)return type(path)=='string' and path:match('%.(BP_Monster_[%w_]+)_C$')end
function M.retireFormation(path)
    local id=M.id(path)
    return id=='BP_Monster_HuaShan_Blue' or id=='BP_Monster_HuaShan_RedTroop_BigBro'
end
local passives={
    [M.xiao]={GA_SummonPassive_XiaoXue_C=4},
    BP_Monster_FemaleVessel_YuZan={GA_YuZan_Passive_Summon_C=3,GA_YuZan_Passive_Summon_P2_C=5},
    BP_Monster_CanQu_BiHai={GA_CanQu_BiHai_SummonPassive_01_C=3,GA_CanQu_BiHai_SummonPassive_02_C=3,GA_CanQu_BiHai_SummonPassive_03_C=3},
    -- The third ordinary passive makes the boss's stunt double, not a combat partner.
    BP_Monster_Danghui={GA_DangHui_SummonPassive_01_C=3,GA_DangHui_SummonPassive_02_C=2,
        GA_DangHui_SummonPassive_P1_Hard_C=4,GA_DangHui_SummonPassive_P2_Hard_C=3},
}
function M.supports(id)return passives[id]~=nil or M.parties[id]~=nil end
local ASSIGN='/SGameAI/BehaviorTree/Task/BTTask_AssignBehaviorTreesToGroupMember.BTTask_AssignBehaviorTreesToGroupMember_C:ExecuteInternal'
local SUMMON='/SGameAI/Core/AIScript/GA_SummonPassive.GA_SummonPassive_C:OnReceivedSpawnSummonsEvent'
local FINISH=SUMMON:gsub(':OnReceivedSpawnSummonsEvent$',':OnSpawnFinish')
local function call(obj,method,...)
    if not U.valid(obj) then return end
    local args=table.pack(...);local ok,value=pcall(function()return obj[method](obj,table.unpack(args,1,args.n))end)
    if ok then return U.unwrap(value) end
end
function M.new(o)
    local self={};local members,groups,leaders,hooks,sent={},{},{},{},{}
    local wantAssign,wantPassive=false,false
    local alive=true
    local edits={}
    local function member(actor)
        local key=U.key(actor);local r=key and members[key]
        if r and r.name==call(actor,'GetFullName') and U.inWorld(actor,o.world()) then return r end
    end
    local function detach()
        for path,ids in pairs(hooks) do
            local ok,result=pcall(o.unregister,path,ids[1],ids[2])
            if ok and result~=false then hooks[path]=nil end
        end
    end
    function self:roster(rows)
        local nextMembers,nextGroups,nextLeaders={},{},{}
        wantAssign,wantPassive=false,false
        for _,r in ipairs(rows)do
            local id=M.id(r.class_path)
            if (r.formation~=nil and passives[id]) or r.formationGroup then
                local k=U.key(r.actor);local name=call(r.actor,'GetFullName')
                if k and name then
                    local owner=r.formationGroup or r.actor
                    if passives[id] then wantPassive=true end
                    if r.formation and M.parties[id] then wantAssign=true end
                    nextMembers[k]={actor=r.actor,id=id,name=name,owner=owner,team=r.team,enabled=r.formation}
                    if r.formation then nextLeaders[owner]=nextMembers[k] end
                    nextGroups[owner]=nextGroups[owner]or{};table.insert(nextGroups[owner],nextMembers[k])
                end
            end
        end
        for key,e in pairs(edits) do
            local row=nextMembers[e.owner];if not row or row.name~=e.name then edits[key]=nil end
        end
        members,groups,leaders=nextMembers,nextGroups,nextLeaders
        if next(members) then self:tick() else detach() end
        for k,n in pairs(sent)do if not members[k] or members[k].name~=n then sent[k]=nil end end
    end
    local function assign(task)
        task=U.unwrap(task)
        local pawn=U.field(task,'ControlledPawn');local r=member(pawn)
        if r and type(r.owner)=='table' and r.owner.nativeFormation then
            if o.nativeAssignment then o.nativeAssignment(task,pawn)end
            return
        end
        if not r or (o.hp(pawn) or 0)<=0 or not U.inWorld(task,o.world()) then return end
        local leader=leaders[r.owner]
        if not leader or not member(leader.actor) or (o.hp(leader.actor)or 0)<=0 or not leader.enabled or not M.parties[leader.id] then return end
        local tree=call(U.field(task,'TreeAsset'),'GetFullName')
        if type(tree)~='string' or not tree:find(leader.id=='BP_Monster_JadeMaskMan' and '/014_JadeMaskMan/AI/AllOutAttack/' or ROOT..'BehaviorTree/',1,true) then return end
        local peers={}
        for _,p in ipairs(groups[r.owner]) do
            if p~=r and p.team==r.team and member(p.actor)==p and (o.hp(p.actor) or 0)>0 then peers[#peers+1]=p.actor end
        end
        if #peers==0 then return end
        local ok=pcall(function()task.ActorsToAssign=peers end)
        local read=ok and U.array(U.field(task,'ActorsToAssign'))
        if not read or #read~=#peers then
            if not leader.assignmentWarning then o.log('[Entourage] 阵法队员写入未读回 '..leader.name);leader.assignmentWarning=true end
            return
        end
        for i,actor in ipairs(peers)do if U.key(read[i])~=U.key(actor) then return end end
        if not leader.reported then
            leader.reported=true;o.log('[Entourage] 原版阵法任务队员读回 '..#read..' '..leader.name)
        end
    end
    local function ownedPassive(ability)
        ability=U.unwrap(ability)
        local r=member(call(ability,'GetAvatarActorFromActorInfo'))
        local cap=r and passives[r.id] and passives[r.id][U.className(ability)]
        if cap then return r,ability,cap end
    end
    local function change(r,a,field,original,value)
        if U.field(a,field)~=original then return end
        local k=U.key(a);if not k then return end
        local ok=pcall(function()a[field]=value end)
        local read=U.field(a,field)
        if ok and read==value then
            local e=edits[k]
            if not e or e.owner~=U.key(r.actor) or e.name~=r.name then
                e={ability=a,owner=U.key(r.actor),name=r.name,fields={}};edits[k]=e
            end
            e.fields[field]={original,value}
        end
        o.log('[Entourage] '..r.name..' '..field..' 设置='..tostring(ok)..' 读回='..tostring(read))
    end
    local function configure(r,a,cap)
        if not r.enabled then change(r,a,'MaxSummonCount',cap,0);return end
        if r.id~=M.xiao then
            -- The native death listener uses a latched copy initialized when the passive starts.
            change(r,a,'DestroySummonsOnDead',true,false)
            change(r,a,'bDestroySummonsOnDeadLatched',true,false)
            change(r,a,'DestroySummonsOnEndAbility',true,false)
        end
    end
    local function guard(ability)
        local r,a,cap=ownedPassive(ability)
        if r then configure(r,a,cap) end
    end
    function self:passive(ability)
        if not alive or not wantPassive then return end
        local r,a,cap=ownedPassive(ability);if not r then return end
        configure(r,a,cap)
        if not r.enabled or r.id~=M.xiao then return end
        local k=U.key(r.actor)
        if sent[k] or U.field(a,'MaxSummonCount')~=4 or (o.hp(r.actor)or 0)<=0 then return end
        local rows=U.array(U.field(a,'SpawnedSummonInstances'));if not rows then return end
        sent[k]=r.name
        if #rows>0 then return end
        -- The native handler subtracts living AND pending summons before choosing its own minions.
        local ok=pcall(function()a:OnReceivedSpawnSummonsEvent({EventMagnitude=4,Instigator=r.actor})end)
        o.log('[Entourage] 小雪原生召唤请求 '..tostring(ok)..'；已有实例 '..#rows..'；结果由召唤名单确认')
    end
    local function born(ability,child)
        local r,a,cap=ownedPassive(ability);child=U.unwrap(child)
        if not r or not r.enabled or not U.inWorld(child,o.world()) then return end
        configure(r,a,cap)
        local path=U.npcPath(child)
        if path and U.key(child)~=U.key(r.actor) then o.adopt(child,r.actor,path) end
    end
    local retry=0
    function self:tick()
        if not alive or not next(members) or ((not wantAssign or hooks[ASSIGN]) and (not wantPassive or (hooks[SUMMON] and hooks[FINISH]))) then return end
        local now=o.now();if now<retry then return end;retry=now+1
        for path,handler in pairs({[ASSIGN]=assign,[SUMMON]=guard,[FINISH]=born})do
            local needed=path==ASSIGN and wantAssign or path~=ASSIGN and wantPassive
            if needed and not hooks[path] and U.valid(o.find(path)) then
                local function callback(...)if alive and next(members)then handler(...)end end
                local function noop()end
                local ok,pre,post=pcall(o.register,path,path==FINISH and noop or callback,path==FINISH and callback or noop)
                if ok and type(pre)=='number' and type(post)=='number' then hooks[path]={pre,post} end
            end
        end
    end
    function self:silence(onGameThread)
        if onGameThread then
            for _,e in pairs(edits) do
                local r,a=ownedPassive(e.ability)
                if r and r.name==e.name and U.key(r.actor)==e.owner then
                    for field,values in pairs(e.fields)do
                        if U.field(a,field)==values[2] then pcall(function()a[field]=values[1] end) end
                    end
                end
            end
        end
        edits={};alive=false;members={};groups={};leaders={};sent={}
        detach()
    end
    return self
end
return M
