local U=require('ue_observe')
local P=require('companion_profile')
local Stats=require('character_stats')
local Native={}
local function call(obj,method,...)
    if not U.valid(obj) then return nil end
    local ok,v=pcall(function(...)return obj[method](obj,...)end,...);if ok then return U.unwrap(v) end
end
local function id(actor)
    local key=U.key(actor);local name=key and call(actor,'GetFullName')
    if type(name)=='string' then return key,name end
end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function vec(p)
    local x,y,z=U.struct(p,'X'),U.struct(p,'Y'),U.struct(p,'Z')
    if finite(x) and finite(y) and finite(z) then return {X=x,Y=y,Z=z} end
end
local function rotation(actor)
    local q=U.struct(call(actor,'GetTransform'),'Rotation')
    local x,y,z,w=U.struct(q,'X'),U.struct(q,'Y'),U.struct(q,'Z'),U.struct(q,'W')
    if finite(x) and finite(y) and finite(z) and finite(w) and math.abs(x*x+y*y+z*z+w*w-1)<.01 then
        return {X=x,Y=y,Z=z,W=w}
    end
end
local function same(a,b)local k=U.key(a);return k~=nil and k==U.key(b) end
function Native.new(o)
    local self={};local attrs=Stats.new()
    local function own(actor,world)
        return U.valid(actor) and U.inWorld(actor,world) and o.destroying(actor)==false
    end
    local function lib()return StaticFindObject('/Script/SGameAI.Default__SGameAIFunctionLibrary') end
    local function sample(r,checkAction)
        local actor,world=r.actor,o.world()
        if not own(actor,world) or not same(world,o.world()) then return end
        local hp,max=o.hp(actor),o.maxHP(actor)
        if not finite(hp) or not finite(max) or max<=0 then return end
        if hp<=0 then return {hp=hp,max=max,safe=false,known=false,canSwitch=false} end
        local ai=o.ai(actor)
        local tag=U.struct(U.field(ai,'CurrentStateTag'),'TagName')
        local name=tag and o.tagName(tag) or ''
        local target,known=o.target(actor)
        local hm=U.field(actor,'BP_PBZHatredManagerComponent')
        local hates=U.arraySize(U.field(hm,'HatredList'))
        local attackers=U.arraySize(U.field(hm,'BeHatredList'))
        local idle=name=='AI.State.Idle' or name:match('^AI%.State%.Idle%.')~=nil
        local combat=name:find('Combat',1,true)~=nil or target~=nil or hates and hates>0 or attackers and attackers>0
        if not combat and (r.pose or r.waiting) then
            local attackersOfPlayer=U.arraySize(U.field(U.field(o.player(),'BP_PBZHatredManagerComponent'),'BeHatredList'))
            combat=attackersOfPlayer and attackersOfPlayer>0
        end
        local safe=not o.blocked(actor) and U.field(ai,'bAIStarted')==true
        local canSwitch
        if checkAction~=false then canSwitch=safe and o.actionBusy(actor)==false end
        return {hp=hp,max=max,target=target,attackers=attackers,combat=combat==true,
            known=known==true and hates~=nil and attackers~=nil and (idle or combat==true),safe=safe,canSwitch=canSwitch}
    end
    local function writeValue(actor,field,value)
        local ok=attrs:writeBase(actor,field,value)
        return ok and Stats.close(attrs:nativeValue(actor,field),value)
    end
    local function stopPose(r)
        local pose=r.pose
        if not pose then return true end
        if same(call(U.field(r.actor,'Mesh'),'GetAnimInstance'),pose.anim) and call(pose.anim,'Montage_IsPlaying',pose.montage)==true then
            call(pose.anim,'Montage_Stop',0,pose.montage)
            if call(pose.anim,'Montage_IsPlaying',pose.montage)~=false then return false end
        end
        r.pose=nil;return true
    end
    local function resume(r)
        local lease=r.lease
        if not lease then return true end
        local controller=U.field(r.actor,'Controller')
        local brain=U.field(controller,'BrainComponent')
        if not U.valid(lease) then r.lease=nil;return true end
        if not same(U.field(controller,'Pawn'),r.actor) or not same(U.field(brain,'AIOwner'),controller) then return false end
        if same(brain,lease) then
            local paused=call(brain,'IsPaused')
            if paused==nil then return false end
            if paused then
                call(lib(),'ResumeLogic',brain,'PhantomGladiator companion command ended')
                if call(brain,'IsPaused')~=false then return false end
            end
        end
        r.lease=nil;return true
    end
    local function restoreTargetable(r)
        if not r.hatred then return true end
        local hm=U.field(r.actor,'BP_PBZHatredManagerComponent')
        if U.valid(r.hatred) then
            if not same(call(hm,'GetOwner'),r.actor) then return false end
            if same(hm,r.hatred) then
                local current=U.field(hm,'CanBeHatredNow')
                if type(current)~='boolean' then return false end
                if not current then
                    pcall(function()hm.CanBeHatredNow=true end)
                    if U.field(hm,'CanBeHatredNow')~=true then return false end
                end
            end
        end
        r.hatred=nil;return true
    end
    function self.release(r)
        local pose,brain,aggro=stopPose(r),resume(r),restoreTargetable(r)
        return pose and brain and aggro
    end
    -- A pause owned by this module can outlast the target blackboard that led to it.
    local function releaseUnused(r)
        if r.p.targetable~=0 then restoreTargetable(r) end
        if r.p.behavior=='active' and not r.pose and not r.waiting then return resume(r) end
        return true
    end
    local function behave(r,v)
        local actor,player=r.actor,nil
        local aggroReady=true
        if r.p.targetable==0 then
            local hm=U.field(actor,'BP_PBZHatredManagerComponent')
            if same(call(hm,'GetOwner'),actor) and U.field(hm,'CanBeHatredNow')==true then
                pcall(function()hm.CanBeHatredNow=false end)
                if U.field(hm,'CanBeHatredNow')==false then r.hatred=hm end
            end
            aggroReady=U.field(hm,'CanBeHatredNow')==false
        else aggroReady=restoreTargetable(r) end
        local assist=false
        if r.p.behavior=='assist' then
            player=o.player()
            local theirs=U.field(player,'BP_PBZHatredManagerComponent')
            local attacked=U.arraySize(U.field(theirs,'BeHatredList'))
            local attackers=v.attackers
            if r.lastHP and v.hp<r.lastHP then r.defendUntil=o.now()+8 end
            assist=attacked and attacked>0 or attackers and attackers>0 or o.now()<(r.defendUntil or 0)
        end
        r.lastHP=v.hp;r.defending=assist==true
        if v.combat then r.waiting=nil end
        local hold=r.waiting or r.pose or r.p.behavior=='peace' or r.p.behavior=='assist' and not assist
        if not hold then return resume(r) and aggroReady end
        local controller=U.field(actor,'Controller');local brain=U.field(controller,'BrainComponent')
        if not same(U.field(controller,'Pawn'),actor) or not same(U.field(brain,'AIOwner'),controller) then return false end
        local paused=call(brain,'IsPaused')
        if r.lease and (not same(brain,r.lease) or paused==false) then r.lease=nil end
        if not r.lease then
            if paused~=false or call(brain,'IsRunning')~=true then return false end
            call(lib(),'PauseLogic',brain,'PhantomGladiator companion command')
            if call(brain,'IsPaused')~=true then return false end
            r.lease=brain
            call(controller,'StopMovement')
        end
        if r.waiting or r.pose or o.now()<(r.nextMove or 0) then return aggroReady end
        player=player or o.player()
        if not U.valid(player) then return false end
        local here,there=vec(o.location(actor)),vec(o.location(player))
        if here and there then
            if o.keepFollowing and not v.combat then o.keepFollowing(actor,player) end
            local gap=(here.X-there.X)^2+(here.Y-there.Y)^2+(here.Z-there.Z)^2
            if gap>(r.p.distance*100)^2 and call(controller,'GetMoveStatus')~=3 then
                call(StaticFindObject('/Script/AIModule.Default__AIBlueprintHelperLibrary'),'SimpleMoveToActor',controller,player)
            elseif gap<=(r.p.distance*100)^2 and call(controller,'GetMoveStatus')==3 then call(controller,'StopMovement') end
            r.nextMove=o.now()+1
        end
        return aggroReady
    end
    function self.transfer(r,world,why,initial)
        local v=sample(r)
        if not v or not v.safe or not v.canSwitch or not v.known or v.hp<=0 or v.combat~=initial.combat
            or not own(r.actor,world) or not P.phase(U.npcPath(r.actor)) then return nil,'原形态当前不可切换' end
        local at,facing=vec(o.location(r.actor)),rotation(r.actor)
        if not at or not facing then return nil,'位置或朝向未确认' end
        local transfer={old=r.actor,world=world,wasCombat=v.combat,target=v.target,at=at,resources={},
            transform={Translation=at,Rotation=facing,Scale3D={X=1,Y=1,Z=1}}}
        for _,field in ipairs({'Health','Shachi'})do
            local value,limit=attrs:read(r.actor,field),attrs:read(r.actor,field..'_Max')
            if not value or not limit or limit.current<=0 or value.current<0 or value.current>limit.current+.001 then return nil,'生命或杀气无法换算' end
            transfer.resources[field]={ratio=math.min(1,value.current/limit.current),original=value.current,max=limit.current}
        end
        return transfer
    end
    function self.commitReady(r,new,x,world)
        if not same(world,o.world()) or not own(new,world) then return false end
        local v=sample(r)
        if not v or not v.safe or not v.canSwitch or not v.known or v.combat~=x.wasCombat
            or (v.target or x.target) and not same(v.target,x.target) then return false end
        for _,field in ipairs({'Health','Shachi'})do
            local entry=attrs:read(r.actor,field)
            if not entry or not Stats.close(entry.current,x.resources[field].original) then return false end
        end
        return true
    end
    function self.restore(r,new,x,why,world)
        local fresh=sample(r);local here=vec(o.location(new));local old=vec(o.location(r.actor))
        if not here or not old or not same(world,x.world) or not same(world,o.world()) or not own(new,world) or not fresh or not fresh.safe
            or not fresh.canSwitch or not fresh.known or fresh.hp<=0 or fresh.combat~=x.wasCombat then return false,'战斗状态已改变' end
        local function close(p)return (p.X-x.at.X)^2+(p.Y-x.at.Y)^2+(p.Z-x.at.Z)^2<=150^2 end
        if not close(here) or not close(old) then return false,'转换时位置发生变化' end
        local face=rotation(new);local before=x.transform.Rotation
        if not face or math.abs(face.X*before.X+face.Y*before.Y+face.Z*before.Z+face.W*before.W)<.99 then return false,'新形态朝向未确认' end
        for _,field in ipairs({'Health','Shachi'})do
            local a=x.resources[field];local value=attrs:read(r.actor,field);local oldMax=attrs:read(r.actor,field..'_Max')
            local max=attrs:read(new,field..'_Max')
            if not max or not oldMax or not value or not Stats.close(value.current,a.original) or not Stats.close(oldMax.current,a.max)
                or max.current<=0 or not writeValue(new,field,max.current*a.ratio) then return false,'转换资源读回失败 '..field end
        end
        if x.target then
            if not same(x.target,fresh.target) or not own(x.target,world) or same(x.target,o.player())
                or call(U.field(new,'Faction Component'),'GetFactionRelation',x.target)~=2 then return false,'转换时敌人发生变化' end
            local ai=o.ai(new);local ok=pcall(function()ai:ForceIntoCombat(x.target)end)
            if not ok then return false,'无法交接当前目标' end
            local list=U.array(U.field(U.field(new,'BP_PBZHatredManagerComponent'),'HatredList'))
            local held=false;for _,target in ipairs(list or {})do if same(target,x.target) then held=true end end
            if not held then return false,'目标仇恨尚未读回' end
        end
        return true
    end
    function self.pose(r)
        if r.pose then local ok=stopPose(r);return {ok=ok,message=ok and '已结束合影动作' or '动作取消未确认'} end
        local name=r.phase==2 and 'MuXiaoKui_P2' or 'MuXiaoKui'
        local base='/HuaShira/Characters/EliteBoss/'..name..'/'
        local path=base..'Anim/'..name..'_ShowPose.'..name..'_ShowPose'
        local mesh=U.field(r.actor,'Mesh');local anim=call(mesh,'GetAnimInstance')
        local loaded,asset=pcall(LoadAsset,path)
        local skeleton=call(call(mesh,'GetSkeletalMeshAsset'),'GetSkeleton')
        if not loaded or not U.valid(asset) or not same(U.field(asset,'Skeleton'),skeleton)
            or call(anim,'IsAnyMontagePlaying')~=false then return {ok=false,message='当前骨骼或动作不支持合影'} end
        call(anim,'PlaySlotAnimationAsDynamicMontage',asset,FName('DefaultSlot'),.15,.15,1,1,-1,0)
        local m=call(anim,'GetCurrentActiveMontage')
        if not U.valid(m) or call(anim,'DynamicMontage_IsPlayingFrom',asset)~=true then return {ok=false,message='合影动作未读回'} end
        r.pose={anim=anim,montage=m};return {ok=true,message='已播放当前形态的展示动作'}
    end
    local nextPreference,lastPreference,turn,preferenceLogs=0,0,0,0
    local function prefer(members,candidates,now)
        if now<lastPreference then nextPreference,turn=0,0 end
        lastPreference=now
        if now<nextPreference or #members==0 then return end
        nextPreference=now+.8
        local world,player=o.world(),o.player()
        if not own(player,world) then return end
        for _=1,#members do
            turn=turn%#members+1
            local row=members[turn]
            if row.team=='neutral' and not row.summoner and not row.reserve and not row.aid then
                local enemy=row.actor
                if not own(enemy,world) or not U.npcPath(enemy) then return end
                local hp=o.hp(enemy)
                if not finite(hp) or hp<=0 or o.blocked(enemy) or o.actionBusy(enemy) or not o.aimedAt(enemy,player) then return end
                local here=vec(o.location(enemy));local best,nearest=nil,2000^2
                if not here then return end
                for _,candidate in ipairs(candidates)do
                    local hp=own(candidate,world) and o.hp(candidate)
                    if finite(hp) and hp>0 and not o.blocked(candidate) and call(U.field(enemy,'Faction Component'),'GetFactionRelation',candidate)==2 then
                        local at=vec(o.location(candidate))
                        if at then
                            local d=(here.X-at.X)^2+(here.Y-at.Y)^2+(here.Z-at.Z)^2
                            if d<nearest then best,nearest=candidate,d end
                        end
                    end
                end
                if best and o.aimedAt(enemy,player) then
                    local ai=o.ai(enemy)
                    if U.valid(ai) then
                        call(ai,'ForceIntoCombat',best)
                        nextPreference=now+3
                        if o.log and preferenceLogs<12 then
                            preferenceLogs=preferenceLogs+1
                            o.log('[CompanionAggro] 无阵营召唤物优先随从，当前目标读回='..tostring(o.aimedAt(enemy,best)))
                        end
                    end
                end
                return
            end
        end
    end
    self.manager=require('companion_manager').new({path=o.path,read=o.read,write=o.write,log=o.log,session=o.session,now=o.now,ioClock=o.ioClock or os.clock,identity=function(actor)
        if not U.inWorld(actor,o.world()) or o.destroying(actor)~=false then return end
        return id(actor)
    end,owned=o.owned,recovered=o.recovered,
    cancelOrder=function(r)return stopPose(r) and resume(r)end,recallSafe=function(a)return not o.blocked(a)end,onDeath=function(r)return not o.blocked(r.actor) and o.onDeath(r.actor) end,brief=function(r)
        local hp=o.hp(r.actor);if not finite(hp) then return 'unknown' elseif hp<=0 then return 'down' end
        local tag=U.struct(U.field(o.ai(r.actor),'CurrentStateTag'),'TagName')
        return tag and o.tagName(tag):find('Combat',1,true) and 'combat' or 'following'
    end,sample=sample,canAct=function(actor)return o.actionBusy(actor)==false end,releaseUnused=releaseUnused,
    prefer=prefer,spawn=o.spawn,swap=o.swap,recall=o.recall,release=self.release,behave=behave,
    heal=function(r,value)if o.canHeal(r.actor) then return writeValue(r.actor,'Health',value) end end,
    pose=self.pose,cancelPose=stopPose,poseEnded=function(r)return call(r.pose.anim,'Montage_IsPlaying',r.pose.montage)~=true end,
    order=function(r,v)local ok=behave(r,v);return {ok=ok==true,message=ok and '随从指令已应用' or '原生行为树状态未确认'} end})
    return self
end
return Native