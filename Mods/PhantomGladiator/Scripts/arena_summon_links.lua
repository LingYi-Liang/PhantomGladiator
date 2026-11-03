-- Only accept a native summon list/avatar link or an exact Owner/Instigator link.
-- No proximity, name, class-family, or level-wide faction guesses.
local U=require('ue_observe')
local Links={}
function Links.new(options)
    options=options or {};local self={lastSummary=nil}
    local findAll=options.findAll or FindAllOf
    function self:scan(members)
        local owned,links={},{}
        for _,unit in ipairs(members) do local key=U.key(unit.actor);if key then owned[key]=unit.actor end end
        if not next(owned) then return {} end
        local world=options.getWorld()
        if not U.valid(world) then return {} end
        local stats={abilities=0,owned=0,rows=0,errors=0,conflicts=0}
        local function candidate(child,parent,proof,rank)
            local ck,pk=U.key(child),U.key(parent)
            if not ck or not pk or ck==pk or owned[ck] or not owned[pk] or not U.inWorld(child,world) or not U.inWorld(parent,world) then return end
            local path=U.npcPath(child);if not path then return end
            local prior=links[ck]
            if prior and prior.rank>rank then return end
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
                    local values,read=U.field(ability,'SpawnedSummonInstances')
                    local rows=read and U.array(values) or nil
                    if not rows then stats.errors=stats.errors+1 end
                    for _,row in ipairs(rows or {}) do
                        if U.valid(ability) then
                            stats.rows=stats.rows+1
                            local pawn=U.struct(row,'Pawn');local pending=U.struct(row,'bPawnPending')
                            if pending==false then candidate(pawn,avatar,'GA_SummonPassive.Avatar + SpawnedSummonInstances.Pawn',2) end
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
                local owner=U.field(npc,'Owner');candidate(npc,owner,'Actor.Owner',1)
                local instigator=U.field(npc,'Instigator');candidate(npc,instigator,'Actor.Instigator',1)
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
