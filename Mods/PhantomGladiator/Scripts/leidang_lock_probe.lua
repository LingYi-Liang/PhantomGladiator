-- Optional lock-on readback for Lei Dang P2. Uses the installed player's native lock handler.
local U=require('ue_observe')
local Probe={}
local LEI='/PBZCombatAsset/ActorData/Mobs/050_LeiDang_P2/BP_Monster_LeiDang_P2.BP_Monster_LeiDang_P2_C'
local COMBAT='Targeting.Target.Combat'
local VALIDATOR='Targeting.Validator.Combat.Default'
local INTERVAL,PER_MODE,PER_SESSION=1.5,10,48

local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args=table.pack(...)
    local ok,result=pcall(function()return object[method](object,table.unpack(args,1,args.n))end)
    if ok then return U.unwrap(result) end
end

local function tagCount(actor,tag)
    return call(U.field(actor,'AbilitySystemComponent'),'GetGameplayTagCount',{TagName=FName(tag)})
end

local function socketOwner(socket)
    return call(U.struct(socket,'Component'),'GetOwner')
end

local function name(value)
    if type(value)=='string' then return value end
    if value~=nil then
        local ok,result=pcall(function()return value:ToString()end)
        if ok and type(result)=='string' then return result end
    end
end

local function readRegistered(sub,key)
    local out={}
    local ok=pcall(function()sub:GetTargetsByTag({TagName=FName(COMBAT)},true,out)end)
    local actors=ok and U.array(out.OutTargets or (out[1] and out))
    if not actors then return nil end
    local unknown=false
    for _,actor in ipairs(actors)do
        local id=U.key(actor)
        if id==key then return true end
        if not id then unknown=true end
    end
    if not unknown then return false end
end

local function primarySocket(utils,actor,key)
    if not U.valid(utils) then return nil,nil end
    local out={}
    local ok,result=pcall(function()return utils:GetPrimaryTargetingData(actor,{TagName=FName(COMBAT)},out)end)
    if not ok then return nil,nil end
    if U.unwrap(result)==false then return false,nil end
    local data=out.OutTarget or out
    local component=U.struct(data,'Component')
    local socket=U.struct(data,'SocketName')
    if U.key(socketOwner(data))==key and U.valid(component) and socket~=nil then
        return true,{Component=component,SocketName=socket}
    end
    return nil,nil
end

local function readRated(handler,key)
    if not U.valid(handler) then return nil,nil,nil end
    local out={}
    -- Sample candidates for initial acquisition, the same query on the combined and standard handlers.
    local ok=pcall(function()handler:FindTargetsRated({},out,false)end)
    local candidates=ok and U.array(out.Targets or (out[1] and out))
    if not candidates then return nil,nil,nil end
    local unknown=false
    for index,entry in ipairs(candidates)do
        local id=U.key(socketOwner(U.struct(entry,'Target')))
        if id==key then return true,index,#candidates end
        if not id then unknown=true end
    end
    if unknown then return nil,nil,#candidates end
    return false,nil,#candidates
end

local function boundTo(handler,playerKey,targetingKey)
    return U.key(U.field(handler,'Avatar'))==playerKey
        and U.key(U.field(handler,'TargetingComponent'))==targetingKey
end

local function readStandard(handler,key,playerKey,targetingKey)
    for _,entry in ipairs(U.array(U.field(handler,'Handlers')) or {})do
        local child=U.struct(entry,'Handler')
        if U.className(child)=='PBZ_TargetingHandler_CombatLock_C' and boundTo(child,playerKey,targetingKey) then
            return (readRated(child,key))
        end
    end
end

local function readBest(targeting)
    local out={}
    local ok,result=pcall(function()return targeting:FindTarget(out)end)
    if not ok then return '?' end
    if U.unwrap(result)==false then return '无' end
    return U.className(socketOwner(out.Target or out)) or '?'
end

