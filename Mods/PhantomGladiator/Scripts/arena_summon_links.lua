-- Only accept a native summon list/avatar link or an exact Owner/Instigator link.
-- No proximity, name, class-family, or level-wide faction guesses.
-- A summon passive's SummonCombatTargetMode (a name variable some passives have, read by the game's summon combat
-- code) says whom its summons fight: InheritedHatred the summoner's foe; EncounterSummons the summoner's other
-- summons (SummonCombatTargetClasses) and Summoner the summoner itself. 冷荼's _NPC summons are of the last two
-- kinds: the 彭猛, 华山, 风雪刀客, 舞狮 and 雷当 who come to help against her; so is 梦华's 虚空 (GA_MengHua_SummonPassive,
-- its faction overridden by GE_SummonFactionOverride). Those links carry opposing=true; main.lua takes them out.
-- A summon still marked pending in its passive's list can be found first by its Owner/Instigator; that link takes
-- the mode of the passive listing it, when the passive belongs to the same summoner.
local U=require('ue_observe')
local Links={}
local OPPOSING={EncounterSummons=true,Summoner=true}
local function text(value)
    if type(value)=='string' then return value end
    if value==nil or type(value)=='number' or type(value)=='boolean' then return nil end
    local ok,result=pcall(function()return value:ToString()end)
    return ok and type(result)=='string' and result or nil
