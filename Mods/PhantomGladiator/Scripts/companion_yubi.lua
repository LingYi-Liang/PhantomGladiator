-- The native CA02 uses a level marker for its warp and later uses that warp to spawn
-- BP_YuBi_CA02_Arena. Supply only the casting companion's warp; never register a map marker.
local U=require('ue_observe')
local Retry=require('lookup_retry')
local M={}
local BASE='/PBZCombatAsset/ActorData/Mobs/YuBi/'
M.actor=BASE..'BP_Monster_YuBi.BP_Monster_YuBi_C'
-- The native activation sets its warp synchronously. Its wall-spawn timeline action is at 2.76 s.
M.prepare=BASE..'Ability/Abilities/V2/GA_YuBi_CA_02.GA_YuBi_CA_02_C:K2_ActivateAbility'
M.finish=BASE..'Ability/Abilities/V2/GA_YuBi_CA_02.GA_YuBi_CA_02_C:K2_OnEndAbility'
M.activate=BASE..'Blueprint/BP_YuBi_CA02_Arena.BP_YuBi_CA02_Arena_C:ActivateArena'
M.controller='/Script/Engine.GameplayStatics:GetPlayerController'
local WARP='/Script/MotionWarping.MotionWarpingComponent'
local WALL='BP_YuBi_CA02_Arena_C'
local RADIUS=2000 -- BP_YuBi_CA02_Arena.ArenaRadius in cm.
local function same(a,b)local k=U.key(a);return k~=nil and k==U.key(b)end
local function call(a,m,...)
    if not U.valid(a)then return false end
    local args,n={...},select('#',...)
    local ok,v=pcall(function()return a[m](a,table.unpack(args,1,n))end)
    return ok,U.unwrap(v)
end
local function vector(v)
    local p={}
    for _,k in ipairs({'X','Y','Z'})do
        local n=U.struct(v,k)
        if type(n)~='number' or not(n>-math.huge and n<math.huge)then return end
        p[k]=n
    end
    return p
end
local function snap(component)
    local rows=U.array(U.field(component,'WarpTargets'))
    if not rows then return nil,false end
    for _,v in ipairs(rows)do
        local key=U.struct(v,'Name')
        if type(key)~='string' then local ok,s=pcall(function()return key:ToString()end);if not ok then return nil,false end;key=s end
        if key=='SnapPoint' then local p=vector(U.struct(v,'Location'));return p,p~=nil end
    end
    return nil,true
