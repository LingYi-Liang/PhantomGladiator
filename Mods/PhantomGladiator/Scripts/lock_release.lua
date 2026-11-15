-- A fighting unit's lock (Targeting Component.LockTarget, an FComponentSocket: what its skills aim at and its grabs go
-- for) on a unit the arena sends nobody at (options.untargetable, boss_stages.lua: 冷荼 while the game marks her out of
-- reach, from her first round of summons until she fights herself) is moved to the unit's assigned opponent, or dropped
-- when it has none in reach. A lock on anyone else is the game's own and is left alone.
-- The game keeps a lock until a skill asks for a new one. A unit that locked her while she was the only enemy in sight
-- kept the lock after the arena sent it at her summons (its blackboard target changed, its lock did not), so its skills
-- and grabs kept going for her while she could not be hurt.
-- UTargetingComponent (SGameCombatSystem): SetLockTarget(FComponentSocket), StopLockTarget().
local U=require('ue_observe')
local Lock={}
local LINES=30

function Lock.new(options)
    local log=options.log or function()end
    local untargetable=options.untargetable or function()return false end
    local fname=options.fname or function(text)return FName(text)end
    local self={moved=0,stopped=0,failed=0}
    local lines=0
    local function name(object)
        if not U.valid(object) then return '无效对象' end
        local ok,value=pcall(function()return object:GetFName():ToString()end)
        return ok and type(value)=='string' and value or '?'
    end
    -- The actor a targeting component is locked on, with the lock and its component.
    local function lockOf(tc)
        local lock,read=U.field(tc,'LockTarget')
        if not read then return nil,nil,nil,false end
        local part,componentRead=U.struct(lock,'Component')
        if not componentRead then return nil,lock,nil,false end
        if not U.valid(part) then return nil,lock,nil,true end
        local ok,owner=pcall(function()return part:GetOwner()end)
        if ok then owner=U.unwrap(owner) else owner=nil end
        return U.valid(owner) and owner or nil,lock,part,ok and U.valid(owner)
    end
    local function failed(reason)
        self.failed=self.failed+1
        if lines<LINES then lines=lines+1;log('[LockRelease] 改锁未执行；读回='..reason) end
        return false
    end
    local function ownedPart(part,actor)
        if not U.valid(part) then return false end
        local ok,owner=pcall(function()return U.unwrap(part:GetOwner())end)
        local key=U.key(actor)
        return ok and key~=nil and U.key(owner)==key
    end
    -- actor: a fighting unit; target: its assigned opponent while in reach, else nil. True once its lock was moved
    -- or dropped and read back; false when there was nothing to do or it did not take.
    function self:release(actor,target)
        local tc=U.field(actor,'Targeting Component')
        if not U.valid(tc) then return false end
        local held,lock,part,read=lockOf(tc)
        if not read then return failed('当前锁定状态未知，保留原锁') end
        if not held then return false end
        local checked,blocked=pcall(untargetable,held)
        if not checked then return failed('目标阶段状态未知，保留原锁') end
        if blocked~=true then return false end
        local move=U.valid(target) and U.key(target)~=U.key(held)
        local called,callError
        if move then
            -- The same part of the new target as the lock had on the old one: its mesh, else its root, same socket.
            local onMesh=U.key(part)~=nil and U.key(part)==U.key(U.field(held,'Mesh'))
            local newPart=onMesh and U.field(target,'Mesh') or U.field(target,'RootComponent')
            local socket=U.struct(lock,'SocketName')
            if not ownedPart(newPart,target) then
                newPart=U.field(target,'RootComponent');socket=nil
            end
            if not ownedPart(newPart,target) then return failed('新目标组件无效或归属未确认，保留原锁') end
            if socket==nil then
                local okName,none=pcall(fname,'None')
                socket=okName and none or nil
            end
            if socket==nil or not U.valid(tc) or not U.valid(newPart) then return failed('新锁定参数未确认，保留原锁') end
            called,callError=pcall(function()tc:SetLockTarget({Component=newPart,SocketName=socket})end)
        else
            called,callError=pcall(function()tc:StopLockTarget()end)
        end
        local after,_,_,readAfter=lockOf(tc)
        local ok
        if move then ok=called and readAfter and after~=nil and U.key(after)==U.key(target)
        else ok=called and readAfter and after==nil end
        if not ok then self.failed=self.failed+1 elseif move then self.moved=self.moved+1 else self.stopped=self.stopped+1 end
        if lines<LINES then
            lines=lines+1
            log(string.format('[LockRelease] %s 锁着打不到的 %s：%s 调用=%s%s 读回锁定=%s %s；累计 改锁=%d 取消=%d 没生效=%d',
                name(actor),name(held),move and '改锁派给它的对手 '..name(target) or '没有能打的对手，取消锁定',tostring(called),
                called and '' or '('..tostring(callError)..')',after and name(after) or '无',ok and '生效' or '没生效',
                self.moved,self.stopped,self.failed))
        end
        return ok
    end
    function self:status()return {lock_moved=self.moved,lock_stopped=self.stopped,lock_failed=self.failed}end
    return self
end
return Lock
