-- Clear only AI target/focus references that still point at the protected player.
-- No ForceOffCombat, whole-list clearing or NPC-vs-NPC target replacement.
local U=require('ue_observe')
local Targets={}
local function same(a,b)local key=U.key(a);return key~=nil and key==U.key(b)end
function Targets.new(options)
    local self={bindings={},round=0};local log=options.log or function()end
    function self:refresh(force)
        self.round=self.round+1
        if not force and self.round~=1 and self.round%10~=0 then return end
        local bindings={};local ok,list=pcall(FindAllOf,'PBZ_TargetingHandler_AI_C')
        if ok then
            for _,handler in ipairs(U.array(list or {}) or {})do
                local bb=U.field(handler,'Blackboard');local key=U.key(bb)
                if key then bindings[key]=bindings[key] or {};bindings[key][#bindings[key]+1]=handler end
            end
        end
        self.bindings=bindings
    end
    function self:release(npc,player)
        if not U.valid(npc) or not U.valid(player) then return false end
        local ctrl=U.field(npc,'Controller');if not U.valid(ctrl) then return true end
        local ai=U.field(ctrl,'SGameAIComponent')
        local bb=U.field(ai,'BlackboardComponent') or U.field(ctrl,'Blackboard')
        local verified=true
        for _,handler in ipairs(self.bindings[U.key(bb)] or {})do
            if U.valid(handler) and U.valid(bb) and same(U.field(handler,'Blackboard'),bb) then
                for _,field in ipairs({'Target Key','LastSensedActorKey'})do
                    local key,read=U.field(handler,field)
                    if read and key~=nil then
                        local got,current=pcall(function()return bb:GetValueAsObject(key)end)
                        if got and same(current,player) then
                            local changed=pcall(function()
                                assert(U.valid(npc) and U.valid(player) and U.valid(bb))
                                bb:ClearValue(key)
                            end)
                            local after,actual=pcall(function()if U.valid(bb) then return bb:GetValueAsObject(key)end end)
                            local cleared=changed and after and not same(actual,player)
                            verified=verified and cleared
                            log('[SpectatorTarget] 仅清除玩家目标 npc='..tostring(U.key(npc))..' field='..field..' cleared='..tostring(cleared))
                        end
                    end
                end
            end
        end
        if U.valid(ctrl) then
            local read,focus=pcall(function()return ctrl:GetFocusActor()end)
            if read and same(focus,player) then
                local changed=pcall(function()if U.valid(ctrl) then ctrl:K2_ClearFocus()end end)
                local got,after=pcall(function()if U.valid(ctrl) then return ctrl:GetFocusActor()end end)
                local cleared=changed and got and not same(after,player)
                verified=verified and cleared
                log('[SpectatorTarget] 仅清除玩家Focus；cleared='..tostring(cleared))
            end
        end
        return verified
    end
    return self
end
return Targets
