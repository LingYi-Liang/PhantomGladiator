package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Look=require('hun_look')
local P=Look.PATHS
local index=0
local function object(label,fields)
    index=index+1;local id=index;local a=fields or {}
    a.label=label;a.valid=true
    function a:IsValid()return self.valid end
    function a:GetFullName()return self.label end
    function a:GetAddress()return id end
    return a
end
local function class(path)
    local c=object('BlueprintGeneratedClass '..path)
    local short=path:match('%.([^%.]+)$')
    function c:GetFName()return {ToString=function()return short end}end
    return c
end
local function instance(cls,h)
    local i=object('AnimInstance '..cls.label)
    function i:GetClass()return cls end
    function i:LinkAnimClassLayers(layer)h.calls[#h.calls+1]='instance link '..layer.label;if not h.linkIgnored then h.layers[layer]=true end end
    return i
end
-- A Hun body with its mesh, anim instance, weapons component and two weapon actors on weapon_r / weapon_l.
local function fixture(opts)
    opts=opts or {}
    local h={logs={},calls={},layers={},loaded={}}
    h.skin=object('SkeletalMesh /Game/Hun_Skin.Hun_Skin')
    h.clone=object('SkeletalMesh '..P.clone)
    h.player=class('/HuaShira/Characters/Hero/Hero_Hun/Animation/PBZ_ABP_Hun_Base.PBZ_ABP_Hun_Base_C')
    h.npc=class(P.anim);h.mm=class(P.mm);h.item=class(P.item)
    h.assets={[P.clone]=h.clone,[P.anim]=h.npc,[P.mm]=h.mm,[P.item]=h.item}
    h.sockets={hatSocket=true,weapon_r=true,weapon_l=true}
    h.materials={'MI_ZeroHun_Head_b','MI_Hun_Haircard_Healthfade'}
    -- A new body (and its weapons) for the same loaded assets and the same look instance.
    function h:body(opts)
    opts=opts or {}
    h.calls,h.layers,h.logAt,h.linkIgnored={},{},{},opts.linkIgnored
    local mesh=object('SkeletalMeshComponent /Game/Map.Hun:CharacterMesh0')
    mesh.asset=h.skin;mesh.AnimClass=h.player;mesh.anim=instance(h.player,h)
    function mesh:GetSkeletalMeshAsset()return self.asset end
    function mesh:SetSkeletalMeshAsset(asset)
        h.calls[#h.calls+1]='mesh '..asset.label;h.logAt=h.logAt or {};h.logAt['mesh '..asset.label]=#h.logs
        if not opts.meshIgnored then self.asset=asset end
    end
    function mesh:SetAnimInstanceClass(cls)
        h.calls[#h.calls+1]='class '..cls.label;h.logAt=h.logAt or {};h.logAt['class '..cls.label]=#h.logs
        if opts.classIgnored and cls==h.npc then return end
        self.AnimClass=cls;self.anim=instance(cls,h);h.layers={}
        if cls==h.npc and not opts.noBeginPlayLink then h.layers[h.mm]=true end
    end
    function mesh:GetAnimInstance()return self.anim end
    function mesh:GetLinkedAnimLayerInstanceByClass(cls)return h.layers[cls] and object('Linked '..cls.label) or nil end
    function mesh:LinkAnimClassLayers(cls)h.calls[#h.calls+1]='mesh link '..cls.label;h.layers[cls]=true end
    function mesh:DoesSocketExist(socket)return h.sockets[socket]==true end
    function mesh:GetNumMaterials()return #h.materials end
    function mesh:GetMaterial(i)return object('MaterialInstanceConstant /Game/M.'..h.materials[i+1])end
    h.mesh=mesh
    h.actor=object('BP_Monster_Hun_C /Game/Map.Hun_1',{Mesh=mesh})
    h.wc=object('CharacterWeaponsComponent')
    function h.wc:LinkDefaultAnimLayers()h.calls[#h.calls+1]='default layers';if not opts.noDefaultLayer then h.layers[h.item]=true end end
    h.actor['Character Weapons Component']=h.wc
    h.weapons={}
    for _,socket in ipairs({'weapon_r','weapon_l'})do
        local weapon=object('BP_Weapon_Hun_JueYing '..socket)
        function weapon:GetOwner()return h.actor end
        local comp=object('SkeletalMeshComponent /Game/Map.Weapon_'..socket..':Weapon Mesh')
        comp.socket=socket
        function comp:GetOwner()return weapon end
        function comp:GetAttachSocketName()return {ToString=function()return comp.socket end}end
        h.weapons[#h.weapons+1]=comp
    end
    function mesh:GetOwner()return h.actor end
    h.bodies=(h.bodies or 0)+1
    h.r={actor=h.actor,name='Hun_'..h.bodies}
    end
    h:body(opts)
    h.still=true
    h.look=Look.new({log=function(s)h.logs[#h.logs+1]=s end,fname=function(s)return s end,
        find=function(path)return h.loaded[path]end,
        load=function(path)local a=h.assets[path];h.loaded[path]=a;return a end,
        findAll=function(kind)assert(kind=='SkeletalMeshComponent');local list={mesh};for _,w in ipairs(h.weapons)do list[#list+1]=w end;return list end})
    function h:apply(r)return self.look:apply(r or self.r,function()return self.still end)end
    function h:logged(text)local n=0;for _,line in ipairs(self.logs)do if line:find(text,1,true)then n=n+1 end end;return n end
    function h:firstLog(text)for i,line in ipairs(self.logs)do if line:find(text,1,true)then return i end end end
    function h:count(text)local n=0;for _,c in ipairs(self.calls)do if c==text then n=n+1 end end;return n end
    return h
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end

test('the mesh becomes Hun_Clone and the anim class the NPC Hun class, each announced before and read back after',function()
    local h=fixture();local result=h:apply()
    assert(result.look==true and result.anim==true)
    assert(h.mesh.asset==h.clone and h.mesh.AnimClass==h.npc and h.layers[h.mm] and h.layers[h.item])
    assert(h.calls[1]=='mesh '..h.clone.label and h.calls[2]=='class '..h.npc.label and h.calls[3]=='default layers','mesh first, then class, then layers')
    local announced=h:firstLog('[HunLook] 即将 换网格');assert(announced and announced<=h.logAt['mesh '..h.clone.label],'the 即将 line is written before the native call')
    announced=h:firstLog('[HunLook] 即将 换动画类');assert(announced and announced<=h.logAt['class '..h.npc.label])
    assert(h:logged('换网格 读回 实例=Hun_1 调用=true 网格=Hun_Clone 材质=[MI_ZeroHun_Head_b|MI_Hun_Haircard_Healthfade] hatSocket=true')==1)
    assert(h:logged('武器挂接=[Weapon Mesh@weapon_l,Weapon Mesh@weapon_r]')>=2 and h:logged('verified=true')==2)
    assert(h:logged('ABP_MM_Monster=true（动画类自己的 BlueprintBeginPlay）')==1 and h:logged('ABP_Item_Hun_Summon=true（武器组件 LinkDefaultAnimLayers 调用=true）')==1)
    assert(h.r.undo.mesh==h.skin and h.r.undo.anim==h.player)
    h.look:recheck(h.r);assert(h:logged('复读 实例=Hun_1 网格=Hun_Clone 动画实例=PBZ_ABP_Base_MonsterHun_C ABP_MM_Monster=true ABP_Item_Hun_Summon=true')==1)
end)
test('a class whose BeginPlay did not link ABP_MM_Monster gets the same call from Lua, and a missing default layer the mesh link',function()
    local h=fixture({noBeginPlayLink=true,noDefaultLayer=true});local result=h:apply()
    assert(result.anim==true and h:count('instance link '..h.mm.label)==1 and h:count('mesh link '..h.item.label)==1)
    assert(h:logged('即将 链接 ABP_MM_Monster_C')==1 and h:logged('ABP_MM_Monster=true（Lua 补链接）')==1 and h:logged('ABP_Item_Hun_Summon=true（网格 LinkAnimClassLayers）')==1)
end)
test('an anim class that does not read back is undone to the recorded class and read back',function()
    local h=fixture({classIgnored=true});local result=h:apply()
    assert(result.look==true and result.anim==false)
    assert(h.mesh.AnimClass==h.player and h:count('class '..h.player.label)==1,'restored with the recorded class')
    assert(h:logged('即将 还原动画类')==1 and h:logged('已还原=true')==1 and h:logged('verified=false')==1)
end)
test('a missing layer after the class swap also undoes it',function()
    local h=fixture({noBeginPlayLink=true});h.linkIgnored=true
    local result=h:apply()
    assert(result.anim==false and h.mesh.AnimClass==h.player and h:logged('ABP_MM_Monster=false（Lua 补链接）')==1 and h:logged('已还原=true')==1)
end)
test('a mesh whose materials are the phantom ones, or that loses a weapon socket, is undone to Hun_Skin',function()
    local h=fixture();h.materials={'MI_FX_PhantomMode_Hun_Head_b'}
    local result=h:apply();assert(result.look==false and h.mesh.asset==h.skin and h:logged('还原网格 实例=Hun_1 调用=true 读回=Hun_Skin 已还原=true')==1)
    h=fixture();h.sockets.weapon_l=nil
    result=h:apply();assert(result.look==false and h.mesh.asset==h.skin and h:logged('插槽都在=false（缺 weapon_l）')==1)
    h=fixture({meshIgnored=true})
    result=h:apply();assert(result.look==false and h:logged('网格=Hun_Skin')>=1)
end)
test('a weapon that moved to another socket during the class swap fails the step and undoes it',function()
    local h=fixture()
    local set=h.mesh.SetAnimInstanceClass
    h.mesh.SetAnimInstanceClass=function(self,cls)set(self,cls);if cls==h.npc then h.weapons[1].socket='root' end end
    local result=h:apply();assert(result.anim==false and h.mesh.AnimClass==h.player and h:logged('（原=[')>=1)
end)
test('nothing is written when the identity changed or the original class cannot be read',function()
    local h=fixture();h.still=false;local result=h:apply()
    assert(result.look==false and result.anim==false and #h.calls==0 and h:logged('实例已变化，不换')==2)
    h=fixture();h.mesh.AnimClass=nil;result=h:apply()
    assert(result.anim==false and h:count('class '..h.npc.label)==0 and h:logged('读不到原动画类，无法保证还原，不换')==1)
end)
test('two bodies in a row failing a step switch it off for the load; a success in between resets the count',function()
    local h=fixture({classIgnored=true});local look=h.look
    local function run(opts)h:body(opts);return h:apply()end
    local a=h:apply();assert(a.anim==false and not look.off.anim)
    local b=run();assert(b.anim==true and look.streak.anim==0,'a success resets the streak')
    run({classIgnored=true});local d=run({classIgnored=true})
    assert(d.anim==false and look.off.anim==true and h:logged('已停用 换动画类：连续 2 只魂失败')==1)
    local e=run();assert(e.anim==nil and h:count('class '..h.npc.label)==0,'switched off: no class write on the next body')
    assert(e.look==true and h.mesh.asset==h.clone,'the other step goes on')
    assert(h:logged('换动画类 本次加载已停用，之后的魂都跳过（实例=Hun_5）')==1)
    run();assert(h:logged('换动画类 本次加载已停用')==1,'the skip is logged once')
    local m=fixture({meshIgnored=true});m:apply();m:body({meshIgnored=true});m:apply()
    assert(m.look.off.look==true and m:logged('已停用 换网格')==1);m:body();m:apply();assert(m:count('mesh '..m.clone.label)==0)
end)
test('a native error inside a step counts as a failure and is logged',function()
    local h=fixture()
    local set=h.mesh.SetAnimInstanceClass
    h.mesh.SetAnimInstanceClass=function(self,cls)if cls==h.npc then error('native fixture failure')end;return set(self,cls)end
    local result=h:apply();assert(result.anim==false and h.mesh.AnimClass==h.player and h:logged('调用=false')>=1 and h:logged('已还原=true')==1)
    local broken=fixture();broken.mesh.GetSkeletalMeshAsset=function()error('boom')end
    result=broken:apply();assert(result.look==false and #broken.calls==0 or broken:count('mesh '..broken.clone.label)==0)
end)
test('switches off leave the body untouched',function()
    local saved={look=Look.STEPS.look,anim=Look.STEPS.anim}
    Look.STEPS.look,Look.STEPS.anim=false,false
    local h=fixture();local result=h:apply();assert(next(result)==nil and #h.calls==0)
    Look.STEPS.look,Look.STEPS.anim=saved.look,saved.anim
end)
print('hun look: PASS '..n..' mesh/anim-class/readback/undo/breaker checks; native gameplay remains unverified')
