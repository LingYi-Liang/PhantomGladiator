package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Effects=arg[1]and assert(loadfile(arg[1]))()or require('effect_instance_aim')
local U=require('ue_observe')
FName=function(text)return text end
local serial=0
local function object(class,label,outer)
    serial=serial+1;local key=serial
    local o={live=true,label=label or class,outer=outer}
    function o:IsValid()return self.live end
    function o:GetAddress()assert(self.live);return key end
    function o:GetFullName()assert(self.live);return class..' '..self.label end
    function o:GetFName()return {ToString=function()return self.label end}end
    function o:GetOuter()assert(self.live);return self.outer end
    return o
end
local classes={}
local function classOf(label)
    if classes[label]then return classes[label]end
    local c=object('Class',label)
    function c:IsAnyClass()return true end
    classes[label]=c;return c
end
local function typed(label,name,outer)
    local o=object(label,name,outer)
    function o:GetClass()return classOf(label)end
    return o
end
local function fixture()
    local h={now=0,thread=true,enabled=true,loop=nil,calls={},hooks={},copies={},scans=0,logs={}}
    h.world=typed('World','World')
    h.actor=typed('BP_Companion_C','Companion',h.world)
    h.enemy=typed('BP_Enemy_C','Enemy',h.world);h.enemy.x=100
    function h.enemy:K2_GetActorLocation()return {X=self.x,Y=0,Z=0}end
    h.player=typed('BP_Player_C','Player',h.world)
    h.key=U.key(h.actor)
    h.worldColor={R=5000,G=10,B=20,A=1}
    h.parent=typed('NiagaraParameterCollection','NPC_CharInfo_001')
    h.parent.Parameters={{Name={ToString=function()return 'NPC.NPC_CharInfo_001.CharRootPos'end}}}
    h.template=typed('NiagaraParameterCollectionInstance','DefaultInstance',h.parent)
    h.template.Collection=h.parent
    h.template.OverridenParameters={}
    h.template.ParameterStorage={ParameterData={GetArrayDataAddress=function()return 10000 end}}
    h.parent.DefaultInstance=h.template
    h.global=typed('NiagaraParameterCollectionInstance','WorldInstance',h.world)
    function h.global:GetColorParameter()return h.worldColor end
    h.lib=typed('NiagaraFunctionLibrary','Library')
    function h.lib:GetNiagaraParameterCollection()return h.global end
    h.original=typed('NiagaraSystem','NS_MengHua_SpaceTear_001')
    h.original.EmitterHandles={1,2}
    h.original.SystemSpawnScript=typed('NiagaraScript','Spawn')
    h.original.SystemUpdateScript=typed('NiagaraScript','Update')
    h.original.ParameterCollectionOverrides={}
    local function bullet(caster)
        local b=typed('PBZ_ParticleBullet','Bullet',h.world);b.BulletOwnerAvatar=caster;b.BulletStatus=2
        local c=typed('NiagaraComponent','Component',b);c.Asset=h.original;c.active=true
        function c:GetOwner()return b end
        function c:IsActive()return self.active end
        function c:SetAsset(value,reset)
            assert(h.thread and reset==false)
            h.calls[#h.calls+1]={'asset',self,value}
            if not h.rejectAsset then self.Asset=value end
            if h.deactivateOnSet then self.active=false end
        end
        function c:Deactivate()self.active=false;h.deactivations=(h.deactivations or 0)+1 end
        function c:Activate()
            h.activations=(h.activations or 0)+1
            assert(h.thread);self.active=not h.badActivation or self.Asset==h.original
        end
        b.ParticleComponent=c
        return b,c
    end
    h.bullet,h.comp=bullet(h.actor)
    h.playerBullet,h.playerComp=bullet(h.player)
    h.list={h.bullet,h.playerBullet}
    local options={clock=function()return h.now end,world=function()return h.world end,
        inGameThread=function()return h.thread end,active=function()return h.enabled end,
        allowed=function(key)return h.enabled and (key==h.key or key==h.extraKey) and not h.busy end,
        actorOf=function(key)return key==h.key and h.actor or key==h.extraKey and h.extraActor or nil end,
        ownerOf=function(value)
            if value==h.actor then return h.key end
            if value and value.BulletOwnerAvatar==h.actor then return h.key end
            if value and value.BulletOwnerAvatar==h.extraActor then return h.extraKey end
            return nil
        end,
        targetOf=function(key)return not h.noTarget and (key==h.extraKey and h.extraEnemy or h.enemy) or nil end,
        paused=function()return h.paused end,
        find=function(path)
            if path:find('Default__NiagaraFunctionLibrary',1,true)then return h.lib end
            if path:find('NPC_CharInfo_001.NPC_CharInfo_001',1,true)then return h.parent end
            return typed('Function',path)
        end,
        construct=function(class,outer,id,flags,internal,transients,archetype,template)
            assert(h.thread and flags==0x40 and internal==0 and transients==false and archetype==false and template)
            local n=typed(class.label,'Private_'..tostring(serial),outer)
            h.copies[#h.copies+1]=n
            if class.label=='NiagaraParameterCollectionInstance'then
                n.Collection=h.parent
                n.ParameterStorage={ParameterData={GetArrayDataAddress=function()return h.aliasBuffer and 10000 or 20000+U.key(n) end}}
                n.OverridenParameters={}
                function n:SetColorParameter(_,value)assert(h.thread);self.color=value;h.writes=(h.writes or 0)+1 end
                function n:GetColorParameter()return self.color or {R=0,G=0,B=0,A=1}end
            else
                n.EmitterHandles={1,2};n.SystemSpawnScript=not h.incomplete and h.original.SystemSpawnScript or nil
                n.SystemUpdateScript=h.original.SystemUpdateScript
                n.ParameterCollectionOverrides=h.aliasOverrides and h.original.ParameterCollectionOverrides or {}
            end
            return n
        end,
        collect=function(kind)assert(kind=='PBZ_ParticleBullet');h.scans=h.scans+1;return h.list end,
        register=function(path,fn)h.hooks[path]=fn;return 1,2 end,unregister=function(path)h.hooks[path]=nil end,
        loop=function(ms,fn)assert(ms==50);h.loop=fn;return 'loop'end,cancel=function()h.loop=nil;return true end,
        log=function(text)h.logs[#h.logs+1]=text end}
    h.effects=Effects.new(options)
    h.options=options
    h.makeBullet=bullet
    function h:step()assert(self.loop);self.loop()end
    return h
end
if arg[2]=='fixture'then return fixture,typed end
local passed=0
local function test(label,fn)fn();passed=passed+1;print('PASS '..label)end
test('owned effects receive private systems and collections while player effects and global values stay native',function()
    local h=fixture();h.effects:arm();h:step()
    assert(h.comp.Asset~=h.original and h.playerComp.Asset==h.original)
    local instance=h.comp.Asset.ParameterCollectionOverrides[1]
    assert(instance and instance~=h.global and instance~=h.template and instance.color.R==100)
    assert(h.worldColor.R==5000 and #h.original.ParameterCollectionOverrides==0)
    h.enemy.x=300;h:step();assert(instance.color.R==300 and h.worldColor.R==5000)
    h.noTarget=true;h:step();assert(instance.color.R==300,'do not replace a missing enemy with the player')
end)
test('pooled components handed to the actual player lose the private asset without changing other effects',function()
    local h=fixture();h.effects:arm();h:step();h.bullet.BulletOwnerAvatar=h.player;h:step()
    assert(h.comp.Asset==h.original and h.playerComp.Asset==h.original and not h.effects:status().running)
end)
test('native asset changes are preserved instead of being overwritten during cleanup',function()
    local h=fixture();h.effects:arm();h:step()
    local other=typed('NiagaraSystem','Other');h.comp.Asset=other;h:step();assert(h.comp.Asset==other)
end)
test('shared parameter memory or incomplete compiled systems cannot be attached',function()
    for _,field in ipairs({'aliasBuffer','incomplete','aliasOverrides'})do
        local h=fixture();h[field]=true;h.effects:arm();h:step()
        assert(h.comp.Asset==h.original and h.effects:status().failed>0 and h.worldColor.R==5000)
    end
end)
test('a private system that cannot activate is restored to the running original',function()
    local h=fixture();h.deactivateOnSet=true;h.badActivation=true
    h.effects:arm();h:step();assert(h.comp.Asset==h.original and h.comp.active==true)
end)
test('world replacement and wrong threads do not write detached systems or player collections',function()
    local h=fixture();h.effects:arm();h:step();local instance=h.comp.Asset.ParameterCollectionOverrides[1]
    h.world=typed('World','Next');h.enemy.x=999;h:step();assert(instance.color.R==100 and h.worldColor.R==5000)
    local other=fixture();other.thread=false;other.effects:arm();assert(other.loop==nil and #other.copies==0)
end)
test('native phase pauses retire owned overrides and unload only silences callbacks',function()
    local h=fixture();h.effects:tick();h.effects:arm();h:step();h.busy=true;h:step();assert(h.comp.Asset==h.original)
    h.busy=false;h.now=0.3;h.effects:arm();h:step();local private=h.comp.Asset
    h.effects:silence();assert(h.comp.Asset==private and h.loop==nil)
end)
test('delayed native bullets remain discoverable with paced scans and stop at the deadline',function()
    local h=fixture();h.list={};h.effects:arm();h:step();assert(h.scans==1)
    for i=1,4 do h.now=i*0.05;h:step()end
    assert(h.scans==1,'the active loop does not scan every frame')
    h.now=2;h.list={h.bullet};h:step();assert(h.comp.Asset~=h.original,'delayed native creation is covered after the first 150 ms')
    h.bullet.BulletStatus=3;h.now=21;h:step();assert(h.loop==nil and h.comp.Asset==h.original)
end)
test('two owned casters keep distinct target collections when sharing the same original system',function()
    local h=fixture();h.extraActor=typed('BP_OtherCompanion_C','OtherCompanion',h.world);h.extraKey=U.key(h.extraActor)
    h.extraEnemy=typed('BP_SecondEnemy_C','SecondEnemy',h.world)
    function h.extraEnemy:K2_GetActorLocation()return {X=900,Y=0,Z=0}end
    local bullet,comp=h.makeBullet(h.extraActor);h.list[#h.list+1]=bullet
    h.effects:arm();h:step()
    local first=h.comp.Asset.ParameterCollectionOverrides[1];local second=comp.Asset.ParameterCollectionOverrides[1]
    assert(first~=second and first.color.R==100 and second.color.R==900 and h.worldColor.R==5000)
end)
test('unknown or player activations do not create copies and owned activation is scoped to the component',function()
    local h=fixture();h.effects:tick()
    h.hooks[Effects.paths.activate](h.playerComp);assert(#h.copies==0)
    h.hooks[Effects.paths.activate](h.actor);assert(#h.copies==0)
    h.effects:arm()
    h.hooks[Effects.paths.activate](h.comp);assert(h.comp.Asset~=h.original and h.playerComp.Asset==h.original)
end)
test('stopping the owned roster cancels pending scans and restores attached assets',function()
    local h=fixture();h.effects:arm();h:step();h.enabled=false;h:step()
    assert(h.loop==nil and h.comp.Asset==h.original)
end)
print('effect_instance_aim: PASS ('..passed..' parameter/asset isolation checks; no game accessed)')
