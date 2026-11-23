-- HuaShan's own AI reads placed spawners, including downed members, before it dispatches its trees.
local U=require('ue_observe')
local Party={}
local ROOT='/PBZCombatAsset/ActorData/Mobs/035_HuaShan/'
local BLUE='BP_Monster_HuaShan_Blue'
local RED='BP_Monster_HuaShan_RedTroop_BigBro'
local DOMAIN='/SGameAI/Tools/MobDomain/BP_MobDomain.BP_MobDomain_C'
local SPAWNER='/SGameAI/Tools/Spawner/BP_AISpawner.BP_AISpawner_C'
local GROUP='/Script/SGameAI.MobGroup'
local SYSTEM='/Script/Engine.Default__KismetSystemLibrary'
local AI='/Script/SGameAI.Default__SGameAIFunctionLibrary'
local GAS='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
local UTILS='/Script/SGameUtils.Default__AbilityUtils'
local INIT=ROOT..'BehaviorTree/Troop/Init/BT_HuaShan_Troop_Init_07.BT_HuaShan_Troop_Init_07'
local INTRO=ROOT..'Abilities/GA_HuaShan_Story_Intro.GA_HuaShan_Story_Intro_C'
local TROOP='CharacterState.AbilityState.Troop.TroopMob'
local CENTER='AI.BlackboardKey.Vector.DomainCenter'
local PREFIX='PhantomGladiator_HuaShan_'
local DEATH_SCRIPT='AIScript_HuaShan_Troop_Blue_Dead_C'

local function call(o,method,...)
    if not U.valid(o) then return false end
    local args=table.pack(...)
    local ok,value=pcall(function()return o[method](o,table.unpack(args,1,args.n))end)
    if ok then return true,U.unwrap(value) end
    return false
end
local function get(o,method,...)
    local ok,value=call(o,method,...)
    if ok then return value end
end
local function text(value)
    if type(value)=='string' then return value end
    local ok,s=pcall(function()return value:ToString()end)
    return ok and type(s)=='string' and s or nil
end
local function pathOf(o)
    local s=get(o,'GetFullName')
    return type(s)=='string' and s:match('^%S+ (/.+)$') or nil
end
local function same(a,b)
    local k=U.key(a);return k~=nil and k==U.key(b)
end
local function empty(o,k)
    local list=U.array(U.field(o,k))
    return list and #list==0
end
local function set(o,k,v)
    if not U.valid(o) then return false end
    local ok=pcall(function()o[k]=v end)
    return ok and U.field(o,k)==v
end
local function setObject(o,k,v)
    if not U.valid(o) or (v~=nil and not U.valid(v)) then return false end
    local ok=pcall(function()o[k]=v end)
    local back,read=U.field(o,k)
    return ok and read and (v==nil and not U.valid(back) or same(back,v))
end
local function sameList(list,expected)
    if not list or #list~=#expected then return false end
    local keys={}
    for _,v in ipairs(list)do local k=U.key(v);if not k or keys[k] then return false end;keys[k]=true end
    for _,v in ipairs(expected)do if not keys[U.key(v)]then return false end end
    return true
end
local function nativeGroup(domain,slot)
    local map=U.struct(U.field(domain,'MobDomainConfig'),'MobGroups')
    if U.kind(map)=='table' then return map[slot] end
    local found
    pcall(function()map:ForEach(function(k,v)
        if text(U.unwrap(k))==slot then found=U.unwrap(v);return true end
    end)end)
    return found
end
-- Let the reflected property parse its own reference type. Never put an Actor userdata in a soft-pointer slot.
local function propertyIs(p,kind)
    if PropertyTypes and PropertyTypes[kind] and p:IsA(PropertyTypes[kind]) then return true end
    -- Older UE4SS builds expose these FFields but omit soft reference kinds from the PropertyTypes table.
    local full=p:GetFullName()
    return type(full)=='string' and full:match('^(%S+) ')==kind
end
local function import(o,field,kind,value)
    local cls=get(o,'GetClass')
    for _=1,16 do
        if not U.valid(cls) or not U.valid(o) then return false end
        local found,wrote=false,false
        local ok=pcall(function()cls:ForEachProperty(function(p)
            if text(p:GetFName())~=field then return end
            found=true
            if not propertyIs(p,kind) then return true end
            if kind=='ArrayProperty' and not propertyIs(p:GetInner(),'SoftObjectProperty')then return true end
            local data=p:ContainerPtrToValuePtr(o,0)
            if data~=nil then p:ImportText(value,data,0,o);wrote=true end
            return true
        end)end)
        if not ok or found then return ok and wrote end
        cls=get(cls,'GetSuperStruct')
    end
    return false
