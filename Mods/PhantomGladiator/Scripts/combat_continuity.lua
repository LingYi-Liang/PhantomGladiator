-- Preserve owned combat intent across temporary protection without cancelling native abilities.
local U=require('ue_observe')
local Continuity={}
local LIB='/Script/SGameAI.Default__SGameAIFunctionLibrary'
local BLOCKED={'CharacterState.Unselectable','AI.Hatred.CanNotBeHatred','AI.Hatred.IgnoreByNPC','CharacterState.Hitreact.State.Executing'}
local BUSY={'CharacterState.Hitreact.State.Executing','CharacterState.Unselectable.Force.Perform'}
local function call(obj,method,...)
    if not U.valid(obj)then return false end
    local args={...};local ok,v=pcall(function()return obj[method](obj,table.unpack(args))end)
    return ok,U.unwrap(v)
end
local function name(obj)
    local ok,v=call(obj,'GetFullName');return ok and type(v)=='string'and v or nil
end
local function tag(v)
    local n=U.struct(v,'TagName')
    if type(n)=='string'then return n end
    local ok,s=pcall(function()return n:ToString()end);return ok and type(s)=='string'and s or nil
end
function Continuity.new(options)
    local self={alive=true,waits=0,resumed=0,repaired=0,failed=0}
    local clock=options.clock or os.clock
    local owned,leases,samples={},{},{}
    local serial=0
    local messages,lines={},{}
    local function log(key,text)
        if messages[key]==text then return end
        messages[key]=text
        local kind=key:match('^[^:]+')or key
        if(lines[kind]or 0)<12 then lines[kind]=(lines[kind]or 0)+1;(options.log or function()end)('[CombatIntent] '..text)end
    end
    local function alive(actor)
        if not U.valid(actor)then return false end
        local ok,hp=pcall(options.hp,actor)
        return ok and type(hp)=='number'and hp==hp and hp>0 and hp<math.huge
    end
    local function worldActor(actor)
        local w=options.world();return U.valid(w)and U.inWorld(actor,w)and w or nil
    end
    local function source(actor)
        local key=U.key(actor);local row=key and owned[key]
        return row and row.name==name(actor)and alive(actor)and worldActor(actor)and key or nil
    end
    local function opponent(actor,target)
        local a,b=owned[U.key(actor)or''],owned[U.key(target)or'']
        return a and b and a.team~=b.team and b.name==name(target)and alive(target)and worldActor(target)
    end
    local function counts(actor,tags)
        local asc=U.field(actor,'AbilitySystemComponent')
        if not U.valid(asc)then return nil end
        local unknown=false
        for _,t in ipairs(tags)do
            local ok,n=call(asc,'GetGameplayTagCount',{TagName=FName(t)})
            if ok and type(n)=='number'then if n>0 then return true end else unknown=true end
        end
        if unknown then return nil end
        return false
    end
    local function state(ai)return tag(U.field(ai,'CurrentStateTag'))end
    local function idle(s)return s=='AI.State.Idle'or s=='AI.State.Search'or s and(s:find('^AI.State.Idle%.')or s:find('^AI.State.Search%.'))~=nil end
    function self:beginTick(members,active)
        samples={};local current={}
        for _,m in ipairs(members or{})do
            if(m.team=='blue'or m.team=='red')and not m.stand and not m.reserve and not m.aid then
                local key,n=U.key(m.actor),name(m.actor)
                if key and n then current[key]={actor=m.actor,name=n,team=m.team}end
            end
        end
        owned=active and current or{}
        for key,r in pairs(leases)do
            if r.owns and(not active or not source(r.actor)or not alive(r.target)or not worldActor(r.target))then self:restore(r)end
            if not owned[key]and not r.owns then leases[key]=nil end
        end
    end
    function self:protected(actor)
        if not U.valid(actor)then return nil end
        local key=U.key(actor);local known=key and samples[key]
        if known and known.name==name(actor)then return known.blocked end
        local value=counts(actor,BLOCKED)
        local hm=options.hatredOf and options.hatredOf(actor)
        if U.valid(hm)and U.field(hm,'CanBeHatredNow')==false then value=true end
        if options.phaseBusy then
            local ok,busy=pcall(options.phaseBusy,actor)
            if ok and busy==true then value=true elseif not ok then value=nil end
        end
        if key then samples[key]={name=name(actor),blocked=value}end
        return value
    end
    function self:actionBusy(actor)
        local blocked=counts(actor,BUSY)
        if blocked~=false then return true end
        local mesh=U.field(actor,'Mesh')
        local got,anim=call(mesh,'GetAnimInstance')
        if not got or not U.valid(anim)then return true end
        local ok,playing=call(anim,'IsAnyMontagePlaying')
        return not ok or playing~=false
    end
    local function brainOf(actor)
        local pc=U.field(actor,'Controller');local brain=U.field(pc,'BrainComponent')
        if U.key(U.field(pc,'Pawn'))~=U.key(actor)or U.key(U.field(brain,'AIOwner'))~=U.key(pc)then return nil end
        if not U.valid(pc)or not U.valid(brain)then return nil end
        return pc,brain
    end
    local function library()
        local ok,v=pcall(options.find or StaticFindObject,LIB);return ok and U.valid(v)and v or nil
    end
    function self:restore(r)
        if not r or not r.owns then return true end
        local w=options.world()
        if not U.valid(r.actor)or not U.valid(r.brain)or not U.valid(r.pc)then r.owns=false;return true end
        local actual=name(r.actor)
        if not U.valid(w)or not actual then return false end
        if actual~=r.name or U.key(w)~=r.world then r.owns=false;return true end
        local pc,brain=brainOf(r.actor)
        if not pc then return false end
        local brainName=name(brain)
        if not brainName then return false end
        if U.key(brain)~=r.brainKey or brainName~=r.brainName then r.owns=false;return true end
        if not U.inWorld(r.actor,w)then return false end
        local read,paused=call(brain,'IsPaused')
        if read and paused==false then r.owns=false;r.waitAt,r.restoreAt=nil,nil;return true end
        if not read or paused~=true or clock()<(r.restoreAt or 0)then return false end
        r.restoreAt=clock()+1
        local lib=library();local sent=call(lib,'ResumeLogic',brain,'PhantomGladiator combat wait ended')
        local checked,after=call(brain,'IsPaused')
        local good=checked and after==false
        if good then r.owns=false;r.waitAt,r.restoreAt=nil,nil;self.resumed=self.resumed+1 end
        log('resume:'..r.key,'恢复等待AI：源='..tostring(r.name)..'；调用='..tostring(sent)..'；IsPaused读回='..tostring(after))
        return good
    end
    function self:resume(actor)
        local r=leases[U.key(actor)or''];return self:restore(r)
    end
    function self:wait(actor,target)
        if not self.alive or not source(actor)or not opponent(actor,target)then return false end
        if self:protected(target)~=true then return false end
        local ordinary=options.ordinary and options.ordinary(actor)
        if ordinary~=true or self:actionBusy(actor)then return false end
        local ai=options.aiOf(actor);local s=state(ai)
        -- Combat actions keep running. Only a confirmed idle/search return path is held.
        if not idle(s)then return s and s:find('^AI.State.Combat')~=nil or false end
        local pc,brain=brainOf(actor);if not pc then return false end
        local key=U.key(actor);local r=leases[key]
        if r and(r.name~=name(actor)or r.brainKey~=U.key(brain)or r.brainName~=name(brain))then
            if not self:restore(r)then return false end;r=nil
        end
        local read,paused=call(brain,'IsPaused')
        if not read or type(paused)~='boolean'then return false end
        if paused and not(r and r.owns)then return false end
        if not paused then
            local known,running=call(brain,'IsRunning')
            if not known or running~=true then return false end
        end
        if not r then
            serial=serial+1
            r={actor=actor,key=key,name=name(actor),pc=pc,brain=brain,brainKey=U.key(brain),brainName=name(brain),world=U.key(options.world()),owns=false}
            leases[key]=r
            if options.track then
                local tracked=options.track('combat-wait:'..key..':'..r.brainKey..':'..tostring(r.brainName)..':'..serial,function()return self:restore(r),'战斗等待AI恢复' end)
                if tracked==false then leases[key]=nil;return false end
            end
        end
        r.target=target
        if clock()<(r.waitAt or 0)then return r.owns end
        r.waitAt=clock()+1
        if not paused then
            local lib=library();local sent=call(lib,'PauseLogic',brain,'PhantomGladiator temporary protected target')
            local checked,after=call(brain,'IsPaused')
            r.owns=checked and after==true
            log('wait:'..key,'保留原对手等待：源='..tostring(r.name)..'；调用='..tostring(sent)..'；IsPaused读回='..tostring(after))
            if not r.owns then self.failed=self.failed+1;return false end
            self.waits=self.waits+1
        end
        local stopped=call(pc,'StopMovement');local got,move=call(pc,'GetMoveStatus')
        log('path:'..key,'等待时停止返程：源='..tostring(r.name)..'；调用='..tostring(stopped)..'；MoveStatus读回='..tostring(move))
        return r.owns and got and move==0
    end
    function self:maintain(actor,target)
        if not self.alive or not source(actor)or not opponent(actor,target)or self:protected(target)~=false or self:protected(actor)~=false then return false end
        if not self:resume(actor)then return false end
        local ai=options.aiOf(actor);local s=state(ai)
        if not s then return false end
        local hm=options.hatredOf(actor)
        if not U.valid(hm)then return false end
        local read,has=pcall(options.hates,hm,target)
        if not read or type(has)~='boolean'then return false end
        local sent=false
        if not has then
            local ok,accepted=pcall(options.addHatred,actor,target);sent=ok and accepted==true
            local checked,after=pcall(options.hates,hm,target)
            has=checked and after==true
            log('hate:'..U.key(actor),'补回原对手仇恨：源='..tostring(name(actor))..'；调用='..tostring(sent)..'；成员读回='..tostring(has))
            if not has then return false end
            self.repaired=self.repaired+1
        end
        if options.holdTarget then options.holdTarget(actor,target,'战斗意图维护')end
        if idle(s)and not self:actionBusy(actor)then
            -- Fall recovery owns AI.DisableCombatAI; leave it to on_ground rather than repeatedly forcing it.
            if counts(actor,{'AI.DisableCombatAI'})~=false then return false end
            local _,brain=brainOf(actor);local checked,paused=call(brain,'IsPaused')
            if not checked or paused~=false then return false end
            local running,active=call(brain,'IsRunning')
            if not running or active~=true then return false end
            local ok,value=pcall(options.engage,actor,target)
            local after=state(options.aiOf(actor))
            log('engage:'..U.key(actor),'等待后继续迎敌：源='..tostring(name(actor))..'；调用='..tostring(ok and value==true)..'；状态读回='..tostring(after))
            return ok and value==true and after and after:find('^AI.State.Combat')~=nil or false
        end
        return true
    end
    function self:status()
        local n=0;for _,r in pairs(leases)do if r.owns then n=n+1 end end
        return {waits=self.waits,resumed=self.resumed,repaired=self.repaired,pending=n,failed=self.failed}
    end
    function self:silence()self.alive=false end
    return self
end
return Continuity
