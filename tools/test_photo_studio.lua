package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Fx=require('photo_visuals')
local Overlay=require('photo_overlay')
local Face=require('photo_face')
local Settings=require('photo_settings')

local serial,all=0,{}
local function object(path,outer,fields)
    local o=fields or {}
    serial=serial+1;o.id=serial;o.path=path;o.outer=outer;o.alive=true
    function o:IsValid()return self.alive end
    function o:GetFullName()return 'Object '..self.path end
    function o:GetAddress()return self.id end
    function o:GetOuter()return self.outer end
    all[path]=o
    return o
end
local world=object('/Studio.World')
local otherWorld=object('/Other.World')
local pc=object('/Studio.World:PC',world)
local journal={}
function journal:GetSharedVariable(k)return self[k] end
function journal:SetSharedVariable(k,v)assert(type(v)=='string');self[k]=v end
local function find(path)return all[path]end
local function fname(v)return v end

local camera=object('/Studio.World:Camera',world)
local settings={}
for _,property in ipairs(Fx.grade(1,0,0,0,200,Settings.defaults(60)))do settings[property[1]]=property[2] end
local comp=object('/Studio.World:Camera.Component',camera,{FieldOfView=80,PostProcessBlendWeight=0,PostProcessSettings=settings})
camera.CameraComponent=comp
function comp:GetOwner()return camera end
function comp:SetFieldOfView(v)self.FieldOfView=v end
function comp:AddOrUpdateBlendable(mid,weight)
    self.PostProcessSettings.WeightedBlendables={Array={{Object=mid,Weight=weight}}}
end
function comp:RemoveBlendable()self.PostProcessSettings.WeightedBlendables={Array={}}end
local parent=object('/PBZVFXPack/VFX/A_Materials/Template/Original/M_FX_PP_RadialBlur.M_FX_PP_RadialBlur')
local matlib=object('/Script/Engine.Default__KismetMaterialLibrary')
function matlib:CreateDynamicMaterialInstance(actor,template)
    assert(actor==camera and template==parent)
    local mid=object(actor.path..'.BlurMID',actor,{params={}})
    function mid:SetScalarParameterValue(name,value)self.params[name]=value end
    function mid:K2_GetScalarParameterValue(name)return self.params[name] end
    return mid
end
local cameraSettings={fov=62,filter=4,strength=100,exposure=.5,aperture=2.8,focus=480,light=25,lightColor=2,lightAngle=0,lightHeight=90}

local cls=object('/Script/Engine.PointLight')
local lib=object('/Script/Engine.Default__GameplayStatics')
local spawned
function lib:BeginDeferredActorSpawnFromClass(w,c,t,method,owner)
    assert(w==world and c==cls and owner==camera and method==1)
    local l=object('/Studio.World:PointLight'..serial,world,{location=t.Translation})
    local lc=object(l.path..'.Component',l,{Intensity=0,AttenuationRadius=0})
    spawned=l;l.PointLightComponent=lc
    function lc:GetOwner()return l end
    function lc:SetMobility(v)assert(v==2);self.Mobility=v end
    function lc:SetIntensity(v)self.Intensity=v end
    function lc:SetLightColor(c)assert(c.A==1);self.color=c end
    function lc:GetLightColor()return self.color end
    function lc:SetAttenuationRadius(v)self.AttenuationRadius=v end
    function lc:SetCastShadows(v)self.CastShadows=v end
    function l:K2_SetActorLocation(p,sweep,hit,warp)assert(not sweep and type(hit)=='table' and warp);self.location=p;return true end
    function l:K2_GetActorLocation()return self.location end
    function l:K2_DestroyActor()self.alive=false end
    return l
end
function lib:FinishSpawningActor(l,t,scale)assert(l==spawned and scale==1);return l end

local function widget(label,world,own)
    local w=object(world.path..':'..label,world,{opacity=.8,visible=true})
    function w:GetOwningPlayer()return own end
    function w:GetWorld()return world end
    function w:IsInViewport()return self.visible end
    function w:RemoveFromParent()self.visible=false end
    function w:SetRenderOpacity(v)self.opacity=v end
    function w:GetRenderOpacity()return self.opacity end
    return w
end
local enemy,other=widget('EnemyHP',world,pc),widget('UnrelatedHP',otherWorld,nil)
local bossBar=widget('BossHP',world,pc)
local opts={world=function()return world end,getController=function()return pc end,find=find,fname=fname,shared=journal,
    findAll=function(class)
        if class=='WB_EnemyHPBar_C' then return {enemy,other}
        elseif class=='WB_BossHPBar_C' then return {bossBar}
        else assert(class=='WB_PlayerHPBar_V1_C');return {} end
    end}
