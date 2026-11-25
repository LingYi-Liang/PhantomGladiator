-- Owned camera optics and light. Temporary HUD and face edits are recovered by exact
-- instance, including after the Lua VM reloads while a photo is open.
local U=require('ue_observe')
local N=require('photo_native')
local V={}
local JOURNAL='PhantomGladiator.photo.resources.v1'
local RADIAL='/PBZVFXPack/VFX/A_Materials/Template/Original/M_FX_PP_RadialBlur.M_FX_PP_RadialBlur'
local MATLIB='/Script/Engine.Default__KismetMaterialLibrary'
local BAR_CLASSES={'WB_PlayerHPBar_V1_C','WB_BossHPBar_C','WB_EnemyHPBar_C'}
local PALETTES={
    {name='原色',sat={1,1,1},gain={1,1,1},contrast=1},
    {name='暖阳',sat={1.08,1.02,.89},gain={1.15,1.03,.86},contrast=1.08},
    {name='冷雾',sat={.86,.94,.96},gain={.83,.99,1.15},contrast=.92},
    {name='墨色',sat={0,0,0},gain={1,1,1},contrast=1.16},
}
local LIGHTS={
    {name='自然白',color={R=1,G=.95,B=.87,A=1}},
    {name='暖金',color={R=1,G=.62,B=.35,A=1}},
    {name='冷蓝',color={R=.44,G=.69,B=1,A=1}},
    {name='玫红',color={R=1,G=.34,B=.49,A=1}},
    {name='自定义'},
}
V.PALETTES,V.LIGHTS=PALETTES,LIGHTS

local function equal(a,b)
    if type(b)=='number' then return N.number(a) and math.abs(a-b)<.02 end
    if type(b)=='boolean' then return a==b end
    for _,axis in ipairs({'X','Y','Z','W'})do
        if not equal(U.struct(a,axis),b[axis]) then return false end
    end
    return true
end
local function sameOpacity(actual,expected)
    return N.number(actual) and math.abs(actual-expected)<.001
end
local function ppField(component,field,val)
    local p=U.field(component,'PostProcessSettings')
    local current=U.struct(p,field)
    if current==nil then return false end
    local ok=pcall(function()
        if type(val)=='table' then
            current.X,current.Y,current.Z,current.W=val.X,val.Y,val.Z,val.W
        else p[field]=val end
    end)
    if not ok then return false end
    return equal(U.struct(U.field(component,'PostProcessSettings'),field),val)
end
local function v4(v,t)
    local function mix(n)return 1+(n-1)*t end
    return {X=mix(v[1]),Y=mix(v[2]),Z=mix(v[3]),W=1}
