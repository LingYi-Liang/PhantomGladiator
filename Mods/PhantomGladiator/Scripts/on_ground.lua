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
local CLEARANCE,PLACE_MAX_DROP,MAX_DROP,BESIDE=3,800,1500,300
local WALKING,FALLING,FLYING=1,3,5
local BLOCK='AI.DisableCombatAI'
local NO_FALL_DEATH=1e9
local CLOSER={0.75,0.5,0.25}
local CAPS={place=12,miss=6,free=30,depth=6}

function Ground.new(options)
    local log=options.log or function()end
    local self={freed=0,placed=0}
    local lines,guarded={},{}
    local function say(kind,text)
        lines[kind]=(lines[kind] or 0)+1
        if lines[kind]<=(CAPS[kind] or 10) then log('[OnGround] '..text) end
    end
    local function halfHeight(actor)
        local ok,half=pcall(function()return U.field(actor,'CapsuleComponent'):GetScaledCapsuleHalfHeight()end)
        return ok and type(half)=='number' and half>0 and half or nil
    end
    local function teleport(actor,dest)
        local okRot,rot=pcall(function()return actor:K2_GetActorRotation()end)
        local moved,result=pcall(function()return actor:K2_TeleportTo(dest,okRot and rot or {Pitch=0,Yaw=0,Roll=0})end)
        return moved and result
    end
    local function trace(world,x,y,z,up)
        local ok,ground=pcall(options.ground,world,x,y,z,up)
        return ok and type(ground)=='number' and ground or nil
    end
    -- From the spot's own height first (a roof over a low room is not its floor), then from over it (a spot inside a slope).
    local function groundAt(world,x,y,z)
        return trace(world,x,y,z,0) or trace(world,x,y,z)
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

    -- BP_NPC_Base's fall rule, once per unit: with DeadDepth out of reach no fall kills or costs health.
    function self:keepFromFallDeath(actor)
        local key=U.key(actor)
        if not key or guarded[key] then return end
        guarded[key]=true
        local before=U.field(actor,'DeadDepth')
        if type(before)~='number' then return end
        local written=pcall(function()actor.DeadDepth=NO_FALL_DEATH end)
        local after=U.field(actor,'DeadDepth')
        say('depth',string.format('%s 坠落致死深度 %.0f -> %s 写入=%s',options.label(actor),before,tostring(after),tostring(written)))
    end

    -- Before the unit starts: its spawn spot. t is the transform it will start with. Returns what settle needs.
    function self:place(pawn,t,world)
        local spot=t and t.Translation
        local half=halfHeight(pawn)
        if type(spot)~='table' or not half then return nil end
        self:keepFromFallDeath(pawn)
        local ground=groundAt(world,spot.X,spot.Y,spot.Z)
        local closer
        if not ground or spot.Z-ground>PLACE_MAX_DROP then
            local player=options.player and options.player()
            local at=player and options.location(player)
            for _,share in ipairs(at and CLOSER or {})do
                local x,y=at.X+(spot.X-at.X)*share,at.Y+(spot.Y-at.Y)*share
                local there=groundAt(world,x,y,spot.Z)
                if there and spot.Z-there<=PLACE_MAX_DROP then
                    spot.X,spot.Y,ground,closer=x,y,there,share
                    break
                end
            end
        end
        if not ground then say('miss','出生点下方没找到地面，高度不变 Z='..tostring(spot.Z));return nil end
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
        say('place',string.format('%s 地面Z=%.1f 半高 出生前=%.1f 现在=%s 原高度=%.1f 目标=%.1f 抬高=%s 读回Z=%s%s',options.label(pawn),placed.ground,placed.half,
            tostring(half),placed.before,placed.wanted,lifted,at and string.format('%.1f',at.Z) or '?',placed.closer and string.format(' 出生点下面是落差，移近玩家到%.0f%%',placed.closer*100) or ''))
    end
    function self:free(actor,target)
        if not U.valid(actor) then return false end
        self:keepFromFallDeath(actor)
        local mode,cmc=self:mode(actor)
        if mode~=FLYING and mode~=FALLING then return false end
        local blocked=self:blocked(actor)
        if mode==FLYING and (not blocked or blocked<=0) then return false end
        local here,half,world=options.location(actor),halfHeight(actor),options.world()
        if not here or not half or not U.valid(world) then return false end
        local feet=here.Z-half
        local ground=trace(world,here.X,here.Y,feet,10)
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
                local beside=groundAt(world,x,y,there.Z)
                dest,how={X=x,Y=y,Z=(beside or there.Z)+half+CLEARANCE},'对手身边'
            end
        end
        if not dest then return false end
        local moved=teleport(actor,dest)
        local walked=pcall(function()cmc:SetMovementMode(WALKING,0)end)
        self.freed=self.freed+1
        local at=options.location(actor)
        say('free',string.format('%s %s：放到%s 从Z=%.1f 到Z=%.1f 传送=%s 改走路=%s；读回 模式=%s 封锁标签=%s Z=%s；累计=%d',mode==FLYING and '解除空中冻结' or '坠崖拉回',options.label(actor),how,here.Z,dest.Z,
            tostring(moved),tostring(walked),tostring((self:mode(actor))),tostring(self:blocked(actor)),at and string.format('%.1f',at.Z) or '?',self.freed))
        return true
    end
    return self
end
return Ground
