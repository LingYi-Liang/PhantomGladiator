local U=require('ue_observe')
local Vitals={}
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<1e12 end
local function close(a,b)return finite(a) and finite(b) and math.abs(a-b)<=.0005 end
local function call(o,key,...)
    if not U.valid(o) then return false end
    local args=table.pack(...)
    return pcall(function()return o[key](o,table.unpack(args,1,args.n))end)
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
function Vitals.montagePlaying(actor)
    local _,anim=call(U.field(actor,'Mesh'),'GetAnimInstance')
    local _,m=call(anim,'GetCurrentActiveMontage')
    if not U.valid(m) then return false end
    local ok,playing=call(anim,'Montage_IsPlaying',m)
    return not ok or playing~=false
end
return Vitals
