package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Look=require('hun_look')
local P=Look.PATHS
local CLONE={look='clone',anim=true}
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
local function vec(x,y,z)return {X=x,Y=y,Z=z}end
-- A Hun body with its mesh, anim instance, weapons component and two weapon actors on weapon_r / weapon_l.
-- AddComponentByClass on the body makes skeletal or cloth parts that behave as the engine does, unless h.broken
-- names a part and a call to break on it.
local function fixture(opts)
    opts=opts or {}
    local h={logs={},calls={},layers={},loaded={},broken={}}
    h.nativePhysics=object('PhysicsAsset '..P.physics)
    h.skin=object('SkeletalMesh /Game/Hun_Skin.Hun_Skin',{PhysicsAsset=not opts.skinNoPhysics and h.nativePhysics or nil})
    h.skeleton=object('Skeleton /Game/Hun_Skin_Skeleton.Hun_Skin_Skeleton');h.skin.Skeleton=h.skeleton
    h.clone=object('SkeletalMesh '..P.clone)
    h.player=class('/HuaShira/Characters/Hero/Hero_Hun/Animation/PBZ_ABP_Hun_Base.PBZ_ABP_Hun_Base_C')
    h.npc=class(P.anim);h.mm=class(P.mm);h.item=class(P.item)
    h.assets={[P.clone]=h.clone,[P.anim]=h.npc,[P.mm]=h.mm,[P.item]=h.item}
    if opts.full~=false then
        h.body_=object('SkeletalMesh '..P.body,{PhysicsAsset=not opts.bodyNoPhysics and object('PhysicsAsset /Game/PA_Hun.PA_Hun') or nil})
        h.copyPose=class(P.copyPose);h.meshClass=class(P.meshClass);h.clothClass=class(P.clothClass)
        h.assets[P.body]=h.body_;h.assets[P.copyPose]=h.copyPose;h.assets[P.meshClass]=h.meshClass;h.assets[P.clothClass]=h.clothClass
        for _,spec in ipairs({Look.HEAD,table.unpack(Look.PARTS)})do h.assets[spec.asset]=object('SkeletalMesh '..spec.asset)end
        for _,spec in ipairs(Look.CLOTH)do h.assets[spec.asset]=object('ChaosClothAsset '..spec.asset)end
    end
    h.sockets={hatSocket=true,weapon_r=true,weapon_l=true,head=true}
    h.materials={'MI_ZeroHun_Head_b','MI_Hun_Haircard_Healthfade'}
    h.headAt=vec(0,0,170)
    -- A new body (and its weapons) for the same loaded assets and the same look instance.
    function h:body(opts)
    opts=opts or {}
    h.calls,h.layers,h.logAt,h.linkIgnored,h.parts={},{},{},opts.linkIgnored,{}
    local mesh=object('SkeletalMeshComponent /Game/Map.Hun:CharacterMesh0')
    mesh.asset=h.skin;mesh.AnimClass=h.player;mesh.anim=instance(h.player,h)
    function mesh:GetSkeletalMeshAsset()return self.asset end
    function mesh:SetPhysicsAsset(asset,force)
        assert(force==false);h.calls[#h.calls+1]='physics '..asset.label;h.logAt['physics']=#h.logs
        if not opts.physicsIgnored then self.PhysicsAssetOverride=asset end
    end
    function mesh:SetSkeletalMeshAsset(asset)
        h.calls[#h.calls+1]='mesh '..asset.label;h.logAt=h.logAt or {};h.logAt['mesh '..asset.label]=#h.logs
        if not opts.meshIgnored and not(opts.bodyIgnored and asset==h.body_)then self.asset=asset end
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
    function mesh:GetSocketLocation(socket)assert(socket=='head');return h.headAt end
    h.mesh=mesh
    h.actor=object('BP_Monster_Hun_C /Game/Map.Hun_1',{Mesh=mesh})
    function h.actor:AddComponentByClass(cls,manual,transform,deferred)
        assert(manual==true and deferred==false and transform.Scale3D.X==1)
        h.calls[#h.calls+1]='add '..cls.label;h.logAt['add '..#h.parts]=#h.logs
        if h.addFails then return nil end
        local cloth=cls==h.clothClass
        local c=object((cloth and'ChaosClothComponent'or'SkeletalMeshComponent')..' /Game/Map.Hun:Part'..#h.parts)
        c.cloth=cloth;c.visible=true;c.ComponentTags={}
        if cloth then c.bUseAttachedParentAsPoseComponent=not h.poseOff end
        local function broken(what)return c.partName and h.broken[c.partName]==what end
        function c:GetOwner()return h.actor end
        function c:K2_AttachToComponent(parent,socket,a,b,s,weld)
            assert(a==2 and b==2 and s==2 and weld==false);self.parent=parent;self.socket=socket
        end
        function c:GetAttachParent()return self.parent end
        function c:GetAttachSocketName()return {ToString=function()return self.socket end}end
        function c:SetSkeletalMeshAsset(asset)
            self.asset=asset
            for _,spec in ipairs({Look.HEAD,table.unpack(Look.PARTS)})do if h.assets[spec.asset]==asset then self.partName=spec.name end end
            h.calls[#h.calls+1]='part '..tostring(self.partName)
            if broken('asset')then self.asset=nil end
        end
        function c:GetSkeletalMeshAsset()return self.asset end
        function c:SetAnimInstanceClass(cls2)h.logAt['part class '..tostring(self.partName)]=#h.logs;if not broken('class')then self.anim=instance(cls2,h)end end
        function c:GetAnimInstance()return self.anim end
        function c:SetAnimationMode(mode,force)assert(force==false);self.mode=mode end
        function c:GetAnimationMode()return self.mode end
        function c:SetEnableAnimation(v)self.animOn=v end
        function c:IsVisible()return self.visible end
        function c:SetVisibility(v,children)assert(children==false);self.visible=v end
        function c:DoesSocketExist(s)return s=='head'end
        function c:GetSocketLocation(s)assert(s=='head');return h.headGap and vec(0,0,170+h.headGap) or h.headAt end
        function c:SetClothAsset(asset)
            for _,spec in ipairs(Look.CLOTH)do if h.assets[spec.asset]==asset then self.partName=spec.name end end
            h.calls[#h.calls+1]='cloth '..tostring(self.partName);h.logAt['cloth '..tostring(self.partName)]=#h.logs
            if not broken('clothAsset')and not broken('anyAsset')then self.clothAsset=asset end
        end
        function c:GetClothAsset()return self.clothAsset end
        function c:SetAsset(asset)h.calls[#h.calls+1]='cloth set '..tostring(self.partName);if not broken('anyAsset')then self.clothAsset=asset end end
        function c:GetAsset()return self.clothAsset end
        function c:SetEnableSimulation(v)self.sim=v and not broken('sim')end
        function c:RecreateClothSimulationProxy()end
        function c:ForceNextUpdateTeleportAndReset()end
        function c:IsSimulationEnabled()return self.sim==true end
        function c:IsSimulationSuspended()return false end
        function c:K2_DestroyComponent(target)assert(target==self);h.calls[#h.calls+1]='destroy '..tostring(self.partName);self.destroying=true end
        function c:IsBeingDestroyed()return self.destroying==true end
        h.parts[#h.parts+1]=c
        return c
    end
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
    h.look=Look.new({log=function(s)h.logs[#h.logs+1]=s end,fname=function(s)return s end,steps=opts.steps or CLONE,player=function()return h.wearer end,
        find=function(path)return h.loaded[path]end,
        load=function(path)local a=h.assets[path];h.loaded[path]=a;return a end,
        findAll=function(kind)
            assert(kind=='SkeletalMeshComponent')
            local list={h.mesh};for _,w in ipairs(h.weapons)do list[#list+1]=w end
            for _,c in ipairs(h.parts)do if not c.cloth then list[#list+1]=c end end
            return list
        end})
    function h:apply(r)return self.look:apply(r or self.r,function()return self.still end)end
    function h:logged(text)local n=0;for _,line in ipairs(self.logs)do if line:find(text,1,true)then n=n+1 end end;return n end
    function h:firstLog(text)for i,line in ipairs(self.logs)do if line:find(text,1,true)then return i end end end
    function h:count(text)local n=0;for _,c in ipairs(self.calls)do if c==text then n=n+1 end end;return n end
    function h:part(name_)for _,c in ipairs(self.parts)do if c.partName==name_ then return c end end end
    function h:position(text)for i,c in ipairs(self.calls)do if c==text then return i end end end
    return h
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end

test('a lost NPC movement layer is restored after the action, without rebuilding the body or item layer',function()
    local h=fixture();assert(h:apply().anim)
    local mesh,main=h.mesh,h.mesh.anim
    local move=object('movement');function move:GetOwner()return h.actor end
    function h.actor:GetMovementComponent()return move end
    function main:TryGetPawnOwner()return h.actor end
    local graph=instance(h.mm,h);function graph:TryGetPawnOwner()return h.actor end
    local refs=0
    function graph:SetReferences()refs=refs+1;self.CharacterMovement=move;self.RenewalHun=h.actor end
    local item=instance(h.item,h);mesh.LinkedInstances={item}
    function mesh:GetLinkedAnimLayerInstanceByClass(c)
        for _,i in ipairs(self.LinkedInstances) do if i:GetClass()==c then return i end end
    end
    local links=0
    function main:LinkAnimClassLayers(c)
        assert(c==h.mm);links=links+1;mesh.LinkedInstances[#mesh.LinkedInstances+1]=graph
    end
    local clip=object('sword swing')
    function main:GetCurrentActiveMontage()return clip end
    function main:Montage_IsPlaying()return true end
    h.look:maintainMotion(h.r,0);assert(links==0,'never relink during an attack')
    clip=nil
    h.look:maintainMotion(h.r,2);assert(links==1 and refs==1 and graph.RenewalHun==h.actor)
    h.look:maintainMotion(h.r,4);assert(links==1 and refs==1 and mesh.anim==main and mesh.LinkedInstances[1]==item)
    mesh.LinkedInstances={item};h.look:maintainMotion(h.r,8)
    assert(links==2,'repair a later loss on the same body, even without a weapon change')
    mesh.LinkedInstances={instance(class('/Game/Cinematic.Cinematic_C'),h),item}
    h.look:maintainMotion(h.r,10);assert(links==2,'preserve a deliberate replacement layer')
    mesh.LinkedInstances={item};h.still=false;h.look:maintainMotion(h.r,12);assert(links==2)
end)
test('a partial bone position during appearance readback leaves the equipped parts attached',function()
    local h=fixture({steps=Look.STEPS});assert(h:apply().full)
    function h.mesh:GetSocketLocation()return {X=0} end
    h.look:recheck(h.r)
    assert(h.r.full and h.r.lookResult.full and not h:part('meshhead').destroying)
end)

---- Stage 1 (Hun_Clone + anim class), with the look switch on 'clone'.
test('local attachment traversal reads both weapon sockets without scanning the world',function()
    local h=fixture()
    h.actor.RootComponent=h.mesh;h.actor.Children={}
    h.mesh.AttachChildren=h.weapons
    function h.mesh:IsA()return true end
    for _,comp in ipairs(h.weapons) do
        comp.AttachChildren={};comp.IsA=h.mesh.IsA
        local weapon=comp:GetOwner();weapon.RootComponent=comp
        h.actor.Children[#h.actor.Children+1]=weapon
    end
    local scans=0
    h.look=Look.new({steps=CLONE,log=function(s)h.logs[#h.logs+1]=s end,fname=function(s)return s end,
        find=function(path)return h.assets[path]end,findAll=function()scans=scans+1;return {} end})
    local result=h:apply()
    assert(result.look and result.anim and scans==0 and h:logged('武器挂接=[Weapon Mesh@weapon_l,Weapon Mesh@weapon_r]')>=2)
end)
test('unload restores the live body before removing the head and respects a newer external mesh',function()
    for _,replace in ipairs({false,true}) do
        local h=fixture({steps={look='full',cloth=true,anim=true}})
        assert(h:apply().full and h.r.appliedAnim==h.npc)
        local original=h.mesh.asset
        if replace then h.mesh.asset=h.clone;h.mesh.AnimClass=h.copyPose end
        h.look:cleanup(h.r,'Mod 卸载')
        assert(h.mesh.asset==(replace and h.clone or h.skin) and h.mesh.asset~=original)
        assert(h.mesh.AnimClass==(replace and h.copyPose or h.player))
        for _,p in ipairs(h.r.parts)do assert(p.gone)end
    end
end)
test('the mesh becomes Hun_Clone and the anim class the NPC Hun class, each announced before and read back after',function()
    local h=fixture();local result=h:apply()
    assert(result.look==true and result.anim==true)
    assert(h.mesh.asset==h.clone and h.mesh.AnimClass==h.npc and h.layers[h.mm] and h.layers[h.item])
    assert(h.calls[1]=='mesh '..h.clone.label and h.calls[2]=='physics '..h.nativePhysics.label and h.calls[3]=='class '..h.npc.label and h.calls[4]=='default layers','mesh first, then collision, class, layers')
    local announced=h:firstLog('[HunLook] 即将 换网格');assert(announced and announced<=h.logAt['mesh '..h.clone.label],'the 即将 line is written before the native call')
    announced=h:firstLog('[HunLook] 即将 换动画类');assert(announced and announced<=h.logAt['class '..h.npc.label])
    assert(h:logged('换网格 读回 实例=Hun_1 调用=true 网格=Hun_Clone 材质=[MI_ZeroHun_Head_b|MI_Hun_Haircard_Healthfade] hatSocket=true')==1)
    assert(h:logged('武器挂接=[Weapon Mesh@weapon_l,Weapon Mesh@weapon_r]')>=2 and h:logged('verified=true')==3)
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
    local h=fixture({steps={look=false,anim=false}});local result=h:apply();assert(next(result)==nil and #h.calls==0)
end)

---- Stage 2 (full look: head, body, parts, cloth).
local FULL={look='full',cloth=true,anim=true}
test('full look: the head reads back before the body is swapped, then the parts; each body gets all four cloth parts',function()
    local h=fixture({steps=FULL});local result=h:apply()
    assert(result.full==true and result.look==nil and result.anim==true,'full look stands, no clone fallback')
    local head=h:part('meshhead')
    assert(head and head.parent==h.mesh and head.socket=='None' and head.anim and head.anim:GetClass()==h.copyPose)
    assert(h:position('part meshhead')<h:position('mesh '..h.body_.label),'the head is added before the body is swapped')
    assert(h.mesh.asset==h.body_ and h.r.undo.mesh==h.skin)
    assert(h:part('meshBrowLashCard').parent==head,'the brow card hangs on the head')
    for _,name_ in ipairs({'meshBand','meshScarf'})do assert(h:part(name_).parent==h.mesh)end
    local hat=h:part('Hun_Hat');assert(hat.parent==h.mesh and hat.socket=='hatSocket' and hat.mode==2 and hat.animOn==false and hat.anim==nil,'the hat is static at hatSocket')
    assert(#head.ComponentTags==2 and h:part('meshBand').ComponentTags[1]=='PBZ.AllowLegacyClothLeaderPose')
    local cloth={};for _,c in ipairs(h.parts)do if c.cloth then cloth[#cloth+1]=c end end
    assert(#cloth==4 and cloth[1].partName=='CA_Hun_Hair' and cloth[1].parent==head and cloth[1].sim==true,'hair attaches to the head')
    assert(h:logged('四件全加')==1 and h:logged('布料 读回 实例=Hun_1 CA_Hun_Hair 挂在=Part0')==1)
    assert(h:logged('布料备选 RefreshClothComponents 本版不做')==1)
    assert(h:logged('部件 读回 实例=Hun_1 meshhead')==1 and h:logged('头骨距离=0.00cm')==1)
    assert(h:logged('武器挂接=[Weapon Mesh@weapon_l,Weapon Mesh@weapon_r]')>=2,'the added parts are not taken for weapons')
    assert(h:logged('完整外观（默认） 头和身体=true 其余部件：meshBrowLashCard=true meshBand=true meshScarf=true Hun_Hat=true')==1)
    -- Every native add and the cloth asset are announced first.
    for i=0,#h.parts-1 do assert(h.logAt['add '..i] and h.logs[h.logAt['add '..i]]:find('即将 新建部件',1,true),'即将 before AddComponentByClass '..i)end
    assert(h.logs[h.logAt['cloth CA_Hun_Hair']]:find('即将 布料 CA_Hun_Hair',1,true))
    assert(h.logs[h.logAt['part class meshhead']]:find('即将 部件 meshhead',1,true))
    h.look:recheck(h.r);assert(h:logged('复读 头部跟随 实例=Hun_1 头骨距离=0.00cm 跟随=true 布料：CA_Hun_Hair 模拟=true')==1)
    -- The second body of the load gets all four cloth parts.
    h:body();local second=h:apply()
    local count=0;for _,c in ipairs(h.parts)do if c.cloth and not c.destroying then count=count+1 end end
    assert(second.full==true and count==4 and h:logged('四件全加')==2)
    assert(h:part('CA_Hun_Skirt').ComponentTags[1]=='SlicedLowerBody' and h:part('CA_Hun_Cape').parent==h.mesh)
end)
test('a head that does not read back is destroyed and the body keeps Hun_Clone (never headless)',function()
    local h=fixture({steps=FULL});h.broken.meshhead='class'
    local result=h:apply()
    assert(result.full==false and result.look==true and h.mesh.asset==h.clone,'falls back to Hun_Clone')
    assert(h:count('mesh '..h.body_.label)==0,'the body is never swapped without a head')
    assert(h:part('meshhead').destroying==true and h:logged('还原完整外观 实例=Hun_1 原因=头没读回 销毁部件：meshhead=调用true/销毁中true/已销毁')==1)
    h=fixture({steps=FULL});h.addFails=true
    result=h:apply();assert(result.full==false and result.look==true and h:count('mesh '..h.body_.label)==0)
end)
test('a body swap that does not read back destroys the head, restores the mesh and takes Hun_Clone',function()
    local h=fixture({steps=FULL,bodyIgnored=true});local result=h:apply()
    assert(result.full==false and result.look==true and h.mesh.asset==h.clone and h:part('meshhead').destroying==true)
    assert(h:logged('换身体 读回 实例=Hun_1 调用=true 网格=Hun_Skin')==1 and h:logged('原因=身体没读回')==1)
    h=fixture({steps=FULL});h.sockets.weapon_r=nil
    result=h:apply();assert(result.full==false and h:logged('插槽都在=false（缺 weapon_r）')>=1 and h:part('meshhead').destroying==true)
end)
test('cloth: a part whose asset does not read back is destroyed and read back; SetAsset is the second try',function()
    local h=fixture({steps=FULL});h:apply()
    h:body();h.broken.CA_Hun_Skirt='anyAsset';h.broken.CA_Hun_Cape='clothAsset'
    local result=h:apply()
    assert(result.full==true,'a body cloth failing leaves the full look')
    assert(h:part('CA_Hun_Skirt').destroying==true and h:logged('布料销毁 实例=Hun_2 CA_Hun_Skirt=调用true/销毁中true/已销毁')==1)
    local cape=h:part('CA_Hun_Cape');assert(not cape.destroying and cape.clothAsset and h:count('cloth set CA_Hun_Cape')==1 and h:logged('资源=CA_Hun_Cape（SetAsset）')==1)
    assert(h.look.streak.cloth==1,'the body counts as a cloth failure')
end)
test('cloth: a pose flag that reads off is written on and read back; simulation that does not start fails the part',function()
    local h=fixture({steps=FULL});h.poseOff=true;h:apply()
    assert(h:part('CA_Hun_Hair').bUseAttachedParentAsPoseComponent==true and h:logged('抄父姿势=false→true')==4)
    h=fixture({steps=FULL});h.broken.CA_Hun_Hair='sim'
    local result=h:apply();assert(result.full==false and result.look==true and h.mesh.asset==h.clone,'no hair: Hun_Clone instead')
    assert(h:logged('原因=头发布料没读回，没有头发，改用 Hun_Clone')==1 and h.look.streak.cloth==1 and h.look.streak.head==0,'a cloth failure, not a head failure')
    for _,c in ipairs(h.parts)do assert(c.destroying==true,'every added part is destroyed')end
end)
test('the cloth breaker: two bodies in a row without hair switch cloth off and later bodies take Hun_Clone directly',function()
    local h=fixture({steps=FULL});h.broken.CA_Hun_Hair='anyAsset';h:apply()
    h:body();h.broken.CA_Hun_Hair='anyAsset';h:apply()
    assert(h.look.off.cloth==true and h:logged('已停用 布料：连续 2 只魂失败')==1)
    h:body();local result=h:apply()
    assert(result.look==true and result.full==nil and #h.parts==0 and h:logged('布料 本次加载已停用，之后的魂都改用 Hun_Clone（实例=Hun_3）')==1)
end)
test('the head breaker: two bodies in a row failing the head switch the full look off',function()
    local h=fixture({steps=FULL});h.broken.meshhead='asset';h:apply()
    h:body();h.broken.meshhead='asset';h:apply()
    assert(h.look.off.head==true and h:logged('已停用 完整外观（头和身体）：连续 2 只魂失败')==1)
    h:body();local result=h:apply();assert(result.look==true and #h.parts==0 and h:count('add '..h.meshClass.label)==0)
end)
test('a head that does not follow the body at the second readback undoes the full look to Hun_Clone',function()
    local h=fixture({steps=FULL});h:apply()
    h.headGap=5;h.look:recheck(h.r)
    assert(h:logged('复读 头部跟随 实例=Hun_1 头骨距离=5.00cm 跟随=false')==1 and h.mesh.asset==h.clone)
    for _,c in ipairs(h.parts)do assert(c.destroying==true)end
    assert(h.r.lookResult.full==false and h.r.lookResult.look==true and h.look.streak.head==1)
end)
test('parts: death and cleanup leave transferred and replaced parts intact',function()
    local h=fixture({steps=FULL});h:body();h:apply()
    local hat,cape=h:part('Hun_Hat'),h:part('CA_Hun_Cape')
    function hat:GetOwner()return h.player end
    cape.label='another component at this address'
    h.look:hideParts(h.r);h.look:cleanup(h.r,'实例离场')
    assert(hat.visible and cape.visible and not hat.destroying and not cape.destroying)
end)
test('native revival shows only the same parts actually hidden for this death',function()
    local h=fixture({steps=FULL});h:apply()
    local head,hat,cape=h:part('meshhead'),h:part('Hun_Hat'),h:part('CA_Hun_Cape')
    cape.visible=false
    h.look:hideParts(h.r);h.look:hideParts(h.r)
    assert(not head.visible and not hat.visible)
    function hat:GetOwner()return h.player end
    h.look:restoreDeathVisibility(h.r)
    assert(head.visible and not cape.visible and not hat.visible)
    head.visible=false;h.look:restoreDeathVisibility(h.r);assert(not head.visible,'consume the restoration only once')
end)
test('parts: visibility text, the death hide, and cleanup destroy every registered part and read it back',function()
    local h=fixture({steps=FULL});h:body();h:apply()
    assert(h.look:partsText(h.r)=='meshhead:true,meshBrowLashCard:true,meshBand:true,meshScarf:true,Hun_Hat:true,CA_Hun_Hair:true,CA_Hun_UpperCloth:true,CA_Hun_Skirt:true,CA_Hun_Cape:true')
    h.look:hideParts(h.r);assert(h:part('Hun_Hat').visible==false and h:logged('死亡隐藏部件 实例=Hun_2 meshhead=调用true/可见false')==1)
    h.look:cleanup(h.r,'实例离场')
    for _,c in ipairs(h.parts)do assert(c.destroying==true)end
    assert(h:logged('清理部件 实例=Hun_2 原因=实例离场 CA_Hun_Cape=调用true/销毁中true/已销毁')==1 and h:logged('全部确认=true')>=1)
    local before=#h.logs;h.look:cleanup(h.r,'again');assert(#h.logs==before,'nothing left to destroy is not logged again')
end)
test('the clone switch never adds parts, and a missing full-look asset falls back to Hun_Clone',function()
    local h=fixture();h:apply();assert(#h.parts==0 and h.mesh.asset==h.clone)
    h=fixture({steps=FULL,full=false});local result=h:apply()
    assert(result.full==false and result.look==true and #h.parts==0 and h:logged('完整外观 实例=Hun_1；没载入：meshClass、copyPose、body，不做')==1)
end)
test('a body mesh with no physics asset gets the native body asset, announced first and read back',function()
    local h=fixture();h:apply()
    assert(h.mesh.asset==h.clone and h.mesh.PhysicsAssetOverride==h.nativePhysics and h:count('physics '..h.nativePhysics.label)==1)
    assert(h.r.physicsPatched==true and h:logged('补受击碰撞 读回 实例=Hun_1 调用=true')==1 and h:logged('verified=true；能否被打中以实战掉血为准')==1)
    assert(h.logs[h.logAt.physics]:find('即将 补受击碰撞（换外观后） 实例=Hun_1 网格 Hun_Clone 没有物理资产',1,true),'the announcement is the last line before the call')
    assert(h:position('physics '..h.nativePhysics.label)<h:position('class '..h.npc.label),'collision before the anim class')
    h=fixture({steps=FULL});h:apply()
    assert(h.mesh.asset==h.body_ and h.mesh.PhysicsAssetOverride==nil and h:logged('补受击碰撞')==0,'a mesh with its own asset is left alone')
    h=fixture({steps=FULL,bodyNoPhysics=true});h:apply()
    assert(h.mesh.asset==h.body_ and h.mesh.PhysicsAssetOverride==h.nativePhysics,'a replaced player body with no asset is patched too')
    h=fixture({physicsIgnored=true});h:apply()
    assert(h.r.physicsPatched==false and h:logged('verified=false')>=1 and h.mesh.asset==h.clone,'an unread write is reported, the look stands')
    h=fixture({skinNoPhysics=true});h.assets[P.physics]=h.nativePhysics;h:apply()
    assert(h.mesh.PhysicsAssetOverride==h.nativePhysics,'falls back to the asset path when the native mesh had none')
    h=fixture({skinNoPhysics=true});h:apply()
    assert(h.mesh.PhysicsAssetOverride==nil and h:logged('原生的也没载入，没补，可能打不中')==1)
    h=fixture();h.still=false;h:apply();assert(h:count('physics '..h.nativePhysics.label)==0,'a changed instance is not written')
    h=fixture({steps={look='clone',anim=true,physics=false}});h:apply();assert(h.mesh.PhysicsAssetOverride==nil and h:logged('受击碰撞')==0)
end)
test('a head that stops following falls back to Hun_Clone at the recheck and still gets collision',function()
    local h=fixture({steps=FULL});h:apply();assert(h.mesh.PhysicsAssetOverride==nil)
    h.headGap=5;h.look:recheck(h.r)
    assert(h.mesh.asset==h.clone and h.mesh.PhysicsAssetOverride==h.nativePhysics and h:logged('即将 补受击碰撞（复读退回后）')==1)
end)

-- The real player as readOutfit reads it: CharacterMesh0 with an attach tree of the player's own components.
local FOLLOW={look='full',cloth=true,anim=true,follow=true}
local function wearer(h,opts)
    opts=opts or {}
    local p=object('BP_Renewal_Hun_C /Game/Map.Player')
    local w={actor=p,assets={}}
    local function asset(kind,name,fields)
        local a=object(kind..' /Game/Outfit/'..name..'.'..name,fields);w.assets[name]=a;return a
    end
    local function comp(kind,name,assetObject,parent,fields)
        local c=object(kind..' /Game/Map.Player:'..name,fields or {})
        c.SkinnedAsset=assetObject;c.AttachChildren={};c.ComponentTags=c.ComponentTags or {}
        function c:GetOwner()return self.owner or p end
        function c:IsA(cls)return(cls==h.meshClass and kind=='SkeletalMeshComponent')or(cls==h.clothClass and kind=='ChaosClothComponent')end
        function c:IsVisible()return not self.bHiddenInGame end
        function c:GetAttachSocketName()return {ToString=function()return c.socket or'None'end}end
        function c:GetAnimInstance()return self.inst end
        function c:GetNumMaterials()return #(self.mats or {})end
        function c:GetMaterial(i)return self.mats[i+1]end
        if parent then parent.AttachChildren[#parent.AttachChildren+1]=c end
        w[name]=c;return c
    end
    local body=asset('SkeletalMesh',opts.bodyName or'Hun_MoTian_Body_Simple',{Skeleton=opts.skeleton or h.skeleton,PhysicsAsset=object('PhysicsAsset /Game/PA.PA')})
    local mesh=comp('SkeletalMeshComponent','CharacterMesh0',body)
    p.Mesh=mesh
    if not opts.wholeModel then
        local pose=function()return instance(h.copyPose,h)end
        local head=comp('SkeletalMeshComponent','meshhead',opts.headAsset or asset('SkeletalMesh','Hun_Head_Mod'),mesh,{inst=pose(),AnimClass=h.copyPose,ComponentTags={'GhostTrailMesh','SlicedUpperBody'}})
        comp('SkeletalMeshComponent','Hun_Hat01',nil,head,{bHiddenInGame=true})
        comp('SkeletalMeshComponent','meshBrowLashCard',asset('SkeletalMesh','Brow_Mod'),head,{inst=pose(),AnimClass=h.copyPose})
        comp('SkeletalMeshComponent','meshScarf',nil,mesh,{inst=pose(),AnimClass=h.copyPose})
        comp('SkeletalMeshComponent','meshBand',asset('SkeletalMesh','Hun_MoTian_Hair_Band'),mesh,{inst=pose(),AnimClass=h.copyPose,ComponentTags={'PBZ.AllowLegacyClothLeaderPose'}})
        comp('SkeletalMeshComponent','Hun_Hat',asset('SkeletalMesh','Hun_Hat_MoTian'),mesh,{socket='hatSocket',bHiddenInGame=not opts.hatShown,AnimClass=h.copyPose})
        comp('SkeletalMeshComponent','Knife',asset('SkeletalMesh','Hun_Knife'),mesh,{socket='Pt_Knife_Back_Socket'})
        comp('StaticMeshComponent','SwitchKey',nil,mesh)
        comp('NiagaraComponent','Shachi Loop',nil,mesh)
        comp('GroomComponent','Hair_Bangs',nil,head).GetClass=function()return class('/Script/HairStrandsCore.GroomComponent')end
        local weapon=comp('SkeletalMeshComponent','Weapon Mesh',asset('SkeletalMesh','Hun_BaiYing'),mesh)
        weapon.owner=object('BP_Weapon_Hun_BaiYing_C')
        comp('ChaosClothComponent','CA_Hun_Hair',opts.hairAsset or asset('ChaosClothAsset','CA_MoTian_Hair'),head)
        for _,name in ipairs({'CA_Hun_UpperCloth','CA_Hun_Skirt','CA_Hun_Cape'})do comp('ChaosClothComponent',name,asset('ChaosClothAsset',name..'_MoTian'),mesh)end
    end
    h.wearer=p
    return w
end
local function partOf(h,a)for _,c in ipairs(h.parts)do if c.asset==a or c.clothAsset==a then return c end end end
test('follow: the body takes what the player wears now, read only; hidden, empty and non-outfit parts are left out',function()
    local h=fixture({steps=FOLLOW});local w=wearer(h);local result=h:apply()
    assert(result.full==true and result.follow==true and result.look==nil and result.anim==true)
    assert(h.mesh.asset==w.assets.Hun_MoTian_Body_Simple and h:count('mesh '..h.body_.label)==0,'the player body, not the default one')
    assert(#h.parts==7,'head, brow card, band and four cloth parts: '..#h.parts)
    local head=partOf(h,w.assets.Hun_Head_Mod)
    assert(head.parent==h.mesh and head.anim:GetClass()==h.copyPose and #head.ComponentTags==2 and h.r.headName=='meshhead')
    assert(partOf(h,w.assets.Brow_Mod).parent==head and partOf(h,w.assets.CA_MoTian_Hair).parent==head)
    assert(partOf(h,w.assets.Hun_MoTian_Hair_Band).ComponentTags[1]=='PBZ.AllowLegacyClothLeaderPose')
    assert(partOf(h,w.assets.CA_Hun_Skirt_MoTian).parent==h.mesh and partOf(h,w.assets.CA_Hun_Skirt_MoTian).sim==true)
    assert(not partOf(h,w.assets.Hun_Knife)and not partOf(h,w.assets.Hun_BaiYing)and not partOf(h,w.assets.Hun_Hat_MoTian))
    assert(h:logged('没抄=[meshScarf（空）,Hun_Hat（隐藏）,Hun_Hat01（空）,Hair_Bangs（发丝，本版不抄）]')==1)
    assert(h:logged('跟随玩家外观 实例=Hun_1 只读玩家：身体=Hun_MoTian_Body_Simple 头=Hun_Head_Mod')==1)
    assert(h:logged('完整外观（玩家当前） 头和身体=true 其余部件：meshBand=true meshBrowLashCard=true')==1 and h:logged('4 件，照玩家当前')==1)
    assert(h.look.streak.follow==0 and h.mesh.PhysicsAssetOverride==nil,'the player body brings its own physics asset')
    for name,c in pairs(w)do if type(c)=='table'and c.AttachChildren then assert(c.asset==nil and c.parent==nil,'the player is only read: '..name)end end
    h.look:recheck(h.r);assert(h.mesh.asset==w.assets.Hun_MoTian_Body_Simple and h:logged('跟随=true')==1)
    h.look:cleanup(h.r,'实例离场');assert(h.mesh.asset==h.skin,'leaving restores the native body')
end)
test('follow: a shown hat is copied as a static part at its socket',function()
    local h=fixture({steps=FOLLOW});local w=wearer(h,{hatShown=true});h:apply()
    local hat=partOf(h,w.assets.Hun_Hat_MoTian)
    assert(hat and hat.parent==h.mesh and hat.socket=='hatSocket'and hat.mode==2 and hat.animOn==false and hat.anim==nil)
end)
test('follow: a whole-model replacement with no separate head or parts stands, and nothing checks a head',function()
    local h=fixture({steps=FOLLOW});local w=wearer(h,{wholeModel=true,bodyName='Other_Character_Full'});local result=h:apply()
    assert(result.full==true and result.follow==true and #h.parts==0 and h.mesh.asset==w.assets.Other_Character_Full and h.r.headName==nil)
    assert(h:logged('完整外观（玩家当前） 身体（没有单独的头）=true')==1)
    h.look:recheck(h.r);assert(h.mesh.asset==w.assets.Other_Character_Full and h:logged('这套外观没有单独的头，不查头部跟随')==1)
end)
test('follow: a player that cannot be followed gives the default look and does not count against the breaker',function()
    local h=fixture({steps=FOLLOW});local result=h:apply()
    assert(result.full==true and result.follow==nil and h.mesh.asset==h.body_ and h:logged('跟随玩家外观 实例=Hun_1；玩家不可读，改用默认外观')==1)
    h=fixture({steps=FOLLOW});wearer(h,{skeleton=object('Skeleton /Game/Other.Other_Skeleton')});result=h:apply()
    assert(result.full==true and result.follow==nil and h.mesh.asset==h.body_ and h:logged('的骨架（Other_Skeleton）和魂的（Hun_Skin_Skeleton）不同，改用默认外观')==1)
    h=fixture({steps=FOLLOW});local w=wearer(h);w.CharacterMesh0.bHiddenInGame=true;result=h:apply()
    assert(result.follow==nil and h.mesh.asset==h.body_ and h:logged('玩家身体当前不可见')==1 and(h.look.streak.follow or 0)==0)
    h=fixture({steps=FOLLOW});w=wearer(h);w.meshhead.bHiddenInGame=true;result=h:apply()
    assert(result.follow==nil and result.full==true and h.mesh.asset==h.body_ and h:logged('玩家的头当前被隐藏')==1,'never a headless body')
    h=fixture({steps=FULL});wearer(h);h:apply();assert(h.mesh.asset==h.body_ and h:logged('跟随玩家外观')==0,'the switch is off unless set')
end)
test('follow: an outfit that fails is undone to the default list, then Hun_Clone; two bodies in a row switch it off',function()
    local h=fixture({steps=FOLLOW});wearer(h,{hairAsset=h.assets[Look.CLOTH[1].asset]})
    h.broken.CA_Hun_Hair='anyAsset'
    local result=h:apply()
    assert(result.follow==false and result.full==false and result.look==true and h.mesh.asset==h.clone,'player, default, then clone')
    assert(h:logged('头发布料没读回，没有头发，改用默认外观')==1 and h:logged('跟随玩家外观 没成 实例=Hun_1，改用默认外观')==1)
    assert(h.look.streak.follow==1 and h.mesh.PhysicsAssetOverride==h.nativePhysics)
    for _,c in ipairs(h.parts)do assert(c.destroying==true,'every part of both attempts is destroyed')end
    h:body();h:apply();assert(h.look.off.follow==true and h:logged('已停用 跟随玩家外观：连续 2 只魂失败')==1)
    h.broken={};h:body();local reads=h:logged('只读玩家：');result=h:apply()
    assert(h:logged('只读玩家：')==reads and h:logged('跟随玩家外观 本次加载已停用，之后的魂都用默认外观（实例=Hun_3）')==1)
end)
test('follow: materials that differ are taken from the player, a dynamic one by its parent, never the phantom one',function()
    local h=fixture({steps=FOLLOW});local w=wearer(h,{wholeModel=true})
    local m1,m2=object('MaterialInstanceConstant /Game/M.MI_Mod_A'),object('MaterialInstanceConstant /Game/M.MI_Mod_B')
    local dynamic=object('MaterialInstanceDynamic /Engine/Transient.MID_1',{Parent=m1})
    function dynamic:GetClass()return class('/Script/Engine.MaterialInstanceDynamic')end
    w.CharacterMesh0.mats={dynamic,m2,object('MaterialInstanceConstant /Game/M.MI_FX_PhantomMode_Hun_Cloth')}
    h.mesh.slots={};local base=h.mesh.GetMaterial
    function h.mesh:SetMaterial(i,m)self.slots[i]=m end
    function h.mesh:GetMaterial(i)return self.slots[i]or base(self,i)end
    function h.mesh:GetNumMaterials()return 2 end
    h:apply()
    assert(h.mesh.slots[0]==m1 and h.mesh.slots[1]==m2 and h.mesh.slots[2]==nil)
    assert(h:logged('即将 抄材质 实例=Hun_1 身体 SetMaterial')==1 and h:logged('抄材质 读回 实例=Hun_1 身体 写入=2 没读回=0')==1)
    h=fixture({steps={look='full',cloth=true,anim=true,follow=true,materials=false}});w=wearer(h,{wholeModel=true});w.CharacterMesh0.mats={m1}
    h:apply();assert(h:logged('抄材质')==0)
end)
print('hun look: PASS '..n..' mesh/anim-class/full-look/cloth/readback/undo/breaker checks; native gameplay remains unverified')
