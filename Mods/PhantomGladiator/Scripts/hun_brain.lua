-- Schedule discretionary NPC actions. Native movement, targeting and ongoing abilities keep their own timing.
local Brain={}
local weaponConfigs=require('hun_weapon_catalog').configs
local BUSY={'CharacterState.Stand.Break','CharacterState.Dead','Ability.Executed','Ability.Action.Execution','CharacterState.HitReact.State.Executing',
    'CharacterState.Unselectable.Force.Perform','CharacterState.Hitreact.Phase.Act','CharacterState.Hitreact.State.Frozen','Ability.Action.Hun.HeiMoShang.Reborn'}
local function active(tag,actor,names)
    for _,name in ipairs(names)do if (tag(actor,name) or 0)>0 then return true end end
    return false
end
local function choosePhase(r,ratio,now,stat)
    if not ratio then return end
    local best,charge,capacity
    local w=r.wep
    for _,p in ipairs(r.loadout.phases or {})do
        local id=p.weapon_id
        if p.enabled~=false and ratio<=p.health_below and (not p.once or not r.usedPhases[p.id])
            and r.phaseWeapons[id] and (not best or p.priority>best.priority)
            and not (w and w.rotation and (w.rotation.failures[id] or 0)>=2)
            and now>=(w and w.phaseRetryAt and w.phaseRetryAt[id] or 0) then
            -- BP_CombatArt_Base.GetUltimateChargeCost has a minimum of one.
            if charge==nil then charge=stat(r.actor,'UltimateChargeCount') end
            if type(charge)~='number' then return end
            local cost=w and w.artCosts and w.artCosts[id] or 1
            if charge<cost and r.loadout.resources and r.loadout.resources.consume_skill_resources==false and capacity==nil then
                capacity=stat(r.actor,'UltimateChargeCount_Max') or false
            end
            if charge>=cost or (type(capacity)=='number' and capacity>=cost) then best=p end
        end
    end
    return best
end
function Brain.new(o)
    local self={}
    function self:start(r)
        r.intent={busy=false}
        r.usedPhases,r.phaseWeapons={},{}
        for _,w in ipairs(r.loadout.weapons or {}) do
            local config=weaponConfigs[w.path]
            if w.weight>0 and config and config.art then r.phaseWeapons[w.id]=true end
        end
        r.nextDecision=0
    end
    function self:tick(r)
        local t=o.now()
        local cast=r.shadowState and r.shadowState.running
        -- This shared timer already fires every 100 ms. Avoid skipping a second tick
        -- because of clock rounding during a short native perfect-release window.
        if type(t)~='number' or t==r.lastDecision or (t<r.nextDecision and not (cast and cast.hold and not cast.released)) then return end
        r.lastDecision,r.nextDecision=t,t+.10
        local intent=r.intent
        if intent.performedPhase then
            r.usedPhases[intent.performedPhase]=true
            o.log('[HunBrain] '..r.name..' 阶段动作已触发 '..intent.performedPhase)
            intent.performedPhase=nil
        end
        local target=o.target(r)
        local hp=target and o.hp(r.actor)
        if not target or type(hp)~='number' or hp<=0 then
            intent.busy,intent.phaseId,intent.weapon_id=false,nil,nil
            -- Settle an in-flight cast or a medicine drink after its target disappears.
            if not r.wasIdle or r.shadowBusy or r.supplyBusy then
                local idle={now=t,busy=true,allowAction=false,allowShadow=false}
                r.supplyBusy=o.supply:tick(r,idle)==true
                r.shadowBusy=o.shadows:tick(r,idle)==true
            end
            r.wasIdle=true
            if not r.supplyBusy and not r.shadowBusy then r.nextDecision=t+.25 end
            return
        end
        r.wasIdle=false
        local max=o.stat(r.actor,'Health_Max')
        local ratio=type(max)=='number' and max>0 and hp/max or nil
        local phase=choosePhase(r,ratio,t,o.stat)
        if phase and intent.phaseId~=phase.id then
            r.phaseRequestedAt=t
            o.log('[HunBrain] '..r.name..' HP='..string.format('%.1f%%',ratio*100)..' 请求阶段 '..phase.id)
        end
        intent.phaseId,intent.weapon_id=phase and phase.id,phase and phase.weapon_id
        local locked=active(o.tag,r.actor,BUSY) or (intent.busyUntil or 0)>t
        local pairProtected=o.pairProtected and o.pairProtected(r,target)
        local opening=(o.tag(target,'CharacterState.Stand.Break') or 0)>0
        local ctx={target=target,now=t,distance=o.distance(r.actor,target),hpRatio=ratio,
            busy=locked,pairProtected=pairProtected==true,opening=opening,targetBroken=opening,
            underThreat=(intent.incomingUntil or -1)>=t,allowAction=not locked,allowShadow=not locked}
        local switching=r.wep and (r.wep.draw~=nil or r.wep.pendingSwitch~=nil)
        ctx.busy=ctx.busy or r.shadowBusy==true or pairProtected==true or switching==true
        local supplyBusy=o.supply:tick(r,ctx)==true
        r.supplyBusy=supplyBusy
        ctx.busy=locked or supplyBusy
        -- Give the requested weapon first choice. A cooling-down or unavailable art must not starve other actions.
        ctx.allowAction=not ctx.busy and not switching and not pairProtected and (not phase or t-(r.phaseRequestedAt or t)>2)
        ctx.allowShadow=ctx.allowAction
        local shadowBusy=o.shadows:tick(r,ctx)==true
        r.shadowBusy=shadowBusy
        intent.busy=ctx.busy or shadowBusy or pairProtected==true
    end
    return self
end
return Brain
