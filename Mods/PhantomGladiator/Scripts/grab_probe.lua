-- Read only: what a monster's grab did to the unit it hit. BP_BulletEvent_Grab.Trigger gives the target the grabbed side's
-- ability and does not look at the result: the grabber plays its success timeline (吞噬尸体的小雪 heals there) whether or not
-- the target went along. 铁杀 and 残钢 were reported not to be grabbed, and nothing offline tells why.
-- Each grab logs both sides at once and twice after: the target's executed-ability tags, its montage and how far it played.
local U=require('ue_observe')
local Retry=require('lookup_retry')
local Probe={}
Probe.path='/SGameExecution/Bullet/Events/BP_BulletEvent_Grab.BP_BulletEvent_Grab_C:Trigger'
local LINES=80
local CHECKS={0.4,1.5}

local function className(actor)
    if not U.valid(actor) then return '无效' end
    local ok,name=pcall(function()return actor:GetClass():GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end
local function short(object)
    if not U.valid(object) then return '无' end
    local ok,name=pcall(function()return object:GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end

function Probe.new(options)
    local clock=options.clock or os.clock
    local self={alive=true,grabs=0}
    local hook,lines,pending=nil,0,{}
    local function say(line)
        if lines>=LINES then return end
        lines=lines+1
        if options.log then options.log('[GrabProbe] '..line) end
    end
    local retry=Retry.new({clock=clock,log=say})
    local function tag(actor,name)
        local asc=U.field(actor,'AbilitySystemComponent')
        if not U.valid(asc) or FName==nil then return '?' end
        local ok,count=pcall(function()return asc:GetGameplayTagCount({TagName=FName(name)})end)
        count=ok and U.unwrap(count) or nil
        return type(count)=='number' and tostring(count) or '?'
    end
    local function montage(actor)
        local mesh=U.field(actor,'Mesh')
        if not U.valid(mesh) then return '无网格' end
        local got,anim=pcall(function()return mesh:GetAnimInstance()end)
        anim=got and U.unwrap(anim) or nil
        if not U.valid(anim) then return '无动画实例' end
        local ok,current=pcall(function()return anim:GetCurrentActiveMontage()end)
        current=ok and U.unwrap(current) or nil
        if not U.valid(current) then return '无' end
        local at,position=pcall(function()return anim:Montage_GetPosition(current)end)
        position=at and U.unwrap(position) or nil
        return short(current)..(type(position)=='number' and string.format('@%.2fs',position) or '')
    end
    local function metres(a,b)
        if not options.location or not U.valid(a) or not U.valid(b) then return '?' end
        local okA,pa=pcall(options.location,a);local okB,pb=pcall(options.location,b)
        if not okA or not okB or not pa or not pb then return '?' end
        return string.format('%.1fm',math.sqrt((pa.X-pb.X)^2+(pa.Y-pb.Y)^2+(pa.Z-pb.Z)^2)/100)
    end
    local function report(entry,label)
        local target,grabber=entry.target,entry.grabber
        say(string.format('%s 目标=%s 被抓标签=%s Executing=%s Dead=%s 蒙太奇=%s 施法方=%s 蒙太奇=%s 距离=%s',label,className(target),
            tag(target,'Ability.Executed'),tag(target,'CharacterState.HitReact.State.Executing'),tag(target,'CharacterState.Dead'),
            montage(target),className(grabber),montage(grabber),metres(target,grabber)))
    end
    -- After the function has run: the target's ability has been given and tried.
    local function onGrab(context,bullet,data)
        if not self.alive then return nil end
        local event=U.unwrap(context)
        local target=U.struct(data,'EventActor')
        target=U.unwrap(target)
        local source=U.unwrap(bullet)
        local grabber
        if U.valid(source) then
            local ok,owner=pcall(function()return source:GetOwnerAvatar()end)
            grabber=ok and U.unwrap(owner) or nil
        end
        if not U.valid(target) then say('命中事件读不到目标 事件='..short(event));return nil end
        if options.isPlayer and options.isPlayer(target) then return nil end
        self.grabs=self.grabs+1
        local entry={target=target,grabber=grabber,at=clock(),next=1}
        pending[#pending+1]=entry
        local timeline=U.field(event,'Success Timeline')
        local named,name=pcall(function()return timeline:ToString() end)
        say(string.format('第 %d 次 事件=%s 跳到时间轴=%s',self.grabs,short(event),named and tostring(name) or tostring(timeline)))
        report(entry,'命中后')
        return nil
    end
    local function install()
        if hook or type(RegisterHook)~='function' then return end
        local found=retry:find(Probe.path)
        if not U.valid(found) then return end
        local ok,pre,post=pcall(RegisterHook,Probe.path,onGrab,function()end)
        if ok and type(pre)=='number' and type(post)=='number' then
            hook={pre=pre,post=post}
            say('挂钩注册ID读回 pre='..pre..' post='..post)
        else say('挂钩注册失败：'..tostring(pre)) end
    end
    local function uninstall(why)
        if not hook then return end
        pcall(UnregisterHook,Probe.path,hook.pre,hook.post)
        hook=nil
        say('摘除挂钩（'..why..'） 累计抓取='..self.grabs)
    end
    function self:tick()
        if not self.alive then return end
        if next(options.members() or {}) then install() else uninstall('场上没有单位') end
        local t=clock()
        for i=#pending,1,-1 do
            local entry=pending[i]
            local wait=CHECKS[entry.next]
            if not wait then table.remove(pending,i)
            elseif t-entry.at>=wait then
                report(entry,string.format('+%.1fs',t-entry.at))
                entry.next=entry.next+1
            end
        end
    end
    function self:silence(why)uninstall(why or 'Mod卸载');self.alive=false;pending={} end
    return self
end
return Probe