end
function V.grade(index,level,exposure,aperture,focus,advanced)
    local p=PALETTES[index]
    local t=level/100
    local needsGrade=index~=1 and level>0
    local saturation=(advanced and advanced.saturation or 100)/100
    local contrast=(1+(p.contrast-1)*t)*((advanced and advanced.contrast or 100)/100)
    local color=v4(p.sat,t)
    color.X,color.Y,color.Z=color.X*saturation,color.Y*saturation,color.Z*saturation
    local out={
        {'bOverride_ColorSaturation',needsGrade or saturation~=1},{'ColorSaturation',color},
        {'bOverride_ColorGain',needsGrade},{'ColorGain',v4(p.gain,t)},
        {'bOverride_ColorContrast',needsGrade or contrast~=1},{'ColorContrast',{X=contrast,Y=contrast,Z=contrast,W=1}},
        {'bOverride_AutoExposureBias',exposure~=0},{'AutoExposureBias',exposure},
        {'bOverride_DepthOfFieldFocalDistance',aperture>0},{'DepthOfFieldFocalDistance',aperture>0 and focus or 0},
        {'bOverride_DepthOfFieldFstop',aperture>0},{'DepthOfFieldFstop',aperture>0 and aperture or 4},
    }
    if advanced then
        local function field(property,key,neutral,default)
            local value=advanced[key]
            if not N.number(value) then value=neutral end
            out[#out+1]={'bOverride_'..property,value~=neutral}
            out[#out+1]={property,value==neutral and default or value}
        end
        local g=(advanced.gamma or 100)/100
        out[#out+1]={'bOverride_ColorGamma',g~=1}
        out[#out+1]={'ColorGamma',{X=g,Y=g,Z=g,W=1}}
        field('WhiteTemp','temperature',6500,6500)
        field('WhiteTint','tint',0,0)
        field('BloomIntensity','bloom',-1,.675)
        field('SceneFringeIntensity','fringe',-1,0)
        field('FilmGrainIntensity','grain',-1,0)
        field('VignetteIntensity','vignette',-1,0.4)
        field('MotionBlurAmount','blur',-1,0.5)
        field('MotionBlurMax','blurMax',-1,5)
        field('IndirectLightingIntensity','environment',-1,1)
    end
    return out
end
local function lightKind(k)return k=='light' or k:match('^light[123]$')~=nil end
local function actorKind(k)return k=='actor1' or k=='actor2'end
local function customColor(h,s,v)
    h=h/60;s=s/100;v=v/100
    local c=v*s
    local x=c*(1-math.abs(h%2-1))
    local colors={{c,x,0},{x,c,0},{0,c,x},{0,x,c},{x,0,c},{c,0,x}}
    local a=colors[math.floor(h)%6+1]
    return {R=a[1]+v-c,G=a[2]+v-c,B=a[3]+v-c,A=1}
end

function V.new(o)
    local self={}
    local find=o.find or StaticFindObject
    local findAll=o.findAll or FindAllOf
    local name=o.fname or FName
    local share=o.shared or ModRef
    local log=o.log or function()end
    local rows={}
    local lights,lastHUD,radial={},nil,nil
    local function save(nextRows)
        if not share then rows=nextRows;return true end
        local lines={}
        for _,r in ipairs(nextRows)do
            lines[#lines+1]=table.concat({r.kind,r.world,r.path,r.id,r.before or '-',r.after or '-',r.morph or '-',r.asset or '-'},'\t')
        end
        local data=table.concat(lines,'\n')
        local ok,saved=pcall(function()share:SetSharedVariable(JOURNAL,data);return share:GetSharedVariable(JOURNAL)==data end)
        if ok and saved then rows=nextRows end
        return ok and saved
    end
    if share then
        local ok,saved=pcall(function()return share:GetSharedVariable(JOURNAL)end)
        if ok and type(saved)=='string' and #saved<=512*1024 then
            for line in saved:gmatch('[^\n]+')do
                local k,w,p,id,a,b,m,v=line:match('^(%w+)\t(%d+)\t(/[^\t]+)\t(%d+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$')
                if k and (k=='menu' or lightKind(k) or k=='hud' or k=='face1' or k=='face2' or actorKind(k)) then
                    local before,after=tonumber(a),tonumber(b)
                    if k=='menu' or lightKind(k) or N.number(before) and N.number(after) then
                        rows[#rows+1]={kind=k,world=w,path=p,id=id,before=before,after=after,morph=m,asset=v}
                    end
                end
            end
        end
    end
    local function entry(kind,obj,a,b,m,asset)
        local p,w,id=N.path(obj),U.key(o.world()),U.key(obj)
        if p and w and id then return {kind=kind,world=w,path=p,id=id,obj=obj,before=a,after=b,morph=m,asset=asset} end
    end
    local function append(items)
        local nextRows={}
        for _,r in ipairs(rows)do nextRows[#nextRows+1]=r end
        for _,r in ipairs(items)do nextRows[#nextRows+1]=r end
        return save(nextRows)
    end
    local function resolve(r)
        if U.key(r.obj)==r.id and N.path(r.obj)==r.path then return r.obj end
        if type(find)~='function' then return end
        local ok,obj=pcall(find,r.path)
        if ok and U.key(obj)==r.id and N.path(obj)==r.path then return obj end
    end
    local function restore(r,w)
        if r.world~=w then return true end
        local obj=resolve(r)
        if not obj then return true end
        if lightKind(r.kind) then
            if not U.inWorld(obj,o.world()) then return true end
            local _,called=N.call(obj,'K2_DestroyActor')
            return called and (not U.valid(obj) or N.call(obj,'IsActorBeingDestroyed')==true)
        elseif r.kind=='menu' then
            if N.call(obj,'IsInViewport')~=true then return true end
            N.call(obj,'RemoveFromParent')
            return not U.valid(obj) or N.call(obj,'IsInViewport')==false
        elseif actorKind(r.kind) then
            if not U.inWorld(obj,o.world()) then return true end
            if U.field(obj,'bHidden')~=(r.after==1) then return true end
            N.call(obj,'SetActorHiddenInGame',r.before==1)
            return U.field(obj,'bHidden')==(r.before==1)
        elseif r.kind=='hud' then
            local opacity=N.call(obj,'GetRenderOpacity')
            if not N.number(opacity) then return false end
            if not sameOpacity(opacity,r.after) then return true end
            N.call(obj,'SetRenderOpacity',r.before)
            return sameOpacity(N.call(obj,'GetRenderOpacity'),r.before)
        end
        if U.key(N.call(obj,'GetSkeletalMeshAsset'))~=r.asset then return true end
        if not name then return false end
        local key=name(r.morph)
        local actual=N.call(obj,'GetMorphTarget',key)
        if not N.number(actual) then return false end
        if not equal(actual,r.after) then return true end
        N.call(obj,'SetMorphTarget',key,r.before,true)
        return equal(N.call(obj,'GetMorphTarget',key),r.before)
    end
    function self:release(kind)
        if #rows==0 then return true end
        local w=U.key(o.world())
        if not w then return false end
        local remaining,done,matched={},true,false
        for _,r in ipairs(rows)do
            if not kind or r.kind==kind then
                matched=true
                if not restore(r,w) then remaining[#remaining+1]=r;done=false end
            else remaining[#remaining+1]=r end
        end
        if not kind then lights={};radial=nil
        elseif lightKind(kind) then lights[kind]=nil end
        if not kind or kind=='hud' then lastHUD=nil end
        return not matched or save(remaining) and done
    end
    function self:pending()return #rows>0 end
    function self:own(obj,kind)
        local item=entry(kind,obj)
        return item~=nil and append({item})
    end
    local function widgetInWorld(widget,w,pc)
        -- UMG's owning player and actor-bound head bars survive harmless widget construction.
        if N.same(N.call(widget,'GetOwningPlayer'),pc) or N.same(N.call(widget,'GetWorld'),w) then return true end
        local actor=U.field(widget,'SelfActor')
        return U.valid(actor) and U.inWorld(actor,w)
    end
    function self:bars(hide,now,force)
        if not hide then return self:release('hud') end
        if not force and lastHUD then return true end
        local world,pc=o.world(),o.getController()
        if not U.valid(world) or not U.valid(pc) or type(findAll)~='function' then return false end
        local nextRows,seen,mask={},{},{}
        local changed,count=false,0
        local worldKey=U.key(world)
        for _,original in ipairs(rows)do
            local r=original
            if r.kind=='hud' and r.world==worldKey then
                local widget=resolve(r)
                if widget and widgetInWorld(widget,world,pc) then
                    local current=N.call(widget,'GetRenderOpacity')
                    if not N.number(current) then return false end
                    if not sameOpacity(current,r.after) and not sameOpacity(current,r.before) then
                        r=entry('hud',widget,current,0)
                        if not r then return false end
                        changed=true
                    end
                    seen[r.id]=true
                    mask[#mask+1]=widget
                end
            end
            nextRows[#nextRows+1]=r
        end
        for _,class in ipairs(BAR_CLASSES)do
            local ok,objects=pcall(findAll,class)
            if not ok then return false end
            for _,widget in ipairs(U.array(objects) or {})do
                local id=U.key(widget)
                if id and not seen[id] and widgetInWorld(widget,world,pc) then
                    local before=N.call(widget,'GetRenderOpacity')
                    if N.number(before) and not sameOpacity(before,0) then
                        local r=entry('hud',widget,before,0)
                        if not r then return false end
                        nextRows[#nextRows+1]=r
                        mask[#mask+1]=widget
                        seen[id]=true
                        changed,count=true,count+1
                    end
                end
            end
        end
        if changed and not save(nextRows) then return false end
        local done=true
        for _,widget in ipairs(mask)do
            if not sameOpacity(N.call(widget,'GetRenderOpacity'),0) then
                N.call(widget,'SetRenderOpacity',0)
                done=sameOpacity(N.call(widget,'GetRenderOpacity'),0) and done
            end
        end
        if done then lastHUD=now or 0 end
        if changed or not done then log('[Photo] 血条遮罩新增='..count..' 读回='..tostring(done)) end
        return done
    end

    function self:expression(role,face,weights)
        local k='face'..role
        if not self:release(k) then return false end
        if #weights==0 then return true end
        local asset=U.key(N.call(face,'GetSkeletalMeshAsset'))
        if not asset or not name then return false end
        local group={}
        for _,change in ipairs(weights)do
            local before=N.call(face,'GetMorphTarget',name(change[1]))
            if not N.number(before) then return false end
            local r=entry(k,face,before,change[2],change[1],asset)
            if not r then return false end
            group[#group+1]=r
        end
        if not append(group) then return false end
        local done=true
        for _,r in ipairs(group)do
            local n=name(r.morph)
            N.call(face,'SetMorphTarget',n,r.after,true)
            done=equal(N.call(face,'GetMorphTarget',n),r.after) and done
        end
        if not done then self:release(k) end
        log('[Photo] 人物 '..role..' 表情权重读回='..tostring(done))
        return done
    end
    function self:subject(role,actor,show)
        local k='actor'..role
        if not self:release(k) then return false end
        if show then return true end
        if not U.inWorld(actor,o.world()) or U.field(actor,'bHidden')~=false then return false end
        local item=entry(k,actor,0,1)
        if not item or not append({item}) then return false end
        N.call(actor,'SetActorHiddenInGame',true)
        return U.field(actor,'bHidden')==true
    end
    function self:focus(actor,aperture,distance)
        local component=U.field(actor,'CameraComponent')
        if not U.valid(component) or not N.same(N.call(component,'GetOwner'),actor) then return false end
        return ppField(component,'bOverride_DepthOfFieldFocalDistance',aperture>0)
            and ppField(component,'DepthOfFieldFocalDistance',aperture>0 and distance or 0)
    end
    local function blendWeight(component,instance)
        local blendables=U.struct(U.field(component,'PostProcessSettings'),'WeightedBlendables')
        for _,entry in ipairs(U.array(U.struct(blendables,'Array')) or {})do
            if N.same(instance,U.struct(entry,'Object')) then return U.struct(entry,'Weight') end
        end
    end
    local function zoomBlur(actor,component,power)
        if radial and not N.same(radial.actor,actor) then radial=nil end
        if power==0 then
            if not radial then return true end
            N.call(component,'RemoveBlendable',radial.mid)
            if (blendWeight(component,radial.mid) or 0)>0 then
                N.call(component,'AddOrUpdateBlendable',radial.mid,0)
            end
            return (blendWeight(component,radial.mid) or 0)==0
        end
        if not radial then
            local lib=type(find)=='function' and find(MATLIB)
            local material=type(find)=='function' and find(RADIAL)
            if not U.valid(material) and type(o.load or LoadAsset)=='function' then
                local ok,loaded=pcall(o.load or LoadAsset,RADIAL)
                if ok then material=loaded end
            end
            if not U.valid(lib) or N.path(material)~=RADIAL or not name then return false end
            local mid=N.call(lib,'CreateDynamicMaterialInstance',actor,material,name('PG_PhotoRadialBlur'),0)
            if not U.valid(mid) or not N.same(N.call(mid,'GetOuter'),actor) then return false end
            radial={actor=actor,mid=mid}
        end
        local mid=radial.mid
        for _,p in ipairs({{'UseMPC',0},{'Intensity',power/100},{'CenterX',.5},{'CenterY',.5},{'VignetteStrength',0}})do
            local parameter=name(p[1])
            local _,called=N.call(mid,'SetScalarParameterValue',parameter,p[2])
            if not called or not equal(N.call(mid,'K2_GetScalarParameterValue',parameter),p[2]) then return false end
        end
        N.call(component,'AddOrUpdateBlendable',mid,1)
        return equal(blendWeight(component,mid),1)
    end
    function self:optics(actor,s)
        local component=U.field(actor,'CameraComponent')
        if not U.valid(component) or not N.same(N.call(component,'GetOwner'),actor) then return false end
        N.call(component,'SetFieldOfView',s.fov)
        local done=equal(U.field(component,'FieldOfView'),s.fov)
        for _,p in ipairs(V.grade(s.filter,s.strength,s.exposure,s.aperture,s.focus,s.lights and s or nil))do
            done=ppField(component,p[1],p[2]) and done
        end
        local blend=pcall(function()component.PostProcessBlendWeight=1 end)
        return zoomBlur(actor,component,s.zoomBlur or 0) and blend and equal(U.field(component,'PostProcessBlendWeight'),1) and done
    end

    local function spawnLight(camera,position,kind)
        local cls=type(find)=='function' and find('/Script/Engine.PointLight')
        local lib=type(find)=='function' and find('/Script/Engine.Default__GameplayStatics')
        local world=o.world()
        if not U.valid(cls) or not U.valid(lib) or not U.inWorld(camera,world) then return nil end
        local transform={Translation=position,Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
        local actor=N.call(lib,'BeginDeferredActorSpawnFromClass',world,cls,transform,1,camera,1)
        if not U.valid(actor) then return nil end
        local c=U.field(actor,'PointLightComponent')
        if not U.valid(c) or not N.same(N.call(c,'GetOwner'),actor) or not self:own(actor,kind) then
            N.call(actor,'K2_DestroyActor')
            return nil
        end
        N.call(c,'SetMobility',2)
        N.call(c,'SetIntensity',0)
        N.call(c,'SetCastShadows',false)
        local _,finished=N.call(lib,'FinishSpawningActor',actor,transform,1)
        local at=N.vec(N.call(actor,'K2_GetActorLocation'))
        if not finished or not U.inWorld(actor,world) or not at
            or math.abs(at.X-position.X)+math.abs(at.Y-position.Y)+math.abs(at.Z-position.Z)>1 then
            self:release(kind)
            return nil
        end
        return {actor=actor,component=c,at=at}
    end
    local function lightAt(r,s)
        local v=r.rotation
        local a=math.rad(v.Yaw)
        local p=r.position
        local focus=r.lens and r.lens.focus
        if not focus then
            local b=math.rad(v.Pitch)
            local d=math.min(700,r.settings.focus)
            focus={X=p.X+math.cos(a)*math.cos(b)*d,Y=p.Y+math.sin(a)*math.cos(b)*d,Z=p.Z+math.sin(b)*d}
        end
        local heading=math.atan(p.Y-focus.Y,p.X-focus.X)+math.rad(s.angle)
        return {X=focus.X+math.cos(heading)*s.distance,Y=focus.Y+math.sin(heading)*s.distance,Z=focus.Z+s.height}
    end
    local function lightOne(r,s,kind)
        if s.power==0 then return self:release(kind) end
        local at=lightAt(r,s)
        if not lights[kind] then
            if not self:release(kind) then return false end
            lights[kind]=spawnLight(r.camera,at,kind)
        end
        local h=lights[kind]
        if not h or not U.valid(h.actor) or not U.valid(h.component) then return false end
        if not h.at or math.abs(h.at.X-at.X)+math.abs(h.at.Y-at.Y)+math.abs(h.at.Z-at.Z)>.5 then
            local result,ok=N.call(h.actor,'K2_SetActorLocation',at,false,{},true)
            if not ok or result==false then return false end
            h.at=at
        end
        if h.power~=s.power then
            N.call(h.component,'SetIntensity',80*s.power)
            if not equal(U.field(h.component,'Intensity'),80*s.power) then return false end
            h.power=s.power
        end
        local colorKey=s.color==5 and table.concat({5,s.hue,s.sat,s.brightness},':') or s.color
        if h.color~=colorKey then
            local wanted=LIGHTS[s.color].color or customColor(s.hue,s.sat,s.brightness)
            local _,ok=N.call(h.component,'SetLightColor',wanted,true)
            local color=N.call(h.component,'GetLightColor')
            if not ok then return false end
            for _,channel in ipairs({'R','G','B'})do
                if not equal(U.struct(color,channel),wanted[channel]) then return false end
            end
            h.color=colorKey
        end
        if h.radius~=s.radius then
            N.call(h.component,'SetAttenuationRadius',s.radius)
            if not equal(U.field(h.component,'AttenuationRadius'),s.radius) then return false end
            h.radius=s.radius
        end
        if s.scatter~=1 or h.scatter then
            if h.scatter~=s.scatter then
                N.call(h.component,'SetVolumetricScatteringIntensity',s.scatter)
                if not equal(U.field(h.component,'VolumetricScatteringIntensity'),s.scatter) then return false end
                h.scatter=s.scatter
            end
        end
        if s.shadows or h.shadows~=nil then
            if h.shadows~=s.shadows then
                N.call(h.component,'SetCastShadows',s.shadows)
                if U.field(h.component,'CastShadows')~=s.shadows then return false end
                h.shadows=s.shadows
            end
        end
        if s.channels~=1 or h.channels then
            if h.channels~=s.channels then
                local a,b,c=(s.channels&1)~=0,(s.channels&2)~=0,(s.channels&4)~=0
                N.call(h.component,'SetLightingChannels',a,b,c)
                local back=U.field(h.component,'LightingChannels')
                if U.struct(back,'bChannel0')~=a or U.struct(back,'bChannel1')~=b or U.struct(back,'bChannel2')~=c then return false end
                h.channels=s.channels
            end
        end
        if not h.logged then h.logged=true;log('[Photo] '..kind..' 位置、颜色、强度和范围已读回') end
        return true
    end
    function self:light(r)
        local s=r.settings
        if not s.lights then
            return lightOne(r,{power=s.light,color=s.lightColor,angle=s.lightAngle,height=s.lightHeight,
                radius=1100,distance=235,scatter=1,channels=1,shadows=false},'light')
        end
        local ok=true
        for i,slot in ipairs(s.lights)do ok=lightOne(r,slot,'light'..i) and ok end
        return ok
    end
    return self
end
return V
