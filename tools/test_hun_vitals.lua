package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Vitals=require('hun_vitals')
local function actor()return {IsValid=function()return true end}end
local target=actor()
local r={actor=target,loadout={attributes={}}}
local writes={}
local opts={current=function(rec)return rec==r end,alive=function(a)return a==target end,log=function()end,
    stats=function()return {writeBase=function(_,a,k,x)assert(a==target);writes[k]=x end}end,
    read=function(_,k)return writes[k]end}
local before={hp=1360,maximum=1360,shachi=640,shachiMax=640}
local after={hp=1360,maximum=1700,shachi=640,shachiMax=800}
Vitals.fillSpawn(r,before,after,opts)
assert(writes.Health==1700 and writes.Shachi==800)
writes={};r.loadout.attributes.Health=1360;after.shachi=560
Vitals.fillSpawn(r,before,after,opts);assert(next(writes)==nil,'preserve explicit HP and actual damage during spawn')
r.loadout.attributes={};before.hp=900;before.shachi=200;after.hp=900;after.shachi=200
Vitals.fillSpawn(r,before,after,opts);assert(next(writes)==nil,'a hurt or partially spent body gets no ongoing refill')
for _,kind in ipairs({'boss','overhead'}) do
    local w=actor()
    for _,field in ipairs({'hpbar','BreakmeterBar'})do
        local bar=actor();w[field]=bar
        bar.RealBar=actor();bar.RealBar.Percent=.8;bar.AnimBar=actor();bar.AnimBar.Percent=.8;bar.CurPercent=.8
        function bar:SetBarPercent(v)self.RealBar.Percent=v;self.AnimBar.Percent=v end
    end
    function w:ForSeq_UpdateHealth(v)self.hpbar.CurPercent=v end
    function w:ForSeq_UpdateShachi(v)self.BreakmeterBar.CurPercent=v end
    assert(Vitals.syncBar(w,'hpbar','ForSeq_UpdateHealth',850,1700))
    assert(Vitals.syncBar(w,'BreakmeterBar','ForSeq_UpdateShachi',0,800))
    assert(w.hpbar.RealBar.Percent==.5 and w.BreakmeterBar.RealBar.Percent==0 and w.BreakmeterBar.AnimBar.Percent==0,kind)
    assert(Vitals.syncBar(w,'BreakmeterBar','ForSeq_UpdateShachi',400,800) and w.BreakmeterBar.RealBar.Percent==.5)
    assert(Vitals.syncBar(w,'BreakmeterBar','ForSeq_UpdateShachi',0,nil)==nil)
end
print('PASS birth bonus and damage/current overrides; top and overhead real foreground and trailing meters including zero')

do
    local row={}
    assert(not Vitals.recentLoss(row,800,800,0))
    assert(Vitals.recentLoss(row,319.3,800,.5)>480)
    assert(Vitals.recentLoss(row,360,800,1)>480)
    assert(not Vitals.recentLoss(row,400,800,2.1))
    assert(not Vitals.recentLoss(row,100,400,2.5),'new maximum resets the comparison')
end

do
    local a,main,linked,m=actor(),actor(),actor(),actor();function a:GetAddress()return 17 end
    a.Mesh=actor();function a.Mesh:GetAnimInstance()return main end
    a.Mesh.LinkedInstances={linked};function linked:TryGetPawnOwner()return a end
    function linked:GetCurrentActiveMontage()return m end;function linked:Montage_IsPlaying()return true end
    assert(Vitals.montagePlaying(a),'a weapon-layer montage must block a new opener or switch')
    function linked:TryGetPawnOwner()return nil end
    assert(not Vitals.montagePlaying(a))
end
do
    local function param(value)return {type=function()return 'RemoteUnrealParam' end,get=function()return value end} end
    local a,main,clip=actor(),actor(),actor()
    a.Mesh=actor();a.Mesh.GetAnimInstance=function()return main end
    main.GetCurrentActiveMontage=function()return clip end
    main.Montage_IsPlaying=function()return param(false) end
    main.Montage_IsActive=function()return param(true) end
    assert(Vitals.actionState(a),'hit stop preserves the active montage')
    main.Montage_IsActive=function()return param(false) end
    assert(not Vitals.actionState(a),'a stopped montage releases the slot even with reflected booleans')
    local input=actor();a['Ability Input Component']=input
    input.InActionPhase=param(true);input.ActionPhase={TagName={ToString=function()return 'CharacterState.Action.Phase.Combo' end}}
    local busy,chain=Vitals.actionState(a);assert(busy and chain)
    input.InActionPhase=param(false);assert(not Vitals.actionState(a),'ignore a stale combo name after the phase ends')
    main.Montage_IsActive=function()return true end
    a.AbilitySystemComponent=actor()
    function a.AbilitySystemComponent:GetGameplayTagCount(tag)return tag.TagName=='CharacterState.Action.Phase.Combo' and 1 or 0 end
    busy,chain=Vitals.actionState(a,function(name)return name end)
    assert(busy and not chain,'an ASC combo tag is stale while the montage is paused')
    main.Montage_IsPlaying=function()return param(true) end
    a.Mesh.bPauseAnims=param(true)
    busy,chain=Vitals.actionState(a,function(name)return name end)
    assert(busy and not chain,'a paused mesh cannot consume an input before its next pose')
    a.Mesh.bPauseAnims=param(false)
    busy,chain=Vitals.actionState(a,function(name)return name end)
    assert(busy and chain,'the native ASC can expose a live combo window on a playing montage')
end
