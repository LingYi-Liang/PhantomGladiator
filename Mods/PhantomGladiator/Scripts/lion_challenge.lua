-- Arena ownership for the native lion-head phase. Only the final cub's completed
-- execution earns a duel with its own summoner for the rest of this pole phase.
local U=require('ue_observe')
local Wave={
    BOSS='/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_LionDancer_P2.BP_Monster_LionDancer_P2_C',
    CUB='/PBZCombatAsset/ActorData/Mobs/DaTouWaWa/BP_Monster_DaTouWaWa_HouHouHou.BP_Monster_DaTouWaWa_HouHouHou_C',
    ON_POLE='CharacterState.AbilityState.LionDancer.OnPole',LAST='CharacterType.HouHouHou.LastOne'
}
function Wave.new(options)
    local self={}
    local sources,cubs,teams,heads,byTeam={},{},{},{},{}
    local world
    local function alive(actor)
        local hp=U.valid(actor) and options.hp(actor)
        return type(hp)=='number' and hp>0
    end
    local function identity(actor)
        if not U.valid(actor) then return end
        local ok,n=pcall(function()return actor:GetFullName()end)
        return ok and n or nil
    end
    function self:sync(members,active)
        local hasBoss=false
        if active then for _,m in ipairs(members)do
            if m.class_path==Wave.BOSS and not m.reserve and not m.aid and (m.team=='red' or m.team=='blue') then hasBoss=true;break end
        end end
        if not hasBoss then
            if world then world=nil;sources,cubs,teams,heads,byTeam={},{},{},{},{} end
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
    function self:lastOwner(victim)
        local wave=cubs[U.key(victim)]
        if wave and alive(victim) and (options.tag(victim,Wave.LAST) or 0)>0 then return wave.actor end
    end
    function self:ticket(actor,victim)
        local wave=cubs[U.key(victim)]
        local key=U.key(actor)
        if not wave or wave.claimed or not teams[key] or teams[key].team==wave.team or not alive(actor) or not alive(victim)
            or (options.tag(victim,Wave.LAST) or 0)<=0 then return end
        return {actor=actor,name=identity(actor),key=key,wave=wave,victim=victim}
    end
    function self:award(proof,actor,boss)
        local key=U.key(actor)
        if not proof or not key or key~=proof.key or not U.valid(proof.actor) or identity(actor)~=proof.name
            or sources[U.key(boss)]~=proof.wave or proof.wave.claimed or not teams[key] or teams[key].team==proof.wave.team
            or not alive(actor) or not alive(boss) or alive(proof.victim) or (options.tag(boss,Wave.ON_POLE) or 0)<=0 then return false end
        proof.wave.claimed=true
        heads[key]=proof
        return true
    end
    function self:holdsHead(actor,boss)
        local proof=heads[U.key(actor)]
        return proof~=nil and proof.wave==sources[U.key(boss)]
    end
    return self
end
return Wave
