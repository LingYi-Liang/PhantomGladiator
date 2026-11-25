-- Focal changes are a lease on our private observer camera component. A borrower receives its original optics.
local U=require('ue_observe')
local Lens={}
local INTERVAL=.05
local PROPS={'bOverride_DepthOfFieldFocalDistance','DepthOfFieldFocalDistance',
    'bOverride_DepthOfFieldFstop','DepthOfFieldFstop'}
local function number(v)return type(v)=='number' and v==v and math.abs(v)<1e12 end
local function sameValue(a,b,tolerance)
    if number(a) and number(b) then return math.abs(a-b)<(tolerance or .02) end
    return a==b
end
local function call(object,method,...)
    if not U.valid(object) then return false end
    local args=table.pack(...)
    return pcall(function()return object[method](object,table.unpack(args,1,args.n))end)
end
local function ppSet(component,index,value)
    local name=PROPS[index]
    local settings=U.field(component,'PostProcessSettings')
    local before=U.struct(settings,name)
    if before==nil then return false end
    if sameValue(before,value) then return true end
    local write=pcall(function()settings[name]=value end)
    return write and sameValue(U.struct(U.field(component,'PostProcessSettings'),name),value)
end
local function weightSet(component,value)
    if sameValue(U.field(component,'PostProcessBlendWeight'),value) then return true end
    return call(component,'SetPostProcessBlendWeight',value) and sameValue(U.field(component,'PostProcessBlendWeight'),value)
end
local function fovSet(component,value)
    if sameValue(U.field(component,'FieldOfView'),value) then return true end
    return call(component,'SetFieldOfView',value) and sameValue(U.field(component,'FieldOfView'),value,.08)
end

function Lens.new(camera,log)
    local component=U.field(camera,'CameraComponent')
    local cameraKey,key=U.key(camera),U.key(component)
    local ok,owner=call(component,'GetOwner')
    if not cameraKey or not key or not ok or U.key(owner)~=cameraKey then return end
    local nextAt=0
    local baseFov=U.field(component,'FieldOfView')
    local fovActive,focusActive,focusDisabled,fovDisabled=false,nil,false,false
    local fovReadback,focusReadback=false,false
    local self={}
    local function current()
        if U.key(camera)~=cameraKey or U.key(U.field(camera,'CameraComponent'))~=key then return false end
        local read,actual=call(component,'GetOwner')
        return read and U.key(actual)==cameraKey
    end
    local function restoreFocus()
        if not focusActive then return true end
        local complete=true
        for i,value in ipairs(focusActive)do complete=ppSet(component,i,value) and complete end
        complete=weightSet(component,focusActive.weight) and complete
        if complete then focusActive=nil end
        return complete
    end
    function self:restore()
        if not fovActive and not focusActive then return true end
        if not current() then return false end
        local complete=restoreFocus()
        if fovActive and fovSet(component,baseFov) then fovActive=false end
        return complete and not fovActive
    end
    function self:update(plan,now)
        if now<nextAt then return true end
        nextAt=now+INTERVAL
        if not plan then return self:restore() end
        if not current() then return false end
        local wanted=plan.fov
        if not fovDisabled and number(baseFov) and number(wanted) and wanted>30 and wanted<110 then
            if not sameValue(U.field(component,'FieldOfView'),wanted,.1) then
                fovActive=true
                if not fovSet(component,wanted) then
                    fovDisabled=true
                    if fovSet(component,baseFov) then fovActive=false end
                    log('[ArenaCinema] 镜头视场角写入读回失败')
                elseif not fovReadback then
                    fovReadback=true
                    log(string.format('[ArenaCinema] 电影机位视场角读回≈%.1f°',wanted))
                end
            end
        end
        if not number(plan.focus) or not number(plan.aperture) then return restoreFocus() end
        if focusDisabled then return restoreFocus() end
        if not focusActive then
            local settings=U.field(component,'PostProcessSettings')
            local w=U.field(component,'PostProcessBlendWeight')
            local row={weight=w}
            for i,name in ipairs(PROPS)do row[i]=U.struct(settings,name) end
            if type(row[1])~='boolean' or type(row[3])~='boolean' or not number(row[2])
                or not number(row[4]) or not number(w) then
                focusDisabled=true
                log('[ArenaCinema] 景深字段不可用，保持取景和推进')
                return true
            end
            focusActive=row
        end
        local focus=math.max(100,math.min(6000,plan.focus))
        local aperture=math.max(4,math.min(10,plan.aperture))
        if not (ppSet(component,2,focus) and ppSet(component,4,aperture)
            and ppSet(component,1,true) and ppSet(component,3,true)
            and weightSet(component,math.max(focusActive.weight,.75))) then
            focusDisabled=true
            local restored=restoreFocus()
            log('[ArenaCinema] 景深写入读回失败，恢复='..tostring(restored))
            return restored
        end
        if not focusReadback then
            focusReadback=true
            log(string.format('[ArenaCinema] 高位机位原生对焦距离读回≈%.0fcm',focus))
        end
        return true
    end
    return self
end
return Lens
