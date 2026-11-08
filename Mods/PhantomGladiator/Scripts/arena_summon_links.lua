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
    -- onOwnedPassive: called with each summon passive of a unit in members.
    function self:scan(members,onOwnedPassive)
        local owned,links={},{}
        for _,unit in ipairs(members) do local key=U.key(unit.actor);if key then owned[key]=unit.actor end end
        if not next(owned) then return {} end
        local world=options.getWorld()
        if not U.valid(world) then return {} end
        local stats={abilities=0,owned=0,rows=0,errors=0,conflicts=0}
        local listed={}
        local function candidate(child,parent,proof,rank,mode)
            local ck,pk=U.key(child),U.key(parent)
            if not ck or not pk or ck==pk or owned[ck] or not owned[pk] or not U.inWorld(child,world) or not U.inWorld(parent,world) then return end
            local path=U.npcPath(child);if not path then return end
            local prior=links[ck]
            if prior and prior.rank>rank then return end
            if prior and prior.rank==rank and prior.parentKey~=pk then prior.conflict=true;stats.conflicts=stats.conflicts+1;return end
            links[ck]={actor=child,parent=owned[pk],parentKey=pk,class_path=path,evidence=proof..(mode and ('；SummonCombatTargetMode='..mode) or ''),
                rank=rank,mode=mode,opposing=OPPOSING[mode or '']==true}
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
                            if pawnKey and mode then listed[pawnKey]={mode=mode,parentKey=ownerKey} end
                            if pending==false then candidate(pawn,avatar,'GA_SummonPassive.Avatar + SpawnedSummonInstances.Pawn',2,mode) end
                        end
                    end
                end
            end
        end
        local ok,npcs=pcall(options.getNPCs)
        if not ok then stats.errors=stats.errors+1;npcs={} end
        for _,npc in ipairs(npcs or {}) do
            local key=U.key(npc)
            if key and not owned[key] then
                local entry=listed[key]
                local function modeFor(parent)return entry and entry.parentKey==U.key(parent) and entry.mode or nil end
                local owner=U.field(npc,'Owner');candidate(npc,owner,'Actor.Owner',1,modeFor(owner))
                local instigator=U.field(npc,'Instigator');candidate(npc,instigator,'Actor.Instigator',1,modeFor(instigator))
            end
        end
        local out={}
        for _,entry in pairs(links) do if not entry.conflict then out[#out+1]=entry end end
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
