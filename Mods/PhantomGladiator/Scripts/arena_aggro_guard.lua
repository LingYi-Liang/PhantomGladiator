-- BP_SGameAIComponent checks its instance StateBlockMap before entering Idle and
-- broadcasting OnStateChanged. AIScript_HatredManage clears HatredList on that event.
local U=require('ue_observe')
local Guard={}
local IDLE,COMBAT='AI.State.Idle','AI.State.Combat'
local JOURNAL='PhantomGladiator.arenaIdleGuard.v1'

local function tagName(t)
    local n=U.struct(t,'TagName')
    if type(n)=='string' then return n end
    local ok,s=pcall(function()return n:ToString()end)
    return ok and s or nil
end
local function same(a,b)
    local k=U.key(a)
    return k~=nil and k==U.key(b)
end
local function name(obj)
    if not U.valid(obj) then return end
    local ok,s=pcall(function()return obj:GetFullName()end)
    if ok and type(s)=='string' and not s:find('[\t\r\n]') then return s end
end
-- false means a confirmed absent key. nil means the map could not be inspected.
local function entry(map,key)
    -- The native map is tiny. Enumerating also distinguishes an absent entry from a
    -- bridge that cannot hash a Lua struct key for Contains/Find.
    local accessible,iterable=pcall(function()return type(map.ForEach)=='function' end)
    if not accessible then return end
    if iterable then
        local seen=false
        local readable=pcall(function()map:ForEach(function(k,v)
            local which=assert(tagName(U.unwrap(k)))
            if which==IDLE then seen=assert(tagName(U.unwrap(v))) end
        end)end)
        if readable then return seen end
        return
    end
    local ok,result=pcall(function()
        local found=map:Contains(key)
        if found==false then return false end
        if found==true then return tagName(U.unwrap(map:Find(key))) end
    end)
    if ok then return result end
