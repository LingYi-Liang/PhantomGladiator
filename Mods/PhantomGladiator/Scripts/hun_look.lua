-- Experimental look and main animation of the owned Hun body (BP_Monster_Hun). Only that instance is written: its
-- CharacterMesh0 mesh asset and anim class, and its weapons component's default layer link. Shared assets and CDOs are
-- only referenced. Before each low-confidence native call a "即将" line goes to the log (a native crash leaves it as
-- the last line); after it the result is read back. A step that does not read back is undone to the value recorded
-- before it and read back again; the body is never held back from the arena by a failed step.
-- PBZ_ABP_Base_MonsterHun is the class the game's own BP_Monster_Hun_Summon_Double uses; its BlueprintBeginPlay links
-- ABP_MM_Monster_C (LinkAnimClassLayers). BP_Renewal_Hun.RelinkAnimLayer relinks the default layers with
-- LinkDefaultAnimLayers after its anim instance is rebuilt; the same order is used here.
local U=require('ue_observe')
local Look={}
-- Switches of this build's Hun body steps. hun_body, arena_executions and arena_grabs read the ones that concern them.
Look.STEPS={
    probe=true,           -- read-only probes of the body and the player (hun_body.lua)
    look='clone',         -- body mesh: 'clone' = Hun_Clone; false leaves Hun_Skin
    anim=true,            -- main anim class PBZ_ABP_Base_MonsterHun_C and default layers
    directExecution=true, -- arena_executions: an executor whose mesh skeleton is its clip's plays on its own mesh
    weaponPairs=true,     -- arena_executions: the Hun weapon's generic pairs for targets with no pair of their own
    guillotineSelf=true,  -- arena_executions: the 荒行子 C4 victim montages on the Hun's own anim instance
    qteGate=true,         -- arena_grabs: QTE grab families facing a Hun keep their NonPlayerGE
    deathWatch=true,      -- hun_body: read-only readback of death and cleanup
}
local HERO='/HuaShira/Characters/Hero/Hero_Hun/'
Look.PATHS={
    clone=HERO..'Hun_Clone.Hun_Clone',
    anim='/HuaShira/Characters/TemplateBP/PBZ_ABP_Base_MonsterHun.PBZ_ABP_Base_MonsterHun_C',
    mm='/PBZCombatAsset/ActorData/Players/Hun/Animation/ABP_MM_Monster.ABP_MM_Monster_C',
    item=HERO..'Summon/ABP_Item_Hun_Summon.ABP_Item_Hun_Summon_C',
}
local ANIM_CLASS='PBZ_ABP_Base_MonsterHun_C'
local PHANTOM='MI_FX_PhantomMode'
-- Bodies in a row on which a step has to be undone before that step is off until the mods are restarted.
Look.LIMIT=2
local LABELS={look='换网格',anim='换动画类'}

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