end
function Links.new(options)
    options=options or {};local self={lastSummary=nil}
    local findAll=options.findAll or FindAllOf
    local clock=options.clock or os.clock
    local previousWorld,previousRoster,lastSweep
    -- onOwnedPassive: called with each summon passive of a unit in members.
    function self:scan(members,onOwnedPassive,background)
        local owned,links={},{}
        -- A single sweep is cheaper than walking many owners' component trees in a large crowd.
        local companionsOnly=background==true and options.localNPC~=nil and options.idleOwner~=nil and #members<=16
        for _,unit in ipairs(members) do
            local key=U.key(unit.actor)
            if key then owned[key]=unit.actor end
            if unit.team~='companion' or unit.stand or unit.aid or unit.reserve then companionsOnly=false end
        end
        if not next(owned) then previousRoster=nil;return {} end
        local world=options.getWorld()
        local worldKey=U.key(world)
        if not worldKey then previousRoster=nil;return {} end
        local stats={abilities=0,owned=0,rows=0,errors=0,conflicts=0}
        local listed={}
        local function candidate(child,ck,pk,proof,rank,localOnly)
            if not ck or not pk or ck==pk or owned[ck] or not owned[pk] then return end
            local prior=links[ck]
            if prior and prior.rank>rank then return end
            if prior and prior.rank==rank and prior.conflict then return end
            if not U.inWorld(child,world) or not U.inWorld(owned[pk],world) then return end
            local path=U.npcPath(child)
            if not path or (rank==1 and options.allowNPC and not options.allowNPC(child))
                or (localOnly and not options.localNPC(child)) then return end
            if prior and prior.rank==rank and prior.parentKey~=pk then prior.conflict=true;stats.conflicts=stats.conflicts+1;return end
            links[ck]={actor=child,parent=owned[pk],parentKey=pk,class_path=path,evidence=proof,rank=rank}
        end
        local found,abilities=pcall(findAll,'GA_SummonPassive_C')
        if not found then stats.errors=stats.errors+1;abilities={} end
        for _,ability in ipairs(U.array(abilities or {}) or {}) do
            if U.valid(ability) then
                stats.abilities=stats.abilities+1
                local ok,avatar=pcall(function() return ability:GetAvatarActorFromActorInfo() end)
                local ownerKey=ok and U.key(avatar) or nil
                if ownerKey and owned[ownerKey] then
                    stats.owned=stats.owned+1
                    if onOwnedPassive and not pcall(onOwnedPassive,ability) then stats.errors=stats.errors+1 end
                    local values,read=U.field(ability,'SpawnedSummonInstances')
                    local rows=read and U.array(values) or nil
                    if not rows then stats.errors=stats.errors+1 end
                    local mode=rows and #rows>0 and text((U.field(ability,'SummonCombatTargetMode'))) or nil
                    if mode=='None' or mode=='' then mode=nil end
                    for _,row in ipairs(rows or {}) do
                        if U.valid(ability) then
                            stats.rows=stats.rows+1
                            local pawn=U.struct(row,'Pawn');local pending=U.struct(row,'bPawnPending')
                            local pawnKey=U.key(pawn)
                            if pawnKey and mode then
                                local parents=listed[pawnKey] or {};listed[pawnKey]=parents
                                local before=parents[ownerKey]
                                if before==nil then parents[ownerKey]=mode
                                elseif before~=false and before~=mode then
                                    if (OPPOSING[before]==true)==(OPPOSING[mode]==true) then
                                        parents[ownerKey]=before<mode and before or mode
                                    else parents[ownerKey]=false end
                                end
                            end
                            if pending==false then candidate(pawn,pawnKey,ownerKey,'GA_SummonPassive.Avatar + SpawnedSummonInstances.Pawn',2) end
                        end
                    end
                end
            end
        end
        local function inspect(npc,localOnly)
            local key=U.key(npc)
            if key and not owned[key] then
                local ok,owner,instigator=pcall(function()return npc.Owner,npc.Instigator end)
                if ok then
                    local pk,ik=U.key(U.unwrap(owner)),U.key(U.unwrap(instigator))
                    if owned[pk] then candidate(npc,key,pk,'Actor.Owner',1,localOnly) end
                    if ik~=pk and owned[ik] then candidate(npc,key,ik,'Actor.Instigator',1,localOnly) end
                else stats.errors=stats.errors+1 end
            end
        end
        local now=clock()
        local roster={}
        if companionsOnly then
            for k,actor in pairs(owned)do
                local ok,name=pcall(function()return actor:GetFullName()end)
                if not ok or type(name)~='string' then companionsOnly=false;break end
                roster[#roster+1]=k..'='..name
            end
            table.sort(roster)
        end
        local signature=companionsOnly and table.concat(roster,'|') or nil
        local localOnly=signature and signature==previousRoster and worldKey==previousWorld and lastSweep
            and now>=lastSweep and now-lastSweep<2 and stats.owned==0 and stats.errors==0
        if localOnly then
            for _,actor in pairs(owned)do
                local ok,idle=pcall(options.idleOwner,actor)
                if not ok or idle~=true then localOnly=false;break end
                local children=U.array(U.field(actor,'Children'))
                if not children then localOnly=false;break end
                for _,child in ipairs(children)do inspect(child,true) end
            end
        end
        if not localOnly then
            local ok,npcs=pcall(options.getNPCs,owned)
            if ok and type(npcs)=='table' then
                for _,npc in ipairs(npcs)do inspect(npc,false) end
                lastSweep=now
            else stats.errors=stats.errors+1;lastSweep=nil end
        end
        previousWorld,previousRoster=worldKey,signature
        local out={}
        for key,entry in pairs(links)do
            local modes=listed[key]
            local mode=modes and modes[entry.parentKey]
            if mode==false then stats.conflicts=stats.conflicts+1
            elseif not entry.conflict then
                entry.mode=mode;entry.opposing=OPPOSING[mode or '']==true
                if mode then entry.evidence=entry.evidence..'；SummonCombatTargetMode='..mode end
                out[#out+1]=entry
            end
        end
        local summary=string.format('abilities=%d owned=%d entries=%d links=%d errors=%d conflicts=%d',stats.abilities,stats.owned,stats.rows,#out,stats.errors,stats.conflicts)
        if summary~=self.lastSummary then
            self.lastSummary=summary
            if options.log then options.log('[SummonLinks] 只读归属核对；读回 '..summary) end
        end
        return out
    end
    return self
end
return Links
