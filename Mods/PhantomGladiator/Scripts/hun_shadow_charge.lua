-- These profiles follow the release paths of the granted ability, including inherited moves.
local U=require('ue_observe')
local M={}
local inputPath='/PBZInput/InputActions/IA_ShachiAbility_Hold.IA_ShachiAbility_Hold'
local componentClass='/Script/SGameInputSystem.SGameInputComponent'
local inputLibrary='/Script/SGameInputSystem.Default__SGameInputUtils'
local identity={Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
local state='CharacterState.AbilityState.'
local axe={kind='axe',tier=2,limit=4,tail=7,result={'Release3','Release2','Release1','SprintRelease2','SprintRelease1'}}
local sprintAxe={kind='axe',tier=1,limit=4,tail=7,result=axe.result}
local mace={kind='mace',limit=5,tail=6,result={'Release3'}}
local bow={kind='aim',ranged=true,window=state..'ShachiBow.Perfect',limit=4.5,tail=4,result={'ShootMax','Shoot'}}
local fist={kind='poll',window=state..'TieKuangQuanTao.Charge.PerfectTime',limit=2,tail=4,
    upgrade='CharacterState.WeaponUpgrade.TieKuangQuanTao.CanCharge',success=state..'TieKuangQuanTao.Charge.PeffectSuccess'}
local channel={kind='channel',limit=2,tail=3}
local profiles={
    GA_BrutalAxe_Normal=axe,GA_BrutalAxe_Sprint=sprintAxe,GA_JinGua_Normal=mace,
    GA_TigerCannon={kind='aim',ranged=true,window=state..'TigerCannon.Perfect',limit=3.8,tail=4,result={'LaunchPerfect','Launch'}},
    GA_UnnamedBow=bow,GA_YouLongCha_Normal=bow,
    GA_DuYan_Bow_Normal={kind='aim',ranged=true,window=bow.window,limit=4.5,tail=4,result={'Shoot'}},
    GA_TieKuangQuanTao_Charge_A=fist,GA_TieKuangQuanTao_Charge_AA=fist,GA_TieKuangQuanTao_Charge_AAA=fist,
    GA_Hun_HuoLiuXing_AAAA={kind='poll',window=state..'HuoLiuXing.CanJumpTimeline',limit=4,tail=5,result={'Final'}},
}
function M.profile(move)
    return profiles[move.cls:match('%.([%w_]+)_C$')] or (move.release and move.release:match('^OnRelease_') and channel or nil)
end
function M.opportunity(p,move,ctx)
    if not p or not ctx.target or ctx.busy or ctx.underThreat or (ctx.hpRatio or 1)<.25 then return false end
    local distance=ctx.distance
    if type(distance)~='number' or not (distance>=0 and distance<=3000) then return false end
    local opening=ctx.opening or ctx.targetBroken
    if p.ranged then return opening or distance>=550 end
    return distance<=math.min(move.radius,650) and (opening or distance>=300)
end
local function same(a,b)
    local key=U.key(a)
    return key~=nil and key==U.key(b)
end
local function number(v)return type(v)=='number' and v>=0 and v<math.huge end
local function mapValue(map,action)
    local ok,value=pcall(function()
        if map:Contains(action) then return U.unwrap(map:Find(action)) end
    end)
    return ok and value or nil
end
function M.new(o)
    local self={}
    local call,say=o.call,o.say
    local function owned(r,component)
        local _,owner=call(component,'GetOwner')
        return same(owner,r.actor)
    end
    local function controlledNPC(r)
        if not o.current(r) then return false end
        local ok,player=call(r.actor,'IsPlayerControlled')
        return ok and player==false
    end
    local function unbind(r,h)
        if h.attached and controlledNPC(r) and owned(r,h.component) and same(U.field(r.actor,'InputComponent'),h.component) then
            local inUse=false
            local map=U.field(h.component,'HoldingInputs')
            local read=pcall(function()map:ForEach(function()inUse=true end) end)
            if not read or inUse then return end
            say(r,'即将还原魂的临时输入组件')
            pcall(function()r.actor.InputComponent=nil end)
            local after,read=U.field(r.actor,'InputComponent')
            say(r,'输入组件还原读回='..tostring(read and not U.valid(after)))
        end
    end
    local function drop(r,h)
        if not h or h.stamp==nil or not controlledNPC(r) or not owned(r,h.component) then return false end
        local map=U.field(h.component,'HoldingInputs')
        local stamp=mapValue(map,h.action)
        if stamp~=h.stamp then
            if stamp~=nil then
                h.attached=false
                if same(r.shadowChargeInput,h.component) then r.shadowChargeInput=nil end
            end
            return false
        end
        say(r,'即将松开魂自身的影武输入')
        local ok=pcall(function()map:Remove(h.action) end)
        local read,held=call(h.component,'IsHolding',h.action)
        if ok and read and held==false then h.stamp=nil;return true end
        return false
    end
    function self:finish(r,h)
        if h then drop(r,h);unbind(r,h) end
    end
    function self:cleanup(r)
        local c=r.shadowChargeInput
        if controlledNPC(r) and owned(r,c) then
            unbind(r,{component=c,attached=true})
            if not same(U.field(r.actor,'InputComponent'),c) then
                say(r,'即将销毁魂的临时输入组件')
                call(c,'K2_DestroyComponent',c)
                local _,gone=call(c,'IsBeingDestroyed')
                say(r,'临时输入销毁读回='..tostring(not U.valid(c) or gone==true))
            end
        end
        r.shadowChargeInput=nil
    end
    function self:begin(r,asc)
        if not controlledNPC(r) then return end
        local action,lib=o.asset(inputPath),o.asset(inputLibrary)
        if not U.valid(action) or not U.valid(lib) then return end
        local orig,read=U.field(r.actor,'InputComponent')
        local ok,c=call(lib,'GetSGameInputComponent',r.actor)
        if not read or not ok then return end
        local h={action=action}
        if U.valid(orig) then
            if not same(orig,c) or not owned(r,c) or not same(U.field(c,'AbilitySystem'),asc) then return end
            h.attached=same(c,r.shadowChargeInput)
        else
            if U.valid(c) then return end
            c=r.shadowChargeInput
            if not owned(r,c) then
                local cls=o.asset(componentClass)
                if not U.valid(cls) then return end
                say(r,'即将为魂创建战斗输入组件')
                local added
                added,c=call(r.actor,'AddComponentByClass',cls,false,identity,false)
                if not added or not owned(r,c) then return end
                r.shadowChargeInput=c
            end
            h.component,h.attached=c,true
            local bound=U.field(c,'AbilitySystem')
            if U.valid(bound) and not same(bound,asc) then return end
            say(r,'即将绑定魂自身的战斗输入')
            pcall(function()c.AbilitySystem=asc;r.actor.InputComponent=c end)
            local _,selected=call(lib,'GetSGameInputComponent',r.actor)
            if not same(selected,c) or not same(U.field(c,'AbilitySystem'),asc) then unbind(r,h);return end
        end
        h.component=c
        local map=U.field(c,'HoldingInputs')
        local readHeld,held=call(c,'IsHolding',action)
        local mapRead,present=pcall(function()return map:Contains(action) end)
        if not mapRead or present~=false or not readHeld or held~=false then unbind(r,h);return end
        -- GetHoldTime subtracts the map entry from the input system's own clock.
        -- Calibrate on this new, exclusively owned key, without dispatching a player input.
        say(r,'即将按住魂自身的影武输入')
        h.stamp=0
        local wrote=pcall(function()map:Add(action,0) end)
        local readTime,start=call(c,'GetHoldTime',action)
        if wrote and readTime and number(start) and mapValue(map,action)==0 then
            -- The reflected map stores float32. Preserve its exact value for conditional removal.
            local stamp=string.unpack('f',string.pack('f',start))
            wrote=pcall(function()map:Add(action,stamp) end)
            if mapValue(map,action)==stamp then h.stamp=stamp end
            local _,holding=call(c,'IsHolding',action)
            local _,elapsed=call(c,'GetHoldTime',action)
            if wrote and h.stamp==stamp and holding==true and number(elapsed) and elapsed<.25 then
                say(r,'影武已按住 原生输入读回=true')
                return h
            end
        end
        self:finish(r,h)
    end
    local function feedback(p,cast,inst,hasTag)
        for _,name in ipairs(p.result or {}) do
            local timeline=U.field(inst,name)
            if U.valid(timeline) then
                local _,playing=call(inst,'IsPlayingTimeline',timeline)
                if playing==true then return name end
            end
        end
        if p.success and cast.released and not cast.priorSuccess and hasTag(p.success) then return '精准成功标签' end
    end
    local function waiting(inst,h)
        for _,task in ipairs(U.array(U.field(inst,'ActiveTasks')) or {}) do
            if U.className(task)=='AbilityTask_WaitSInputRelease' and same(U.field(task,'Ability'),inst) and same(U.field(task,'Input'),h.action)
                and same(U.field(task,'InputComponent'),h.component) then return true end
        end
        return false
    end
    function self:tap(r,cast,inst,now)
        if cast.released or now-cast.started<.12 or not controlledNPC(r) then return end
        local receiver=cast.move.release
        if not receiver or not receiver:match('^OnRelease_') then return end
        local action=o.asset(inputPath)
        for _,task in ipairs(U.array(U.field(inst,'ActiveTasks')) or {}) do
            if U.className(task)=='AbilityTask_WaitSInputRelease' and same(U.field(task,'Ability'),inst) and same(U.field(task,'Input'),action) then
                local c=U.field(task,'InputComponent')
                local actorInput=U.field(r.actor,'InputComponent')
                local _,held=call(c,'IsHolding',action)
                if (not U.valid(c) and not U.valid(actorInput)) or (owned(r,c) and same(c,actorInput) and held==false) then
                    cast.released=true
                    say(r,'即将结束魂的影武点按 '..cast.choice.meta.label)
                    local ok=call(inst,receiver,now-cast.started)
                    say(r,'影武点按回调='..tostring(ok))
                    return
                end
            end
        end
    end
    local function whenReady(p,inst,hasTag)
        if p.window and hasTag(p.window) then return '原生窗口' end
        if p.kind=='axe' then
            local level=U.field(inst,'Current Charge')
            if number(level) and level>=p.tier then return '斧蓄力段 '..level end
        elseif p.kind=='mace' and hasTag(state..'JinGua.CanRelease') and hasTag(state..'JinGua.Charge3') then
            return '金瓜三段'
        end
    end
    local function directRelease(p,inst,hasTag)
        local _,charging=call(inst,'Is Charging')
        local allowed=U.field(inst,'Min Duration Reached')==true
        if p.kind=='mace' then allowed=hasTag(state..'JinGua.CanRelease') end
        if charging==true and allowed then return call(inst,'To Release') end
    end
    function self:observe(r,cast,inst,ctx,now,hasTag)
        local h,p=cast.hold,cast.profile
        if not h or not p or cast.confirmed or not owned(r,h.component) then return end
        local result=feedback(p,cast,inst,hasTag)
        if result then
            self:finish(r,h)
            cast.confirmed=true;cast.released=true
            say(r,'影武释放结果读回 '..cast.choice.meta.label..' '..result)
            return
        end
        if cast.released then
            if cast.awaitWindow and directRelease(p,inst,hasTag) then
                cast.awaitWindow=false;say(r,'影武已在可释放窗口补发松手 '..cast.choice.meta.label)
            end
            return
        end
        if not same(U.field(r.actor,'InputComponent'),h.component) or mapValue(U.field(h.component,'HoldingInputs'),h.action)~=h.stamp then
            self:finish(r,h);cast.released=true
            say(r,'影武输入归属发生变化，停止驱动本次蓄力')
            return
        end
        local reason
        if ctx.busy or ctx.underThreat or (ctx.hpRatio or 1)<.25 then reason='受压'
        elseif not M.opportunity(p,cast.move,ctx) or (cast.opening and not (ctx.targetBroken or ctx.opening)) then reason='机会结束'
        else reason=whenReady(p,inst,hasTag) end
        if not reason and now-cast.started>=p.limit then reason='达到最长等待' end
        if not reason then return end
        local receiver=cast.move.release
        local task=p.kind=='aim' or p.kind=='channel'
        -- A delegate on a different task, action or component cannot release this cast.
        if task and not waiting(inst,h) then return end
        local _,heldTime=call(h.component,'GetHoldTime',h.action)
        if not drop(r,h) then return end
        cast.released=true
        local sent
        if task then sent=call(inst,receiver,number(heldTime) and heldTime or now-cast.started)
        elseif p.kind=='axe' or p.kind=='mace' then
            sent=directRelease(p,inst,hasTag)
            cast.awaitWindow=sent==nil
        end
        say(r,'影武松手 '..cast.choice.meta.label..' '..reason..' 输入读回=false 回调='..tostring(sent))
        local after=feedback(p,cast,inst,hasTag)
        if after then cast.confirmed=true;say(r,'影武释放结果读回 '..cast.choice.meta.label..' '..after) end
    end
    return self
end
return M
