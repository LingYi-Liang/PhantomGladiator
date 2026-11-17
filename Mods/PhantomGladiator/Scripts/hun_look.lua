-- Experimental look and main animation of the owned Hun body (BP_Monster_Hun). Only that instance is written: its
-- CharacterMesh0 mesh asset and anim class, components added to it, and its weapons component's default layer link.
-- Shared assets and CDOs are only referenced. Before each low-confidence native call a "即将" line goes to the log (a
-- native crash leaves it as the last line); after it the result is read back. A step that does not read back is
-- undone to the value recorded before it and read back again; the body is never held back from the arena by a failed
-- step.
-- PBZ_ABP_Base_MonsterHun is the class the game's own BP_Monster_Hun_Summon_Double uses; its BlueprintBeginPlay links
-- ABP_MM_Monster_C (LinkAnimClassLayers). BP_Renewal_Hun.RelinkAnimLayer relinks the default layers with
-- LinkDefaultAnimLayers after its anim instance is rebuilt; the same order is used here.
-- The full look copies the player class BP_Renewal_Hun's component tree (appearance/tree-BP_Renewal_Hun.txt): body
-- Hun_Body_Simple; skeletal parts driven by Hun_CopyPose_C from their attach parent; the hat static at hatSocket;
-- four ChaosClothComponents. The head goes first and the body is swapped only after the head reads back, since
-- Hun_Body_Simple has no head.
local U=require('ue_observe')
local Look={}
-- Switches of this build's Hun body steps. hun_body, arena_executions and arena_grabs read the ones that concern them.
-- The weapon steps have their own table, hun_weapons.lua Weapons.STEPS.
Look.STEPS={
    probe=true,           -- read-only probes of the body and the player (hun_body.lua)
    look='full',          -- body look: 'full' = player component tree, 'clone' = Hun_Clone, false leaves Hun_Skin
    cloth=true,           -- 'full' only: ChaosClothComponents (first body of a load: hair only; later bodies: all four)
    anim=true,            -- main anim class PBZ_ABP_Base_MonsterHun_C and default layers
    deathHide=false,      -- hide the added parts 1 s after HP reaches 0 (off: the death readback only reads them)
    directExecution=true, -- arena_executions: an executor whose mesh skeleton is its clip's plays on its own mesh
    weaponPairs=true,     -- arena_executions: the Hun weapon's generic pairs for targets with no pair of their own
    guillotineSelf=true,  -- arena_executions: the 荒行子 C4 victim montages on the Hun's own anim instance
    qteGate=true,         -- arena_grabs: QTE grab families facing a Hun keep their NonPlayerGE
    deathWatch=true,      -- hun_body: read-only readback of death and cleanup
}
local HERO='/HuaShira/Characters/Hero/Hero_Hun/'
local SKP=HERO..'SkinParts/'
Look.PATHS={
    clone=HERO..'Hun_Clone.Hun_Clone',
    anim='/HuaShira/Characters/TemplateBP/PBZ_ABP_Base_MonsterHun.PBZ_ABP_Base_MonsterHun_C',
    mm='/PBZCombatAsset/ActorData/Players/Hun/Animation/ABP_MM_Monster.ABP_MM_Monster_C',
    item=HERO..'Summon/ABP_Item_Hun_Summon.ABP_Item_Hun_Summon_C',
    body=SKP..'Hun_Body_Simple.Hun_Body_Simple',
    copyPose=HERO..'Hun_CopyPose.Hun_CopyPose_C',
    meshClass='/Script/Engine.SkeletalMeshComponent',
    clothClass='/Script/ChaosClothAssetEngine.ChaosClothComponent',
}
-- BP_Renewal_Hun's skeletal parts. parent: 'Mesh' = CharacterMesh0, otherwise the name of a part added before.
-- static: AnimationMode 2 (custom) with animation off, as the template's Hun_Hat.
Look.HEAD={name='meshhead',asset=SKP..'Hun_Head_New.Hun_Head_New',parent='Mesh',tags={'GhostTrailMesh','SlicedUpperBody'}}
Look.PARTS={
    {name='meshBrowLashCard',asset=SKP..'Hun_BrowLashCard.Hun_BrowLashCard',parent='meshhead'},
    {name='meshBand',asset=SKP..'Hun_Hair_Band.Hun_Hair_Band',parent='Mesh',tags={'PBZ.AllowLegacyClothLeaderPose'}},
    {name='meshScarf',asset=SKP..'Hun_Scarf.Hun_Scarf',parent='Mesh',tags={'PBZ.AllowLegacyClothLeaderPose'}},
    {name='Hun_Hat',asset=HERO..'Hats/Hun_Hat_00.Hun_Hat_00',parent='Mesh',socket='hatSocket',static=true},
}
Look.CLOTH={
    {name='CA_Hun_Hair',asset=SKP..'Cloth/CA_Hun_Hair01.CA_Hun_Hair01',parent='meshhead',hair=true},
    {name='CA_Hun_UpperCloth',asset=SKP..'Cloth/CA_Hun_UpperCloth.CA_Hun_UpperCloth',parent='Mesh'},
    {name='CA_Hun_Skirt',asset=SKP..'Cloth/CA_Hun_Skirt.CA_Hun_Skirt',parent='Mesh',tags={'SlicedLowerBody'}},
    {name='CA_Hun_Cape',asset=SKP..'Cloth/CA_Hun_Cape.CA_Hun_Cape',parent='Mesh'},
}
local ANIM_CLASS='PBZ_ABP_Base_MonsterHun_C'
local PHANTOM='MI_FX_PhantomMode'
local IDENTITY={Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
local SNAP=2               -- EAttachmentRule::SnapToTarget
local TICK_ALWAYS=0        -- EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones
local CUSTOM_MODE=2        -- EAnimationMode::AnimationCustomMode
local HEAD_FOLLOW_CM=1     -- largest distance between the head part's head socket and the body's that counts as following
-- Bodies in a row on which a step has to be undone before that step is off until the mods are restarted.
Look.LIMIT=2
local LABELS={look='换网格',anim='换动画类',head='完整外观（头和身体）',cloth='布料'}
-- Why the native PBZAppearanceComponent:RefreshClothComponents route is not taken (plan 2-2 alternative).
Look.CLOTH_ALTERNATIVE_SKIPPED='PBZAppearanceComponent 带 PreSaveGame、BeginSuppressAppearanceSave/EndSuppressAppearanceSave、'
    ..'ReconcileEntitlementOutfits、HandleOwnerControllerChanged、静态 GetPBZAppearanceComponent，原生 BeginPlay 读不到，'
    ..'离线无法确认新建的实例不会被存档或"取外观组件"的流程读到'

local function call(o,m,...)
    if not U.valid(o)then return false end
    local a,n={...},select('#',...);local ok,value=pcall(function()return o[m](o,table.unpack(a,1,n))end)
    return ok,U.unwrap(value)
end
local function short(o)
    if not U.valid(o)then return'无'end
    local ok,n=call(o,'GetFullName')
    if ok and type(n)=='string'then return n:match('[%.:]([^%.:]+)$')or n end
    return'?'
end
local function text(v)
    if type(v)=='string'then return v end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string'and s or nil
end
local function truthy(v)return v==true or v==1 end

function Look.new(o)
    local self={off={},streak={},skipped={},clothBodies=0}
    local steps=o.steps or Look.STEPS
    local find=o.find or StaticFindObject
    local load=o.load or LoadAsset
    local findAll=o.findAll or FindAllOf
    local fname=o.fname or FName
    local function say(s)(o.log or function()end)('[HunLook] '..s)end
    local function object(path)
        local ok,found=pcall(find,path)
        if ok and U.valid(found)then return found end
        local loaded,value=pcall(load,path)
        if loaded and U.valid(value)then return value end
        ok,found=pcall(find,path)
        if ok and U.valid(found)then return found end
    end
    local function materials(mesh)
        local got,count=call(mesh,'GetNumMaterials')
        if not got or type(count)~='number'then return'?'end
        local names={}
        for i=0,math.min(count,16)-1 do local _,m=call(mesh,'GetMaterial',i);names[#names+1]=short(m)end
        return table.concat(names,'|')..(count>16 and'|…共'..count or'')
    end
    -- Every skinned mesh the body or its attached weapon actors own, other than its own Mesh and the parts this module
    -- added, with its socket. One text, so a change after a step shows as a different text.
    local function weaponSockets(actor,mesh,skip)
        local key,list=U.key(actor),{}
        local ok,all=pcall(findAll,'SkeletalMeshComponent')
        for _,comp in ipairs(ok and type(all)=='table'and all or{})do
            local ck=U.key(comp)
            if ck and ck~=U.key(mesh)and not(skip and skip[ck])then
                local gotOwner,owner=call(comp,'GetOwner')
                local mine=gotOwner and U.key(owner)==key
                if not mine and gotOwner and U.valid(owner)then
                    local gotParent,parent=call(owner,'GetOwner');mine=gotParent and U.key(parent)==key
                end
                if mine then
                    local _,socket=call(comp,'GetAttachSocketName')
                    list[#list+1]=short(comp)..'@'..tostring(text(socket)or'?')
                end
            end
        end
        table.sort(list)
        return table.concat(list,','),list
    end
    local function socketsExist(mesh,list)
        for _,entry in ipairs(list)do
            local socket=entry:match('@(.+)$')
            if socket and socket~='None'and socket~='?'then
                local got,exists=call(mesh,'DoesSocketExist',fname(socket))
                if not got or exists~=true then return false,socket end
            end
        end
        return true
    end
    local function layer(mesh,cls)
        if not U.valid(cls)then return false end
        local got,instance=call(mesh,'GetLinkedAnimLayerInstanceByClass',cls)
        return got and U.valid(instance)
    end
    local function instanceClass(mesh)local _,instance=call(mesh,'GetAnimInstance');return U.className(instance)or'无',instance end
    local function skipSet(r)
        local set={}
        for _,part in ipairs(r.parts or{})do if part.key then set[part.key]=true end end
        return set
    end
    local function distance(a,b)
        if type(a)~='table'and type(a)~='userdata'then return nil end
        local ax,ay,az=U.struct(a,'X'),U.struct(a,'Y'),U.struct(a,'Z')
        local bx,by,bz=U.struct(b,'X'),U.struct(b,'Y'),U.struct(b,'Z')
        for _,v in ipairs({ax,ay,az,bx,by,bz})do if type(v)~='number'then return nil end end
        return math.sqrt((ax-bx)^2+(ay-by)^2+(az-bz)^2)
    end
    -- How far the head part's head socket is from the body's (cm), or nil when either cannot be read.
    local function headGap(head,mesh)
        local gotA,a=call(head,'GetSocketLocation',fname('head'))
        local gotB,b=call(mesh,'GetSocketLocation',fname('head'))
        if not gotA or not gotB then return nil end
        return distance(a,b)
    end

    -- 1-2: the body mesh becomes Hun_Clone (hair cards, hat, band) on the same skeleton.
    local function meshStep(r,mesh,still,before)
        local target=object(Look.PATHS.clone)
        if not target then say('换网格 实例='..r.name..'；Hun_Clone 没载入，不换');return false end
        local gotAsset,old=call(mesh,'GetSkeletalMeshAsset')
        if not gotAsset or not U.valid(old)then say('换网格 实例='..r.name..'；读不到原网格，不换');return false end
        r.undo.mesh=r.undo.mesh or old
        if not still()then say('换网格 实例='..r.name..'；实例已变化，不换');return false end
        say('即将 换网格 实例='..r.name..' '..short(mesh)..':SetSkeletalMeshAsset('..short(target)..') 原网格='..short(old))
        local called=call(mesh,'SetSkeletalMeshAsset',target)
        local _,after=call(mesh,'GetSkeletalMeshAsset')
        local mats=materials(mesh)
        local _,hat=call(mesh,'DoesSocketExist',fname('hatSocket'))
        local sockets,list=weaponSockets(r.actor,mesh,skipSet(r))
        local exist,missing=socketsExist(mesh,list)
        local verified=called==true and U.key(after)==U.key(target)and not mats:find(PHANTOM,1,true)and sockets==before and exist
        say('换网格 读回 实例='..r.name..' 调用='..tostring(called==true)..' 网格='..short(after)..' 材质=['..mats..'] hatSocket='..tostring(hat)
            ..' 武器挂接=['..sockets..']'..(sockets==before and''or'（原=['..before..']）')..' 插槽都在='..tostring(exist)..(missing and'（缺 '..missing..'）'or'')
            ..' verified='..tostring(verified))
        if verified then r.lookKind='clone';return true end
        if still()then
            local back=call(mesh,'SetSkeletalMeshAsset',old)
            local _,now=call(mesh,'GetSkeletalMeshAsset')
            say('还原网格 实例='..r.name..' 调用='..tostring(back==true)..' 读回='..short(now)..' 已还原='..tostring(U.key(now)==U.key(old)))
        else say('还原网格 实例='..r.name..'；实例已变化，不写')end
        return false
    end

    ---- 2-1 / 2-2: parts added to the body. Every one is registered in r.parts the moment it exists.
    local function register(r,comp,spec,kind)
        r.parts=r.parts or{}
        local part={comp=comp,key=U.key(comp),name=spec.name,kind=kind}
        r.parts[#r.parts+1]=part
        return part
    end
    local function findPart(r,name)
        for _,part in ipairs(r.parts or{})do if part.name==name and not part.gone then return part end end
    end
    -- K2_DestroyComponent on one registered part, read back with IsBeingDestroyed. Returns a short text.
    local function destroyPart(part)
        if part.gone then return part.name..'=已销毁过'end
        if not U.valid(part.comp)then part.gone=true;return part.name..'=已无效'end
        local _,already=call(part.comp,'IsBeingDestroyed')
        local called=already==true
        if not called then called=call(part.comp,'K2_DestroyComponent',part.comp)==true end
        local valid=U.valid(part.comp)
        local _,after=call(part.comp,'IsBeingDestroyed')
        local done=not valid or after==true
        if done then part.gone=true end
        return part.name..'=调用'..tostring(called)..'/销毁中'..tostring(valid and after or'无效')..'/'..(done and'已销毁'or'未确认')
    end
    local function destroyParts(r,filter)
        local texts,all={},true
        for i=#(r.parts or{}),1,-1 do
            local part=r.parts[i]
            if not part.gone and(not filter or filter(part))then
                local line=destroyPart(part);texts[#texts+1]=line
                if not part.gone then all=false end
            end
        end
        return table.concat(texts,' '),all
    end
    local function setTags(comp,names)
        if not names or #names==0 then return'无'end
        local list={};for _,n in ipairs(names)do list[#list+1]=fname(n)end
        local wrote=pcall(function()comp.ComponentTags=list end)
        local back=U.array(U.field(comp,'ComponentTags'))
        return(wrote and'写入'or'写入失败')..'/读回'..(back and #back or'?')..'个'
    end
    local function newComponent(r,cls,spec,kind)
        say('即将 新建部件 实例='..r.name..' '..spec.name..' AddComponentByClass('..short(cls)..')')
        local ok,comp=call(r.actor,'AddComponentByClass',cls,true,IDENTITY,false)
        if not ok or not U.valid(comp)then return nil,'AddComponentByClass 调用='..tostring(ok)..' 返回无效'end
        return register(r,comp,spec,kind)
    end
    local function parentOf(r,mesh,spec)
        if spec.parent=='Mesh'then return mesh end
        local part=findPart(r,spec.parent)
        return part and U.valid(part.comp)and part.comp or nil
    end
    -- One skeletal part: add, attach, asset, CopyPose class (or static mode), tick option, tags; then read back.
    local function meshPart(r,mesh,spec,still,assets)
        local parent=parentOf(r,mesh,spec)
        if not parent then say('部件 '..spec.name..' 实例='..r.name..'；父部件 '..spec.parent..' 不在，不加');return false end
        local asset=object(spec.asset)
        if not asset then say('部件 '..spec.name..' 实例='..r.name..'；资源没载入，不加');return false end
        if spec.socket then
            local _,exists=call(parent,'DoesSocketExist',fname(spec.socket))
            if exists~=true then say('部件 '..spec.name..' 实例='..r.name..'；父网格没有插槽 '..spec.socket..'，不加');return false end
        end
        if not still()then say('部件 '..spec.name..' 实例='..r.name..'；实例已变化，不加');return false end
        local part,why=newComponent(r,assets.meshClass,spec,'mesh')
        if not part then say('部件 '..spec.name..' 实例='..r.name..'；'..why);return false end
        local comp=part.comp
        local socket=spec.socket or'None'
        local attached=call(comp,'K2_AttachToComponent',parent,fname(socket),SNAP,SNAP,SNAP,false)
        local assigned=call(comp,'SetSkeletalMeshAsset',asset)
        local animated
        if spec.static then
            animated=call(comp,'SetAnimationMode',CUSTOM_MODE,false)
            call(comp,'SetEnableAnimation',false)
        else
            say('即将 部件 '..spec.name..' 实例='..r.name..' SetAnimInstanceClass('..short(assets.copyPose)..')')
            animated=call(comp,'SetAnimInstanceClass',assets.copyPose)
        end
        local ticked=pcall(function()comp.VisibilityBasedAnimTickOption=TICK_ALWAYS end)
        local tags=setTags(comp,spec.tags)
        local _,gotParent=call(comp,'GetAttachParent')
        local _,gotSocket=call(comp,'GetAttachSocketName')
        local _,gotAsset=call(comp,'GetSkeletalMeshAsset')
        local _,visible=call(comp,'IsVisible')
        local classText,modeText,animOK
        if spec.static then
            local _,mode=call(comp,'GetAnimationMode')
            modeText='动画模式='..tostring(mode);animOK=mode==CUSTOM_MODE
        else
            classText=instanceClass(comp);animOK=classText==short(assets.copyPose)
        end
        local socketText=text(gotSocket)or'?'
        local verified=attached==true and assigned==true and animated==true and U.key(gotParent)==U.key(parent)
            and socketText==socket and U.key(gotAsset)==U.key(asset)and animOK
        local gap=not spec.static and headGap(comp,mesh)or nil
        say('部件 读回 实例='..r.name..' '..spec.name..' 挂在='..short(gotParent)..'@'..socketText..'（应为 '..short(parent)..'@'..socket..'） 资源='..short(gotAsset)
            ..' '..(modeText or('动画实例='..tostring(classText)))..' 可见='..tostring(visible)..' 常驻姿势='..tostring(ticked)..' 标签='..tags
            ..(spec==Look.HEAD and(' 头骨距离='..(gap and string.format('%.2fcm',gap)or'不可读')..'（立即读，姿势下一帧才抄）')or'')
            ..' verified='..tostring(verified))
        return verified
    end
    -- One cloth part: add, attach, asset (SetClothAsset, else SetAsset), pose from the attach parent, simulation on.
    local function clothPart(r,mesh,spec,still,assets)
        local parent=parentOf(r,mesh,spec)
        if not parent then say('布料 '..spec.name..' 实例='..r.name..'；父部件 '..spec.parent..' 不在，不加');return false end
        local asset=object(spec.asset)
        if not asset then say('布料 '..spec.name..' 实例='..r.name..'；资源没载入，不加');return false end
        if not still()then say('布料 '..spec.name..' 实例='..r.name..'；实例已变化，不加');return false end
        local part,why=newComponent(r,assets.clothClass,spec,'cloth')
        if not part then say('布料 '..spec.name..' 实例='..r.name..'；'..why);return false end
        local comp=part.comp
        local attached=call(comp,'K2_AttachToComponent',parent,fname('None'),SNAP,SNAP,SNAP,false)
        say('即将 布料 '..spec.name..' 实例='..r.name..' SetClothAsset('..short(asset)..')')
        local set,how=call(comp,'SetClothAsset',asset),'SetClothAsset'
        local _,got=call(comp,'GetClothAsset')
        if U.key(got)~=U.key(asset)then
            say('即将 布料 '..spec.name..' 实例='..r.name..' SetAsset('..short(asset)..')（SetClothAsset 读回='..short(got)..'）')
            set,how=call(comp,'SetAsset',asset),'SetAsset'
            _,got=call(comp,'GetAsset')
        end
        local pose=U.field(comp,'bUseAttachedParentAsPoseComponent')
        local poseBefore=pose
        if not truthy(pose)then
            say('即将 布料 '..spec.name..' 实例='..r.name..' 写位域 bUseAttachedParentAsPoseComponent=true（读到 '..tostring(pose)..'）')
            pcall(function()comp.bUseAttachedParentAsPoseComponent=true end)
            pose=U.field(comp,'bUseAttachedParentAsPoseComponent')
        end
        local tags=setTags(comp,spec.tags)
        say('即将 布料 '..spec.name..' 实例='..r.name..' SetEnableSimulation(true)+RecreateClothSimulationProxy+ForceNextUpdateTeleportAndReset')
        local enabled=call(comp,'SetEnableSimulation',true)
        local recreated=call(comp,'RecreateClothSimulationProxy')
        local reset=call(comp,'ForceNextUpdateTeleportAndReset')
        local _,simulating=call(comp,'IsSimulationEnabled')
        local _,suspended=call(comp,'IsSimulationSuspended')
        local _,gotParent=call(comp,'GetAttachParent')
        local verified=attached==true and set==true and U.key(got)==U.key(asset)and truthy(pose)and simulating==true
            and U.key(gotParent)==U.key(parent)
        say('布料 读回 实例='..r.name..' '..spec.name..' 挂在='..short(gotParent)..'（应为 '..short(parent)..'） 资源='..short(got)..'（'..how..'）'
            ..' 抄父姿势='..tostring(poseBefore)..'→'..tostring(pose)..' 模拟开='..tostring(simulating)..' 暂停='..tostring(suspended)
            ..' 调用 开模拟/重建/重置='..tostring(enabled==true)..'/'..tostring(recreated==true)..'/'..tostring(reset==true)..' 标签='..tags
            ..' verified='..tostring(verified))
        return verified
    end
    -- Undo of the full look: every added part destroyed and read back, the body mesh back to the one recorded before.
    local function undoFull(r,mesh,still,why)
        local destroyed,all=destroyParts(r)
        say('还原完整外观 实例='..r.name..' 原因='..why..' 销毁部件：'..(destroyed~=''and destroyed or'无')..' 全部确认='..tostring(all))
        local _,asset=call(mesh,'GetSkeletalMeshAsset')
        if r.undo.mesh and U.key(asset)~=U.key(r.undo.mesh)then
            if still()then
                local back=call(mesh,'SetSkeletalMeshAsset',r.undo.mesh)
                local _,now=call(mesh,'GetSkeletalMeshAsset')
                say('还原身体网格 实例='..r.name..' 调用='..tostring(back==true)..' 读回='..short(now)..' 已还原='..tostring(U.key(now)==U.key(r.undo.mesh)))
            else say('还原身体网格 实例='..r.name..'；实例已变化，不写')end
        end
        r.full=nil;r.lookKind=nil
    end
    -- A step on one body; the breaker counts bodies in a row on which it failed.
    local function record(step,passed)
        if passed then self.streak[step]=0
        else
            self.streak[step]=(self.streak[step]or 0)+1
            if self.streak[step]>=Look.LIMIT and not self.off[step]then
                self.off[step]=true
                say('已停用 '..LABELS[step]..'：连续 '..self.streak[step]..' 只魂失败，下次 Restart All Mods 恢复')
            end
        end
    end
    local function run(step,r,fn)
        if self.off[step]then
            if not self.skipped[step]then self.skipped[step]=true;say(LABELS[step]..' 本次加载已停用，之后的魂都跳过（实例='..r.name..'）')end
            return nil
        end
        local ok,result=pcall(fn)
        local passed=ok and result==true
        if not ok then say(LABELS[step]..' 中断：实例='..r.name..' 原因='..tostring(result))end
        record(step,passed)
        return passed
    end
    -- The cloth of one body: the first body of a load gets the hair only, later bodies all four.
    local function clothStep(r,mesh,still,assets)
        self.clothBodies=self.clothBodies+1
        local all=self.clothBodies>1
        if not self.clothNoted then
            self.clothNoted=true
            say('布料备选 RefreshClothComponents 本版不做：'..Look.CLOTH_ALTERNATIVE_SKIPPED)
        end
        say('布料 实例='..r.name..' 本次加载第'..self.clothBodies..'只魂：'..(all and'四件全加'or'只加头发 CA_Hun_Hair01（对照用）'))
        local passed,hair=true,true
        for _,spec in ipairs(Look.CLOTH)do
            if spec.hair or all then
                local ok,result=pcall(clothPart,r,mesh,spec,still,assets)
                if not ok then say('布料 '..spec.name..' 中断：实例='..r.name..' 原因='..tostring(result))end
                local verified=ok and result==true
                if not verified then
                    passed=false;if spec.hair then hair=false end
                    local part=findPart(r,spec.name);if part then say('布料销毁 实例='..r.name..' '..destroyPart(part))end
                end
            end
        end
        return passed,hair
    end
    -- 2-1 / 2-2: head on the current body; only when it reads back is the body swapped and the rest added.
    -- Returns true (full look stands), false (head or body did not read back) or 'cloth' (the hair cloth did not);
    -- the last two after undoing to the recorded mesh, and the caller then tries Hun_Clone.
    local function fullStep(r,mesh,still,before)
        local assets={meshClass=object(Look.PATHS.meshClass),clothClass=object(Look.PATHS.clothClass),copyPose=object(Look.PATHS.copyPose),body=object(Look.PATHS.body)}
        local missing={}
        for _,k in ipairs({'meshClass','copyPose','body'})do if not assets[k]then missing[#missing+1]=k end end
        if #missing>0 then say('完整外观 实例='..r.name..'；没载入：'..table.concat(missing,'、')..'，不做');return false end
        local gotAsset,old=call(mesh,'GetSkeletalMeshAsset')
        if not gotAsset or not U.valid(old)then say('完整外观 实例='..r.name..'；读不到原网格，不做');return false end
        r.undo.mesh=old
        if not still()then say('完整外观 实例='..r.name..'；实例已变化，不做');return false end
        local headOK=meshPart(r,mesh,Look.HEAD,still,assets)
        if not headOK then undoFull(r,mesh,still,'头没读回');return false end
        if not still()then undoFull(r,mesh,still,'实例已变化');return false end
        say('即将 换身体 实例='..r.name..' '..short(mesh)..':SetSkeletalMeshAsset('..short(assets.body)..') 原网格='..short(old))
        local called=call(mesh,'SetSkeletalMeshAsset',assets.body)
        local _,after=call(mesh,'GetSkeletalMeshAsset')
        local mats=materials(mesh)
        local _,hat=call(mesh,'DoesSocketExist',fname('hatSocket'))
        local sockets,list=weaponSockets(r.actor,mesh,skipSet(r))
        local exist,lack=socketsExist(mesh,list)
        local verified=called==true and U.key(after)==U.key(assets.body)and not mats:find(PHANTOM,1,true)and sockets==before and exist
        say('换身体 读回 实例='..r.name..' 调用='..tostring(called==true)..' 网格='..short(after)..' 材质=['..mats..'] hatSocket='..tostring(hat)
            ..' 武器挂接=['..sockets..']'..(sockets==before and''or'（原=['..before..']）')..' 插槽都在='..tostring(exist)..(lack and'（缺 '..lack..'）'or'')
            ..' verified='..tostring(verified))
        if not verified then undoFull(r,mesh,still,'身体没读回');return false end
        r.full=true;r.lookKind='full'
        local extras={}
        for _,spec in ipairs(Look.PARTS)do
            local ok,result=pcall(meshPart,r,mesh,spec,still,assets)
            if not ok then say('部件 '..spec.name..' 中断：实例='..r.name..' 原因='..tostring(result))end
            if ok and result==true then extras[#extras+1]=spec.name..'=true'
            else
                extras[#extras+1]=spec.name..'=false'
                local part=findPart(r,spec.name);if part then say('部件销毁 实例='..r.name..' '..destroyPart(part))end
            end
        end
        say('完整外观 头和身体=true 其余部件：'..table.concat(extras,' '))
        if steps.cloth then
            if not assets.clothClass then say('布料 实例='..r.name..'；ChaosClothComponent 类没载入')end
            local ok,passed,hair=pcall(clothStep,r,mesh,still,assets)
            if not ok then say('布料 中断：实例='..r.name..' 原因='..tostring(passed));passed,hair=false,false end
            record('cloth',passed==true)
            if not hair then undoFull(r,mesh,still,'头发布料没读回，没有头发，改用 Hun_Clone');return'cloth'end
        end
        return true
    end
    -- 1-1: the main anim class becomes the NPC Hun class, then the weapons component relinks the default layers.
    local function animStep(r,actor,mesh,still,before)
        local cls=object(Look.PATHS.anim)
        if not cls then say('换动画类 实例='..r.name..'；'..ANIM_CLASS..' 没载入，不换');return false end
        local old=U.field(mesh,'AnimClass')
        if not U.valid(old)then say('换动画类 实例='..r.name..'；读不到原动画类，无法保证还原，不换');return false end
        r.undo.anim=old
        if not still()then say('换动画类 实例='..r.name..'；实例已变化，不换');return false end
        local wc=U.field(actor,'Character Weapons Component')
        say('即将 换动画类 实例='..r.name..' '..short(mesh)..':SetAnimInstanceClass('..short(cls)..') 原动画类='..short(old)..' 原动画实例='..instanceClass(mesh))
        local called=call(mesh,'SetAnimInstanceClass',cls)
        local current,instance=instanceClass(mesh)
        local classOK=current==ANIM_CLASS
        local mm,item=object(Look.PATHS.mm),object(Look.PATHS.item)
        local mmOK,mmHow=layer(mesh,mm),'动画类自己的 BlueprintBeginPlay'
        if classOK and U.valid(mm)and not mmOK and still()then
            say('即将 链接 '..short(mm)..' 实例='..r.name..' 动画实例:LinkAnimClassLayers（与原版 BlueprintBeginPlay 同一调用）')
            call(instance,'LinkAnimClassLayers',mm)
            mmOK,mmHow=layer(mesh,mm),'Lua 补链接'
        end
        local itemOK,itemHow=false,'没调用'
        if classOK and still()then
            say('即将 武器组件 LinkDefaultAnimLayers 实例='..r.name..' 组件有效='..tostring(U.valid(wc)))
            local linked=call(wc,'LinkDefaultAnimLayers')
            itemOK,itemHow=layer(mesh,item),'武器组件 LinkDefaultAnimLayers 调用='..tostring(linked==true)
            if not itemOK and U.valid(item)and still()then
                say('即将 链接 '..short(item)..' 实例='..r.name..' 网格:LinkAnimClassLayers（备选）')
                call(mesh,'LinkAnimClassLayers',item)
                itemOK,itemHow=layer(mesh,item),'网格 LinkAnimClassLayers'
            end
        end
        local sockets=weaponSockets(actor,mesh,skipSet(r))
        local verified=called==true and classOK and mmOK and itemOK and sockets==before
        say('换动画类 读回 实例='..r.name..' 调用='..tostring(called==true)..' 动画实例='..current..' ABP_MM_Monster='..tostring(mmOK)..'（'..mmHow..'）'
            ..' ABP_Item_Hun_Summon='..tostring(itemOK)..'（'..itemHow..'） 武器挂接=['..sockets..']'..(sockets==before and''or'（原=['..before..']）')
            ..' verified='..tostring(verified))
        if verified then return true end
        if still()then
            say('即将 还原动画类 实例='..r.name..' SetAnimInstanceClass('..short(old)..') + LinkDefaultAnimLayers')
            local back=call(mesh,'SetAnimInstanceClass',old)
            call(wc,'LinkDefaultAnimLayers')
            local now=instanceClass(mesh)
            say('还原动画类 实例='..r.name..' 调用='..tostring(back==true)..' 读回动画实例='..now..' 已还原='..tostring(now==short(old)))
        else say('还原动画类 实例='..r.name..'；实例已变化，不写')end
        return false
    end
    -- Look first (full, falling back to Hun_Clone), then anim class. still(): the body's identity is unchanged.
    function self:apply(r,still)
        local actor=r.actor
        local mesh=U.field(actor,'Mesh')
        if not U.valid(mesh)then say('实例='..r.name..'；没有 Mesh，不改外观和动画');return {}end
        if not steps.look and not steps.anim then return {}end
        r.undo={};r.parts=r.parts or{};r.still=still
        local before=weaponSockets(actor,mesh)
        local _,asset=call(mesh,'GetSkeletalMeshAsset')
        say('改前 实例='..r.name..' 网格='..short(asset)..' 动画实例='..instanceClass(mesh)..' 武器挂接=['..before..'] 外观开关='..tostring(steps.look))
        r.socketsBefore=before
        local result={}
        if steps.look=='full'then
            if self.off.head or(steps.cloth and self.off.cloth)then
                local step=self.off.head and'head'or'cloth'
                if not self.skipped[step]then
                    self.skipped[step]=true
                    say(LABELS[step]..' 本次加载已停用，之后的魂都改用 Hun_Clone（实例='..r.name..'）')
                end
            else
                local ok,outcome=pcall(fullStep,r,mesh,still,before)
                if not ok then
                    say(LABELS.head..' 中断：实例='..r.name..' 原因='..tostring(outcome))
                    pcall(undoFull,r,mesh,still,'中断');outcome=false
                end
                -- A hair cloth that did not read back is the cloth step's failure, not the head's.
                record('head',outcome==true or outcome=='cloth')
                result.full=outcome==true
            end
            if result.full~=true then result.look=run('look',r,function()return meshStep(r,mesh,still,before)end)end
        elseif steps.look=='clone'then result.look=run('look',r,function()return meshStep(r,mesh,still,before)end)end
        if steps.anim then result.anim=run('anim',r,function()return animStep(r,actor,mesh,still,before)end)end
        r.lookResult=result
        return result
    end
    -- The parts still present on a body, with their visibility. One text.
    function self:partsText(r)
        local list={}
        for _,part in ipairs(r.parts or{})do
            if not part.gone then
                if U.valid(part.comp)then local _,v=call(part.comp,'IsVisible');list[#list+1]=part.name..':'..tostring(v)
                else list[#list+1]=part.name..':无效'end
            end
        end
        return table.concat(list,',')
    end
    -- A second readback one support cycle later: what the body shows now. A head that does not follow the body by then
    -- undoes the full look (and the body takes Hun_Clone).
    function self:recheck(r)
        if not r.lookResult then return end
        local mesh=U.field(r.actor,'Mesh')
        local _,asset=call(mesh,'GetSkeletalMeshAsset')
        local mm,item=object(Look.PATHS.mm),object(Look.PATHS.item)
        say('复读 实例='..r.name..' 网格='..short(asset)..' 动画实例='..instanceClass(mesh)..' ABP_MM_Monster='..tostring(layer(mesh,mm))
            ..' ABP_Item_Hun_Summon='..tostring(layer(mesh,item))..' 完整外观='..tostring(r.lookResult.full)..' 换网格='..tostring(r.lookResult.look)
            ..' 换动画类='..tostring(r.lookResult.anim)..((r.parts and #r.parts>0)and(' 部件可见=['..self:partsText(r)..']')or''))
        if not r.full then return end
        local head=findPart(r,Look.HEAD.name)
        local gap=head and U.valid(head.comp)and headGap(head.comp,mesh)or nil
        local cloth={}
        for _,part in ipairs(r.parts or{})do
            if part.kind=='cloth'and not part.gone and U.valid(part.comp)then
                local _,sim=call(part.comp,'IsSimulationEnabled');local _,sus=call(part.comp,'IsSimulationSuspended')
                cloth[#cloth+1]=part.name..' 模拟='..tostring(sim)..' 暂停='..tostring(sus)
            end
        end
        local follows=head~=nil and U.valid(head.comp)and(gap==nil or gap<HEAD_FOLLOW_CM)
        say('复读 头部跟随 实例='..r.name..' 头骨距离='..(gap and string.format('%.2fcm',gap)or'不可读')..' 跟随='..tostring(follows)
            ..(#cloth>0 and(' 布料：'..table.concat(cloth,'；'))or''))
        if not follows then
            local still=r.still or function()return true end
            undoFull(r,mesh,still,'复读时头没跟随身体（>'..HEAD_FOLLOW_CM..'cm 或头已无效）')
            record('head',false)
            r.lookResult.full=false
            if not self.off.look then r.lookResult.look=run('look',r,function()return meshStep(r,mesh,still,r.socketsBefore or'')end)end
        end
    end
    -- 2-3, used only with Look.STEPS.deathHide: every added part hidden, read back.
    function self:hideParts(r)
        local list={}
        for _,part in ipairs(r.parts or{})do
            if not part.gone and U.valid(part.comp)then
                local called=call(part.comp,'SetVisibility',false,false)
                local _,v=call(part.comp,'IsVisible')
                list[#list+1]=part.name..'=调用'..tostring(called==true)..'/可见'..tostring(v)
            end
        end
        if #list>0 then say('死亡隐藏部件 实例='..r.name..' '..table.concat(list,' '))end
    end
    -- The body left the arena or its death readback ended: every part still registered is destroyed and read back.
    function self:cleanup(r,why)
        if not r.parts or #r.parts==0 then return end
        local destroyed,all=destroyParts(r)
        if destroyed~=''then say('清理部件 实例='..r.name..' 原因='..tostring(why)..' '..destroyed..' 全部确认='..tostring(all))end
    end
    return self
end
return Look
