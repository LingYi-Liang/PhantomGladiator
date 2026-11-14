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

local function harness()
    local h={hooks={},logs={},rules={},members={},now=1,ready=true,thread=true,copies=0,unhooked=0,actions={}}
    local lib=object('AbilitySystemBlueprintLibrary')
    function lib:GetGameplayEffectFromSpecHandle(spec)return spec.effect end
    function lib:GetEffectContext(spec)return {actor=spec.actor}end
    function lib:EffectContextGetEffectCauser(context)return context.actor end
    function lib:EffectContextGetInstigatorActor(context)return context.actor end
    h.m=Reflect.new({log=function(s)h.logs[#h.logs+1]=s end,clock=function()return h.now end,fname=function(s)return s end,
        rule=function(id)return h.rules[id] or 'keep' end,members=function()return h.members end,ready=function()return h.ready end,
        inGameThread=function()return h.thread end,
        find=function(path)if path:find('Default__AbilitySystemBlueprintLibrary',1,true)then return lib end;return object('Function')end,
        findAll=function()return h.actions end,
        construct=function(class,outer,n,flags,internal,copyTransient,archetype,template)
            assert(flags==0x40 and copyTransient==false and archetype==false and template)
            h.copies=h.copies+1
            local copy=object('DamageCalculator_PBZDeflect')
            for _,field in ipairs({'AttackerAngerDamageMultiplier','TargetAngerDamageMultiplier','CanBreakAttacker','CanBreakAttackerFinal','CanBreakTarget'})do copy[field]=template[field]end
            return copy
        end,
        register=function(path,pre,post)h.hooks[path]={pre=pre,post=post};return 1,2 end,
        unregister=function()h.unhooked=h.unhooked+1 end})
    function h:fire(which,...)
        local hook=assert(self.hooks[Reflect.paths[which]],which)
        return hook.pre(...)
    end
    function h:actor(id,off)
        self.rules[id]=off and 'off' or 'keep'
        local actor=object(id..'_C');self.members[#self.members+1]={actor=actor,team='blue'}
        self.m:capture(actor,'/Game/'..id..'.'..id..'_C')
        return actor
    end
    function h:payload(actor,b)
        local p=object('DamagePreTakePayload');p.TargetActor=actor;p.DamageSource=object('BulletAttackModule');p.DamageSource.Bullet=b
        return p
    end
    function h:damage(actor,b,calculator,cause)
        local module=object('BulletAttackModule');module.Bullet=b
        local result=param(calculator)
        self:fire('damage',param(module),param(actor),nil,nil,param(tag(cause or 'Damage.Cause.Deflect.Perfect')),result)
        return result.value
    end
    function h:counter(actor,payload,kind,field)
        if payload then self:fire('owner',param(payload)) end
        local value=param(0.25)
        self:fire('magnitude',nil,param({effect=object(kind or 'GE_JingYe_Shield_Counter_C'),actor=actor}),param(tag(field or 'SetByCaller.Shield.CounterDamage.PhysicalDamage')),value)
        return value.value
    end
    return h
end
local function calculator()
    local calc=object('DamageCalculator_PBZDeflect')
    calc.AttackerAngerDamageMultiplier=0.5;calc.TargetAngerDamageMultiplier=0.75
    calc.CanBreakAttacker=true;calc.CanBreakAttackerFinal=true;calc.CanBreakTarget=true
    return calc
end
do
    local h=harness();h:actor('BP_Default',false)
    assert(next(h.hooks)==nil,'default installs no hooks')
    local a=h:actor('BP_Off',true);local c=calculator()
    local changed=h:damage(a,ranged,c)
    assert(changed~=c and changed.AttackerAngerDamageMultiplier==0 and changed.CanBreakAttacker==false)
    assert(changed.TargetAngerDamageMultiplier==c.TargetAngerDamageMultiplier and changed.CanBreakTarget==c.CanBreakTarget)
    assert(c.AttackerAngerDamageMultiplier==0.5 and c.CanBreakAttacker,'the shared calculator is untouched')
    assert(h:damage(a,ranged,c)==changed and h.copies==1,'same unit/template reuses a valid transient copy')
    assert(h:damage(a,melee,c)==c and h:damage(a,ranged,c,'Damage.Cause.Hit')==c)
    assert(h:damage(a,trace,c)==changed)
    local other=object('BP_Off_C');assert(h:damage(other,ranged,c)==c,'map actors of the same class are unaffected')
    local b=h:actor('BP_Off',false);assert(h:damage(b,ranged,c)==c,'new default spawn keeps the original')
    assert(h:damage(a,ranged,c)==changed,'a saved change does not rewrite an existing spawn')
    changed.valid=false;assert(h:damage(a,ranged,c)~=changed and h.copies==2,'GC-invalidated copies are rebuilt')
    local p=h:payload(a,ranged)
    assert(h:counter(a,p)==0)
    assert(h:counter(a,p,'GE_MaleThug_ClubShield_Counter_C','SetByCaller.Shield.CounterDamage.BleedAccumulation')==0)
    assert(h:counter(a,h:payload(a,melee))==0.25,'a later melee hit must replace the earlier ranged provenance')
    assert(h:counter(a,h:payload(a,ranged),'OtherEffect_C')==0.25)
    h:fire('owner',param(p));h.now=h.now+0.051;assert(h:counter(a,nil)==0.25,'stale provenance never suppresses another hit')
    h.now=2
    local t,v=param(1),param(7)
    h:fire('modify',param(p),param(tag('Damage.Damage.Attacker.AngerDamage.Normal')),t,v,param(false),param(false))
    assert(t.value==3 and v.value==0)
    t,v=param(1),param(7);v.deny=true
    h:fire('modify',param(p),param(tag('Damage.Damage.Attacker.AngerDamage.Normal')),t,v,param(false),param(false))
    assert(t.value==1 and v.value==7,'a refused value write must restore the modifier operation')
    h.thread=false;assert(h:damage(a,ranged,c)==c,'worker-thread callbacks cannot change gameplay state');h.thread=true
    t,v=param(1),param(7)
    h:fire('children',param(p),param(tag('Damage.Damage.Target.GeneralDamage')),t,v)
    assert(t.value==1 and v.value==7,'incoming damage and defence are preserved')
    h:fire('modify',param(p),param(tag('Damage.Damage.Attacker.UltimateChargeRegen')),t,v)
    assert(t.value==1 and v.value==7,'beneficial attacker regeneration is not retaliation')
    local component=object('PrimitiveComponent');local trigger=object('TriggerCapsule')
    function component:GetOwner()return trigger end
    function component:GetCollisionResponseToChannel()return self.response end
    function trigger:GetAttachParentActor()return a end
    local action=object('GAAction_ReboundProjectile_C');action.Trigger=trigger;action.GetAvatarActor=function()return a end;h.actions={action}
    local response=param(1)
    h:fire('collision',param(component),param(24),response)
    assert(response.value==0)
    component.response=response.value;h.hooks[Reflect.paths.collision].post(param(component))
    local unmatched=object('TriggerCapsule');action.Trigger=unmatched;response=param(1)
    h:fire('collision',param(component),param(24),response);assert(response.value==1,'unrelated trigger capsules are unchanged')
    response=param(1);h:fire('collision',param(component),param(1),response);assert(response.value==1,'other collision channels are untouched')
    h.ready=false;assert(h:damage(a,ranged,c)==c);h.m:tick()
    h.ready=true;h.members={};h.m:tick();assert(h:damage(a,ranged,c)==c,'world change and cleanup release actor records')
    local late=h.hooks[Reflect.paths.damage].pre;h.m:silence();assert(h.unhooked==6)
    late(nil,param(a),nil,nil,param(tag('Damage.Cause.Deflect')),param(c))
    assert(h.m:status().hooks==0)
end
print('remote_reflect: PASS (source classification, native hook flow, per-spawn isolation, melee/default preservation, cleanup)')
