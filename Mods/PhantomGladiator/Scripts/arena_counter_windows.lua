-- Arena-only handoffs for player-input branches. Health never creates a counter window.
local U=require('ue_observe')
local BASE='/PBZCombatAsset/ActorData/'
local function asset(dir,n)return BASE..dir..n..'.'..n..'_C' end
local C={
    BLADE=asset('Mobs/008_GreatBladeMan/','BP_Monster_GreatBladeMan'),
    JADE=asset('Mobs/YuDing_00/','BP_Monster_FemaleVessel_YuDing'),
    BLADE_GRAB=asset('Mobs/008_GreatBladeMan/Ability/Abilities/','GA_GreatBladeMan_CA_01_Gex'),
    JADE_GRAB_BASE=asset('Mobs/YuDing_00/Ability/Abilities/Grab/','GA_YuDing_GEx_01'),
    JADE_GRAB=asset('Mobs/YuDing_00/Ability/Abilities/Grab/','GA_YuDing_GEx_01_Execution'),
    JADE_COUNTER=asset('Players/Hun/Abilities/Common/ExE/YuDing/','GA_Hun_BDEx_Common_YuDing_M_01'),
    JADE_EXECUTED=asset('Players/Hun/Abilities/Common/ExE/YuDing/','GA_Hun_BDEd_Common_YuDing_M_01'),
    JUDGE='CharacterState.AbilityState.PengMeng.FinalExecutionJudge',READY='Deflect.ReadyForDodge.CanDodge',
}
local function call(obj,method,...)
    if not U.valid(obj) then return nil end
    local args=table.pack(...)
    local ok,v=pcall(function()return obj[method](obj,table.unpack(args,1,args.n))end)
    if ok then return U.unwrap(v) end
end
local function weak(v)
    v=U.unwrap(v)
    if U.key(v) then return v end
    local ok,obj=pcall(function()return v:Get()end)
    return ok and U.valid(obj) and obj or nil
end
local function same(a,b)
    local key=U.key(a)
    return key~=nil and key==U.key(b)
end
local function nameOfTag(v)
    local n=U.struct(v,'TagName')
    if type(n)=='string' then return n end
    local ok,value=pcall(function()return n:ToString()end)
    return ok and value
end
local function exactClass(cls,path)
    local full=call(cls,'GetFullName')
    return type(full)=='string' and full:match('^%S+ (/.+)$')==path
