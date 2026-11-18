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