end
local function distance2(a,b)return (a.X-b.X)^2+(a.Y-b.Y)^2 end
function M.new(o)
    local self={alive=true}
    local owned,pins,hooks={},{},{}
    local retry=Retry.new({clock=o.clock,log=function(s)if o.log then o.log('[YuBiArena] '..s)end end})
    local probe,empty
    local function gameThread()
        if not o.inGameThread then return true end
        local ok,yes=pcall(o.inGameThread);return ok and yes==true
    end
    local function say(s)if o.log then o.log('[YuBiArena] '..s) end end
    local function validEnemy(r)
        if not U.valid(r.target) or same(r.target,o.player()) or not U.inWorld(r.target,r.world) or not same(o.world(),r.world) then return false end
        local _,sourceName=call(r.actor,'GetFullName');local _,enemyName=call(r.target,'GetFullName')
        if sourceName~=r.actorName or enemyName~=r.targetName then return false end
        return same(o.current(r.actor),r.target)
    end
    local function answer(context,index,controller,cls)
        if not self.alive or (not probe and not next(pins)) or not gameThread() or U.unwrap(index)~=0 then return end
        local ctx=U.unwrap(context)
        if probe and same(ctx,probe.actor) then
            probe.hits=probe.hits+1
            return controller and empty or probe.expected
        end
        if (cls or U.className(ctx))~=WALL then return end
        local _,actor=call(ctx,'GetOwner')
        local r=pins[U.key(actor) or '']
        if not r or not same(actor,r.actor) or not U.inWorld(ctx,r.world) then return end
        r.walls[U.key(ctx)]=ctx
        if controller then return empty end -- NPC walls have no local camera or gamepad recipient.
        local ok,valid=pcall(validEnemy,r)
        if ok and valid then return r.target end
        return empty
    end
    function self:character(ctx,index,cls)return answer(ctx,index,false,cls)end
    function self:hasPending()return self.alive and next(pins)~=nil end
    local function verified(actor,target)
        local lib=o.statics()
        if empty==nil then
            local ok,v=pcall(o.invalid or CreateInvalidObject)
            if not ok or v==nil or U.valid(v)then return false end
            empty=v
        end
        for _,step in ipairs({{'GetPlayerCharacter',target},{'GetPlayerCharacter',empty},{'GetPlayerController',empty}})do
            probe={actor=actor,expected=step[2],hits=0}
            local ok,back=call(lib,step[1],actor,0)
            local confirmed=ok and probe.hits==1 and (same(step[2],target) and same(back,target) or step[2]==empty and not U.valid(back))
            probe=nil
            if not confirmed then return false end
        end
        return true
    end
    local function clearAnchor(r)
        if not r.point then return true end
        local _,owner=call(r.component,'GetOwner')
        if not same(owner,r.actor) then r.point=nil;return true end
        local p,read=snap(r.component)
        if not read then return false end
        if p and distance2(p,r.point)<.01 and math.abs(p.Z-r.point.Z)<.1 then
            say('即将撤下该随从的临时落点')
            call(r.component,'RemoveWarpTarget',(o.fname or FName)('SnapPoint'))
            local after,got=snap(r.component)
            if not got or after then return false end
            say('临时落点已移除')
        end
        r.point=nil;return true
    end
    local function retire(r)
        r.target=nil
        local done=clearAnchor(r)
        for key,wall in pairs(r.walls)do
            local _,owner=call(wall,'GetOwner')
            if same(owner,r.actor) and U.field(wall,'bRetiring')~=true then
                say('即将收回该随从的电围墙')
                call(wall,'RetireArena')
            end
            if not same(owner,r.actor) or not U.valid(wall) or U.field(wall,'bRetiring')==true then r.walls[key]=nil else done=false end
        end
        return done
    end
    function self:releaseActor(actor)
        local r=pins[U.key(actor) or '']
        return not r or retire(r)
    end
    function self:prepare(context)
        if not self.alive or not gameThread() or not hooks[M.controller] or not hooks[M.finish] or not hooks[M.activate] then return end
        local ability=U.unwrap(context)
        local _,actor=call(ability,'GetAvatarActorFromActorInfo')
        local key=U.key(actor)
        if not key or not same(owned[key],actor) or U.npcPath(actor)~=M.actor then return end
        local world=o.world();local target=o.current(actor)
        if not U.valid(target) or same(target,o.player()) or same(target,actor) or not U.inWorld(target,world) or not U.inWorld(actor,world) then return end
        local old=pins[key]
        if old and not same(old.target,target) and not retire(old)then return end
        local _,sourceName=call(actor,'GetFullName');local _,enemyName=call(target,'GetFullName')
        if type(sourceName)~='string' or type(enemyName)~='string' then return end
        local r=old and same(old.target,target) and old or {actor=actor,target=target,world=world,walls={},actorName=sourceName,targetName=enemyName}
        if not verified(actor,target) then say('玩家与敌方取参隔离未确认，保留原生落点');return end
        local cls=retry:find(WARP,o.find)
        if not U.valid(cls)then return end
        local _,component=call(actor,'GetComponentByClass',cls);local _,owner=call(component,'GetOwner')
        if not same(owner,actor)then return end
        local p,read=snap(component);local a,b=vector(o.location(actor)),vector(o.location(target))
        if not read or not a or not b or not validEnemy(r) then return end
        pins[key]=r
        r.ability=ability
        if p and distance2(p,a)<=RADIUS^2 and distance2(p,b)<=RADIUS^2 then return end
        if p then
            -- This activation just wrote a warp outside the current fight. Never move a level marker.
            say('即将撤下本次技能选中的远处落点')
            call(component,'RemoveWarpTarget',(o.fname or FName)('SnapPoint'))
            local remaining,got=snap(component)
            say('远处落点移除读回='..tostring(got and remaining==nil))
            if not got or remaining then return end
        end
        if distance2(a,b)>(2*RADIUS)^2 then return end
        local x,y=(a.X+b.X)/2,(a.Y+b.Y)/2
        local z=o.ground(world,x,y,(a.Z+b.Z)/2,100,{actor,target})
        local point=vector({X=x,Y=y,Z=z})
        if not point or math.abs(z-a.Z)>1200 or math.abs(z-b.Z)>1200 or not validEnemy(r) then return end
        r.component,r.point=component,point
        say('即将为随从玉璧本次原生 CA02 设置交战落点')
        local wrote=call(component,'AddOrUpdateWarpTargetFromLocation',(o.fname or FName)('SnapPoint'),point)
        local after=snap(component)
        local confirmed=wrote and after and distance2(after,point)<.01 and math.abs(after.Z-z)<.1
        say('私有落点读回='..tostring(confirmed==true)..' 敌人='..tostring(U.key(target)))
        if not confirmed then clearAnchor(r)end
    end
    local function finish(context)
        if not self.alive or not next(pins) or not gameThread() then return end
        local ability=U.unwrap(context);local _,actor=call(ability,'GetAvatarActorFromActorInfo')
        local key=U.key(actor);local r=key and pins[key]
        if r and same(ability,r.ability) then
            r.ability=nil
            if clearAnchor(r) and not next(r.walls) then pins[key]=nil end
        end
    end
    local function verifyWall(r,wall)
        if not validEnemy(r) or U.valid(U.field(wall,'StormFeedbackController')) or not same(U.field(wall,'SourceBoss'),r.actor)
            or not same(U.field(wall,'PlayerCharacter'),r.target)
            or not same(U.field(wall,'BossASC'),U.field(r.actor,'AbilitySystemComponent'))
            or not same(U.field(wall,'PlayerASC'),U.field(r.target,'AbilitySystemComponent')) then
            say('电墙参与者未读回，收回本次围墙')
            pcall(function()
                wall.PlayerCharacter=nil;wall.PlayerASC=nil;wall.PlayerCapsule=nil;wall.PlayerHitreact=nil
            end)
            say('电墙目标与属性组件解绑读回='..tostring(not U.valid(U.field(wall,'PlayerCharacter')) and not U.valid(U.field(wall,'PlayerASC'))))
            retire(r);return false
        end
        -- The native feedback entry skips its three effects when there is no local controller.
        -- Start only the wall's positional audio. Its native retirement stops the same playing ID.
        if U.field(wall,'StormFeedbackActive')==false and not U.valid(U.field(wall,'StormFeedbackController')) then
            say('即将启动随从电墙的场地音效')
            pcall(function()wall.StormFeedbackActive=true end)
            if U.field(wall,'StormFeedbackActive')==true then
                call(wall,'StartStormAudio')
                say('场地音效播放 ID 读回='..tostring(U.field(wall,'StormSoundPlayingID')))
            end
        end
        say('电墙本体和双方属性组件已读回；敌人='..tostring(U.key(r.target)))
        return true
    end
    local function activated(context)
        if not self.alive or not gameThread() then return end
        local wall=U.unwrap(context);local _,owner=call(wall,'GetOwner')
        local r=pins[U.key(owner) or ''];local key=U.key(wall)
        if key and r and same(owner,r.actor) and U.inWorld(wall,r.world) then
            r.walls[key]=wall;verifyWall(r,wall)
        end
    end
    local function install(path,fn)
        if hooks[path] or not retry:ready('hook:'..path) then return end
        local found=retry:find(path,function(p)
            local find=o.find or StaticFindObject
            local v=find(p)
            if not U.valid(v) and p~=M.controller then
                pcall(o.load or LoadAsset,p:match('^([^:]+):'));v=find(p)
            end
            return v
        end)
        if not U.valid(found) then return end
        local ok,a,b=pcall(o.register or RegisterHook,path,fn)
        ok=ok and type(a)=='number' and type(b)=='number'
        retry:result('hook:'..path,ok)
        if ok then hooks[path]={a,b} end
    end
    local function unhook()
        for p,ids in pairs(hooks)do
            local ok,result=pcall(o.unregister or UnregisterHook,p,ids[1],ids[2])
            if ok and result~=false then hooks[p]=nil end
        end
    end
    local function installHooks()
        install(M.controller,function(_,context,index)return answer(context,index,true)end)
        install(M.activate,activated);install(M.finish,finish)
        install(M.prepare,function(context)self:prepare(context)end)
    end
    function self:roster(roster)
        if not self.alive then return end
        local here={}
        for _,m in ipairs(roster or {})do
            if m.team=='companion' and m.class_path==M.actor and not m.reserve and not m.stand then
                local key=U.key(m.actor);if key then here[key]=m.actor end
            end
        end
        owned=here
        if next(owned) then installHooks() end
    end
    function self:tick(roster)
        if not self.alive then return end
        if roster then self:roster(roster) end
        for k,r in pairs(pins)do
            if not same(owned[k],r.actor) or not validEnemy(r) then
                -- Keep a live companion's empty recipient until its next cast: a late boundary
                -- callback from the old cast must still receive null instead of player zero.
                if retire(r) and (not U.valid(r.actor) or not U.valid(r.ability)) then pins[k]=nil end
            else
                for id,w in pairs(r.walls)do
                    if not U.valid(w) or U.field(w,'bRetiring')==true then r.walls[id]=nil
                    elseif not same(U.field(w,'PlayerCharacter'),r.target) or not same(U.field(w,'PlayerASC'),U.field(r.target,'AbilitySystemComponent'))
                        or U.valid(U.field(w,'StormFeedbackController')) then
                        verifyWall(r,w);break
                    end
                end
                if not next(r.walls) and not r.ability and clearAnchor(r) then pins[k]=nil end
            end
        end
        if next(owned) and (not hooks[M.controller] or not hooks[M.finish] or not hooks[M.prepare] or not hooks[M.activate]) then
            installHooks()
        elseif not next(owned) and not next(pins) and next(hooks) then unhook()end
    end
    function self:silence(onGameThread)
        self.alive=false
        if onGameThread then for _,r in pairs(pins)do retire(r)end end
        unhook();owned,pins={},{}
    end
    return self
end
return M
