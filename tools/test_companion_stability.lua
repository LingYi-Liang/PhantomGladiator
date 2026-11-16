package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local before,only=arg[1],arg[2]
local function fixtures(file,module)
    local saved=arg;arg={before and(before..'/'..module..'.lua')or nil,'fixture'}
    local a,b,c=assert(loadfile(file))();arg=saved;return a,b,c
end
local fx,typed=fixtures('tools/test_effect_instance_aim.lua','effect_instance_aim')
local aimFixture,obj,key=fixtures('tools/test_companion_aim.lua','player_aim')
local Effects=before and assert(loadfile(before..'/effect_instance_aim.lua'))()or require('effect_instance_aim')
local passed=0
local function test(id,label,fn)
    if only and only~=id then return end
    fn();passed=passed+1;print('PASS '..id..' '..label)
end
test('retire','ending a particle cannot reactivate a new attack with the original player-targeting asset',function()
    local h=fx();h.effects:arm();h:step();local activations=h.activations or 0
    h.bullet.BulletStatus=3;h.now=0.3;h:step()
    assert(h.comp.Asset==h.original and h.comp.active==false,'retired particle must remain inactive')
    assert((h.activations or 0)==activations,'cleanup cannot replay an attack')
end)
test('idle','idle companion activation hooks avoid reflected Asset queries on unrelated components',function()
    local h=fx();h.effects:tick();local reads=0
    local unrelated=typed('AudioComponent','Audio',h.actor)
    setmetatable(unrelated,{__index=function(_,field)if field=='Asset'then reads=reads+1 end end})
    for _=1,5000 do h.hooks[Effects.paths.activate](unrelated)end
    print('MEASURE idle activations=5000 Asset reads='..reads)
    assert(reads==0,'idle hooks should not query a missing property on every activation')
end)
test('activation_retry','failed private activation backs off instead of resetting a running system every scan',function()
    local h=fx();h.deactivateOnSet=true;h.badActivation=true;h.effects:arm();h:step()
    for i=1,80 do h.now=i*0.05;h:step()end
    print('MEASURE failed activation 4 seconds Asset sets='..#h.calls)
    assert(#h.calls<=2,'activation failure should only bind/restore once within the retry interval')
end)
test('recovery','a failed restoration remains pending until a later confirmed restoration',function()
    local h=fx();h.deactivateOnSet=true;h.badActivation=true
    local native=h.comp.SetAsset;local blocked=true
    h.comp.SetAsset=function(self,value,reset)
        if blocked and value==h.original then return end
        return native(self,value,reset)
    end
    h.effects:arm();h:step();assert(h.comp.Asset~=h.original)
    blocked=false;h.now=1.1;h:step()
    assert(h.comp.Asset==h.original,'an incomplete recovery cannot be mistaken for an ordinary running record')
end)
test('cancel','failed timer cancellation retries at most once per second',function()
    local h=fx();local attempts=0
    h.options.cancel=function()attempts=attempts+1;return false end
    h.effects:arm();h:step();h.enabled=false
    for i=1,60 do h.now=i*0.05;h:step()end
    print('MEASURE failed cancellation 3 seconds attempts='..attempts)
    assert(attempts<=4,'native cancellation failures cannot be polled at 20 Hz')
end)
test('generation','a retained callback from a cancelled loop cannot act on a later session',function()
    local h=fx();h.effects:arm();h:step();local old=h.loop
    h.enabled=false;h:step();assert(h.loop==nil)
    h.enabled=true;h.effects:arm();local scan,writes,calls=h.scans,h.writes,#h.calls
    h.now=0.3;old()
    assert(h.scans==scan and h.writes==writes and #h.calls==calls,'a cancelled callback must stay inert after rearming')
end)
test('group_reads','one caster with many active components validates the shared target once per frame',function()
    local h=fx()
    for _=1,19 do h.list[#h.list+1]=h.makeBullet(h.actor)end
    h.effects:arm();h:step();local calls=0;local native=h.options.world
    h.options.world=function()calls=calls+1;return native()end
    h.now=0.05;h:step()
    print('MEASURE 20 components shared target World reads='..calls)
    assert(calls<=1,'already-updated groups cannot repeat the same world/outer validation for every component')
end)
local function golden()
    local h=aimFixture();local caster=h.unit('companion');local enemy=obj('BP_Enemy_C')
    enemy.K2_GetActorLocation=function()return {X=100,Y=0,Z=0}end
    caster.K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end
    h.player.K2_GetActorLocation=function()return {X=5000,Y=0,Z=0}end
    h.targets[key(caster)]=enemy
    local a=h.new();a:tick();local loops={};local list={}
    LoopInGameThreadWithDelay=function(_,fn)loops[#loops+1]=fn;return #loops end
    CancelDelayedAction=function()return h.cancelFails~=true end
    FindAllOf=function()return list end
    FName=function(s)return s end
    local data=obj('Data');data.GetFName=function()return {ToString=function()return 'BD_ZuoShang_Skill_19'end}end
    local asset=obj('NiagaraSystem');asset.GetFName=function()return {ToString=function()return 'NS_ZuoShang_SwordShooting_001'end}end
    local bullet=obj('PBZ_ParticleBullet',{BulletOwnerAvatar=caster,BulletData=data,BulletStatus=2})
    local comp=obj('NiagaraComponent',{Asset=asset,writes=0})
    comp.GetOwner=function()return bullet end
    comp.SetVariableBool=function(self,_,value)self.use=value;self.writes=self.writes+1 end
    comp.SetVariablePosition=function(self,_,value)self.position=value end;comp.SetVariableVec3=comp.SetVariablePosition
    bullet.ParticleComponent=comp
    local action=obj('GAA_DelayDeflectProjectileBullet_C',{['Bullet Data']=data,GetAvatarActor=function()return caster end})
    local function launch()h.hooks[require('player_aim').paths.launch](action)end
    return h,a,loops,list,bullet,comp,launch
end
test('golden_cancel','failed sword-rain cancellation never creates a second active timer',function()
    local h,a,loops,list,bullet,comp,launch=golden();h.cancelFails=true;launch()
    for _=1,3 do loops[1]()end
    launch();print('MEASURE failed golden cancellation active timer registrations='..#loops)
    assert(#loops==1,'a failed cancellation handle must be retained, not replaced by another loop')
end)
test('golden_reuse','a detached component reused by another actor is not reset by the old bullet',function()
    local h,a,loops,list,bullet,comp,launch=golden();list[1]=bullet;launch();loops[1]();assert(comp.use==true)
    local foreign=obj('OtherBullet');comp.GetOwner=function()return foreign end
    local writes=comp.writes;bullet.ParticleComponent=nil;bullet.BulletStatus=3;loops[1]()
    assert(comp.writes==writes,'the retired bullet cannot turn off a different owner component')
end)
test('golden_invalid','a component destroyed by one setter is not dereferenced by the next setter',function()
    local h,a,loops,list,bullet,comp,launch=golden();local invalid=0
    comp.SetVariablePosition=function(self)self.alive=false end
    comp.SetVariableVec3=function(self)if not self.alive then invalid=invalid+1 end end
    comp.SetVariableBool=function(self)if not self.alive then invalid=invalid+1 end end
    list[1]=bullet;launch();loops[1]()
    print('MEASURE invalid component setter calls='..invalid)
    assert(invalid==0,'each subsequent native setter needs a fresh validity check')
end)
test('golden_position','non-finite coordinates never reach native particle setters',function()
    local h,a,loops,list,bullet,comp,launch=golden()
    h.targets[key(bullet.BulletOwnerAvatar)].K2_GetActorLocation=function()return {X=0/0,Y=0,Z=0}end
    list[1]=bullet;launch();loops[1]()
    assert(comp.writes==0 and comp.position==nil,'NaN targets cannot be written to Niagara')
end)
test('foreign_target','private effect coordinates cannot come from a detached target world',function()
    local h=fx();h.enemy.outer=typed('World','OtherWorld');h.effects:arm();h:step()
    assert(h.comp.Asset==h.original,'a foreign-world enemy cannot attach a private attack')
end)
local function party()
    local h=aimFixture();local caster=h.unit('companion');local ally=h.unit('companion');local enemy=obj('BP_Enemy_C')
    for _,actor in ipairs({caster,ally,enemy})do actor.RootComponent=obj('Capsule',{GetOwner=function()return actor end})end
    h.targets[key(caster)]=enemy;h.targets[key(ally)]=enemy
    local a=h.new();a:tick()
    return h,a,caster,ally,enemy
end
test('ally_bullet','bullet selectors reject another companion as a retained attack target',function()
    FName=function(text)return text end
    local h,a,caster,ally,enemy=party();local value={Component=ally.RootComponent}
    local out={type=function()return 'RemoteUnrealParam'end,get=function()return value end,set=function(_,v)value=v end}
    local ability=obj('GA_Test_C',{GetAvatarActorFromActorInfo=function()return caster end})
    h.hooks[a.paths and a.paths.bullet or require('player_aim').paths.bullet](nil,caster,nil,ability,nil,nil,out)
    assert(value.Component==enemy.RootComponent,'a companion is friendly even though present in the fighter roster')
end)
test('ally_lock','ability locks on another companion are repaired to the current enemy',function()
    FName=function(text)return text end
    local h,a,caster,ally,enemy=party()
    local ability=obj('GA_Test_C',{GetAvatarActorFromActorInfo=function()return caster end,['Lock Target']={Component=ally.RootComponent}})
    h.hooks[require('player_aim').paths.lock](ability)
    assert(ability['Lock Target'].Component==enemy.RootComponent,'ally locks cannot be kept as hostile locks')
end)
test('stress','one thousand move/retire/reuse/world/invalid/unload transitions preserve ownership',function()
    for i=1,1000 do
        local h=fx();h.effects:arm();h:step();local queued=h.loop
        local mode=i%7
        if mode==0 then h.enemy.x=100+i
        elseif mode==1 then h.noTarget=true
        elseif mode==2 then h.world=typed('World','Replacement')
        elseif mode==3 then h.bullet.BulletOwnerAvatar=h.player
        elseif mode==4 then h.comp.Asset=typed('NiagaraSystem','External')
        elseif mode==5 then h.comp.live=false
        else h.enabled=false end
        h.now=0.3;h:step()
        assert(h.worldColor.R==5000 and h.playerComp.Asset==h.original,'an unrelated player instance must remain untouched')
        h.effects:silence();local calls,writes=#h.calls,h.writes;queued()
        assert(#h.calls==calls and h.writes==writes,'unloaded callbacks must stay inert')
    end
    print('MEASURE mixed lifecycle transitions=1000 ownership/global-write violations=0')
end)
print('companion stability: PASS '..passed..' failure/reuse/performance checks; no game accessed')