local function cameraAngles(camera,socket)
    if not socket or not U.valid(camera) then return '?' end
    local from=call(camera,'GetCameraLocation')
    local look=call(camera,'GetCameraRotation')
    local at=call(socket.Component,'GetSocketLocation',socket.SocketName)
    local x,y,z=U.struct(at,'X'),U.struct(at,'Y'),U.struct(at,'Z')
    local a,b,c=U.struct(from,'X'),U.struct(from,'Y'),U.struct(from,'Z')
    local yaw,pitch=U.struct(look,'Yaw'),U.struct(look,'Pitch')
    for _,value in pairs({x=x,y=y,z=z,a=a,b=b,c=c,yaw=yaw,pitch=pitch})do
        if type(value)~='number' or value~=value or math.abs(value)==math.huge then return '?' end
    end
    if x==nil or y==nil or z==nil or a==nil or b==nil or c==nil or yaw==nil or pitch==nil then return '?' end
    local dx,dy,dz=x-a,y-b,z-c
    local horizontal=math.sqrt(dx*dx+dy*dy)
    local dyaw=(math.deg(math.atan(dy,dx))-yaw+180)%360-180
    local dpitch=(math.deg(math.atan(dz,horizontal))-pitch+180)%360-180
    return string.format('%.1fm/%.1f°/%.1f°',math.sqrt(horizontal*horizontal+dz*dz)/100,dyaw,dpitch)
end

local function stage(s)
    if s.locked==true then return '已锁定' end
    if s.registered==false then return '未注册为战斗目标' end
    if s.primary==false then return '未取得原生锁点' end
    if s.rated==true then return '进入原生候选' end
    if s.primary==true and s.bone==false then return '模型缺少原生锁点' end
    if (s.dead or 0)>0 or (s.deathAnim or 0)>0 or (s.executing or 0)>0
        or ((s.unselectable or 0)>0 and s.keep==0) then
        return '目标状态被过滤'
    end
    if s.validator==false then return '原生验证器拒绝' end
    if s.rated==false and s.path==false then return '未通过镜头路径检查' end
    if s.rated==false and s.standard==true then
        if (s.inCombat or 0)>0 then return '进战处理器筛掉目标' end
        if (s.finding or 0)>0 then return '重试锁定时普通处理器未入选' end
    end
    if s.rated==false then return '未进入原生候选' end
    return '候选结果未读回'
end

