-- Follow the montage the native execution ability actually selected (rider L/R and continuation branches).
-- Never choose the first exported variant. The primary mesh still owns native root motion and warping.
local U=require('ue_observe')
local Playback={}
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args,n={...},select('#',...)
    local ok,v=pcall(function()return object[method](object,table.unpack(args,1,n))end)
    if ok then return U.unwrap(v) end
    return nil
end
local function short(object)
    local n=call(object,'GetFName');local ok,s=pcall(function()return n:ToString()end)
    return ok and s or nil
end
function Playback.clipPosition(def,position)
    return math.max(def.clip_from or 0,math.min(def.clip_to,(def.clip_from or 0)+position*(def.rate or 1)))
end
function Playback.start(options)
    local self={alive=true,handle=nil,ready=false}
    local now=options.now
    local started=now()
    local folded={};for key,def in pairs(options.variants)do folded[key:lower()]=def end
    local selected,missingAt=nil,nil
    local loop=options.loop or LoopInGameThreadWithDelay
    local cancel=options.cancel or CancelDelayedAction
    local function stop()
        self.alive=false
        if self.handle then pcall(cancel,self.handle);self.handle=nil end
    end
    self.stop=stop
    local function ended(reason,failed)stop();options.onEnd(reason,failed)end
    function self:update()
        if not self.alive then return end
        if not U.valid(options.actor) then ended('执行方失效',true);return end
        local ability=options.ability()
        local montage=call(ability,'GetCurrentMontage')
        local anim=call(U.field(options.actor,'Mesh'),'GetAnimInstance')
        local key=short(montage)
        local def=key and (options.variants[key] or folded[key:lower()])
        local live=U.valid(montage) and call(anim,'Montage_IsActive',montage)
        if live==nil then live=U.valid(montage) and U.key(montage)==U.key(call(anim,'GetCurrentActiveMontage')) end
        local position=def and live==true and call(anim,'Montage_GetPosition',montage)
        if type(position)=='number' and position==position then
            missingAt=nil
            if key~=selected then
                local ok,why=options.onVariant(def,key,position)
                if not ok then ended('动态处决接管失败：'..tostring(why),true);return end
                selected=key;self.ready=true
            end
            local desired=Playback.clipPosition(def,position)
            local ok,why=options.onPosition(desired,position,def)
            if not ok then ended('动态动画位置未确认：'..tostring(why),true);return end
        else
            missingAt=missingAt or now()
            if not self.ready and now()-started>=2 then ended('未读到本技能支持的原生蒙太奇',true);return end
            if self.ready and now()-missingAt>=0.3 then ended('原生动态处决结束',false);return end
        end
        if now()-started>=120 then ended('动态处决超过有界等待时间',true) end
    end
    local ok,err=pcall(self.update,self)
    if not ok and self.alive then ended('动态处决初始化失败：'..tostring(err),true) end
    if self.alive then
        local registered,handle=pcall(loop,16,function()
            local ok,err=pcall(self.update,self)
            if not ok and self.alive then ended('动态处决读取失败：'..tostring(err),true) end
        end)
        if registered then self.handle=handle end
        if not self.handle then ended('动态处决更新未登记：'..tostring(handle),true) end
    end
    return self
end
return Playback
