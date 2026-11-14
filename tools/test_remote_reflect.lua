package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Remote=require('remote_attack')
local Reflect=require('remote_reflect')
local serial=0
local function name(text)return {ToString=function()return text end}end
local function cls(text,super)
    return {IsValid=function()return true end,GetFName=function()return name(text)end,GetSuperStruct=function()return super end}
end
local function object(text,super)
    serial=serial+1
    local class=cls(text,super)
    local out={valid=true,key=serial,full=text..'_'..serial}
    function out:IsValid()return self.valid end
    function out:GetAddress()return self.key end
    function out:GetFullName()assert(self.valid);return self.full end
    function out:GetClass()assert(self.valid);return class end
    return out
end
local function param(value)
    return {value=value,type=function()return 'RemoteUnrealParam'end,get=function(s)return s.value end,
        set=function(s,v)if not s.deny then s.value=v end end}
end
local function tag(text)return {TagName=text}end
local function bullet(kind,parent)
    local data=object(kind..'Data')
    local out=object(kind);out.ParentBullet=parent
    function out:GetData()return data end
    return out,data
end
local ranged=bullet('PBZ_ProjectileBullet')
local melee=bullet('PBZ_SweepTraceBullet')
local trace=bullet('PBZ_SweepTraceBullet',ranged)
local remote=Remote.new({fname=function(x)return x end})
assert(remote:bullet(ranged)==true)
assert(remote:bullet(melee)==false)
assert(remote:bullet(trace)==true,'a projectile child trace remains ranged')
assert(remote:bullet(bullet('PBZ_ParticleBullet'))==true)
assert(remote:bullet(bullet('PBZ_OverlapBullet'))==true)
assert(remote:bullet(bullet('PBZ_ExecutionBullet',ranged))==false,'a grab is not reclassified by its parent')
local arrow,arrowData=bullet('PBZ_SweepTraceBullet');arrowData.AttackType=tag('HitReact.AttackType.Physical.Projectile.Arrow')
assert(remote:bullet(arrow)==true)
local energy,energyData=bullet('PBZ_SweepTraceBullet');energyData.AttackType=tag('Hitreact.AttackType.Energy.DuYanEyeLaser')
assert(remote:bullet(energy)==true)
local controlled=bullet('PBZ_SweepTraceBullet');controlled.HasTag=function()return true end
assert(remote:bullet(controlled)==true)
local cycle=bullet('PBZ_SweepTraceBullet');cycle.ParentBullet=cycle
assert(remote:bullet(cycle)==false)
local invalid=object('Invalid');invalid.valid=false
assert(remote:bullet(invalid)==nil)

local laser=object('BP_Bullet_Laser_Base_C',cls('PBZ_SweepTraceBullet'))
laser.GetData=function()return object('PBZ_SweepTraceBulletData')end
assert(remote:bullet(laser)==true,'the native legacy laser class is ranged even with a sweep trace')
local JINGYE='BP_Monster_JingYe'
local THUG='BP_Monster_MaleThug_Club_Yellow_Shield'
assert(Reflect.paths.damage==nil and Reflect.paths.modify==nil and Reflect.paths.collision==nil,
    'shield controls never hook normal parry damage or projectile rebound')
