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
    local serial,epoch=0,0
    local tagNames,engageAfter={},{}
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
            if tagNames[t]==nil then tagNames[t]=FName(t)end
            local ok,n=call(asc,'GetGameplayTagCount',{TagName=tagNames[t]})
            if ok and type(n)=='number'then if n>0 then return true end else unknown=true end
        end
        if unknown then return nil end
        return false
    end
    local function state(ai)return tag(U.field(ai,'CurrentStateTag'))end
    local function idle(s)return s=='AI.State.Idle'or s=='AI.State.Search'or s and(s:find('^AI.State.Idle%.')or s:find('^AI.State.Search%.'))~=nil end
    function self:beginTick(members,active)
        epoch=epoch+1
        samples={};local current={}
        for _,m in ipairs(members or{})do
            if(m.team=='blue'or m.team=='red')and not m.stand and not m.reserve and not m.aid then
                local key,n=U.key(m.actor),name(m.actor)
                if key and n then current[key]={actor=m.actor,name=n,team=m.team}end
            end
        end
        owned=active and current or{}
        for key in pairs(engageAfter)do if not owned[key]then engageAfter[key]=nil end end
        for key,r in pairs(leases)do
            if r.owns and(not active or not source(r.actor)or not alive(r.target)or not worldActor(r.target)or self:actionBusy(r.actor))then self:restore(r)end
            if not owned[key]and not r.owns then leases[key]=nil end
        end
    end
    function self:protected(actor,fresh)
        if not U.valid(actor)then return nil end
        local key=U.key(actor);local known=key and samples[key]
        if not fresh and known and known.name==name(actor)then return known.blocked end
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
    local function operation(actor,target)
        local e=epoch
        local token=options.context and options.context()or nil
        if options.context and token==nil then return nil end
        if not self.alive or not source(actor)or not opponent(actor,target)then return nil end
        local pc,brain=brainOf(actor)
        if not pc then return nil end
        local c={epoch=e,token=token,actor=actor,target=target,name=name(actor),targetName=name(target),world=U.key(options.world()),
            pc=U.key(pc),pcName=name(pc),brain=U.key(brain),brainName=name(brain)}
        return epoch==e and c.name and c.targetName and c.pcName and c.brainName and c or nil
    end
    local function current(c,blocked,fresh)
        if not c or not self.alive or c.epoch~=epoch or options.context and options.context()~=c.token or not source(c.actor)or not opponent(c.actor,c.target)
            or name(c.actor)~=c.name or name(c.target)~=c.targetName or U.key(options.world())~=c.world then return false end
        local pc,brain=brainOf(c.actor)
        if not pc or U.key(pc)~=c.pc or name(pc)~=c.pcName or U.key(brain)~=c.brain or name(brain)~=c.brainName then return false end
        if self:protected(c.target,fresh)~=blocked or self:protected(c.actor,fresh)~=false then return false end
        return self.alive and c.epoch==epoch and(not options.context or options.context()==c.token)
    end
    function self:restore(r)
        if not r or not r.owns then return true end
        local w=options.world()
        if not U.valid(r.actor)or not U.valid(r.brain)or not U.valid(r.pc)then r.owns=false;return true end
        local actual=name(r.actor)
        if not U.valid(w)or not actual then return false end
        if actual~=r.name then r.owns=false;return true end
        if U.key(w)~=r.world and not U.inWorld(r.actor,w)then r.owns=false;return true end
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
    local function rollback(r)
        if r and not self:restore(r)then
            leases[r.key]=r
            if options.track then
                serial=serial+1
                options.track('combat-wait-rollback:'..r.key..':'..serial,function()return self:restore(r),'等待中止恢复' end)
            end
        end
        return false
    end
    function self:wait(actor,target)
        local c=operation(actor,target)
        if not current(c,true)then return false end
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
            if not current(c,true,true)or self:actionBusy(actor)then return false end
            -- Reserve rollback responsibility before a native call can reenter cleanup.
            r.owns=true
            local lib=library();local sent=call(lib,'PauseLogic',brain,'PhantomGladiator temporary protected target')
            local checked,after=call(brain,'IsPaused')
            r.owns=not checked or after~=false
            log('wait:'..key,'保留原对手等待：源='..tostring(r.name)..'；调用='..tostring(sent)..'；IsPaused读回='..tostring(after))
            if not checked or after~=true then
                self.failed=self.failed+1
                if r.owns then
                    leases[key]=r
                    if not current(c,true)then return rollback(r)end
                end
                return false
            end
            self.waits=self.waits+1
        end
        if not current(c,true,true)or self:actionBusy(actor)or not idle(state(options.aiOf(actor)))then return rollback(r)end
        local stopped=call(pc,'StopMovement');local got,move=call(pc,'GetMoveStatus')
        if not current(c,true)then return rollback(r)end
        log('path:'..key,'等待时停止返程：源='..tostring(r.name)..'；调用='..tostring(stopped)..'；MoveStatus读回='..tostring(move))
        return r.owns and got and move==0
    end
    function self:maintain(actor,target)
        local c=operation(actor,target)
        if not current(c,false)then return false end
        if not self:resume(actor)then return false end
        if not current(c,false)then return false end
        local ai=options.aiOf(actor);local s=state(ai)
        if not s then return false end
        local hm=options.hatredOf(actor)
        if not U.valid(hm)then return false end
        local read,has=pcall(options.hates,hm,target)
        if not read or type(has)~='boolean'then return false end
        local sent=false
        if not has then
            if not current(c,false,true)then return false end
            local ok,accepted=pcall(options.addHatred,actor,target);sent=ok and accepted==true
            if not current(c,false)then return false end
            local checked,after=pcall(options.hates,hm,target)
            has=checked and after==true
            log('hate:'..U.key(actor),'补回原对手仇恨：源='..tostring(name(actor))..'；调用='..tostring(sent)..'；成员读回='..tostring(has))
            if not has then return false end
            self.repaired=self.repaired+1
        end
        if options.holdTarget and(not options.deferTargetHold or idle(s))and not self:actionBusy(actor)then
            if not current(c,false,true)then return false end
            options.holdTarget(actor,target,'战斗意图维护')
        end
        if not current(c,false)then return false end
        s=state(options.aiOf(actor))
        if idle(s)and not self:actionBusy(actor)then
            -- Fall recovery owns AI.DisableCombatAI; leave it to on_ground rather than repeatedly forcing it.
            if counts(actor,{'AI.DisableCombatAI'})~=false then return false end
            local _,brain=brainOf(actor);local checked,paused=call(brain,'IsPaused')
            if not checked or paused~=false then return false end
            local running,active=call(brain,'IsRunning')
            if not running or active~=true then return false end
            if not current(c,false,true)or self:actionBusy(actor)then return false end
            local key=U.key(actor);local last=engageAfter[key]
            if last and last.name==c.name and last.brain==c.brain and last.target==U.key(target)and clock()<last.at then return false end
            engageAfter[key]={name=c.name,brain=c.brain,target=U.key(target),at=clock()+1}
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
    function self:silence()self.alive=false;epoch=epoch+1;owned={}end
    return self
end
return Continuity