end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<1e12 end
function C.new(o)
    local self={blade=false,jade=false}
    local members,usedBlade,usedDodge,watch={},{},{},{}
    local timer,generation,world=nil,0,nil
    local lines=0
    local function log(text)
        if lines<48 then lines=lines+1;o.log('[ArenaCounter] '..text) end
    end
    local function count(actor,t)
        return call(U.field(actor,'AbilitySystemComponent'),'GetGameplayTagCount',{TagName=o.fname(t)})
    end
    local function stopTimer()
        generation=generation+1
        if timer then pcall(o.cancel or CancelDelayedAction,timer);timer=nil end
    end
    function self:clear()
        stopTimer();members,usedBlade,usedDodge,watch={},{},{},{}
        self.blade,self.jade=false,false
    end
    function self:sync(list,fighting,foes)
        local function managed(m)
            if m.reserve or m.stand or m.aid then return false end
            return fighting and (m.team=='red' or m.team=='blue') or foes and m.team=='companion'
        end
        local blade,jade=false,false
        for _,m in ipairs(list)do
            if managed(m) then
                if m.class_path==C.BLADE then blade=true elseif m.class_path==C.JADE and m.team~='companion' then jade=true end
            end
        end
        local mapBlades={}
        for _,foe in ipairs(foes or {})do
            if U.className(foe.actor)=='BP_Monster_GreatBladeMan_C' and exactClass(call(foe.actor,'GetClass'),C.BLADE) then
                mapBlades[foe.key]=true;blade=true
            end
        end
        if not blade and not jade then if self.blade or self.jade then self:clear() end;return end
        local w=U.key(o.world())
        if w~=world then self:clear();world=w end
        if not w then return end
        self.blade,self.jade=blade,jade
        local present={}
        for _,m in ipairs(list)do
            if managed(m) then
                local key=U.key(m.actor);if key then present[key]=m end
            end
        end
        for _,foe in ipairs(foes or {})do
            if not present[foe.key] then present[foe.key]={actor=foe.actor,team='companion-foe',class_path=mapBlades[foe.key] and C.BLADE} end
        end
        members=present
        for k in pairs(usedBlade)do if not present[k] then usedBlade[k]=nil end end
        for k in pairs(usedDodge)do if not present[k] then usedDodge[k]=nil end end
        if not jade then watch={};if timer then stopTimer() end end
    end
    local function pair(npc,boss,path)
        local a,b=members[U.key(npc)],members[U.key(boss)]
        if not a or not b or b.class_path~=path or a.team==b.team then return false end
        if a.team=='companion' or b.team=='companion' then
            if path~=C.BLADE then return false end
            local companion=a.team=='companion' and a or b
            local enemy=a.team=='companion' and b or a
            if enemy.team~='companion-foe' or not U.npcPath(enemy.actor) then return false end
            local hatred=U.array(U.field(U.field(companion.actor,'BP_PBZHatredManagerComponent'),'HatredList'))
            local engaged=false
            for _,target in ipairs(hatred or {})do if same(target,enemy.actor) then engaged=true;break end end
            if not engaged then return false end
        elseif not ((a.team=='red' and b.team=='blue') or (a.team=='blue' and b.team=='red')) then return false end
        local current=o.world();local player=o.player()
        if not U.valid(player) or same(player,npc) or same(player,boss) or call(npc,'IsPlayerControlled')==true
            or call(boss,'IsPlayerControlled')==true or U.key(current)~=world
            or not U.inWorld(npc,current) or not U.inWorld(boss,current) then return false end
        local ah,bh=o.hp(npc),o.hp(boss)
        return finite(ah) and ah>0 and finite(bh) and bh>0
    end
    local function inRange(actor,boss)
        local a,b=o.location(actor),o.location(boss)
        if not a or not b or not finite(a.X) or not finite(a.Y) or not finite(a.Z)
            or not finite(b.X) or not finite(b.Y) or not finite(b.Z) then return end
        local d=(a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2
        return finite(d) and d<=600^2 and d or nil
    end
    local function canAct(actor)
        local state=U.field(actor,'Actor State Component')
        return same(call(state,'GetOwner'),actor) and call(state,'CanActivateNewState',{TagName=o.fname('CharacterState.Action')})==true
    end
    function self:bladeTick(ability)
        if not self.blade or U.field(ability,'bIsActive')~=true then return end
        local boss=call(ability,'GetAvatarActorFromActorInfo')
        local k=U.key(boss);local m=members[k]
        if not m or m.class_path~=C.BLADE then return end
        local judge=count(boss,C.JUDGE)
        if judge==0 then usedBlade[k]=nil end
        if not finite(judge) or judge<=0 then return end
        if not exactClass(call(ability,'GetClass'),C.BLADE_GRAB) then return end
        local task=call(ability,'GetPlayTimelineTask');local taskKey=U.key(task)
        local time=U.field(task,'CurrentTime')
        if not taskKey or usedBlade[k]==taskKey or not finite(time) or time<0 then return end
        local info=U.field(ability,'Execution Info')
        local executor=weak(U.struct(info,'Executor'))
        if executor and not same(executor,boss) then return end
        local victim=weak(U.struct(info,'Target'))
        if not victim then victim=call(U.struct(U.field(ability,'Lock Target'),'Component'),'GetOwner') end
        if not pair(victim,boss,C.BLADE) then return end
        local current=U.field(U.field(boss,'Execution Component'),'CurrentExecutionInfo')
        if same(weak(U.struct(current,'Executor')),o.player()) and (count(boss,'Ability.Executed') or 0)>0 then return end
        local best,dist
        for _,foe in pairs(members)do
            local actor=foe.actor
            if foe.team~=m.team and (same(actor,victim) or same(o.assigned(actor),boss)) then
                local d=inRange(actor,boss)
                if d and (not best or d<dist or same(actor,victim)) and pair(actor,boss,C.BLADE) and o.eligible(actor,boss,'blade') then
                    if canAct(actor) then
                        best,dist=actor,d
                        if same(actor,victim) then break end
                    end
                end
            end
        end
        if not best or not pair(best,boss,C.BLADE) or not inRange(best,boss) or not canAct(best) or not o.eligible(best,boss,'blade') or U.field(ability,'bIsActive')~=true
            or not same(task,call(ability,'GetPlayTimelineTask')) or (count(boss,C.JUDGE) or 0)<=0 then return end
        time=U.field(task,'CurrentTime')
        if not finite(time) or time<0 then return end
        usedBlade[k]=taskKey
        local ok=o.bladeCounter(best,boss,time)
        log(string.format('毕峰原生终结判定 距离=%.0f 时间轴=%.3f NPC=%s 启动读回=%s',math.sqrt(dist),time,U.key(best),tostring(ok)))
    end
    function self:jadeResult(actor,boss,cast)
        if not self.jade or not U.valid(actor) then return end
        local dc=U.field(actor,'Deflect Component')
        local result=U.field(dc,'PerfectDodgeResultData')
        if not same(weak(U.struct(result,'DefenderAvatar')),actor) or not same(weak(U.struct(result,'SourceAvatar')),boss)
            or nameOfTag(U.struct(result,'DeflectResult'))~='Deflect.Result.Perfect' then return end
        local hit,now=U.struct(result,'HitGameTime'),o.now()
        local key=U.key(actor);local last=usedDodge[key]
        if not finite(hit) or not finite(now) or hit<=0 or hit>now or now-hit>0.35 or cast and hit<cast.start then return end
        local class=U.struct(result,'CounterAbility');local action=weak(U.struct(result,'SourceAction'))
        local sourceAbility=call(action,'GetAbility')
        if cast and not same(sourceAbility,cast.ability) then return end
        if last and last.hit==hit and last.boss==U.key(boss) and last.action==U.key(action) then return end
        if not exactClass(class,C.JADE_COUNTER) or not same(call(action,'GetAvatarActor'),boss)
            or not same(U.field(action,'CounterAbility'),class) or U.field(action,'DeflectBulletType')~=3
            or not exactClass(call(sourceAbility,'GetClass'),C.JADE_GRAB)
            or not same(call(dc,'GetOwner'),actor) or not pair(actor,boss,C.JADE) or not o.eligible(actor,boss,'jade')
            or (count(actor,C.READY) or 0)<=0 or count(actor,'CharacterState.Stand.Break')~=0 then return end
        local asc=U.field(actor,'AbilitySystemComponent')
        if not same(asc,U.field(U.field(actor,'Ability Input Component'),'AbilitySystem')) then return end
        local specs=U.array(U.struct(U.field(asc,'ActivatableAbilities'),'Items'))
        if not specs then return end
        local handle
        for _,row in ipairs(specs)do
            if same(call(U.struct(row,'Ability'),'GetClass'),class) then
                if handle or U.struct(row,'ActiveCount')~=0 then return end
                handle=U.struct(U.struct(row,'Handle'),'Handle')
                if not finite(handle) or handle<=0 then return end
            end
        end
        usedDodge[key]={hit=hit,boss=U.key(boss),action=U.key(action)}
        local accepted=false
        if handle then accepted=call(asc,'TryActivateAbility',{Handle=handle},false)==true
        else
            -- Temporary grant. The ASC must still pass the counter's native CanActivateAbility.
            local granted=call(asc,'K2_GiveAbilityAndActivateOnce',class,1,-1)
            local id=U.struct(granted,'Handle');accepted=finite(id) and id>0
        end
        log('玉鼎原生精准闪避 来源='..U.key(boss)..' NPC='..key..' HitGameTime='..hit..' 专用反制请求='..tostring(accepted))
    end
    -- This branch plays a victim ability directly instead of calling PlayExactExecution.
    -- Observe both native abilities and their recorded participants before borrowing a pose.
    function self:jadePair(ability)
        if not self.jade or U.field(ability,'bIsActive')~=true then return end
        local ex=call(ability,'GetClass')
        if not exactClass(ex,C.JADE_COUNTER) then return end
        local actor=call(ability,'GetAvatarActorFromActorInfo')
        local info=U.field(ability,'Execution Info')
        local boss=weak(U.struct(info,'Target'))
        if not same(weak(U.struct(info,'Executor')),actor) or not pair(actor,boss,C.JADE) then return end
        local frame=U.field(ability,'Current Frame')
        if not same(weak(U.struct(frame,'DefenderAvatar')),actor) or not same(weak(U.struct(frame,'SourceAvatar')),boss)
            or not same(U.struct(frame,'CounterAbility'),ex) or nameOfTag(U.struct(frame,'DeflectResult'))~='Deflect.Result.Perfect' then return end
        local victim=U.field(ability,'TargetExecutedAbilitySpec')
        local ed=call(victim,'GetClass')
        if not exactClass(ed,C.JADE_EXECUTED) or U.field(victim,'bIsActive')~=true or not same(call(victim,'GetAvatarActorFromActorInfo'),boss) then return end
        local received=U.field(victim,'Execution Info')
        if not same(weak(U.struct(received,'Executor')),actor) or not same(weak(U.struct(received,'Target')),boss) then return end
        return {executor=actor,target=boss,execution=ex,executed=ed,source='玉鼎精准闪避双方技能读回',start=0}
    end
    local function sample()
        local now=o.now()
        for key,r in pairs(watch)do
            if not finite(now) or now<r.start or now-r.start>16 or not members[key] or not U.valid(r.ability) then watch[key]=nil
            else
                self:jadeResult(r.target,r.source,r)
                if U.field(r.ability,'bIsActive')~=true then watch[key]=nil end
            end
        end
        if not next(watch) then stopTimer() end
    end
    function self:jadeCast(ability)
        if not self.jade or not exactClass(call(ability,'GetClass'),C.JADE_GRAB) then return end
        local source=call(ability,'GetAvatarActorFromActorInfo')
        local target=call(U.struct(U.field(ability,'Lock Target'),'Component'),'GetOwner')
        if not U.valid(target) and U.valid(source) then target=o.assigned(source) end
        local now=o.now()
        if not finite(now) or not pair(target,source,C.JADE) then return end
        watch[U.key(source)]={ability=ability,target=target,source=source,start=now}
        if timer then return end
        generation=generation+1;local token=generation
        local ok,h=pcall(o.loop or LoopInGameThreadWithDelay,40,function()
            if token~=generation then return true end
            sample()
            return token~=generation
        end)
        if ok and h~=nil and h~=false then timer=h else generation=generation+1;watch={} end
    end
    return self
end
return C
