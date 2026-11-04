-- Read only: where a fighting unit went. Once a second each blue and red unit's position, movement mode, distance from
-- the camera, health, hidden flag, AI state and combat block are kept for its last few seconds. A change that can make a
-- unit vanish from view is logged when it happens (a big jump, a fall, hidden, frozen in the air, past the distances
-- AIScript_GroundCheck acts at), and when a unit with health left leaves the fight its last seconds are logged. Lines are
-- capped per class and kind, so a crowd of one class says what it does a few times and the rest of the fight stays heard.
local U=require('ue_observe')
local Watch={}
local SECONDS,KEEP,KIND_LINES,EXIT_LINES,TOTAL_LINES=1,15,6,3,400
local JUMP_CM,DROP_CM=2000,800
-- AIScript_GroundCheck: a falling unit over 60 m from the camera goes back to its initial location or is frozen, and any
-- unit over 128 m is frozen in the air.
local BANDS={{6000,'60米内'},{12800,'60~128米'},{math.huge,'128米外'}}
local MODES={[0]='无',[1]='走路',[2]='导航走路',[3]='下落',[4]='游泳',[5]='飞行',[6]='自定义'}

local function band(distance)
    if not distance then return nil end
    for _,entry in ipairs(BANDS)do if distance<entry[1] then return entry[2] end end
end
local function modeName(mode)return mode==nil and '?' or MODES[mode] or tostring(mode) end
local function className(actor)
    local ok,name=pcall(function()return actor:GetClass():GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end

function Watch.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local self={alive=true,exits=0,events=0}
    local tracks,nextAt,total,seenClasses,counted={},0,0,{},{}
    local function say(text)
        if total>=TOTAL_LINES then return end
        total=total+1
        log('[FightWatch] '..text)
    end
    local function format(s,now)
        return string.format('%.0fs前 位置=(%.0f,%.0f,%.0f) 模式=%s 距镜头=%s HP=%s 状态=%s 封锁=%s%s',now-s.t,s.x,s.y,s.z,modeName(s.mode),
            s.camera and string.format('%.0fm',s.camera/100) or '?',s.hp and string.format('%.0f',s.hp) or '?',tostring(s.state),tostring(s.blocked),s.hidden and ' 隐藏' or '')
    end
    -- Which ground-check script the class runs and its distances, once per class.
    local function readScripts(actor,name)
        if seenClasses[name] or not options.scripts then return end
        local ok,scripts=pcall(options.scripts,actor)
        if not ok or not scripts or #scripts==0 then return end
        seenClasses[name]=true
        local found={}
        for _,script in ipairs(scripts)do
            local cls=className(script)
            if cls:find('GroundCheck',1,true) then
                found[#found+1]=string.format('%s 强制飞行=%s 下落安全=%s 信任地面=%s 检测=%s',cls,tostring(U.field(script,'ForceFlyingDistance')),
                    tostring(U.field(script,'FallSafetyDistance')),tostring(U.field(script,'GroundRecoveryTrustDistance')),tostring(U.field(script,'GroundCheckDistance')))
            end
        end
        say(name..' 的 AI 脚本 '..#scripts..' 个；地面检测：'..(#found>0 and table.concat(found,'；') or '没有'))
    end
    local function sample(actor,now)
        local at=options.location(actor)
        if not at then return nil end
        local ok,read=pcall(options.read,actor)
        read=ok and read or {}
        local camera=options.camera and options.camera()
        local distance
        if camera then distance=math.sqrt((camera.X-at.X)^2+(camera.Y-at.Y)^2+(camera.Z-at.Z)^2) end
        local okHp,hp=pcall(options.hp,actor)
        return {t=now,x=at.X,y=at.Y,z=at.Z,camera=distance,hp=okHp and hp or nil,mode=read.mode,hidden=read.hidden==true,state=read.state,blocked=read.blocked}
    end
    local function event(track,kind,text)
        self.events=self.events+1
        local key=track.name..'|'..kind
        counted[key]=(counted[key] or 0)+1
        if counted[key]<=KIND_LINES then say(track.name..' '..text) end
    end
    local function compare(track,last,s)
        local moved=math.sqrt((s.x-last.x)^2+(s.y-last.y)^2+(s.z-last.z)^2)
        if moved>=JUMP_CM then event(track,'jump',string.format('一秒内移动 %.0fm：(%.0f,%.0f,%.0f) -> (%.0f,%.0f,%.0f) 模式=%s',moved/100,last.x,last.y,last.z,s.x,s.y,s.z,modeName(s.mode))) end
        if last.z-s.z>=DROP_CM then event(track,'drop',string.format('一秒内下降 %.0fm：Z=%.0f -> %.0f 模式=%s 距镜头=%s',(last.z-s.z)/100,last.z,s.z,modeName(s.mode),band(s.camera) or '?')) end
        if s.hidden~=last.hidden then event(track,'hidden',s.hidden and '被隐藏' or '取消隐藏') end
        if (s.blocked or 0)>0 and (last.blocked or 0)<=0 then event(track,'blocked',string.format('进战斗被封锁 AI.DisableCombatAI 模式=%s Z=%.0f 距镜头=%s',modeName(s.mode),s.z,band(s.camera) or '?')) end
        if band(s.camera)~=band(last.camera) and s.camera and last.camera then event(track,'band',string.format('距镜头 %s -> %s（%.0fm）',band(last.camera),band(s.camera),s.camera/100)) end
        if (last.hp or 0)>0 and s.hp==0 and last.hp>=0.2*track.top then event(track,'sudden',string.format('血量 %.0f -> 0（最高 %.0f）模式=%s Z=%.0f',last.hp,track.top,modeName(last.mode),s.z)) end
    end
    local function leave(key,track,now)
        tracks[key]=nil
        local last=track.samples[#track.samples]
        if not last or (last.hp or 0)<=0 then return end
        self.exits=self.exits+1
        local exitKey=track.name..'|exit'
        counted[exitKey]=(counted[exitKey] or 0)+1
        if counted[exitKey]>EXIT_LINES then return end
        say(track.name..' 还有血就退场（对象失效或被清理） team='..track.team)
        for i=math.max(1,#track.samples-7),#track.samples do say('  '..format(track.samples[i],now)) end
    end

    function self:tick()
        if not self.alive then return end
        local now=clock()
        if now<nextAt then return end
        nextAt=now+SECONDS
        local seen={}
        for _,member in ipairs(options.members() or {})do
            local actor=member.actor
            if (member.team=='blue' or member.team=='red') and U.valid(actor) then
                local key=U.key(actor)
                if key then
                    seen[key]=true
                    local track=tracks[key]
                    if not track then
                        track={name=className(actor),team=member.team,samples={},top=0}
                        tracks[key]=track
                        readScripts(actor,track.name)
                    end
                    local s=sample(actor,now)
                    if s then
                        local last=track.samples[#track.samples]
                        track.top=math.max(track.top,s.hp or 0,last and last.hp or 0)
                        if last then compare(track,last,s) end
                        track.samples[#track.samples+1]=s
                        if #track.samples>KEEP then table.remove(track.samples,1) end
                    end
                end
            end
        end
        for key,track in pairs(tracks)do
            if not seen[key] then leave(key,track,now) end
        end
    end
    function self:status()return {events=self.events,exits=self.exits} end
    function self:silence()self.alive=false end
    return self
end
return Watch