end
local function point(v)
    if not v then return nil end
    local ok,x,y,z=pcall(function()return v.X,v.Y,v.Z end)
    local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
    if ok and finite(x) and finite(y) and finite(z) then return {X=x,Y=y,Z=z} end
end
function Party.isSpawner(spawner)
    if not U.valid(spawner)then return false end
    local id=text(U.field(spawner,'SpawnerID'))
    return id~=nil and id:sub(1,#PREFIX)==PREFIX
end

function Party.new(o)
    local self={}
    local groups,owners,fieldActors,sides,assets={},{},{},{},{}
    local casts={}
    local latestRows,revision,rosterRead,alive={},0,-1,true
    local clock=o.now or os.clock
    local retryClock=o.retryClock or clock
    local function cooling(stamp,seconds)
        if not stamp then return false end
        local now=retryClock() or os.clock()
        return now>=stamp and now-stamp<seconds
    end
    local fname=o.fname or FName
    local function tag(n)return {TagName=fname(n)}end
    local function say(s)o.log('[HuaShan] '..s)end
    local function asset(path,loadable)
        if U.valid(assets[path]) then return assets[path] end
        local ok,v=pcall(o.find or StaticFindObject,path)
        if (not ok or not U.valid(v)) and loadable then
            ok,v=pcall(o.load or LoadAsset,path)
            if not ok or not U.valid(v) or pathOf(v)~=path then ok,v=pcall(o.find or StaticFindObject,path) end
        end
        if ok and U.valid(v) then assets[path]=v;return v end
    end
    local function reference(a)
        local p=text(get(asset(SYSTEM),'GetPathName',a))
        if p and p:match('^/') and not p:find('["\\%c]') then return '"'..p..'"' end
    end
    local function resolveSoft(o,k,method)
        local ref=U.field(o,k)
        if U.kind(ref)=='TSoftObjectPtrUserdata' then return get(asset(SYSTEM),method,ref) end
    end
    local function here(r)return same(r.world,o.world())end
    local function owned(a,name,r)return name and U.inWorld(a,r.world) and pathOf(a)==name end
    local function groupOf(actor)
        local r=owners[U.key(actor)]
        if r and not r.retiring and here(r) and same(U.field(actor,'MobGroup'),r.group) then return r end
    end
    local function refreshRoster()
        if rosterRead==revision then return end
        fieldActors,sides={},{}
        for _,row in ipairs(latestRows)do
            if (row.team=='red' or row.team=='blue') and not row.aid and not row.stand and not row.reserve then
                local k=U.key(row.actor)
                if k then fieldActors[#fieldActors+1]=row.actor;sides[k]=row.team end
            end
        end
        rosterRead=revision
    end
    local function helper(r,row,path,transform)
        local lib=o.statics();local cls=asset(path,true)
        if not here(r) or get(cls,'IsAnyClass')~=true or pathOf(cls)~=path then return false end
        local a=get(lib,'BeginDeferredActorSpawnFromClass',r.world,cls,transform,1,nil,1)
        -- The deferred actor already exists even when the first reflection read fails.
        row.helper=a;row.helperClass=cls;row.helperName=pathOf(a)
        if not row.helperName then
            row.helperShort=text(get(a,'GetFName'));row.helperKey=U.key(a)
            return false
        end
        if not U.inWorld(a,r.world) or not same(get(a,'GetClass'),cls) then return false end
        row.classVerified=true
        if path==SPAWNER then
            local id=PREFIX..U.key(a)
            if not set(a,'InitialSpawn',false) or not set(a,'ShouldSpawn',false)
                or not set(a,'AutoRespawnOnDead',false) or not set(a,'SetShouldNotSpawnAfterDead',false)
                or not pcall(function()a.SpawnerID=fname(id)end) or text(U.field(a,'SpawnerID'))~=id then return false end
        end
        if not call(a,'SetActorEnableCollision',false) then return false end
        if not call(lib,'FinishSpawningActor',a,transform,1) or not owned(a,row.helperName,r) then return false end
        call(a,'SetActorHiddenInGame',true)
        call(a,'SetActorEnableCollision',false)
        if get(a,'GetActorEnableCollision')~=false then return false end
        if path==DOMAIN then
            if not call(a,'SetEnabled',false) or U.field(a,'bEnabled')~=false then return false end
        elseif U.field(a,'InitialSpawn')~=false or U.field(a,'ShouldSpawn')~=false or U.field(a,'AutoRespawnOnDead')~=false
            or U.field(a,'SetShouldNotSpawnAfterDead')~=false or U.valid(U.field(a,'SpawnedAI')) then return false end
        return true
    end
    local function domainMembers(r,pass)
        if r.revision==revision then return true end
        if cooling(r.domainFailedAt,.5) then return false end
        refreshRoster()
        if not owned(r.site.helper,r.site.helperName,r) then
            r.domainFailedAt=retryClock() or os.clock();return false
        end
        -- One game-thread pass can project the same roster for multiple private domains.
        pass=pass or {}
        if pass.revision~=revision or pass.worldKey~=r.worldKey then
            pass.targets={};pass.revision=revision;pass.worldKey=r.worldKey
            for _,a in ipairs(fieldActors)do
                if U.inWorld(a,r.world) then pass.targets[#pass.targets+1]=a end
            end
        end
        local targets=pass.targets
        local d=r.site.helper
        if not sameList(U.array(U.field(d,'ActorsInMobDomain')),targets) then
            local ok=pcall(function()
                local arr=d.ActorsInMobDomain
                if U.kind(arr)=='TArray' then arr:Empty()end
                d.ActorsInMobDomain=targets
            end)
            if not ok or not sameList(U.array(U.field(d,'ActorsInMobDomain')),targets) then
                r.domainFailedAt=retryClock() or os.clock();return false
            end
        end
        r.revision=pass.revision;r.domainFailedAt=nil;return r.revision==revision
    end
    local function privateGroup(r)
        local d=r.site.helper
        local group=nativeGroup(d,'DefaultGroup')
        if not same(get(group,'GetOuter'),d) then
            local cls=asset(GROUP)
            if get(cls,'IsAnyClass')~=true then return false end
            local ok,value=pcall(o.construct or StaticConstructObject,cls,d,fname('PG_HuaShan_Group'),0x40)
            if not ok or not same(get(value,'GetOuter'),d) then return false end
            group=value
            local map=U.struct(U.field(d,'MobDomainConfig'),'MobGroups')
            local stored=pcall(function()map:Add(fname('PG_HuaShan'),group)end)
            if not stored or not same(nativeGroup(d,'PG_HuaShan'),group)then return false end
        end
        if pathOf(get(group,'GetClass'))~=GROUP or not empty(group,'Scripts') or not empty(group,'Members')
            or not empty(group,'RuntimeMembers') then return false end
        local ref=reference(d)
        if not ref then return false end
        if not same(U.field(group,'MobDomain'),d) then
            if not import(group,'MobDomain','InterfaceProperty',ref) or not same(U.field(group,'MobDomain'),d)then return false end
        end
        if not same(resolveSoft(group,'MobDomainActor','Conv_SoftObjectReferenceToObject'),d) then
            if not import(group,'MobDomainActor','SoftObjectProperty',ref)
                or not same(resolveSoft(group,'MobDomainActor','Conv_SoftObjectReferenceToObject'),d) then return false end
        end
        if not same(get(group,'GetOuter'),d) or not same(U.field(group,'MobDomain'),d) then return false end
        r.group=group
        return domainMembers(r)
    end
    local function detach(o,field,original)
        local value,read=U.field(o,field)
        return read and (not same(value,original) or setObject(o,field,nil))
    end
    local function confirmedGone(a)
        local ok,valid=pcall(function()return a:IsValid()end)
        return ok and valid==false
    end
    local function unbind(row,r)
        if not row.binding or row.unbound then return true end
        local a=row.actor
        if not U.valid(a) then return confirmedGone(a) end
        local name=pathOf(a)
        if not name then return false end
        if name~=row.name then return true end
        if not U.inWorld(a,r.world) or not detach(a,'Spawner',row.helper) or not detach(a,'MobGroup',r.group) then return false end
        if row.marked then
            local asc=U.field(a,'AbilitySystemComponent')
            local n=get(asc,'GetGameplayTagCount',tag(TROOP))
            if type(n)~='number' then return false end
            if n>0 then
                call(asset(UTILS),'RemoveLooseGameplayTag',a,tag(TROOP),false)
                if get(asc,'GetGameplayTagCount',tag(TROOP))~=n-1 then return false end
            end
            row.marked=nil
        end
        row.unbound=true
        return true
    end
    local function remove(row,r)
        local a=row.helper
        if a==nil then return true end
        if not U.valid(a) then return confirmedGone(a) end
        if not U.inWorld(a,r.world) then return false end
        if row.helperName then
            local name=pathOf(a)
            if not name then return false end
            if name~=row.helperName then return true end
        else
            local name=text(get(a,'GetFName'))
            local key=U.key(a)
            if not name or not key or not row.helperShort or not row.helperKey then return false end
            if name~=row.helperShort or key~=row.helperKey then return true end
        end
        if not row.classVerified then
            local cls=get(a,'GetClass')
            if not U.valid(cls) then return false end
            if not same(cls,row.helperClass) then return true end
        end
        if get(a,'IsActorBeingDestroyed')==true then return true end
        if row.binding and not detach(a,'SpawnedAI',row.actor) then return false end
        call(a,'K2_DestroyActor')
        if U.valid(a) then return get(a,'IsActorBeingDestroyed')==true end
        return confirmedGone(a)
    end
    local function release(r,current,force)
        r.retiring=true
        current=current or U.key(o.world())
        if not current then return false end
        local done=true
        if current==r.worldKey then
            if not force and cooling(r.cleanupAt,1) then return false end
            r.cleanupAt=retryClock() or os.clock()
            for _,row in ipairs(r.rows)do
                if not unbind(row,r) then done=false end
            end
            if not done then return false end
            for _,row in ipairs(r.rows)do
                if row.helper then
                    if remove(row,r) then row.helper=nil;row.binding=nil else done=false end
                end
            end
            if not done or not remove(r.site,r) then return false end
        end
        for _,row in ipairs(r.rows)do
            if owners[row.key]==r then owners[row.key]=nil end
            if casts[row.key] and casts[row.key].group==r then casts[row.key]=nil end
        end
        groups[r.token]=nil
        return true
    end
    function self:roster(rows)
        revision=revision+1;latestRows=rows
        if not next(groups) then return end
        local present,currentOwners={},{}
        for _,row in ipairs(rows)do
            if row.formationGroup then
                present[row.formationGroup]=true
                local r=groups[row.formationGroup];local k=r and U.key(row.actor)
                if k and owners[k]==r then currentOwners[k]=r end
            end
        end
        owners=currentOwners
        for token,r in pairs(groups)do if not present[token] and not r.building then release(r) end end
    end
    function self:abort(token)
        local r=groups[token]
        if not r then return true end
        -- Arena rollback can still reclaim its staged fighters if the first immediate cleanup was refused.
        local first=not r.abortRequested
        r.abortRequested=true
        return release(r,nil,first)
    end
    local function troopTag(row)
        local asc=U.field(row.actor,'AbilitySystemComponent')
        local before=get(asc,'GetGameplayTagCount',tag(TROOP))
        if type(before)~='number' then return false end
        if before>0 then return true end
        if not call(asset(UTILS),'AddLooseGameplayTag',row.actor,tag(TROOP),false) then return false end
        local after=get(asc,'GetGameplayTagCount',tag(TROOP))
        if after==1 then row.marked=true;return true end
        return false
    end
    local function nativeRoster(r)
        local list=U.array(get(r.group,'GetMemberInterfaces'))
        if not list or #list~=#r.rows then return false end
        local allowed,expected={},{}
        for _,row in ipairs(r.rows)do
            local key=U.key(row.helper)
            if not key then return false end
            allowed[key],allowed[row.key]=row,row
        end
        for _,member in ipairs(list)do
            local row=allowed[U.key(member)]
            if not row or expected[row] or (not same(member,row.actor) and not same(get(member,'GetPawn'),row.actor)) then return false end
            expected[row]=true
        end
        return true
    end
    local function populate(r)
        if not helper(r,r.site,DOMAIN,r.rows[1].transform) or not privateGroup(r) then return false,'专属战斗区域或原生分组未读回' end
        local refs={}
        for i,row in ipairs(r.rows)do
            if not helper(r,row,SPAWNER,row.transform) then return false,'第 '..i..' 个出生器未就绪' end
            local sp=row.helper;local cls=get(row.actor,'GetClass')
            local ref=reference(cls)
            if not ref or not import(sp,'Class','SoftClassProperty',ref)
                or not same(resolveSoft(sp,'Class','Conv_SoftClassReferenceToClass'),cls) then return false,'出生器角色类型未读回' end
            refs[i]=reference(sp)
            if not refs[i] then return false,'出生器路径未读回' end
        end
        for _,row in ipairs(r.rows)do
            row.binding=true
            if not owned(row.actor,row.name,r) or not owned(row.helper,row.helperName,r)
                or not setObject(row.helper,'MobGroup',r.group) or not setObject(row.helper,'SpawnedAI',row.actor)
                or not same(get(row.helper,'GetPawn'),row.actor) then return false,'出生器没有读回本组队员' end
        end
        if not import(r.group,'Members','ArrayProperty','('..table.concat(refs,',')..')') or not nativeRoster(r) then
            return false,'七个原生成员未全部读回'
        end
        for _,row in ipairs(r.rows)do
            if not setObject(row.actor,'Spawner',row.helper) or not setObject(row.actor,'MobGroup',r.group)
                or not same(get(row.actor,'GetAISpawner'),row.helper)
                or not same(get(row.actor,'GetMobGroup'),r.group) then return false,'角色与原生出生器未双向绑定' end
            if r.blue then troopTag(row) end
        end
        return true
    end
    function self:prepare(token,batch,world,team)
        if not alive or not token or groups[token] or #batch~=7 or (team~='blue' and team~='red') or not same(world,o.world()) then
            return false,'剑阵队伍、世界或人数未确认'
        end
        local first=batch[1];local id=U.className(first.actor)
        local blue=id==BLUE..'_C'
        if not blue and id~=RED..'_C' then return false,'剑阵主将未确认' end
        local r={world=world,worldKey=U.key(world),token=token,team=team,blue=blue,site={},rows={},building=true}
        refreshRoster()
        local seen={}
        for i,item in ipairs(batch)do
            local expected=i==1 and (blue and BLUE or RED) or (blue and 'BP_Monster_HuaShan_White' or 'BP_Monster_HuaShan_RedTroop_Soldier')
            local a=item.actor;local k=U.key(a);local name=pathOf(a)
            local sp,spRead=U.field(a,'Spawner');local gr,groupRead=U.field(a,'MobGroup')
            if not k or not name or seen[k] or owners[k] or not U.inWorld(a,world) or sides[k]~=team
                or item.path~=ROOT..expected..'.'..expected..'_C' or pathOf(get(a,'GetClass'))~=item.path
                or (i>1 and not same(item.parent,first.actor)) or not spRead or not groupRead or U.valid(sp) or U.valid(gr) then
                return false,'剑阵队员归属未确认'
            end
            seen[k]=true
            r.rows[i]={actor=a,key=k,name=name,transform=item.transform}
        end
        groups[token]=r
        for _,row in ipairs(r.rows)do owners[row.key]=r end
        local called,ok,why=pcall(populate,r)
        r.building=false
        if not called or not ok then
            local err=tostring(why or ok);local clean=release(r)
            say('建组未完成 '..err..'；自有物件清理读回='..tostring(clean));return false,err
        end
        say('原生小队在登场前就绪 '..r.rows[1].name..' 阵营='..team..' 出生器及双向队员读回=7/7')
        return true
    end
    local function center(r,verify)
        if not r.blue then return true end
        local a=r.rows[1].actor;local bb=U.field(o.aiOf(a),'BlackboardComponent')
        local v=r.origin
        local key=U.key(bb)
        if not key or not v then return false end
        if not verify and r.center==key then return true end
        local lib=asset(AI)
        local function matches()
            local back=point(get(lib,'GetValueAsVectorByTag',bb,tag(CENTER)))
            return back and math.abs(back.X-v.X)<1 and math.abs(back.Y-v.Y)<1 and math.abs(back.Z-v.Z)<1
        end
        if matches() or (call(lib,'SetValueAsVectorByTag',bb,tag(CENTER),v) and matches()) then r.center=key;return true end
        r.center=nil;return false
    end
    function self:ready(token)
        local r=groups[token]
        if not r or r.retiring or not here(r) then return false,'原生编队已离场' end
        if not nativeRoster(r) then return false,'登场后七个原生成员未全部读回' end
        for _,row in ipairs(r.rows)do
            if not owned(row.actor,row.name,r) or not same(get(row.actor,'GetMobGroup'),r.group)
                or not same(get(row.helper,'GetPawn'),row.actor) then return false,'登场后队伍归属变化' end
            if r.blue and not troopTag(row) then return false,'原版白衣阵标签未读回' end
        end
        r.origin=point(o.location(r.rows[1].actor)) or point(r.rows[1].transform.Translation)
        center(r);r.ready=true
        return true
    end
    local function livingRoster(r)
        local expected={}
        for _,row in ipairs(r.rows)do
            if owned(row.actor,row.name,r) and (o.hp(row.actor) or 0)>0 then expected[#expected+1]=row.actor end
        end
        local members=U.array(get(r.group,'GetAliveMemberPawns'))
        return sameList(members,expected),members and #members,#expected
    end
    function self:activated(token)
        local r=groups[token]
        if not r or not r.ready or r.retiring or not here(r) then return false,'分组已离场' end
        center(r,true)
        local verified,n,wanted=livingRoster(r)
        if not verified or wanted~=7 then
            r.livingChecks=0
            say('登场时原生存活名单='..tostring(n)..'/7；七个出生器已登记，等待游戏更新')
            return true,'七个剑阵队员已登记，原生存活名单正在更新'
        end
        say('原生存活名单读回=7/7 主将='..r.rows[1].name)
        return true
    end
    function self:beforeAttack(actor,foe)
        if not next(groups) then return true end
        local r=groupOf(actor)
        if not r then return true end
        if not r.ready or r.retiring or not here(r) or not domainMembers(r) then return false end
        center(r)
        if same(actor,r.rows[1].actor) and sides[U.key(foe)] and sides[U.key(foe)]~=r.team then r.entering=true end
        return true
    end
    local opening
    function self:assigned(actor,foe)
        if not next(groups) then return end
        local r=groupOf(actor)
        if r and r.ready and same(r.rows[1].actor,actor) and sides[U.key(foe)]~=r.team
            and sides[U.key(foe)] and not r.encounter then
            r.encounter=clock()
            local peers=U.array(get(r.rows[1].helper,'GetOtherAliveMembersInGroup'))
            say('首次交战 '..r.rows[1].name..' 原生可用队友='..tostring(peers and #peers))
            if not r.blue and r.encounter then opening(r,r.encounter,foe) end
        end
    end
    local emptyActor
    function self:localPlayerLookup(ability)
        if not next(groups) then return end
        local actor=get(ability,'GetAvatarActorFromActorInfo');local r=groupOf(actor)
        if not r or not r.ready or not U.inWorld(ability,r.world) then return end
        if emptyActor==nil then
            local ok,v=pcall(o.invalid or CreateInvalidObject)
            if ok and v~=nil and not U.valid(v) then emptyActor=v end
        end
        return emptyActor
    end
    local function running(a)
        local controller=get(a,'GetController')
        return U.valid(controller) and get(asset(AI),'GetRunningBehaviorTree',controller) or nil
    end
    function self:started(ability,name)
        if not next(groups) then return end
        local actor=get(ability,'GetAvatarActorFromActorInfo');local r=groupOf(actor)
        local key=U.key(actor)
        if not r or not r.ready or not key then return end
        if name=='GA_HuaShan_Story_Intro_C' then
            if r.blue or not same(r.rows[1].actor,actor) then return end
            r.opened=true;r.introSeen=true
        elseif name~='GA_HuaShan_Troop_Healing_C' and name~='GA_HuaShan_Troop_Resurrection_C' then
            return
        end
        casts[key]={group=r,ability=ability}
        if (r.castLogs or 0)<8 then
            r.castLogs=(r.castLogs or 0)+1
            say('原版技能起手 '..name..' 施术者='..tostring(pathOf(actor))..' 本组主将='..r.rows[1].name)
        end
    end
    function self:supporting(key)
        local cast=casts[key]
        if not cast then return false end
        local r,ability=cast.group,cast.ability
        if owners[key]==r and not r.retiring and here(r) and U.field(ability,'bIsActive')==true
            and U.key(get(ability,'GetAvatarActorFromActorInfo'))==key then return true end
        casts[key]=nil;return false
    end
    function self:supportingActor(actor)
        return next(casts)~=nil and self:supporting(U.key(actor))
    end
    function self:observe(task,actor)
        local r=groupOf(actor)
        if not r or not same(r.rows[1].actor,actor) then return end
        local tree=pathOf(U.field(task,'TreeAsset'))
        if not tree or not tree:find(ROOT..'BehaviorTree/',1,true) then return end
        local peers=U.array(U.field(task,'ActorsToAssign'));local own=0
        for _,a in ipairs(peers or {}) do if owners[U.key(a)]==r then own=own+1 end end
        if r.blue and tree==INIT and (r.entering or r.encounter) and own>0 and own==#peers then r.opened=true end
        if not r.seen then r.seen={} end
        if r.seen[tree]==own or (r.reports or 0)>=24 then return end
        r.seen[tree]=own;r.reports=(r.reports or 0)+1
        say('原生派阵 '..r.rows[1].name..' 树='..tree:match('[^%.]+$')..' 本组候选读回='..own..'/'..tostring(peers and #peers))
        if peers and own>0 and #peers==own then
            local wanted,branches={},{}
            local map=U.field(task,'AssignToTransformAndBehaviorTree')
            local function branch(value)
                local path=pathOf(U.unwrap(value))
                if path then branches[path]=true end
            end
            if U.kind(map)=='TMap' then pcall(function()map:ForEach(function(_,v)branch(v)end)end)
            elseif type(map)=='table' then for _,value in pairs(map)do branch(value)end end
            for _,a in ipairs(peers)do wanted[#wanted+1]={actor=a,hp=o.hp(a)} end
            r.receipt={tree=tree,branches=branches,peers=wanted,leaderHP=o.hp(actor),at=clock()}
        end
    end
    local function receipts(r,now)
        local trace=r.receipt
        if not trace or not trace.at or now-trace.at<0.5 then return end
        local count,changes=0,{}
        for _,row in ipairs(trace.peers)do
            local a=row.actor
            if owners[U.key(a)]==r then
                local tree=pathOf(running(a))
                if tree and trace.branches[tree] then count=count+1 end
                local hp=o.hp(a)
                if type(hp)=='number' and hp~=row.hp then changes[#changes+1]=tostring(U.key(a))..' '..tostring(row.hp)..'→'..hp end
            end
        end
        say('派阵后采样 '..trace.tree:match('[^%.]+$')..' 当次指定子树读回='..tostring(next(trace.branches) and count or '未知')..'/'..#trace.peers
            ..' 主将HP='..tostring(trace.leaderHP)..'→'..tostring(o.hp(r.rows[1].actor))..' 队员HP变化='..table.concat(changes,','))
        r.receipt=nil
    end
    function self:lifeChanged(token,actor,living)
        local r=groups[token]
        if not r or not r.blue or not r.ready or r.retiring or not here(r) then return end
        local key=U.key(actor)
        for i=2,#r.rows do
            local row=r.rows[i]
            if row.key==key and owned(actor,row.name,r) then
                if living then row.deathSent=nil end
                if not r.deaths then r.deaths={} end
                r.deaths[key]=not living and not row.deathSent and row or nil
                break
            end
        end
    end
    local function memberDeaths(r,now)
        if not r.deaths or not next(r.deaths) or (r.nextDeathCheck and now<r.nextDeathCheck) then return end
        r.nextDeathCheck=now+1
        local leader=r.rows[1].actor
        if not owned(leader,r.rows[1].name,r) or (o.hp(leader) or 0)<=0 then r.deaths=nil;return end
        for key,row in pairs(r.deaths)do
            local a,sp=row.actor,row.helper
            if not owned(a,row.name,r) or not owned(sp,row.helperName,r) or not same(U.field(sp,'SpawnedAI'),a) then
                r.deaths[key]=nil
            else
                local hp=o.hp(a)
                if type(hp)=='number' and hp>0 then row.deathSent=nil;r.deaths[key]=nil
                elseif type(hp)=='number' and hp<=0 and not row.deathSent
                    and (get(U.field(a,'AbilitySystemComponent'),'GetGameplayTagCount',tag('CharacterState.Dead')) or 0)>0 then
                    -- Placed spawners normally broadcast from their save/respawn listener. The private one is quiet.
                    if U.valid(U.field(sp,'WaitSpawnedAIDeadAsyncAction')) then row.deathSent=true
                    else
                        local ai=o.aiOf(leader)
                        for _,script in ipairs(U.array(U.field(ai,'SpawnedAIScripts')) or {})do
                            if U.className(script)==DEATH_SCRIPT and same(U.field(script,'Pawn'),leader)
                                and same(U.field(leader,'MobGroup'),r.group) then
                                row.deathSent=true
                                local called=call(script,'OnGroupMemberDead',sp)
                                say('白衣队员阵亡通知 '..row.name..' 原版处理调用='..tostring(called))
                                break
                            end
                        end
                    end
                end
                if row.deathSent then r.deaths[key]=nil end
            end
        end
    end
    opening=function(r,now,assignedFoe)
        if r.opened or not r.encounter then return end
        if now<r.encounter or now-r.encounter>12 then
            r.opened=true;say('开场窗口结束 '..r.rows[1].name..' 未读到可用开场');return
        end
        if now<(r.nextOpen or 0) then return end
        r.nextOpen=now+0.5
        local a=r.rows[1].actor
        if not owned(a,r.rows[1].name,r) or (o.hp(a) or 0)<=0 then return end
        local foe=assignedFoe or o.opponent(a)
        if not U.valid(foe) or not sides[U.key(foe)] or sides[U.key(foe)]==r.team or (o.hp(foe) or 0)<=0 then return end
        if r.blue and pathOf(running(a))==INIT then r.opened=true;return end
        if r.blue and now-r.encounter<0.5 then return end
        if r.blue then
            for i=2,#r.rows do
                local tree=pathOf(running(r.rows[i].actor))
                if tree and tree:find(ROOT..'BehaviorTree/Troop/Init/BT_HuaShan_Troop_Init_',1,true)==1 then r.opened=true;return end
            end
        end
        if o.busy(a) then return end
        if r.blue then
            local tree=asset(INIT,true);local lib=asset(GAS)
            if not U.valid(tree) or not U.valid(lib) then return end
            local event=tag('GameplayEvent.AI.EventTransition.CustomState')
            r.opened=true
            local sent=call(lib,'SendGameplayEventToActor',a,event,{EventTag=event,Instigator=a,OptionalObject=tree})
            say('大师兄起手 '..r.rows[1].name..' 原版树调用='..tostring(sent)..' 当前树相符='..tostring(same(running(a),tree)))
        else
            local asc=U.field(a,'AbilitySystemComponent');local cls=asset(INTRO,true)
            local specs=U.array(U.struct(U.field(asc,'ActivatableAbilities'),'Items'))
            if not specs or not U.valid(cls) or get(cls,'IsAnyClass')~=true then return end
            local spec
            for _,row in ipairs(specs)do if same(get(U.struct(row,'Ability'),'GetClass'),cls) then spec=row;break end end
            r.opened=true
            local accepted
            local refused=false
            if spec then
                local count=U.struct(spec,'ActiveCount')
                if type(count)=='number' then
                    if count>0 then accepted=true
                    else
                        local ok,result=call(asc,'TryActivateAbilityByClass',cls,false)
                        accepted=ok and result==true;refused=ok and result==false
                    end
                end
            else
                local handle=U.struct(get(asc,'K2_GiveAbilityAndActivateOnce',cls,1,-1),'Handle')
                accepted=type(handle)=='number' and handle>0
                refused=type(handle)=='number' and handle<=0
            end
            if refused and not r.introSeen and not r.introRetried then r.opened=false;r.introRetried=true;r.nextOpen=now+1 end
            say('阿瑾爆脸转化 '..r.rows[1].name..' 原生技能受理='..tostring(accepted))
        end
    end
    function self:tick()
        if not alive or not next(groups) then return end
        local current=U.key(o.world());if not current then return end
        local now=clock()
        for key in pairs(casts)do self:supporting(key)end
        local pass
        for _,r in pairs(groups)do
            if not r.building then
                if r.retiring or r.worldKey~=current then release(r,current)
                elseif r.ready and type(now)=='number' then
                    if r.livingChecks and now>=(r.nextLivingCheck or 0) then
                        local verified,n,wanted=livingRoster(r)
                        r.livingChecks=r.livingChecks+1;r.nextLivingCheck=now+1
                        if verified or r.livingChecks>=6 then
                            say('登场后原生存活复核 '..r.rows[1].name..' 读回='..tostring(n)..' 当前正HP='..wanted..' 相符='..tostring(verified))
                            r.livingChecks=nil
                        end
                    end
                    if r.revision~=revision then pass=pass or {};domainMembers(r,pass)end
                    opening(r,now);memberDeaths(r,now);receipts(r,now)
                end
            end
        end
    end
    function self:silence(gameThread)
        alive=false
        if not next(groups) then return end
        local function retire()
            for _,r in pairs(groups)do release(r,nil,true)end
        end
        if gameThread then retire()
        elseif type(o.defer or ExecuteInGameThread)=='function' then pcall(o.defer or ExecuteInGameThread,retire) end
    end
    return self
end
return Party