function Look.new(o)
    local self={off={},streak={},skipped={}}
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
    -- Every skinned mesh the body or its attached weapon actors own, other than its own Mesh, with its socket.
    -- One text, so a change after a step shows as a different text.
    local function weaponSockets(actor,mesh)
        local key,list=U.key(actor),{}
        local ok,all=pcall(findAll,'SkeletalMeshComponent')
        for _,comp in ipairs(ok and type(all)=='table'and all or{})do
            if U.valid(comp)and U.key(comp)~=U.key(mesh)then
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

    -- 1-2: the body mesh becomes Hun_Clone (hair cards, hat, band) on the same skeleton.
    local function meshStep(r,mesh,still,before)
        local target=object(Look.PATHS.clone)
        if not target then say('换网格 实例='..r.name..'；Hun_Clone 没载入，不换');return false end
        local gotAsset,old=call(mesh,'GetSkeletalMeshAsset')
        if not gotAsset or not U.valid(old)then say('换网格 实例='..r.name..'；读不到原网格，不换');return false end
        r.undo.mesh=old
        if not still()then say('换网格 实例='..r.name..'；实例已变化，不换');return false end
        say('即将 换网格 实例='..r.name..' '..short(mesh)..':SetSkeletalMeshAsset('..short(target)..') 原网格='..short(old))
        local called=call(mesh,'SetSkeletalMeshAsset',target)
        local _,after=call(mesh,'GetSkeletalMeshAsset')
        local mats=materials(mesh)
        local _,hat=call(mesh,'DoesSocketExist',fname('hatSocket'))
        local sockets,list=weaponSockets(r.actor,mesh)
        local exist,missing=socketsExist(mesh,list)
        local verified=called==true and U.key(after)==U.key(target)and not mats:find(PHANTOM,1,true)and sockets==before and exist
        say('换网格 读回 实例='..r.name..' 调用='..tostring(called==true)..' 网格='..short(after)..' 材质=['..mats..'] hatSocket='..tostring(hat)
            ..' 武器挂接=['..sockets..']'..(sockets==before and''or'（原=['..before..']）')..' 插槽都在='..tostring(exist)..(missing and'（缺 '..missing..'）'or'')
            ..' verified='..tostring(verified))
        if verified then return true end
        if still()then
            local back=call(mesh,'SetSkeletalMeshAsset',old)
            local _,now=call(mesh,'GetSkeletalMeshAsset')
            say('还原网格 实例='..r.name..' 调用='..tostring(back==true)..' 读回='..short(now)..' 已还原='..tostring(U.key(now)==U.key(old)))
        else say('还原网格 实例='..r.name..'；实例已变化，不写')end
        return false
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
        local sockets=weaponSockets(actor,mesh)
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
    -- A step on one body; the breaker counts bodies in a row on which it failed.
    local function run(step,r,fn)
        if self.off[step]then
            if not self.skipped[step]then self.skipped[step]=true;say(LABELS[step]..' 本次加载已停用，之后的魂都跳过（实例='..r.name..'）')end
            return nil
        end
        local ok,result=pcall(fn)
        local passed=ok and result==true
        if not ok then say(LABELS[step]..' 中断：实例='..r.name..' 原因='..tostring(result))end
        if passed then self.streak[step]=0
        else
            self.streak[step]=(self.streak[step]or 0)+1
            if self.streak[step]>=Look.LIMIT then
                self.off[step]=true
                say('已停用 '..LABELS[step]..'：连续 '..self.streak[step]..' 只魂失败，下次 Restart All Mods 恢复')
            end
        end
        return passed
    end
    -- Mesh first, then anim class. still(): the body's identity is unchanged (checked again before every write).
    function self:apply(r,still)
        local actor=r.actor
        local mesh=U.field(actor,'Mesh')
        if not U.valid(mesh)then say('实例='..r.name..'；没有 Mesh，不改外观和动画');return {}end
        if not steps.look and not steps.anim then return {}end
        r.undo={}
        local before=weaponSockets(actor,mesh)
        local _,asset=call(mesh,'GetSkeletalMeshAsset')
        say('改前 实例='..r.name..' 网格='..short(asset)..' 动画实例='..instanceClass(mesh)..' 武器挂接=['..before..']')
        local result={}
        if steps.look=='clone'then result.look=run('look',r,function()return meshStep(r,mesh,still,before)end)end
        if steps.anim then result.anim=run('anim',r,function()return animStep(r,actor,mesh,still,before)end)end
        r.lookResult=result
        return result
    end
    -- A second readback one support cycle later: what the body shows now.
    function self:recheck(r)
        if not r.lookResult then return end
        local mesh=U.field(r.actor,'Mesh')
        local _,asset=call(mesh,'GetSkeletalMeshAsset')
        local mm,item=object(Look.PATHS.mm),object(Look.PATHS.item)
        say('复读 实例='..r.name..' 网格='..short(asset)..' 动画实例='..instanceClass(mesh)..' ABP_MM_Monster='..tostring(layer(mesh,mm))
            ..' ABP_Item_Hun_Summon='..tostring(layer(mesh,item))..' 换网格='..tostring(r.lookResult.look)..' 换动画类='..tostring(r.lookResult.anim))
    end
    return self
end
return Look
