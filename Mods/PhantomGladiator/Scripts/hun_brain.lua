-- Schedule discretionary NPC actions. Native movement, targeting and ongoing abilities keep their own timing.
local Brain={}
local BUSY={'Ability.Executed','Ability.Action.Execution','CharacterState.HitReact.State.Executing','CharacterState.Unselectable.Force.Perform'}
local function active(tag,actor,names)
    for _,name in ipairs(names)do if (tag(actor,name) or 0)>0 then return true end end
    return false
end
local function choosePhase(r,ratio)
    if not ratio then return end
    local best
    for _,p in ipairs(r.loadout.phases or {})do
        if p.enabled~=false and ratio<=p.health_below and (not p.once or not r.usedPhases[p.id])
            and r.enabledWeapons[p.weapon_id] and (not best or p.priority>best.priority) then best=p end
    end
    return best
end
function Brain.new(o)
    local self={}
    function self:start(r)
        r.intent={busy=false}
        r.usedPhases,r.enabledWeapons={},{}
        for _,w in ipairs(r.loadout.weapons or {})do if w.weight>0 then r.enabledWeapons[w.id]=true end end
        r.nextDecision=0
    end
    function self:tick(r)
        local t=o.now()
        if type(t)~='number' or t<r.nextDecision then return end
        r.nextDecision=t+.10
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
        local phase=choosePhase(r,ratio)
        if phase and intent.phaseId~=phase.id then
            r.phaseRequestedAt=t
            o.log('[HunBrain] '..r.name..' HP='..string.format('%.1f%%',ratio*100)..' 请求阶段 '..phase.id)
        end
        intent.phaseId,intent.weapon_id=phase and phase.id,phase and phase.weapon_id
        local locked=active(o.tag,r.actor,BUSY) or (intent.busyUntil or 0)>t
        local opening=(o.tag(target,'CharacterState.Stand.Break') or 0)>0
        local ctx={target=target,now=t,distance=o.distance(r.actor,target),hpRatio=ratio,
            busy=locked,opening=opening,targetBroken=opening,allowAction=not locked,allowShadow=not locked}
        ctx.busy=ctx.busy or r.shadowBusy==true
        local supplyBusy=o.supply:tick(r,ctx)==true
        r.supplyBusy=supplyBusy
        ctx.busy=locked or supplyBusy
        -- Give the requested weapon first choice. A cooling-down or unavailable art must not starve other actions.
        ctx.allowAction=not ctx.busy and (not phase or t-(r.phaseRequestedAt or t)>2)
        ctx.allowShadow=ctx.allowAction
        local shadowBusy=o.shadows:tick(r,ctx)==true
        r.shadowBusy=shadowBusy
        intent.busy=ctx.busy or shadowBusy
    end
    return self
end
return Brain
