-- Summons and fighting units stay on the ground and alive, out of reach of the game's two fall rules.
--   AIScript_GroundCheck stops a falling unit in the air (Flying, no velocity, GE_GroundCheckFailed: AI.DisableCombatAI,
--   which blocks the change to AI.State.Combat) until the camera is within 10 m of it or there is ground 5 cm under it;
--   ForceIntoCombat does nothing meanwhile, the unit stays Idle.
--   BP_NPC_Base: a fall of DamageDepth (10 m) up to DeadDepth (20 m) costs that share of Health_Max on landing, and at
--   DeadDepth GE_Kill ends the unit in the air, whatever its health. A unit knocked off a ledge vanished from the fight.
-- Summons came 50 cm over the player's height, so with the free camera over 10 m away a unit could hang there and ignore
-- the start of the fight, and one summoned over a drop could fall to its death.
--   place, settle: a summon starts on the ground under its spot, or closer to the player when its spot is over a drop
--   (before it starts, and again with its real capsule). Its fall rule is taken away.
--   free: a fighting unit held in the air or falling far goes on the ground under it, or beside its opponent when that is
--   too far down or not there; walking mode ends the ground check, which removes the effect, and the AI carries on to the
--   state it was asked for.
local U=require('ue_observe')
local Ground={}
local CLEARANCE,PLACE_MAX_DROP,MAX_DROP,BESIDE,MAX_RISE,PARK_STEP=3,800,1500,300,60,300
local WALKING,NAV_WALKING,FALLING,FLYING=1,2,3,5
local BLOCK='AI.DisableCombatAI'
local NO_FALL_DEATH=1e9
local CLOSER={0.75,0.5,0.25,0}
local CAPS={place=12,miss=6,free=30,depth=6}