function Probe.new(options)
    local self={}
    local record,used=nil,0
    local function snapshot(player,actor,world,playerKey,key,mode,status)
        local targeting=U.field(player,'Targeting Component')
        local targetingKey=U.key(targeting)
        if not targetingKey or U.key(call(targeting,'GetOwner'))~=playerKey then return nil end
        local utils=options.utils()
        local sub=U.field(targeting,'TargetingSubsystem')
        local registryReady=U.inWorld(sub,world)
        local s={}
        if registryReady then s.registered=readRegistered(sub,key) end
        s.primary,s.socket=primarySocket(utils,actor,key)
        local mesh=s.socket and s.socket.Component or U.field(actor,'Mesh')
        local socket=s.socket and s.socket.SocketName or FName('spine_04')
        if name(socket)~='None' and U.key(call(mesh,'GetOwner'))==key then
            s.bone=call(mesh,'DoesSocketExist',socket)
        end
        s.forward=options.relation(player,actor)
        s.reverse=options.relation(actor,player)
        s.unselectable=tagCount(actor,'CharacterState.Unselectable')
        s.keep=tagCount(actor,'CharacterState.Unselectable.KeepLock')
        s.dead=tagCount(actor,'CharacterState.Dead')
        s.deathAnim=tagCount(actor,'CharacterState.HitReact.State.Dead')
        s.executing=tagCount(actor,'CharacterState.HitReact.State.Executing')
        local lock,read=U.field(targeting,'LockTarget')
        local lockOwner=socketOwner(lock)
        local lockComponent,lockKnown=U.struct(lock,'Component')
        if read and lockKnown and (not U.valid(lockComponent) or U.key(lockOwner)) then
            s.locked=U.key(lockOwner)==key
            if s.locked then s.indicator=call(U.field(targeting,'LockWidget'),'IsVisible') end
        end
        local handler=U.field(targeting,'CurrentHandler')
        if not U.valid(handler) then handler=U.field(targeting,'DefaultTargetHandler') end
        local handlerClass=U.className(handler)
        local camera=options.camera()
        local searchReady=registryReady and U.inWorld(camera,world)
            and boundTo(handler,playerKey,targetingKey)
        s.inCombat=tagCount(player,'CharacterState.InCombat')
        s.finding=tagCount(player,'CharacterState.Native.FindingLockTarget')
        local best
        if searchReady then
            if s.socket and U.key(socketOwner(s.socket))==key then
                local validator=U.field(handler,'ValidatorTag')
                if name(U.struct(validator,'TagName'))==VALIDATOR and U.valid(U.field(actor,'AbilitySystemComponent')) then
                    s.validator=call(targeting,'IsTargetValid',{TagName=FName(VALIDATOR)},s.socket)
                end
                -- The two native hard-lock handlers use ELockPathCondition.Camera (5).
                if handlerClass=='PBZ_TargetingHandler_CombatLock_Combined_C'
                    or handlerClass=='PBZ_TargetingHandler_CombatLock_C'
                    or handlerClass=='PBZ_TargetingHandler_CombatLock_InCombat_C' then
                    s.path=call(utils,'IsLockPathValid',player,s.socket,5)
                end
            end
            s.rated,s.index,s.total=readRated(handler,key)
            if s.rated==false and s.validator==true and s.path~=false
                and handlerClass=='PBZ_TargetingHandler_CombatLock_Combined_C'
                and ((s.inCombat or 0)>0 or (s.finding or 0)>0) then
                s.standard=readStandard(handler,key,playerKey,targetingKey)
            end
            if s.rated==nil then best=readBest(targeting) end
        end
        local fields={
            {'无仇恨',mode},{'可被仇恨',status.player_can_be_hatred_readback},
            {'玩家',U.key(player)},{'独臂虎',key},{'玩家对雷当',s.forward},{'雷当对玩家',s.reverse},
            {'注册',s.registered},{'原生锁点',s.primary},{'骨骼',name(socket)},{'存在',s.bone},
            {'死亡',s.dead},{'死亡动画',s.deathAnim},{'处决',s.executing},
            {'不可选',s.unselectable},{'保留锁定',s.keep},{'玩家进战',s.inCombat},{'寻找锁定',s.finding},
            {'处理器',handlerClass},{'搜索组件就绪',searchReady},{'验证通过',s.validator},{'镜头路径',s.path},{'进入候选',s.rated},
            {'候选位置',s.index},{'候选数',s.total},{'普通处理器通过',s.standard},
            {'当前锁住',s.locked},{'当前目标',U.className(lockOwner)},{'锁定标记可见',s.indicator},
            {'镜头距离偏航俯仰',cameraAngles(camera,s.socket)},{'回退首选',best},{'判断',stage(s)},
        }
        local line={}
        for i,field in ipairs(fields)do
            line[i]=field[1]..'='..(field[2]==nil and '?' or tostring(field[2]))
        end
        return table.concat(line,' ')
    end
    function self:sync(members)
        if used>=PER_SESSION or options.inGameThread()~=true then return end
        local actor
        for _,member in ipairs(members)do
            if member.class_path==LEI then actor=member.actor;break end
        end
        if not actor then record=nil;return end
        local now=options.clock()
        if record and now<record.nextAt then return end
        local player,world=options.player(),options.world()
        local key,playerKey=U.key(actor),U.key(player)
        if not key or not playerKey or not U.inWorld(actor,world) or not U.inWorld(player,world) or options.freeCam() then return end
        local status=options.spectator()
        local mode=status.enabled_requested==true
        if not record or record.key~=key or record.playerKey~=playerKey then
            record={key=key,playerKey=playerKey,samples=0}
        elseif mode~=record.mode then record.samples=0 end
        record.mode,record.nextAt=mode,now+INTERVAL
        if record.samples>=PER_MODE then return end
        record.samples,used=record.samples+1,used+1
        local line=snapshot(player,actor,world,playerKey,key,mode,status)
        options.log('[LeiDangLock] '..(line or '玩家原生锁定组件未读回'))
    end
    return self
end
return Probe