local fx=Fx.new(opts)
assert(fx:optics(camera,cameraSettings))
assert(comp.FieldOfView==62 and comp.PostProcessBlendWeight==1 and settings.ColorSaturation.Y==0)
assert(settings.bOverride_DepthOfFieldFstop and settings.DepthOfFieldFstop==2.8 and settings.DepthOfFieldFocalDistance==480)
assert(fx:bars(true,1) and enemy.opacity==0 and bossBar.opacity==0 and other.opacity==.8)
bossBar.opacity=.6
assert(fx:bars(true,1.2,true) and bossBar.opacity==0,'a fresh capture masks a changed native widget')
local r={settings=cameraSettings,camera=camera,position={X=500,Y=0,Z=40},rotation={Yaw=0,Pitch=0,Roll=0}}
assert(fx:light(r) and spawned.PointLightComponent.Intensity==2000 and not spawned.PointLightComponent.CastShadows)
local a=spawned.location
cameraSettings.lightAngle=90
assert(fx:light(r) and spawned.location.Y~=a.Y)
cameraSettings.light=0
assert(fx:light(r) and not spawned.alive,'turning the light off destroys only the owned actor')
cameraSettings.light=25
assert(fx:light(r) and spawned.alive)

local meshClass=object('/Script/Engine.SkeletalMeshComponent')
local actor=object('/Studio.World:Companion',world)
local face=object('/Studio.World:Companion.Head',actor,{morph={}})
local asset=object('/Test.FaceAsset',nil,{MorphTargets={}})
function actor:K2_GetComponentsByClass(c)assert(c==meshClass);return {face} end
function face:GetOwner()return actor end
function face:GetSkeletalMeshAsset()return asset end
function face:GetMorphTarget(f)return self.morph[f] end
function face:SetMorphTarget(f,v)assert(self.morph[f]);self.morph[f]=v end
for _,m in ipairs({'brow_down_L','brow_down_R','jaw_open','eye_widen_L','eye_widen_R'})do
    local n='head_lod0_mesh__'..m
    local channel=object(asset.path..':'..n,asset)
    function channel:GetFName()return n end
    asset.MorphTargets[#asset.MorphTargets+1]=channel
    face.morph[n]=.15
end
local pick=Face.expressions(actor,find)
assert(pick.mesh==face and #pick.options==3 and pick.options[2].name=='凝神' and pick.options[3].name=='惊讶')
assert(fx:expression(2,face,pick.options[2].weights) and face.morph.head_lod0_mesh__brow_down_L==.72)
assert(fx:release('face1') and face.morph.head_lod0_mesh__brow_down_L==.72,'release must stay scoped to one subject')
local reloaded=Fx.new(opts)
assert(reloaded:pending() and reloaded:release())
assert(enemy.opacity==.8 and bossBar.opacity==.6 and other.opacity==.8 and not spawned.alive)
assert(face.morph.head_lod0_mesh__brow_down_L==.15 and not reloaded:pending())

local classNames={'CommonUI.CommonUserWidget','UMG.Default__WidgetBlueprintLibrary','UMG.CanvasPanel','UMG.TextBlock',
    'UMG.Border','Engine.Default__KismetTextLibrary','UMG.Default__WidgetLayoutLibrary'}
for _,key in ipairs(classNames)do object('/Script/'..key) end
local ui
local factory=all['/Script/UMG.Default__WidgetBlueprintLibrary']
local text=all['/Script/Engine.Default__KismetTextLibrary']
local layout=all['/Script/UMG.Default__WidgetLayoutLibrary']
function text:Conv_StringToText(v)return v end
function layout:GetViewportSize()return {X=1280,Y=720} end
function layout:GetViewportScale()return 1 end
function factory:Create(w,class,owner)
    assert(w==world and owner==pc and class.path=='/Script/CommonUI.CommonUserWidget')
    ui=widget('OwnMenu'..serial,w,owner)
    ui.WidgetTree=object(ui.path..'.Tree',ui)
    function ui:SetDesiredSizeInViewport(v)assert(v.X>0 and v.Y>0)end
    function ui:SetAlignmentInViewport(v)assert(v.X==1 or v.X==0)end
    function ui:SetRenderTransformPivot(v)assert(v.X==1)end
    function ui:SetRenderScale(v)self.scale=v end
    function ui:SetPositionInViewport(v)self.position=v end
    function ui:AddToViewport(z)assert(z==42 or z==41);self.visible=true end
    function ui:SetVisibility(v)if not self.visibilityStuck then self.vis=v end end
    function ui:GetVisibility()return self.vis end
    return ui
end
local function construct(class,outer,name)
    assert(not class.path:find('/Game/',1,true) and outer==ui.WidgetTree)
    local obj=object(outer.path..'.'..name,outer,{Font={Size=16}})
    function obj:SetBrushColor(v)assert(v.A>0) end
    function obj:AddChildToCanvas(child)
        local slot=object(self.path..'.Slot'..serial,self)
        function slot:SetPosition(v)assert(v.X>=0 and v.Y>=0)end
        function slot:SetSize(v)assert(v.X>=0 and v.Y>=0)end
        function slot:SetZOrder(v)assert(v<0)end
        return slot
    end
    function obj:SetText(v)self.text=v end
    function obj:SetVisibility(v)self.vis=v end
    function obj:SetFont(v)assert(v.Size>0)end
    function obj:SetColorAndOpacity(v)assert(v.SpecifiedColor and v.ColorUseRule==0)end
    function obj:SetJustification(v)assert(v==2)end
    function obj:SetAutoWrapText(v)assert(v)end
    function obj:SetShadowColorAndOpacity(c)assert(c.A>0)end
    function obj:SetShadowOffset(v)assert(v.X==1)end
    return obj
end
local menu=Overlay.new({find=find,fname=fname,construct=construct})
assert(menu:open(world,pc,function(w)return reloaded:own(w,'menu')end))
assert(menu:render({visible=true,title='双人自拍',tabs='〔镜头〕',selected=1,hint='空格拍照',signature='1',
    rows={{label='视场角',value='62°'}}},1) and ui.position.X==1260)
assert(ui.WidgetTree.RootWidget.path:find('PG_StudioRoot',1,true))
local panel=ui
panel.visibilityStuck=true
assert(menu:hide()==false and panel.vis==3,'a visible menu must block clean capture')
panel.visibilityStuck=false
assert(menu:hide()==true and panel.vis==1)
local scene=Settings.defaults(65)
scene.grid,scene.border,scene.mark,scene.focusMark=true,3,2,true
assert(menu:composition(scene,false,2))
local decor=ui;assert(decor~=panel and decor.visible and decor.WidgetTree.RootWidget.path:find('PG_PhotoCompositionRoot',1,true))
local guides=all[decor.WidgetTree.path..'.PG_PhotoCompositionGuide1']
assert(guides.vis==3)
assert(menu:composition(scene,true,3) and guides.vis==1 and decor.vis==3)
scene.captureHDR=true
decor.visibilityStuck=true
assert(menu:composition(scene,true,4)==false and decor.vis==3,'a visible composition overlay must block HDR capture')
decor.visibilityStuck=false
assert(menu:composition(scene,true,4) and decor.vis==1,'HDR must not include preview overlays')
assert(Fx.new(opts):release() and not panel.visible and not decor.visible,'reload removes our own viewport widgets')

scene.fov=64;scene.bloom=2;scene.bars=false;scene.show1=false;scene.saturation=75;scene.contrast=135;scene.zoomBlur=30
scene.lights[1].power=25;scene.lights[2].power=40;scene.lights[2].color=5;scene.lights[2].hue=180
local encoded=Settings.encode(scene)
local saved=assert(Settings.decode(encoded))
assert(saved.fov==64 and not saved.bars and not saved.show1 and saved.lights[2].hue==180)
local fx=Fx.new(opts)
assert(fx:optics(camera,saved))
assert(settings.BloomIntensity==2 and settings.bOverride_BloomIntensity and settings.ColorContrast.X==1.35)
local blend=settings.WeightedBlendables.Array[1]
assert(blend.Weight==1 and blend.Object:GetOuter()==camera and blend.Object.params.UseMPC==0 and blend.Object.params.Intensity==.3)
saved.zoomBlur=0
assert(fx:optics(camera,saved) and #settings.WeightedBlendables.Array==0)
assert(fx:light({settings=saved,camera=camera,position=r.position,rotation=r.rotation}))
local live={}
for path,a in pairs(all)do if path:match('^/Studio%.World:PointLight%d+$') and a.alive then live[#live+1]=a end end
assert(#live==2 and live[1]~=live[2])
local subject=object('/Studio.World:Subject',world,{bHidden=false})
function subject:SetActorHiddenInGame(on)self.bHidden=on end
assert(fx:subject(1,subject,false) and subject.bHidden)
assert(fx:release() and not subject.bHidden)
assert(not live[1].alive and not live[2].alive)
print('photo_studio: PASS composition, private lighting slots, optics, presets, subject visibility and cleanup')