function Ground.new(options)
    local log=options.log or function()end
    local self={freed=0,placed=0}
    local lines={}
    local anchors={}
    function self:prune(keys)
        for key in pairs(anchors)do if not keys[key] then anchors[key]=nil end end
    end
    local function say(kind,text)
        lines[kind]=(lines[kind] or 0)+1
        if lines[kind]<=(CAPS[kind] or 10) then log('[OnGround] '..text) end
    end
    local function halfHeight(actor)
        local capsule=U.field(actor,'CapsuleComponent')
        if not U.valid(capsule) then return nil end
        local ok,half=pcall(function()return capsule:GetScaledCapsuleHalfHeight()end)
        return ok and type(half)=='number' and half>0 and half or nil
    end
    local function teleport(actor,dest)
        local okRot,rot=pcall(function()return actor:K2_GetActorRotation()end)
        local moved,result=pcall(function()return actor:K2_TeleportTo(dest,okRot and rot or {Pitch=0,Yaw=0,Roll=0})end)
        return moved and result
    end
    local function trace(world,x,y,z,up,ignored)
        local ok,ground,why=pcall(options.ground,world,x,y,z,up,ignored)
        if ok and type(ground)=='number' then return ground end
        return nil,ok and why or nil
    end
    -- From its own height first (a roof over a low room is not its floor), then from 3 m up for a spot under a hill or inside
    -- something. Under a hill the first look finds nothing and the surface can be metres up. A first look that starts inside
    -- something solid and a second one landing high means the top of that thing (seen 90 and 116 cm up): not a floor.
    local function groundAt(world,x,y,z,ignored)
        local found,why=trace(world,x,y,z,0,ignored)
        if found then return found end
        found=trace(world,x,y,z,nil,ignored)
        if found and why=='inside' and found>z+MAX_RISE then return nil end
        return found
    end
    function self:tagCount(actor,tag)
        local asc=U.field(actor,'AbilitySystemComponent')
        if not U.valid(asc) then return nil end
        local ok,n=pcall(function()return asc:GetGameplayTagCount({TagName=options.name(tag)})end)
        return ok and type(n)=='number' and n or nil
    end
    function self:mode(actor)
        local cmc=U.field(actor,'CharacterMovement')
        if not U.valid(cmc) then return nil,nil end
        return tonumber((U.field(cmc,'MovementMode'))),cmc
    end
    function self:blocked(actor)return self:tagCount(actor,BLOCK) end

    -- Read the property each time: an address can belong to a different actor after destruction.
    function self:keepFromFallDeath(actor)
        local before=U.field(actor,'DeadDepth')
        if type(before)~='number' or before==NO_FALL_DEATH then return end
        local written=pcall(function()actor.DeadDepth=NO_FALL_DEATH end)
        local after=U.field(actor,'DeadDepth')
        say('depth',string.format('%s 坠落致死深度 %.0f -> %s 写入=%s',options.label(actor),before,tostring(after),tostring(written)))
    end

    -- Before the unit starts: its spawn spot. t is the transform it will start with. Returns what settle needs.
    function self:place(pawn,t,world)
        local key=U.key(pawn)
        if key then anchors[key]=nil end
        local spot=t and t.Translation
        local half=halfHeight(pawn)
        if type(spot)~='table' or not half then return nil end
        self:keepFromFallDeath(pawn)
        local ground=groundAt(world,spot.X,spot.Y,spot.Z)
        local closer
        if not ground or spot.Z-ground>PLACE_MAX_DROP then
            -- Toward the middle of the batch (spawn_spot.lua), which is the player unless the free camera chose the spot.
            local at=options.anchor and options.anchor() or nil
            if not at then
                local player=options.player and options.player()
                at=player and options.location(player)
            end
            for _,share in ipairs(at and CLOSER or {})do
                local x,y=at.X+(spot.X-at.X)*share,at.Y+(spot.Y-at.Y)*share
                local there=groundAt(world,x,y,spot.Z)
                if there and spot.Z-there<=PLACE_MAX_DROP then
                    spot.X,spot.Y,ground,closer=x,y,there,share
                    break
                end
            end
        end
        if not ground or spot.Z-ground>PLACE_MAX_DROP then say('miss','出生点下方没找到地面，高度不变 Z='..tostring(spot.Z));return nil end
        local before=spot.Z
        spot.Z=ground+half+CLEARANCE
        self.placed=self.placed+1
        return {ground=ground,half=half,before=before,wanted=spot.Z,closer=closer}
    end
    -- After it starts: the capsule read before can be the class default; a taller real one is lifted out of the ground.
    function self:settle(pawn,placed)
        if not placed or not U.valid(pawn) then return end
        local half,at=halfHeight(pawn),options.location(pawn)
        local lifted='否'
        if half and at and placed.ground+half+CLEARANCE-at.Z>2 then
            lifted=tostring(teleport(pawn,{X=at.X,Y=at.Y,Z=placed.ground+half+CLEARANCE}))
            at=options.location(pawn)
        end
        local key=U.key(pawn)
        if key and half and at and math.abs(at.Z-half-placed.ground)<=MAX_RISE then
            anchors[key]={world=U.key(options.world()),x=at.X,y=at.Y,z=placed.ground}
        end
        say('place',string.format('%s 地面Z=%.1f 半高 出生前=%.1f 现在=%s 原高度=%.1f 目标=%.1f 抬高=%s 读回Z=%s%s',options.label(pawn),placed.ground,placed.half,
            tostring(half),placed.before,placed.wanted,lifted,at and string.format('%.1f',at.Z) or '?',placed.closer and string.format(' 出生点下面是落差，移近玩家到%.0f%%',placed.closer*100) or ''))
    end
    -- CurrentFloor can be one movement sample older than the capsule after a warp or a floor break.
    local function floorAtFeet(cmc,at,half)
        if not at or not half then return end
        local floor=U.field(cmc,'CurrentFloor')
        if U.struct(floor,'bWalkableFloor')~=true or U.struct(floor,'bBlockingHit')~=true then return end
        local hit=U.struct(floor,'HitResult')
        if U.struct(hit,'bStartPenetrating')==true then return end
        local point=U.struct(hit,'ImpactPoint')
        local x,y,z=U.struct(point,'X'),U.struct(point,'Y'),U.struct(point,'Z')
        if type(x)=='number' and type(y)=='number' and type(z)=='number' and math.abs(z-(at.Z-half))<=MAX_RISE
            and (x-at.X)^2+(y-at.Y)^2<=MAX_RISE^2 then return z end
    end
    function self:free(actor,target)
        if not U.valid(actor) then return false end
        self:keepFromFallDeath(actor)
        local mode,cmc=self:mode(actor)
        if mode==WALKING or mode==NAV_WALKING then
            local at=options.location(actor)
            local z=floorAtFeet(cmc,at,halfHeight(actor))
            if z then
                local key,world=U.key(actor),U.key(options.world())
                if key and world then anchors[key]={world=world,x=at.X,y=at.Y,z=z} end
            end
        end
        if mode~=FLYING and mode~=FALLING then return false end
        local blocked=self:blocked(actor)
        if mode==FLYING and (not blocked or blocked<=0) then return false end
        local here,half,world=options.location(actor),halfHeight(actor),options.world()
        if not here or not half or not U.valid(world) then return false end
        local feet=here.Z-half
        local ignored={actor};if U.valid(target) then ignored[2]=target end
        local ground=trace(world,here.X,here.Y,feet,10,ignored)
        -- Falling with ground in reach is an ordinary fall: it lands by itself.
        if mode==FALLING and ground and feet-ground<=MAX_DROP then return false end
        local dest,how
        if ground and feet-ground<=MAX_DROP then
            dest,how={X=here.X,Y=here.Y,Z=ground+half+CLEARANCE},'脚下地面'
        else
            local there=U.valid(target) and options.location(target) or nil
            if there then
                local dx,dy=here.X-there.X,here.Y-there.Y
                local length=math.sqrt(dx*dx+dy*dy)
                if length<1 then dx,dy,length=1,0,1 end
                local x,y=there.X+dx/length*BESIDE,there.Y+dy/length*BESIDE
                local beside=groundAt(world,x,y,there.Z,ignored)
                local theirHalf=halfHeight(target)
                if beside and theirHalf and math.abs(there.Z-theirHalf-beside)<=PLACE_MAX_DROP then
                    dest,how={X=x,Y=y,Z=beside+half+CLEARANCE},'对手身边'
                end
            end
        end
        if not dest then
            local anchor=anchors[U.key(actor)]
            if anchor and anchor.world==U.key(world) then
                local support=trace(world,anchor.x,anchor.y,anchor.z+MAX_RISE,0,ignored)
                if support and math.abs(support-anchor.z)<=MAX_RISE then
                    dest,how={X=anchor.x,Y=anchor.y,Z=support+half+CLEARANCE},'此前已确认的地面'
                end
            end
        end
        if not dest then return false end
        local moved=teleport(actor,dest)
        if not moved or not U.valid(actor) then return false end
        local reached=options.location(actor)
        if not reached or math.abs(reached.Z-dest.Z)>MAX_RISE or (reached.X-dest.X)^2+(reached.Y-dest.Y)^2>MAX_RISE^2 then return false end
        local walked=U.valid(actor) and U.valid(cmc) and pcall(function()cmc:SetMovementMode(WALKING,0)end)
        self.freed=self.freed+1
        local at=options.location(actor)
        say('free',string.format('%s %s：放到%s 从Z=%.1f 到Z=%.1f 传送=%s 改走路=%s；读回 模式=%s 封锁标签=%s Z=%s；累计=%d',mode==FLYING and '解除空中冻结' or '坠崖拉回',options.label(actor),how,here.Z,dest.Z,
            tostring(moved),tostring(walked),tostring((self:mode(actor))),tostring(self:blocked(actor)),at and string.format('%.1f',at.Z) or '?',self.freed))
        return true
    end
    -- A stand between moves (stand_keep.lua): on the ground, walking. Where it is if it may stay and the ground is in reach;
    -- otherwise beside its summoner, or on the summoner's own spot when beside it is a wall or a drop. Says what it did.
    function self:park(actor,owner,mayStay)
        if not U.valid(actor) or not U.valid(owner) then return {why='对象失效'} end
        self:keepFromFallDeath(actor)
        local here,there,half,world=options.location(actor),options.location(owner),halfHeight(actor),options.world()
        if not here or not there or not half or not U.valid(world) then return {why='读不到位置或胶囊'} end
        local x,y,ground,how
        if mayStay then
            local feet=here.Z-half
            local found=trace(world,here.X,here.Y,feet,10)
            if found and feet-found<=MAX_DROP then x,y,ground,how=here.X,here.Y,found,'脚下地面' end
        end
        if not ground then
            local dx,dy=here.X-there.X,here.Y-there.Y
            local length=math.sqrt(dx*dx+dy*dy)
            if length<1 then dx,dy,length=1,0,1 end
            local ownerFeet=there.Z-(halfHeight(owner) or half)
            x,y,how=there.X+dx/length*BESIDE,there.Y+dy/length*BESIDE,'召唤者身边'
            ground=groundAt(world,x,y,there.Z)
            if not ground or math.abs(ground-ownerFeet)>PARK_STEP then
                x,y,how=there.X,there.Y,'召唤者脚下'
                ground=groundAt(world,x,y,there.Z,{actor,owner})
                if not ground or math.abs(ground-ownerFeet)>PARK_STEP then
                    local ownerMode,cmc=self:mode(owner)
                    ground=(ownerMode==WALKING or ownerMode==NAV_WALKING) and floorAtFeet(cmc,there,halfHeight(owner))
                    if not ground then return {why='召唤者脚下尚无可确认的地面'} end
                end
            end
        end
        local dest={X=x,Y=y,Z=ground+half+CLEARANCE}
        local moved=teleport(actor,dest)
        local _,cmc=self:mode(actor)
        local walked=U.valid(cmc) and pcall(function()cmc:SetMovementMode(WALKING,0)end)
        return {moved=moved==true,walked=walked==true,how=how,dest=dest}
    end
    return self
end
return Ground
