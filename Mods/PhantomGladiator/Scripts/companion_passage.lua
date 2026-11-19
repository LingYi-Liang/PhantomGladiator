-- 玩家可以穿过随从: the app switch (set_companion_passage). On (the default), a companion's capsule ignores the
-- collision channel of the real player's capsule, so the player walks through companions instead of being blocked
-- in a narrow place; enemies collide with companions as before, and hits are unchanged (they are traced against the
-- body mesh's physics bodies, not the capsule). Off, as in the game. Saved in Runtime/companion-passage.tsv.
-- Only the companion's own capsule is written (and its mount's): its response to one channel, with the value it had
-- recorded first. The player's capsule is only read, for its object type. A companion that leaves the team, the
-- switch going off and the mod unloading on the game thread put the recorded response back and read it again.
-- The same call on a capsule (SetCollisionResponseToChannel) is what the free camera's hold uses on the player's.
local U=require('ue_observe')
local Passage={}
local HEADER='CompanionPassageV1'
local IGNORE=0            -- ECollisionResponse: Ignore 0, Overlap 1, Block 2
local LINES=24            -- apply / restore lines in a load
local function call(o,m,...)
    if not U.valid(o)then return false end
    local a,n={...},select('#',...);local ok,value=pcall(function()return o[m](o,table.unpack(a,1,n))end)
    return ok,U.unwrap(value)
end
local function nameOf(o)local ok,n=call(o,'GetFullName');return ok and type(n)=='string'and n or nil end
local function short(n)return n and(n:match('[%.:]([^%.:]+)$')or n)or'?'end
-- options: path, log, io, members() -> the arena's member list, player() -> the real player pawn,
-- mount(actor) -> the vehicle a companion rides, or nil.
function Passage.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local file=options.path..'/companion-passage.tsv'
    local self={on=true,alive=true,message=''}
    local records={}      -- capsule address -> {capsule, name, channel, old}
    local lines,noChannel=0,false
    local function say(text)if lines<LINES then lines=lines+1;log('[CompanionPassage] '..text)end end
    local function readFile()
        local f=fs.open(file,'r');if not f then return nil end
        local value=f:read('*a');f:close();return value
    end
    do
        local saved=readFile()
        if type(saved)=='string' and saved:sub(1,#HEADER+1)==HEADER..'\t' then self.on=saved:find('\ton=1',1,true)~=nil end
    end
    local function responseOf(capsule,channel)
        local ok,value=call(capsule,'GetCollisionResponseToChannel',channel)
        return ok and tonumber(value) or nil
    end
    -- Puts one capsule's recorded response back, when it is still the same actor's capsule and still ignores.
    local function restore(key,why)
        local r=records[key];records[key]=nil
        if not r or not U.valid(r.capsule)then return end
        local _,owner=call(r.capsule,'GetOwner')
        if nameOf(owner)~=r.name then return end
        if responseOf(r.capsule,r.channel)~=IGNORE then return end
        call(r.capsule,'SetCollisionResponseToChannel',r.channel,r.old)
        local after=responseOf(r.capsule,r.channel)
        say('还原 '..short(r.name)..' 对玩家通道'..r.channel..'的碰撞 '..IGNORE..'→'..tostring(after)..'（原值'..r.old..'） 原因='..why..' 已还原='..tostring(after==r.old))
    end
    local function restoreAll(why)
        for key in pairs(records)do restore(key,why)end
    end
    local function apply(actor,channel,wanted)
        local capsule=U.field(actor,'CapsuleComponent')
        local key,name=U.key(capsule),nameOf(actor)
        if not key or not name then return end
        local r=records[key]
        if r and (r.name~=name or r.channel~=channel)then records[key]=nil;r=nil end  -- the address belongs to another actor now
        wanted[key]=true
        local now=responseOf(capsule,channel)
        -- Already ignoring: ours from an earlier tick, or the game's own setting (then there is nothing to put back).
        if now==nil or now==IGNORE then return end
        if not r then r={capsule=capsule,name=name,channel=channel,old=now};records[key]=r end
        say('即将 让玩家穿过 '..short(name)..'：胶囊体对玩家通道'..channel..'的碰撞 '..now..'→'..IGNORE..'（SetCollisionResponseToChannel）')
        call(capsule,'SetCollisionResponseToChannel',channel,IGNORE)
        local after=responseOf(capsule,channel)
        say('让玩家穿过 读回 '..short(name)..' 通道'..channel..'='..tostring(after)..' verified='..tostring(after==IGNORE)..'；能否走过去以画面为准')
        if after~=IGNORE then records[key]=nil end
    end
    function self:set(value)
        if value~='ON' and value~='OFF' then return {ok=false,message='穿过随从开关只接受 ON 或 OFF',spawned_count=0} end
        local wanted=value=='ON'
        local text=HEADER..'\ton='..(wanted and '1' or '0')..'\n'
        local f=fs.open(file,'w')
        local wrote=f and f:write(text)
        local closed=f and f:close()
        local saved=f~=nil and wrote~=nil and wrote~=false and closed==true and readFile()==text
        if saved then
            self.on=wanted
            if not wanted then restoreAll('开关关闭')end
        end
        log('[CompanionPassage] 设置 开关='..value..' 保存读回='..tostring(saved)..' 当前='..tostring(self.on))
        return {ok=saved,spawned_count=0,message=saved and (wanted and '已开启：你可以直接穿过随从' or '已关闭：随从会像原版一样挡住你') or '穿过随从的设置没有保存'}
    end
    -- Support tick: every companion (and its mount) ignores the player's channel; whoever left gets its response back.
    function self:tick()
        if not self.alive then return end
        if not self.on then
            if next(records)then restoreAll('开关关闭')end
            return
        end
        local companions={}
        for _,member in ipairs(options.members() or {})do
            if member.team=='companion' and not member.reserve and U.valid(member.actor)then companions[#companions+1]=member.actor end
        end
        if #companions==0 then
            if next(records)then restoreAll('随从离队')end
            return
        end
        local player=options.player()
        local ok,channel=call(U.field(player,'CapsuleComponent'),'GetCollisionObjectType')
        channel=ok and tonumber(channel) or nil
        if not channel then
            if not noChannel then noChannel=true;say('读不到玩家胶囊体的碰撞通道，这一轮不改')end
            return
        end
        noChannel=false
        local wanted={}
        for _,actor in ipairs(companions)do
            apply(actor,channel,wanted)
            local mount=options.mount and options.mount(actor)
            if U.valid(mount)then apply(mount,channel,wanted)end
        end
        for key in pairs(records)do
            if not wanted[key]then restore(key,'随从离队')end
        end
    end
    function self:status()
        local count=0;for _ in pairs(records)do count=count+1 end
        return {on=self.on,applied=count}
    end
    -- Unloading: the recorded responses go back only on the game thread; otherwise nothing is written.
    function self:silence(onGameThread)
        if onGameThread==true and self.alive then restoreAll('Mod 卸载')end
        self.alive=false;records={}
    end
    return self
end
return Passage