end
function Guard.new(o)
    local self={retained=0,unverified=0}
    local records,retry={},{}
    local now=o.clock or os.clock
    local flags={}
    local idle,combat
    local function say(kind,msg)
        flags[kind]=(flags[kind] or 0)+1
        if flags[kind]<=8 and o.log then o.log('[ArenaAggro] '..msg) end
    end
    local function tags()
        if idle then return true end
        local f=o.fname or FName
        local i,c={TagName=f(IDLE)},{TagName=f(COMBAT)}
        if tagName(i)~=IDLE or tagName(c)~=COMBAT then return false end
        idle,combat=i,c
        return true
    end
    local function matches(r)
        return U.key(r.ai)==r.aiKey and name(r.ai)==r.aiName and U.key(r.actor)==r.key and name(r.actor)==r.actorName
    end
    local function release(r)
        if not U.valid(r.ai) then return true end
        local aiName=name(r.ai)
        if not aiName then return false end
        if U.key(r.ai)~=r.aiKey or aiName~=r.aiName then return true end
        if not tags() then return false end
        local map=U.field(r.ai,'StateBlockMap')
        local value=entry(map,idle)
        if value==nil then return false end
        if value==COMBAT then
            say('remove','即将解除本体的战斗保持 '..r.actorName)
            r.removing=true
            pcall(function()map:Remove(idle)end)
            if entry(map,idle)~=false then return false end
            say('removed','已读回待机限制移除 '..r.actorName)
        elseif value~=false or not r.removing then return true end
        -- A native idle request may have been blocked just before stop or the opponent's death.
        if matches(r) and same(o.aiOf(r.actor),r.ai) and same(U.field(r.ai,'Pawn'),r.actor) and U.field(r.ai,'bAIStarted')==true and
            tagName(U.field(r.ai,'CurrentStateTag'))==COMBAT and tagName(U.field(r.ai,'DesiredStateTag'))==IDLE then
            say('pending','交还尚未完成的原生待机请求 '..r.actorName)
            pcall(function()r.ai['Set Current State'](r.ai,idle)end)
            say('pendingRead','交还后原生状态='..tostring(tagName(U.field(r.ai,'CurrentStateTag'))))
            if not U.valid(r.ai) then return true end
            local current=tagName(U.field(r.ai,'CurrentStateTag'))
            local desired=tagName(U.field(r.ai,'DesiredStateTag'))
            return current~=nil and desired~=nil and (current~=COMBAT or desired~=IDLE)
        end
        return true
    end
    local function remove(r)
        if release(r) then records[r.key]=nil;return true end
        return false
    end
    local function attributed(ai,actor)
        return U.valid(ai) and same(U.field(ai,'Pawn'),actor) and
            same(U.field(ai,'AbilitySystemComponent'),U.field(actor,'AbilitySystemComponent'))
    end
    function self:arm(actor,target)
        local k=U.key(actor)
        if not k or not U.valid(target) or same(actor,target) then return end
        local ai=o.aiOf(actor)
        local old=records[k]
        if old then
            if old.verified and not old.removing and same(old.ai,ai) and U.field(ai,'bAIStarted')==true and
                tagName(U.field(ai,'CurrentStateTag'))==COMBAT then
                if now()<(old.checkAt or 0) then return end
                old.checkAt=now()+1
                if matches(old) and entry(U.field(ai,'StateBlockMap'),idle)==COMBAT then return end
            end
            if not remove(old) then return end
        end
        if (retry[k] or -1)>now() then return end
        retry[k]=now()+1
        if not attributed(ai,actor) or U.field(ai,'bAIStarted')~=true or o.protected(actor,true)~=false then return end
        if tagName(U.field(ai,'CurrentStateTag'))~=COMBAT or tagName(U.field(ai,'DesiredStateTag'))~=COMBAT then return end
        if not tags() or o.hates(actor,target)~=true then return end
        local asc=U.field(ai,'AbilitySystemComponent')
        local ok,n=pcall(function()return asc:GetGameplayTagCount(combat)end)
        if not ok or type(n)~='number' or n<=0 then return end
        local map=U.field(ai,'StateBlockMap')
        local methods,writable=pcall(function()return type(map.Add)=='function' and type(map.Remove)=='function' end)
        local previous=entry(map,idle)
        if not methods or not writable or previous==nil then
            say('unavailable','本体待机限制表无法验证，继续原有迎敌处理 '..tostring(name(actor)));return
        end
        if previous~=false then return end
        local r={key=k,actor=actor,ai=ai,aiKey=U.key(ai),aiName=name(ai),actorName=name(actor)}
        if not r.aiName or not r.actorName or not r.aiKey then return end
        records[k]=r -- A partially applied map write must still be recoverable.
        say('arm','即将保留擂台对手仇恨 '..r.actorName)
        pcall(function()map:Add(idle,combat)end)
        r.verified=entry(map,idle)==COMBAT
        say('armed','本体待机限制读回='..tostring(r.verified)..' '..r.actorName)
        if not r.verified then self.unverified=self.unverified+1;remove(r) end
    end
    function self:onDrop(actor,ai)
        local r=records[U.key(actor) or '']
        if not r or not r.verified or r.removing or not same(ai,r.ai) or not matches(r) then return false end
        local target=o.opponent(actor)
        if not U.valid(target) or o.protected(actor,true)~=false then remove(r);return false end
        if not attributed(ai,actor) or U.field(ai,'bAIStarted')~=true or
            tagName(U.field(ai,'CurrentStateTag'))~=COMBAT or tagName(U.field(ai,'DesiredStateTag'))~=IDLE then return false end
        local gate=entry(U.field(ai,'StateBlockMap'),idle)
        if gate==nil then return false end
        if gate~=COMBAT then records[r.key]=nil;return false end
        -- Set Current State writes DesiredStateTag *before* consulting StateBlockMap. Leave the
        -- native state machine ready for the next combat transition without reentering Combat.
        local kept=o.hates(actor,target)==true
        pcall(function()ai.DesiredStateTag=combat end)
        if tagName(U.field(ai,'DesiredStateTag'))~=COMBAT then
            self.unverified=self.unverified+1;remove(r);return false
        end
        if not kept or o.hates(actor,target)~=true then return false end
        self.retained=self.retained+1
        say('retained','脱战请求已拦住 原生状态=Combat 原对手仇恨=true '..r.actorName)
        return true
    end

    -- Only immutable identity strings cross a Lua reload. Recovery runs on the game thread.
    local shared=o.shared or ModRef
    local recovery={}
    local loaded,stored=pcall(function()return shared:GetSharedVariable(JOURNAL)end)
    if loaded and type(stored)=='string' then
        for line in stored:gmatch('[^\r\n]+')do
            local k,an,ak,ain=line:match('^(%d+)\t([^\t]+)\t(%d+)\t([^\t]+)$')
            if k then recovery[#recovery+1]={key=k,actorName=an,aiKey=ak,aiName=ain} end
        end
    end
    local function saveRecovery(includeLive)
        local rows={}
        local function add(r)rows[#rows+1]=table.concat({r.key,r.actorName,r.aiKey,r.aiName},'\t') end
        for _,r in ipairs(recovery)do add(r) end
        if includeLive then for _,r in pairs(records)do add(r) end end
        local data=table.concat(rows,'\n')
        local ok,verified=pcall(function()
            shared:SetSharedVariable(JOURNAL,data);return shared:GetSharedVariable(JOURNAL)==data
        end)
        if not ok or not verified then say('journal','热重载还原记录未读回') end
    end
    local recoveryAt=0
    local function recover()
        if #recovery==0 or now()<recoveryAt or (o.ready and not o.ready()) then return end
        recoveryAt=now()+1
        local pending={}
        local find=o.find or StaticFindObject
        for _,r in ipairs(recovery) do
            local ok,a=pcall(find,r.actorName:match('^%S+ (/.+)$'))
            local got,ai=pcall(find,r.aiName:match('^%S+ (/.+)$'))
            if ok and U.key(a)==r.key and name(a)==r.actorName and not U.valid(ai) then got,ai=pcall(o.aiOf,a) end
            if ok and got then r.actor,r.ai=a,ai end
            if not U.valid(ai) then r.misses=(r.misses or 0)+1 end
            if not ok or not got or (not U.valid(ai) and r.misses<=5) or not release(r) then pending[#pending+1]=r end
        end
        recovery=pending;saveRecovery(false)
    end
    function self:sync(members,active)
        recover()
        if not active then
            if next(records) then self:stop() end
            retry={};return
        end
        local seen={}
        for _,m in ipairs(members)do
            if (m.team=='red' or m.team=='blue') and not m.aid and not m.stand and not m.reserve then
                local actor=m.actor;local k=U.key(actor)
                local target=k and o.opponent(actor)
                if U.valid(target) and o.protected(actor)==false then
                    seen[k]=true;self:arm(actor,target)
                    local r=records[k]
                    if r and r.verified and tagName(U.field(r.ai,'DesiredStateTag'))==IDLE then self:onDrop(actor,r.ai) end
                end
            end
        end
        for k,r in pairs(records)do if not seen[k] then remove(r) end end
        for k in pairs(retry)do if not seen[k] then retry[k]=nil end end
    end
    function self:stop()
        local ok=true
        for _,r in pairs(records)do if not remove(r) then ok=false end end
        retry={};return ok
    end
    function self:silence(onGameThread)
        if onGameThread then self:stop() end
        if next(records) or #recovery>0 then saveRecovery(true) end
    end
    return self
end
return Guard
