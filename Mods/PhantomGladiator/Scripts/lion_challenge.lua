-- Ownership for the native lion-head phase. Only the final cub's completed
-- execution earns a duel with its own summoner for the rest of this pole phase.
local U=require('ue_observe')
local Wave={
    BOSS='/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_LionDancer_P2.BP_Monster_LionDancer_P2_C',
    CUB='/PBZCombatAsset/ActorData/Mobs/DaTouWaWa/BP_Monster_DaTouWaWa_HouHouHou.BP_Monster_DaTouWaWa_HouHouHou_C',
    ON_POLE='CharacterState.AbilityState.LionDancer.OnPole',LAST='CharacterType.HouHouHou.LastOne'
}
local PASSIVE='GA_SummonPassive_LionDancer_P2_C'
local PASSIVE_NAME='BlueprintGeneratedClass /PBZCombatAsset/ActorData/Mobs/LionDancer_P2/Ability/GA_SummonPassive_LionDancer_P2.GA_SummonPassive_LionDancer_P2_C'
local function get(object,method,...)
    if not U.valid(object) then return end
    local ok,value=pcall(function(o,k,...)return o[k](o,...)end,object,method,...)
    if ok then return U.unwrap(value) end
end
function Wave.new(options)
    local self={}
    local sources,cubs,teams,heads,byTeam={},{},{},{},{}
    local world
    local fieldSources,fieldCubs,fieldTracks,fieldReceipts={},{},{},{}
    local fieldWorld,fieldNext=nil,0
    local clock=options.clock or os.clock
    local findAll=options.findAll or FindAllOf
    local function alive(actor)
        local hp=U.valid(actor) and options.hp(actor)
        return type(hp)=='number' and hp>0
    end
    local function identity(actor)
        if not U.valid(actor) then return end
        local ok,n=pcall(function()return actor:GetFullName()end)
        return ok and n or nil
    end
    local function onPole(actor,w)
        return U.inWorld(actor,w) and alive(actor) and (options.tag(actor,Wave.ON_POLE) or 0)>0
    end
    local function paused()return options.paused and options.paused()==true end
    local function allowed(actor)
        return not options.fieldEnabled or options.fieldEnabled(actor)==true
    end
    local function hostile(actor,target,w)
        return U.inWorld(actor,w) and U.inWorld(target,w) and alive(actor) and alive(target)
            and tonumber(get(U.field(actor,'Faction Component'),'GetFactionRelation',target))==2
    end
    local function syncField(members)
        if not options.companionOpponent or type(findAll)~='function' then return end
        local w=options.world()
        local wk=U.key(w)
        if fieldWorld~=wk then
            fieldSources,fieldCubs,fieldTracks,fieldReceipts={},{},{},{}
            fieldWorld,fieldNext=wk,0
        end
        if paused() then return end
        local now=clock()
        if not wk or type(now)~='number' or now~=now or math.abs(now)==math.huge or now<fieldNext then return end
        fieldNext=now+0.25
        local demands,owned={},{}
        for _,m in ipairs(members)do
            local key=U.key(m.actor)
            if key then owned[key]=true end
            if key and m.team=='companion' and not m.stand and not m.reserve and not m.aid and allowed(m.actor)
                and U.inWorld(m.actor,w) and alive(m.actor) then
                local target=options.companionOpponent(m.actor)
                local path=U.npcPath(target)
                local track=fieldTracks[key]
                local receipt=fieldReceipts[key]
                local kept=track and track.name==identity(m.actor) and (track.head or receipt and now<receipt.expires)
                    and onPole(track.wave.actor,w) and hostile(m.actor,track.wave.actor,w)
                if path==Wave.BOSS or path==Wave.CUB or (not U.valid(target) and kept) then
                    demands[key]={actor=m.actor,target=target,path=path,kept=kept and track or nil}
                end
            end
        end
        if not next(demands) then fieldSources,fieldCubs,fieldTracks,fieldReceipts={},{},{},{};return end

        local fresh,cubs,ambiguous,tracks={},{},{},{}
        local ok,passives=pcall(findAll,PASSIVE)
        -- A known head or active execution can remain valid after the game removes the final summon row.
        for _,d in pairs(demands)do
            local kept=d.kept
            local wave=kept and kept.wave
            if wave and (not U.valid(d.target) or U.key(d.target)==U.key(wave.actor) or wave.cubs[U.key(d.target)]) then
                local key=U.key(wave.actor)
                if not owned[key] then fresh[key]=wave end
            end
        end
        local bosses={}
        for _,ability in ipairs(ok and U.array(passives) or {})do
            if identity(get(ability,'GetClass'))==PASSIVE_NAME and U.field(ability,'bIsActive')==true then
                local boss=get(ability,'GetAvatarActorFromActorInfo')
                local key,name=U.key(boss),identity(boss)
                if key and name and not owned[key] and not bosses[key] and U.npcPath(boss)==Wave.BOSS and onPole(boss,w) then
                    bosses[key]=true
                    local wave=fieldSources[key]
                    if not wave or wave.name~=name or not U.valid(wave.actor) then
                        wave={actor=boss,name=name,field=true,world=w,cubs={}}
                    end
                    wave.cubs={}
                    fresh[key]=wave
                    for _,row in ipairs(U.array(U.field(ability,'SpawnedSummonInstances')) or {})do
                        local cub=U.struct(row,'Pawn')
                        local id=U.key(cub)
                        if id and not owned[id] and U.struct(row,'bPawnPending')==false and U.npcPath(cub)==Wave.CUB
                            and U.inWorld(cub,w) and alive(cub) then
                            if cubs[id] and cubs[id]~=wave then ambiguous[id]=true end
                            wave.cubs[id]=cub
                            cubs[id]=wave
                        end
                    end
                end
            end
        end
        for id in pairs(ambiguous)do
            cubs[id]=nil
            for _,wave in pairs(fresh)do wave.cubs[id]=nil end
        end
        -- No connection may be inherited from an unrelated wave or an actor that changed teams.
        for key,d in pairs(demands)do
            local targetKey=U.key(d.target)
            local kept=d.kept
            local wave=d.path==Wave.BOSS and fresh[targetKey] or d.path==Wave.CUB and cubs[targetKey] or nil
            if not U.valid(d.target) and kept and fresh[U.key(kept.wave.actor)]==kept.wave then wave=kept.wave end
            if wave and hostile(d.actor,wave.actor,w) then
                local prior=fieldTracks[key]
                if prior and prior.wave==wave and prior.name==identity(d.actor) then
                    tracks[key]=prior
                else
                    tracks[key]={actor=d.actor,name=identity(d.actor),wave=wave}
                    fieldReceipts[key]=nil
                end
            end
        end
        fieldSources,fieldCubs,fieldTracks=fresh,cubs,tracks
        for key,receipt in pairs(fieldReceipts)do
            if not tracks[key] or now>=receipt.expires then fieldReceipts[key]=nil end
        end
        if options.focusCompanion then
            for key,track in pairs(tracks)do
                local wave=track.wave
                if not track.head and not fieldReceipts[key] and U.key(demands[key].target)==U.key(wave.actor)
                    and (not track.nextFocus or now>=track.nextFocus) then
                    track.nextFocus=now+0.5
                    local choices={}
                    for _,cub in pairs(wave.cubs)do
                        if hostile(track.actor,cub,w) then choices[#choices+1]=cub end
                    end
                    if #choices>0 then options.focusCompanion(track.actor,choices,wave.actor) end
                end
            end
        end
    end
    local function fieldTrack(actor)
        local key=U.key(actor)
        local track=key and fieldTracks[key]
        if track and track.name==identity(actor) and (paused() or allowed(actor)) and onPole(track.wave.actor,track.wave.world)
            and U.key(options.world())==fieldWorld and hostile(actor,track.wave.actor,track.wave.world) then return track end
    end
    function self:fieldSource(actor)
        local track=fieldTrack(actor)
        return track and track.wave.actor
    end
    function self:canFieldTarget(actor,victim)
        if paused() then return false end
        local wave=fieldCubs[U.key(victim)]
        local track=wave and fieldTrack(actor)
        if not track or wave~=track.wave or wave.claimed or not hostile(actor,victim,wave.world)
            or (options.tag(victim,Wave.LAST) or 0)<=0 then return false end
        local targetKey=U.key(options.companionOpponent(actor))
        return targetKey~=nil and (targetKey==U.key(wave.actor) or wave.cubs[targetKey]~=nil)
    end
    function self:fieldLastCubs()
        if paused() then return {} end
        local out,seen={},{}
        for _,track in pairs(fieldTracks)do
            for key,cub in pairs(track.wave.cubs)do
                if not seen[key] and self:canFieldTarget(track.actor,cub) then
                    seen[key]=true;out[#out+1]={actor=cub,key=key,owner=track.wave.actor}
                end
            end
        end
        return out
    end
    function self:cancelTicket(proof)
        if proof and fieldReceipts[proof.key]==proof then fieldReceipts[proof.key]=nil end
    end
    function self:stopArena()
        world=nil
        sources,cubs,teams,heads,byTeam={},{},{},{},{}
    end
    function self:sync(members,active)
        syncField(members)
        local hasBoss=false
        if active then for _,m in ipairs(members)do
            if m.class_path==Wave.BOSS and not m.reserve and not m.aid and (m.team=='red' or m.team=='blue') then hasBoss=true;break end
        end end
        if not hasBoss then
            if world then self:stopArena() end
            return
        end
        local current={}
        local w=options.world()
        local wk=U.key(w)
        if wk then
            for _,m in ipairs(members)do
                if m.class_path==Wave.BOSS and not m.reserve and not m.aid and (m.team=='red' or m.team=='blue')
                    and U.inWorld(m.actor,w) and alive(m.actor) and (options.tag(m.actor,Wave.ON_POLE) or 0)>0 then
                    local key=U.key(m.actor)
                    if key then
                        local prior=world==wk and sources[key]
                        local name=identity(m.actor)
                        local wave=prior and prior.team==m.team and U.valid(prior.actor) and prior.name==name and prior
                            or {actor=m.actor,team=m.team,name=name,bossOnly={[key]=true}}
                        wave.cubs={};current[key]=wave
                    end
                end
            end
        end
        world,sources=wk,current
        cubs,teams,byTeam={},{},{}
        if next(sources) then
            for _,m in ipairs(members)do
                if not m.reserve and not m.aid and not m.stand and (m.team=='red' or m.team=='blue') then
                    local key=U.key(m.actor)
                    if key then
                        teams[key]=m
                        local wave=m.class_path==Wave.CUB and sources[U.key(m.summoner)]
                        if wave and wave.team==m.team and alive(m.actor) then
                            cubs[key]=wave;wave.cubs[key]=true
                            local list=byTeam[m.team] or {};list[key]=true;byTeam[m.team]=list
                        end
                    end
                end
            end
        end
        for key,proof in pairs(heads)do
            local m=teams[key]
            if sources[U.key(proof.wave.actor)]~=proof.wave or not m or m.team==proof.wave.team or not alive(m.actor)
                or not U.valid(proof.actor) or identity(m.actor)~=proof.name then heads[key]=nil end
        end
    end
    function self:preferred(actor,team,currentKey)
        if not next(sources) then return end
        local key=U.key(actor)
        if not teams[key] or teams[key].team~=team or sources[key] or cubs[key] then return end
        local won=heads[key]
        if won then return won.wave.bossOnly end
        local paired=sources[currentKey] or cubs[currentKey]
        if paired and paired.team~=team and next(paired.cubs) then return paired.cubs end
        return byTeam[team=='red' and 'blue' or 'red']
    end
    -- A live cub wave takes priority over its own on-pole boss. Limit this extra
    -- check to arena attackers and to a lock on that exact boss instance.
    function self:blocksAim(actor,target)
        if not next(sources) then return false end
        local key,wave=U.key(actor),sources[U.key(target) or false]
        local unit=teams[key or false]
        return wave~=nil and unit~=nil and unit.team~=wave.team and not sources[key] and not cubs[key] and not heads[key]
            and next(wave.cubs)~=nil and U.key(options.world())==world and identity(target)==wave.name
            and (options.tag(target,Wave.ON_POLE) or 0)>0
    end

    function self:lastOwner(victim)
        local wave=cubs[U.key(victim)]
        if wave and alive(victim) and (options.tag(victim,Wave.LAST) or 0)>0 then return wave.actor end
    end
    function self:ticket(actor,victim)
        local victimKey=U.key(victim)
        local wave=cubs[victimKey]
        local key=U.key(actor)
        if self:canFieldTarget(actor,victim) and not fieldReceipts[key] then
            local now=clock()
            if type(now)~='number' or now~=now or math.abs(now)==math.huge then return end
            wave=fieldCubs[victimKey]
            local proof={actor=actor,name=identity(actor),key=key,wave=wave,victim=victim,
                victimName=identity(victim),expires=now+12}
            fieldReceipts[key]=proof
            return proof
        end
        if not wave or wave.claimed or not teams[key] or teams[key].team==wave.team or not alive(actor) or not alive(victim)
            or (options.tag(victim,Wave.LAST) or 0)<=0 then return end
        return {actor=actor,name=identity(actor),key=key,wave=wave,victim=victim}
    end
    function self:award(proof,actor,boss,deathReadback)
        local key=U.key(actor)
        if proof and proof.wave and proof.wave.field then
            local track=fieldTrack(actor)
            local now=clock()
            if not track or fieldReceipts[key]~=proof or key~=proof.key or identity(actor)~=proof.name
                or type(now)~='number' or now~=now or now>=proof.expires or track.wave~=proof.wave or U.key(boss)~=U.key(track.wave.actor)
                or track.wave.claimed then return false end
            if U.valid(proof.victim) then
                if identity(proof.victim)~=proof.victimName then return false end
                local hp=options.hp(proof.victim)
                if type(hp)~='number' or not (hp<=0 and hp>-math.huge) then return false end
            elseif deathReadback~=true then return false end
            fieldReceipts[key]=nil
            track.wave.claimed=true
            track.head=proof
            return true
        end
        if not proof or not key or key~=proof.key or not U.valid(proof.actor) or identity(actor)~=proof.name
            or sources[U.key(boss)]~=proof.wave or proof.wave.claimed or not teams[key] or teams[key].team==proof.wave.team
            or not alive(actor) or not alive(boss) or alive(proof.victim) or (options.tag(boss,Wave.ON_POLE) or 0)<=0 then return false end
        proof.wave.claimed=true
        heads[key]=proof
        return true
    end
    function self:holdsHead(actor,boss)
        local track=fieldTrack(actor)
        if track and track.head and U.key(boss)==U.key(track.wave.actor) then return true end
        local proof=heads[U.key(actor)]
        return proof~=nil and proof.wave==sources[U.key(boss)]
    end
    return self
end
return Wave
