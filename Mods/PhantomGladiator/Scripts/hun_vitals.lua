local U=require('ue_observe')
local Vitals={}
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<1e12 end
local function close(a,b)return finite(a) and finite(b) and math.abs(a-b)<=.0005 end
local function call(o,key,...)
    if not U.valid(o) then return false end
    local args=table.pack(...)
    local ok,result=pcall(function()return o[key](o,table.unpack(args,1,args.n))end)
    if ok then return true,U.unwrap(result) end
    return false
end

function Vitals.read(actor,read)
    return {hp=read(actor,'Health'),maximum=read(actor,'Health_Max'),shachi=read(actor,'Shachi'),shachiMax=read(actor,'Shachi_Max')}
end

-- Only fill the capacity added during this spawn's accessory pass. A selected or already damaged current value wins.
function Vitals.fillSpawn(r,before,after,options)
    for _,pair in ipairs({{'Health','hp','maximum'},{'Shachi','shachi','shachiMax'}})do
        local field,key,cap=table.unpack(pair)
        if (r.loadout.attributes or {})[field]==nil and close(before[key],before[cap]) and finite(after[cap])
            and finite(after[key]) and before[key]>0 and after[key]>=before[key]-.0005 and after[key]<after[cap]-.0005
            and after[cap]>before[cap] and options.current(r) and options.alive(r.actor) then
            options.log('[HunStats] 即将补齐出生时新增上限 '..field..' '..after[key]..'→'..after[cap])
            local stats=options.stats()
            if stats then stats:writeBase(r.actor,field,after[cap]) end
            options.log('[HunStats] 出生满槽 '..field..' 读回='..tostring(options.read(r.actor,field))..' 上限='..after[cap])
        end
    end
end

-- The foreground is RealBar.Percent. CurPercent alone can be stale after the widget's gradual/zero update.
-- PBZAnimProgressBar.SetBarPercent updates the actual bars and their material ratios immediately.
function Vitals.syncBar(widget,field,setter,value,maximum)
    if not finite(value) or not finite(maximum) or maximum<=0 then return nil end
    local bar=U.field(widget,field)
    if not U.valid(bar) then return false end
    local ratio=math.max(0,math.min(1,value/maximum))
    if field=='BreakmeterBar' then
        local ok,visibility=call(bar,'GetVisibility')
        if ok and (visibility==1 or visibility==2) then call(bar,'SetVisibility',3) end
    end
    local real=U.field(bar,'RealBar')
    local trail=U.field(bar,'AnimBar')
    local function measured()
        if U.valid(real) then return U.field(real,'Percent') end
        return U.field(bar,'CurPercent')
    end
    if not close(measured(),ratio) then
        call(widget,setter,ratio)
    end
    if not close(measured(),ratio) or U.valid(trail) and not close(U.field(trail,'Percent'),ratio) then call(bar,'SetBarPercent',ratio) end
    return close(measured(),ratio)
end
-- Show the last observed net decrease briefly even if regeneration has already started.
function Vitals.recentLoss(record,value,cap,now)
    if not finite(value) or not finite(cap) or cap<=0 or cap~=record.lastShaCap then
        record.shaDrop,record.shaDropAt=nil,nil
    elseif finite(record.lastShaValue) and record.lastShaValue-value>=.5 then
        record.shaDrop,record.shaDropAt=record.lastShaValue-value,now
    end
    record.lastShaValue,record.lastShaCap=value,cap
    if record.shaDropAt and now-record.shaDropAt<1.5 then return record.shaDrop end
end
local function montageState(anim,checkPause)
    local _,m=call(anim,'GetCurrentActiveMontage')
    if not U.valid(m) then return false end
    local measured,active=call(anim,'Montage_IsActive',m)
    if measured and type(active)=='boolean' then
        if not active or not checkPause then return active,false end
        local ok,moving=call(anim,'Montage_IsPlaying',m)
        return true,ok and moving==false
    end
    local ok,moving=call(anim,'Montage_IsPlaying',m)
    return not ok or moving~=false,false
end
local function poseState(actor,checkPause)
    local mesh=U.field(actor,'Mesh')
    if U.field(mesh,'bPauseAnims')==true then return true,true end
    local _,main=call(mesh,'GetAnimInstance')
    local busy,paused=montageState(main,checkPause)
    if paused or busy and not checkPause then return true,paused end
    local key=U.key(actor)
    if not key then return busy,false end
    for _,linked in ipairs(U.array(U.field(mesh,'LinkedInstances')) or {})do
        local active,held=montageState(linked,checkPause)
        if active then
            local _,owner=call(linked,'TryGetPawnOwner')
            if U.key(owner)==key then
                if held or not checkPause then return true,held end
                busy=true
            end
        end
    end
    return busy,false
end
function Vitals.montagePlaying(actor)
    return (poseState(actor,false))
end
-- The phase of the running action: its input component's, else a Combo or Cancel tag on the ASC.
function Vitals.phase(actor,fname)
    local input=U.field(actor,'Ability Input Component')
    if U.field(input,'InActionPhase')==true then
        local phase=U.struct(U.field(input,'ActionPhase'),'TagName')
        if type(phase)=='string' then return phase end
        local ok,name=pcall(function()return phase:ToString()end)
        return ok and type(name)=='string' and name or nil
    end
    local asc=U.field(actor,'AbilitySystemComponent')
    for _,phase in ipairs({'CharacterState.Action.Phase.Combo','CharacterState.Action.Phase.Cancel'}) do
        local _,count=call(asc,'GetGameplayTagCount',{TagName=fname(phase)})
        if type(count)=='number' and count>0 then return phase end
    end
end
-- The input map lists the preceding ability tag throughout a swing. Only the
-- native Combo and Cancel phases open its transition window.
function Vitals.actionState(actor,fname)
    local input=U.field(actor,'Ability Input Component')
    if U.field(input,'InActionPhase')==true then
        local phase=U.struct(U.field(input,'ActionPhase'),'TagName')
        if type(phase)~='string' then
            local ok,name=pcall(function()return phase:ToString()end)
            phase=ok and name
        end
        if phase~='CharacterState.Action.Phase.Combo' and phase~='CharacterState.Action.Phase.Cancel' then return true,false end
        local _,paused=poseState(actor,true)
        return true,not paused
    end
    local busy,paused=poseState(actor,fname~=nil)
    if not busy or paused then return busy,false end
    -- Some native abilities expose the window on the ASC instead of the input
    -- component. Only check those tags for callers about to issue an input.
    if fname then
        local asc=U.field(actor,'AbilitySystemComponent')
        for _,phase in ipairs({'CharacterState.Action.Phase.Combo','CharacterState.Action.Phase.Cancel'}) do
            local _,count=call(asc,'GetGameplayTagCount',{TagName=fname(phase)})
            if type(count)=='number' and count>0 then return true,true end
        end
    end
    return true,false
end
return Vitals