local function harness()
    local h={hooks={},logs={},rules={},members={},now=1,ready=true,thread=true,unhooked=0,registered=0,readyReads=0}
    local lib=object('AbilitySystemBlueprintLibrary')
    function lib:GetGameplayEffectFromSpecHandle(spec)return spec.effect end
    function lib:GetEffectContext(spec)return {actor=spec.actor}end
    function lib:EffectContextGetEffectCauser(context)return context.actor end
    function lib:EffectContextGetInstigatorActor(context)return context.actor end
    h.m=Reflect.new({log=function(s)h.logs[#h.logs+1]=s end,clock=function()return h.now end,fname=function(s)return s end,
        rule=function(id)return h.rules[id] or 'keep' end,members=function()return h.members end,
        ready=function()h.readyReads=h.readyReads+1;return h.ready end,
        inGameThread=function()return h.thread end,
        find=function(path)if path:find('Default__AbilitySystemBlueprintLibrary',1,true)then return lib end;return object('Function')end,
        register=function(path,pre,post)h.registered=h.registered+1;h.hooks[path]={pre=pre,post=post};return 1,2 end,
        unregister=function()h.unhooked=h.unhooked+1 end})
    function h:fire(which,...)
        local hook=assert(self.hooks[Reflect.paths[which]],which)
        return hook.pre(...)
    end
    function h:actor(id,off)
        self.rules[id]=off and 'off' or 'keep'
        local actor=object(id..'_C');local path='/Game/'..id..'.'..id..'_C'
        self.members[#self.members+1]={actor=actor,team='blue',class_path=path}
        self.m:capture(actor,path)
        return actor
    end
    function h:payload(actor,b)
        local p=object('DamagePreTakePayload');p.TargetActor=actor;p.DamageSource=object('BulletAttackModule');p.DamageSource.Bullet=b
        return p
    end
    function h:counter(actor,payload,kind,field,deny)
        if payload then self:fire('owner',param(payload)) end
        local value=param(0.25);value.deny=deny
        self:fire('magnitude',nil,param({effect=object(kind or 'GE_JingYe_Shield_Counter_C'),actor=actor}),
            param(tag(field or 'SetByCaller.Shield.CounterDamage.PhysicalDamage')),value)
        return value.value
    end
    return h
end
do
    local h=harness()
    h:actor('BP_Monster_MBoss',true)
    assert(next(h.hooks)==nil,'an old broad rule for a non-shield unit cannot install any hook')
    h:actor(JINGYE,false)
    assert(next(h.hooks)==nil,'default thorns shields keep the original without hooks')
    local a=h:actor(JINGYE,true)
    assert(h.m:status().hooks==2)
    for _,b in ipairs({ranged,trace,energy,laser,(bullet('PBZ_OverlapBullet'))})do
        assert(h:counter(a,h:payload(a,b))==0,b:GetFullName())
    end
    assert(h:counter(a,h:payload(a,melee))==0.25,'a melee hit replaces prior ranged provenance')
    assert(h:counter(a,h:payload(a,bullet('PBZ_ExecutionBullet',ranged)))==0.25,'grabs keep their own rules')
    local p=h:payload(a,ranged)
    assert(h:counter(a,p,'OtherEffect_C')==0.25)
    assert(h:counter(a,p,'GE_MaleThug_ClubShield_Counter_C')==0.25,'even a shield cannot alter the other shield GE')
    assert(h:counter(a,p,nil,'SetByCaller.NormalAttack.PhysicalDamage')==0.25,'normal attacks are not shield retaliation')
    assert(h:counter(a,p,nil,nil,true)==0.25,'refused parameter writes do not change the original')
    local other=object(JINGYE..'_C')
    assert(h:counter(other,h:payload(other,ranged))==0.25,'map actors of the same class are unaffected')
    local thug=h:actor(THUG,true)
    assert(h:counter(thug,h:payload(thug,ranged),'GE_MaleThug_ClubShield_Counter_C','SetByCaller.Shield.CounterDamage.BleedAccumulation')==0)
    assert(h:counter(thug,h:payload(thug,melee),'GE_MaleThug_ClubShield_Counter_C')==0.25)
    local teaching=h:actor(THUG..'_Teaching',true)
    assert(h:counter(teaching,h:payload(teaching,ranged),'GE_MaleThug_ClubShield_Counter_C')==0)
    local b=h:actor(JINGYE,false)
    assert(h:counter(b,h:payload(b,ranged))==0.25,'new default spawn preserves original damage')
    assert(h:counter(a,p)==0,'existing spawn retains its captured setting')
    h:fire('owner',param(p));h.now=h.now+0.051
    assert(h:counter(a,nil)==0.25,'stale provenance is never used for another hit')
    h.thread=false;assert(h:counter(a,p)==0.25,'worker-thread callbacks cannot alter damage');h.thread=true
    h.ready=false;assert(h:counter(a,p)==0.25);h.m:tick()
    h.ready=true;h.members={};h.m:tick()
    assert(h:counter(a,p)==0.25,'world changes and cleanup release actor records')
    local late=h.hooks[Reflect.paths.magnitude].pre;h.m:silence();assert(h.unhooked==2)
    local value=param(0.25);late(nil,param({effect=object('GE_JingYe_Shield_Counter_C'),actor=a}),param(tag('SetByCaller.Shield.CounterDamage.PhysicalDamage')),value)
    assert(value.value==0.25 and h.m:status().hooks==0)
    h:actor(JINGYE,true)
    assert(h.m:status().hooks==0,'late actor callbacks cannot reinstall hooks after unload')
end
-- Global native callbacks reject unrelated hits/tags before checking the expensive live session.
do
    local h=harness();local actor=h:actor(JINGYE,true)
    local outside=object('BP_MapUnit_C');local otherPayload=h:payload(outside,ranged)
    h.readyReads=0
    for _=1,100 do
        h:fire('owner',param(otherPayload))
        h:fire('magnitude',nil,param({effect=object('OtherEffect_C'),actor=outside}),param(tag('SetByCaller.NormalAttack.PhysicalDamage')),param(1))
    end
    assert(h.readyReads==0,'unrelated native calls queried live session '..h.readyReads..' times')
    assert(h:counter(actor,h:payload(actor,ranged))==0)
    assert(h.readyReads<=2,'a related owner/magnitude pair needs at most two session checks')
    h.members={};h.m:tick()
    assert(h.m:status().hooks==0 and h.unhooked==2,'the last selected shield leaving releases global hooks')
    h.readyReads=0;h.m:tick()
    assert(h.readyReads==0,'idle module does not poll the live session')
end
-- Discovery through the member roster still works without the direct spawn callback.
do
    local h=harness();h.rules[JINGYE]='off'
    h.members={{actor=object(JINGYE..'_C'),class_path='/Game/'..JINGYE..'.'..JINGYE..'_C',team='blue'}}
    h.m:tick();assert(h.m:status().hooks==2,'newly discovered shields retain their captured rule')
    h.ready=false;h.m:tick();assert(h.m:status().hooks==0)
    h.ready=true;h.m:tick()
    assert(h.m:status().hooks==2,'same-world readiness recovery rediscovers shields still in the roster')
    assert(h:counter(h.members[1].actor,h:payload(h.members[1].actor,ranged))==0)
end
-- Retained roster entries while the player is not ready must not install and remove hooks every tick.
do
    local h=harness();h.rules[JINGYE]='off';h.ready=false
    h.members={{actor=object(JINGYE..'_C'),class_path='/Game/'..JINGYE..'.'..JINGYE..'_C',team='blue'}}
    for _=1,10 do h.now=h.now+0.1;h.m:tick() end
    assert(h.registered==0 and h.unhooked==0,'not-ready discovery churned hooks: '..h.registered..' installs/'..h.unhooked..' removals')
    h.ready=true;h.m:tick();assert(h.registered==2 and h.m:status().hooks==2)
    h.ready=false;h.m:tick();assert(h.unhooked==2)
    for _=1,10 do h.now=h.now+0.1;h.m:tick() end
    assert(h.registered==2 and h.unhooked==2,'continued not-ready ticks must remain unhooked')
end
print('remote_reflect: PASS (thorns shields only, ranged/bleed suppression, melee/normal/parry/rebound preserved, cleanup)')
