-- A stand waits for its summoner's next move where the last one left it, and nothing moves it until then.
-- Its AIScript_GroundCheck keeps running after StopAI: more than 128 m from the camera the stand is set to Flying, and the
-- AI.DisableGroundCheck tag keeps the script from ever setting it back. Flying or falling takes CharacterState.Space.Ground
-- away (GA_SpaceState). 32 of 玉妖's 35 abilities require that tag and none of 铁鬼's, so she alone stops coming: her part of
-- a move does not start, with no model and no damage, while the summoner's own sound plays.
-- So a stand that is not in a move goes back on the ground when it is in the air, and beside its summoner when it is left far
-- behind, before the ground under it unloads. Not while the camera is out of the script's reach of the summoner: the script
-- would set it back within 0.1 s.
local U=require('ue_observe')
local Keep={}
local EVERY,FALL_SECONDS,RETRY_SECONDS=0.5,1,2
local FAR_CM,CAMERA_CM=6000,12000
local FALLING,FLYING=3,5
local LINES=60
local SPACE_GROUND='CharacterState.Space.Ground'
local MODES={[0]='无',[1]='走路',[2]='导航走路',[3]='下落',[4]='游泳',[5]='飞行',[6]='自定义'}
local function modeName(mode)return mode==nil and '?' or MODES[mode] or tostring(mode) end
local function apart(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2) end
local function meters(cm)return cm and string.format('%.1fm',cm/100) or '?' end

function Keep.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local ground=options.ground
    local self={parked=0}
    local records,nextAt,lines={},0,0
    local function say(text)
        if lines<LINES then lines=lines+1;log('[StandKeep] '..text) end
    end
    local function label(actor)
        return options.label and options.label(actor) or tostring(U.key(actor))
    end
    local function check(member,key,now)
        local actor,owner=member.actor,member.summoner
        local record=records[key]
        if not record then
            record={}
            records[key]=record
            ground:keepFromFallDeath(actor)
        end
        -- In a move, or the tags do not read: left alone.
        if ground:tagCount(actor,'Ability.Action')~=0 or ground:tagCount(actor,'CharacterType.Stand.Enable')~=0 then
            record.fallingAt=nil
            return
        end
        if not U.valid(owner) then return end
        local mode=ground:mode(actor)
        if mode==nil then return end
        if mode==FALLING then record.fallingAt=record.fallingAt or now else record.fallingAt=nil end
        local at,there=options.location(actor),options.location(owner)
        if not at or not there then return end
        local far=apart(at,there)
        local why
        if mode==FLYING then why='飞行'
        elseif mode==FALLING and now-record.fallingAt>=FALL_SECONDS then why='下落'
        elseif far>FAR_CM then why='离召唤者太远' end
        if not why then
            record.waiting=nil
            return
        end
        if record.triedAt and now-record.triedAt<RETRY_SECONDS then return end
        local camera=options.camera and options.camera()
        local view=camera and apart(camera,there) or nil
        if view and view>=CAMERA_CM then
            if not record.waiting then
                record.waiting=true
                say(string.format('%s %s，镜头离召唤者 %s，超过游戏让单位停在空中的距离，等镜头回来再放回地面',label(actor),why,meters(view)))
            end
            return
        end
        record.waiting=nil
        record.triedAt=now
        local before=ground:tagCount(actor,SPACE_GROUND)
        local done=ground:park(actor,owner,far<=FAR_CM)
        local mode2=ground:mode(actor)
        local after=options.location(actor)
        if done.moved and done.walked then self.parked=self.parked+1 end
        say(string.format('%s %s：模式=%s 在地面标签=%s 离召唤者=%s；放到%s 传送=%s 改走路=%s%s；读回 模式=%s 在地面标签=%s 离召唤者=%s；累计=%d',label(actor),why,modeName(mode),
            tostring(before),meters(far),tostring(done.how),tostring(done.moved),tostring(done.walked),done.why and (' 原因='..done.why) or '',modeName(mode2),
            tostring(ground:tagCount(actor,SPACE_GROUND)),meters(after and apart(after,there)),self.parked))
    end
    function self:tick()
        local now=clock()
        if now<nextAt then return end
        nextAt=now+EVERY
        local present={}
        for _,member in ipairs(options.members() or {})do
            if member.stand and U.valid(member.actor) then
                local key=U.key(member.actor)
                if key then
                    present[key]=true
                    check(member,key,now)
                end
            end
        end
        for key in pairs(records)do
            if not present[key] then records[key]=nil end
        end
    end
    return self
end
return Keep
