-- The Hun body's footwork (AIConfig_Hun PreMoveToExecuteTasks) may not end a move the mod started on it.
package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Guard=require('hun_action_guard')
local PHASE='CharacterState.Action.Phase.'
local COOLDOWN='Cooldown_2_C711E94E40D3CE24089AD884023A69F9'
local serial=0
local function object(class,fields)
    serial=serial+1;local id=serial
    local a=fields or {}
    a.valid=true
    function a:IsValid()return self.valid end
    function a:GetAddress()return id end
    function a:GetFullName()return class..'_'..id end
    function a:GetClass()
        return {IsValid=function()return true end,GetFName=function()return {ToString=function()return class end}end}
    end
    return a
end
local function fixture(options)
    options=options or {}
    local h={logs={},wall=100,game=5000,cancelled={},moved={},registered=0,unregistered=0,thread=true,current=true}
    h.actor=object('BP_Monster_Hun_C')
    h.controller=object('BP_SGameAIController_C');h.actor.Controller=h.controller
    local asc=object('AbilitySystemComponent',{tags={},specs={}})
    asc.ActivatableAbilities={Items=asc.specs}
    function asc:GetGameplayTagCount(t)return self.tags[t.TagName] or 0 end
    h.actor.AbilitySystemComponent=asc;h.asc=asc
    h.input=object('AbilityInputComponent',{InActionPhase=false,ActionPhase={TagName='None'}})
    h.actor['Ability Input Component']=h.input
    h.actor.Mesh=object('Mesh');function h.actor.Mesh:GetAnimInstance()return nil end
    h.r={actor=h.actor,name='Hun_1',wep={}}
    -- One active ability: the instance answers like UGameplayAbility (CancelAbility asks CanBeCanceled).
    function h:ability(class,tags)
        local list={};for _,t in ipairs(tags or {'Ability.Action.Hun.Light.A.Normal'})do list[#list+1]={TagName=t}end
        local a=object(class,{cancelable=true})
        setmetatable(a,{__index=function(self,k)if k=='bIsCancelable' then return self.cancelable end end})
        function a:GetAvatarActorFromActorInfo()return h.actor end
        function a:SetCanBeCanceled(v)self.cancelable=v;h.sets=(h.sets or 0)+1 end
        a['Move Cancel Ability']=function(self)h.moved[#h.moved+1]=class;self.spec.ActiveCount=0 end
        a.spec={Ability=object(class,{AbilityTags={GameplayTags=list}}),Handle={Handle=#asc.specs+1},ActiveCount=1,
            NonReplicatedInstances={a},ReplicatedInstances={}}
        a.tags=tags or {'Ability.Action.Hun.Light.A.Normal'}
        a['Cooldown Data']={[COOLDOWN]=0,Charges=1};a['Cooldown Mark Time']=-10000
        asc.specs[#asc.specs+1]=a.spec
        return a
    end
    function h:phase(name)
        self.input.InActionPhase=name~=nil
        self.input.ActionPhase={TagName=name and PHASE..name or 'None'}
    end
    h.utils=object('AbilityUtils');function h.utils:IsAbilityActive(a)return a.spec.ActiveCount>0 end
    h.options={log=function(s)h.logs[#h.logs+1]=s end,fname=function(s)return s end,wall=function()return h.wall end,
        now=function()return h.game end,current=function()return h.current end,inGameThread=function()return h.thread end,
        find=function(path)assert(path==Guard.UTILS);return h.utils end,
        register=function(path,pre,post)
            assert(path==Guard.HOOK);h.tries=(h.tries or 0)+1
            if h.refuse then error('not ready') end
            h.registered=h.registered+1;h.pre,h.post=pre,post;return 41,42
        end,
        unregister=function(path,a,b)
            assert(path==Guard.HOOK and a==41 and b==42)
            if h.keepHook then error('busy') end
            h.unregistered=h.unregistered+1;h.pre,h.post=nil,nil
        end}
    h.guard=Guard.new(h.options)
    -- BTTask_BaseMoveToTask: task:ExecuteTask_Internal(controller), hooked on both sides.
    function h:step(o2)
        o2=o2 or {}
        local task=object(o2.task or 'AITask_CancelAbilities_C')
        local controller=o2.controller or self.controller
        if self.pre then self.pre(task,controller) end
        if o2.task==nil or o2.task=='SGameAITask_CancelAbility' then
            for _,spec in ipairs(asc.specs)do
                local a=spec.NonReplicatedInstances[1]
                local action=false
                for _,t in ipairs(a.tags)do action=action or t:find('^Ability%.Action') end
                if spec.ActiveCount>0 and action and a.cancelable and controller==self.controller then
                    spec.ActiveCount=0;self.cancelled[#self.cancelled+1]=a
                end
            end
        end
        if self.post and not o2.noPost then
            if o2.returned then self.post(task,nil,controller) elseif o2.bare then self.post(task) else self.post(task,controller) end
        end
    end
    return h
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end

test('a step during the swing leaves the weapon attack running and cancellable again',function()
    for _,task in ipairs({'AITask_CancelAbilities_C','SGameAITask_CancelAbility'})do
        local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C')
        h.guard:follow(h.r);assert(h.registered==1)
        for _,phase in ipairs({'Start','Act'})do
            h:phase(phase);h:step({task=task~='AITask_CancelAbilities_C' and task or nil})
            assert(a.spec.ActiveCount==1 and a.cancelable==true and #h.cancelled==0,phase)
        end
        assert(h.sets==4 and h.guard:status().kept==2)
        h.guard:follow(h.r);assert(h.sets==4,'the pair of calls left nothing open')
    end
    local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C');h:phase('Act');h:step()
    assert(a.spec.ActiveCount==0 and #h.cancelled==1,'without the guard the same step ends it')
end)
test('the recovery may be walked out of, and the combo window only while a chain is being pressed',function()
    local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r)
    h:phase('Cancel');h:step();assert(a.spec.ActiveCount==0 and h.sets==nil)
    a.spec.ActiveCount=1;h:phase('Combo');h:step();assert(a.spec.ActiveCount==0,'no weapon loop pass yet')
    a.spec.ActiveCount=1;h.r.wep.comboWall=h.wall-.2;h:step();assert(a.spec.ActiveCount==1)
    h.r.wep.comboWall=h.wall-.5;h:step();assert(a.spec.ActiveCount==0,'the loop stopped looking')
    a.spec.ActiveCount=1;h.r.wep.comboWall=h.wall;h.r.wep.comboOff=true;h:step();assert(a.spec.ActiveCount==0)
end)
test('the body own attacks keep their native cancel unless the weapon loop pressed them',function()
    local h=fixture();local a=h:ability('GA_Hun_Double_AA_C',{'Ability.Action.Hun.Light.AA'});h.guard:follow(h.r)
    h:phase('Act');h:step();assert(a.spec.ActiveCount==0 and h.sets==nil)
    a.spec.ActiveCount=1;h.r.wep.push={class='GA_Hun_Double_AA_C',at=h.wall-1};h:step();assert(a.spec.ActiveCount==1)
    h.r.wep.push.at=h.wall-7;h:step();assert(a.spec.ActiveCount==0,'an old press no longer counts')
    local g=fixture();local guardMove=g:ability('GA_Hun_Double_Stance_C',{'Ability.Action.Stance'});g.guard:follow(g.r)
    g:phase('Act');g:step();assert(guardMove.spec.ActiveCount==1,'the guard the mod holds is not a native attack')
end)
test('a new defense gets a fresh timeout and preserves native cancellability',function()
    local h=fixture();local guard=h:ability('GA_Hun_Deflect_C')
    h.guard:follow(h.r);h:phase('Start');h.guard:pressed(h.r);h:step();assert(guard.spec.ActiveCount==1)
    h.wall=h.wall+.7;h:phase('Cancel');h.guard:settle(h.r,false);assert(guard.spec.ActiveCount==0)
    h:phase(nil);h.wall=h.wall+13;h.guard:follow(h.r)
    guard.spec.ActiveCount=1;h:phase('Start');h.guard:pressed(h.r);h:step()
    assert(guard.spec.ActiveCount==1,'a fresh defense after idling must not inherit the previous timer')
    guard.cancelable=false;h:step();assert(guard.cancelable==false,'keep the original native flag')
end)
test('only abilities the task would cancel are touched',function()
    local h=fixture();local hit=h:ability('GA_Hit_Stand_C',{'Ability.Hitreact.Stand'})
    local a=h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r);h:phase('Act');h:step()
    assert(a.spec.ActiveCount==1 and h.sets==2 and hit.cancelable==true)
    local none=fixture();none:ability('GA_Hit_Stand_C',{'Ability.Hitreact.Stand'});none.guard:follow(none.r)
    none:phase('Act');none:step();assert(none.sets==nil and none.guard:status().kept==0)
    local other=fixture();local b=other:ability('GA_Hun_Chaos_A_C');other.guard:follow(other.r)
    function b:GetAvatarActorFromActorInfo()return object('BP_Other_C')end
    other:phase('Act');other:step();assert(other.sets==nil,'another actor instance is not this body')
end)
test('other controllers, other tasks, other threads and executions are left alone',function()
    local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r);h:phase('Act')
    h:step({controller=object('BP_SGameAIController_C')});h:step({task='AITask_SetTag_C'});assert(h.sets==nil)
    h.thread=false;h:step();assert(h.sets==nil and a.spec.ActiveCount==0)
    h.thread=true;a.spec.ActiveCount=1
    for _,tag in ipairs({'Ability.Action.Execution','Ability.Executed','CharacterState.HitReact.State.Executing'})do
        h.asc.tags[tag]=1;h:step();assert(h.sets==nil and a.spec.ActiveCount==0,tag)
        h.asc.tags[tag]=nil;a.spec.ActiveCount=1
    end
    h.r.dead=true;h:step();assert(h.sets==nil and a.spec.ActiveCount==0)
    h.r.dead=false;a.spec.ActiveCount=1;h.current=false;h:step();assert(h.sets==nil)
    h.current=true;a.spec.ActiveCount=1;h:phase(nil);h:step();assert(h.sets==nil,'nothing is running')
end)
test('one action is not kept for ever',function()
    local h=fixture();local a=h:ability('GA_Shadow_C',{'Ability.Action.Shachi.X'});h.guard:follow(h.r);h:phase('Act')
    for _=1,12 do h:step();h.wall=h.wall+1 end
    assert(a.spec.ActiveCount==1);h.wall=h.wall+.5;h:step();assert(a.spec.ActiveCount==0)
    local g=fixture();local b=g:ability('GA_Hun_Chaos_A_C');g.guard:follow(g.r);g:phase('Act');g:step()
    g.wall=g.wall+20;g.r.wep.push={class='GA_Hun_Chaos_A_C',at=g.wall-1};g:step();assert(b.spec.ActiveCount==1,'a new press starts over')
end)
test('a refused step is granted in the recovery when nothing is chained',function()
    local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r)
    h:phase('Act');h:step()
    h.guard:settle(h.r,false);assert(#h.moved==0,'the swing goes on')
    h:phase('Combo');h.guard:settle(h.r,false);assert(#h.moved==0,'the combo window is the chain\'s')
    h:phase('Cancel');h.guard:settle(h.r,false);assert(#h.moved==1 and a.spec.ActiveCount==0 and h.guard:status().granted==1)
    h.guard:settle(h.r,false);assert(#h.moved==1,'once')
    local c=fixture();c:ability('GA_Hun_Chaos_A_C');c.guard:follow(c.r);c:phase('Act');c:step()
    c.guard:settle(c.r,true);c:phase('Cancel');c.guard:settle(c.r,false);assert(#c.moved==0,'a chain took its place')
    local e=fixture();local b=e:ability('GA_Hun_Chaos_A_C');e.guard:follow(e.r);e:phase('Act');e:step()
    b.spec.ActiveCount=0;e:phase('Cancel');e.guard:settle(e.r,false);assert(#e.moved==0,'it has ended by itself')
    local f=fixture();f:ability('GA_Hun_Chaos_A_C');f.guard:follow(f.r);f:phase('Cancel');f.guard:settle(f.r,false)
    assert(#f.moved==0,'nothing was refused')
    local g=fixture();g:ability('GA_Hun_Chaos_A_C');g.guard:follow(g.r);g:phase('Act');g:step()
    g:phase(nil);g.guard:settle(g.r,false);g:phase('Cancel');g.guard:settle(g.r,false);assert(#g.moved==0,'the wait ended with the action')
end)
test('the hook lives as long as a body does, and a refused registration is retried with a delay',function()
    local h=fixture();h.refuse=true;h.guard:follow(h.r);assert(h.tries==1)
    h.guard:follow(h.r);h.wall=h.wall+2.9;h.guard:follow(h.r);assert(h.tries==1)
    h.wall=h.wall+.2;h.guard:follow(h.r);assert(h.tries==2);h.wall=h.wall+5.9;h.guard:follow(h.r);assert(h.tries==2)
    h.refuse=false;h.wall=h.wall+.2;h.guard:follow(h.r);assert(h.registered==1 and h.guard:status().hooked)
    local other={actor=object('BP_Monster_Hun_C',{Controller=object('C')}),name='Hun_2',wep={}}
    h.guard:follow(other);h.guard:stop(h.r);assert(h.unregistered==0)
    h.keepHook=true;h.guard:stop(other);assert(h.unregistered==0 and h.guard:status().hooked,'a refused removal is kept')
    h.guard:follow(h.r);assert(h.registered==1);h.keepHook=false;h.guard:stop(h.r);assert(h.unregistered==1 and not h.guard:status().hooked)
    h.guard:stop(h.r);assert(h.unregistered==1)
end)
test('a new controller is followed and the old one no longer counts',function()
    local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r);h:phase('Act')
    local old=h.controller;h.controller=object('BP_SGameAIController_C');h.actor.Controller=h.controller
    h:step();assert(a.spec.ActiveCount==0);a.spec.ActiveCount=1
    h.guard:follow(h.r);h:step();assert(a.spec.ActiveCount==1)
    local sets=h.sets;h:step({controller=old});assert(h.sets==sets)
end)
test('a missing post-hook is made up for, and unloading leaves nothing uncancellable',function()
    local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r);h:phase('Act')
    h:step({noPost=true});assert(a.cancelable==false);h.guard:follow(h.r);assert(a.cancelable==true)
    h:step({noPost=true});assert(a.cancelable==false);h.guard:silence(true);assert(a.cancelable==true and h.unregistered==1)
    h:step();assert(a.spec.ActiveCount==0);h.guard:follow(h.r);assert(h.registered==1,'nothing starts after unloading')
    local g=fixture();local b=g:ability('GA_Hun_Chaos_A_C');g.guard:follow(g.r);g:phase('Act');g:step({noPost=true})
    local sets=g.sets;g.guard:silence(false);assert(g.unregistered==0 and g.sets==sets,'nothing native off the game thread')
    g:step();assert(g.sets==sets)
end)
-- BP_AbilityBase:K2_CanActivateAbility: a cooldown of 0 is always ready, else a full cooldown must have passed since the mark.
local function ready(a,now)
    local cooldown,mark=a['Cooldown Data'][COOLDOWN],a['Cooldown Mark Time']
    if cooldown==0 or mark<0 then return true end
    return math.min(math.floor((now-mark)/cooldown),1)>=1
end
local function pool(h)
    local list={}
    for _,s in ipairs({'A','AA','AAA','AAAA','AAAAA','B','BB','BBB','BBBB'})do
        local a=h:ability('GA_Hun_Double_'..s..'_C');a.spec.ActiveCount=0;list[#list+1]=a
    end
    return list
end
test('while a move of the mod runs the nine native attacks are refused, and afterwards they are as they were',function()
    local h=fixture();local native=pool(h);local mine=h:ability('GA_Hun_SlitheringSword_AAA_C');h.guard:follow(h.r)
    for _,a in ipairs(native)do assert(ready(a,h.game)) end
    h:phase('Start');h.guard:pressed(h.r);assert(h.guard:status().gated==1)
    for _,a in ipairs(native)do assert(not ready(a,h.game) and not ready(a,h.game+1)) end
    assert(ready(mine,h.game),'the weapon\'s own moves are not touched')
    h.wall=h.wall+.3;h:phase('Act');h.guard:settle(h.r,false);h.guard:follow(h.r)
    for _,a in ipairs(native)do assert(not ready(a,h.game)) end
    h:phase('Combo');h.guard:settle(h.r,false);assert(not ready(native[1],h.game),'the combo window is the chain\'s')
    h:phase('Cancel');h.guard:settle(h.r,false)
    for _,a in ipairs(native)do assert(ready(a,h.game) and a['Cooldown Data'][COOLDOWN]==0 and a['Cooldown Mark Time']==-10000) end
    h.guard:settle(h.r,false);assert(h.guard:status().gated==1)
end)
test('the native attacks come back when the move ends, is too long, or the body dies, leaves or is unloaded',function()
    local ends={
        function(h)h:phase(nil);h.guard:settle(h.r,false)end,
        function(h)h:phase(nil);h.guard:follow(h.r)end,
        function(h)h:phase(nil);h.guard:observe(h.r,false,false)end,
        function(h)h:phase('Act');h.wall=h.wall+12.2;h.guard:follow(h.r)end,
        function(h)h:phase('Act');h.r.dead=true;h.guard:follow(h.r)end,
        function(h)h.guard:stop(h.r)end,
        function(h)h.guard:silence(true)end,
    }
    for i,finish in ipairs(ends)do
        local h=fixture();local native=pool(h);h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r);h:phase('Act');h.guard:pressed(h.r)
        assert(not ready(native[3],h.game));h.wall=h.wall+.3;finish(h)
        for _,a in ipairs(native)do assert(ready(a,h.game) and a['Cooldown Mark Time']==-10000,'end '..i) end
    end
    local h=fixture();local native=pool(h);h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r);h:phase('Act');h.guard:pressed(h.r)
    h.guard:silence(false);assert(not ready(native[1],h.game),'nothing native off the game thread')
    assert(ready(native[1],h.game+3),'even without a game-thread restore the temporary suppression expires')
end)
test('a press survives the first montage read; the same gate renews across a chain',function()
    local h=fixture();local native=pool(h);h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r)
    h:phase(nil);h.guard:pressed(h.r);h.guard:settle(h.r,false);assert(not ready(native[1],h.game))
    h.wall=h.wall+.2;h:phase('Act');h.guard:settle(h.r,false);assert(not ready(native[1],h.game))
    h.game=h.game+3;h.guard:pressed(h.r);h.guard:settle(h.r,true)
    assert(native[1]['Cooldown Mark Time']==5003 and not ready(native[1],h.game) and h.guard:status().gated==1)
    h.wall=h.wall+.2;h:phase(nil);h.guard:settle(h.r,false);assert(ready(native[1],h.game))
    h.wall=h.wall+1;h.guard:pressed(h.r);assert(h.guard:status().gated==2 and native[1]['Cooldown Mark Time']==5003)
end)
test('attacks the weapon in hand grants itself are never gated, nor another actor\'s, nor unreadable ones',function()
    local h=fixture();local native=pool(h)
    h.r.wep.currentConfig=object('Config',{['Equip Abilities']={object('BlueprintGeneratedClass /Game/GA_Hun_Double_A.GA_Hun_Double_A_C')}})
    h.r.wep.currentConfig['Equip Abilities'][1].GetFullName=function()return 'BlueprintGeneratedClass /Game/GA_Hun_Double_A.GA_Hun_Double_A_C' end
    native[2].GetAvatarActorFromActorInfo=function()return object('BP_Other_C')end
    native[3]['Cooldown Data']=nil;native[4]['Cooldown Mark Time']='?'
    h.guard:follow(h.r);h:phase('Act');h.guard:pressed(h.r)
    assert(ready(native[1],h.game) and ready(native[2],h.game) and native[4]['Cooldown Mark Time']=='?')
    for i=5,9 do assert(not ready(native[i],h.game)) end
    local none=fixture();none.guard:follow(none.r);none:ability('GA_Hun_Chaos_A_C');none:phase('Act');none.guard:pressed(none.r)
    assert(none.guard:status().gated==0,'a body without the native pool has nothing to gate')
    local blind=fixture();pool(blind);blind.game=nil;blind.guard:follow(blind.r);blind.guard:pressed(blind.r);assert(blind.guard:status().gated==0)
    local gone=fixture();pool(gone);gone.guard:follow(gone.r);gone.current=false;gone.guard:pressed(gone.r);assert(gone.guard:status().gated==0)
    local stranger=fixture();pool(stranger);stranger.guard:pressed(stranger.r);assert(stranger.guard:status().gated==0,'not a followed body')
end)
test('a write that does not stick is taken back, and a value the game changed meanwhile stays the game\'s',function()
    local h=fixture();local native=pool(h)
    local stuck=native[1];local data={Charges=1}
    stuck['Cooldown Data']=setmetatable(data,{__index=function(_,k)if k==COOLDOWN then return 0 end end,__newindex=function(_,k,v)if k~=COOLDOWN then rawset(data,k,v) end end})
    h.guard:follow(h.r);h:phase('Act');h.guard:pressed(h.r)
    assert(stuck['Cooldown Mark Time']==-10000 and ready(stuck,h.game) and not ready(native[2],h.game))
    native[2]['Cooldown Data'][COOLDOWN]=7;native[3]['Cooldown Mark Time']=6000
    h.wall=h.wall+1;h:phase(nil);h.guard:settle(h.r,false)
    assert(native[2]['Cooldown Data'][COOLDOWN]==7 and native[3]['Cooldown Mark Time']==6000 and ready(native[4],h.game))
    local real=fixture();local b=pool(real);b[1]['Cooldown Data'][COOLDOWN]=4;b[1]['Cooldown Mark Time']=4990
    real.guard:follow(real.r);real:phase('Act');real.guard:pressed(real.r);real.wall=real.wall+1;real:phase(nil);real.guard:settle(real.r,false)
    assert(b[1]['Cooldown Data'][COOLDOWN]==4 and b[1]['Cooldown Mark Time']==4990,'a real cooldown is put back as it was')
    local again=fixture();local c=pool(again);c[2]['Cooldown Data'][COOLDOWN]=1e6;c[2]['Cooldown Mark Time']=4800
    again.guard:follow(again.r);again:phase('Act');again.guard:pressed(again.r);assert(not ready(c[2],again.game))
    again.wall=again.wall+1;again:phase(nil);again.guard:settle(again.r,false)
    assert(c[2]['Cooldown Data'][COOLDOWN]==0 and c[2]['Cooldown Mark Time']==-10000,'what an earlier load left goes with the first gate')
end)
test('cleanup retries a cooldown whose first restoration is refused',function()
    local h=fixture();local a=pool(h)[1]
    local value,deny=0,false
    a['Cooldown Data']=setmetatable({},{
        __index=function(_,key)if key==COOLDOWN then return value end end,
        __newindex=function(_,key,v)if key==COOLDOWN and not deny then value=v end end})
    h.guard:follow(h.r);h:phase('Act');h.guard:pressed(h.r);assert(not ready(a,h.game))
    deny=true;h.wall=h.wall+.5;h:phase(nil);h.guard:stop(h.r)
    assert(value>0 and not ready(a,h.game),'the simulated cooldown write was refused')
    deny=false;h.wall=h.wall+1;h.guard:tick()
    assert(value==0 and ready(a,h.game) and a['Cooldown Mark Time']==-10000)
end)
test('cooldown restore handles both a rejected refresh and an applied refresh with unreadable readback',function()
    for _,writes in ipairs({true,false})do
        local h=fixture();local a=pool(h)[1];local property='Cooldown Mark Time'
        local original,mark,blind=4980,4980,false
        a['Cooldown Data'][COOLDOWN]=12;a[property]=nil
        setmetatable(a,{
            __index=function(_,k)
                if k==property then
                    if blind then blind=false;return nil end
                    return mark
                end
            end,
            __newindex=function(obj,k,v)
                if k~=property then rawset(obj,k,v);return end
                if v~=5002 or writes then mark=v end
                if v==5002 then blind=true end
            end})
        h.guard:follow(h.r);h:phase('Act');h.guard:pressed(h.r)
        h.wall=h.wall+.5;h.game=5002;h.guard:follow(h.r)
        assert(a[property]==(writes and 5002 or 5000))
        h.guard:stop(h.r)
        assert(a[property]==original and a['Cooldown Data'][COOLDOWN]==12,'restore both temporary fields')
    end
end)
test('missing ability objects after reload stop consuming lookup time',function()
    local h=fixture();local world=object('World')
    h.options.world=function()return world end
    local saved={}
    for i=1,6 do saved[i]=table.concat({'cooldown',world:GetAddress(),'420',800+i,
        'Hun /Game/Map.Map:Hun_0','Ability /Game/Map.Map:Hun_0.Native_'..i,0,-10000,i==1 and 1 or 5000,0},'\t') end
    h.options.shared={
        GetSharedVariable=function()return table.concat(saved,'\n')end,
        SetSharedVariable=function()end}
    local calls=0
    h.options.find=function()calls=calls+1 end
    h.guard=Guard.new(h.options)
    for _=1,90 do
        h.wall=h.wall+.5;local before=calls
        h.guard:tick();assert(calls-before<=1,'one unsuccessful native lookup per tick')
    end
    assert(calls==18,'three checks per missing object, then stop')
end)
test('a nested cancellation with no new writes cannot release the outer action',function()
    local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C')
    local task=object('AITask_CancelAbilities_C')
    h.guard:follow(h.r);h:phase('Act')
    h.pre(task,h.controller);h.pre(task,h.controller)
    h.post(task,h.controller);assert(a.cancelable==false)
    h.post(task,h.controller);assert(a.cancelable==true and h.sets==2)
    h.pre(task,h.controller);h.guard:stop(h.r)
    assert(a.cancelable==true and not h.guard:status().hooked)
end)
test('an off-thread unload is restored by name and identity in the next game-thread tick',function()
    local h=fixture()
    local native=pool(h)[1]
    local mine=h:ability('GA_Hun_Chaos_A_C')
    local world=object('World');h.options.world=function()return world end
    local values={}
    h.options.shared={SetSharedVariable=function(_,k,v)values[k]=v end,GetSharedVariable=function(_,k)return values[k]end}
    function h.actor:GetFullName()return 'Hun /Game/Map.Map:Hun_0' end
    function native:GetFullName()return 'Ability /Game/Map.Map:Hun_0.Native' end
    function mine:GetFullName()return 'Ability /Game/Map.Map:Hun_0.Mod' end
    local savedFind=h.options.find
    h.options.find=function(path)
        if path=='/Game/Map.Map:Hun_0.Native' then return native end
        if path=='/Game/Map.Map:Hun_0.Mod' then return mine end
        if path==Guard.UTILS then return savedFind(path) end
    end
    local property='Cooldown Mark Time'
    local original,mark,unreadable=h.game-12,h.game-12,false
    local inherited=getmetatable(native).__index
    native['Cooldown Data'][COOLDOWN]=4;native[property]=nil
    setmetatable(native,{
        __index=function(obj,key)
            if key~=property then return inherited(obj,key) end
            if unreadable then unreadable=false;return nil end
            return mark
        end,
        __newindex=function(obj,key,value)
            if key==property then
                mark=value
                if value==5001 and not h.failedRead then unreadable=true;h.failedRead=true end
            else rawset(obj,key,value) end
        end})
    h.guard=Guard.new(h.options);h.guard:follow(h.r);h:phase('Act');h.guard:pressed(h.r)
    h.game=5001;h.wall=h.wall+.5;h.guard:follow(h.r)
    assert(h.failedRead and native[property]==5001,'the accepted renewal survived the failed immediate read')
    h.pre(object('AITask_CancelAbilities_C'),h.controller)
    assert(not ready(native,h.game) and not mine.cancelable)
    h.guard:silence(false);assert(not ready(native,h.game) and not mine.cancelable)
    h.guard=Guard.new(h.options)
    h.thread=false;h.guard:tick();assert(not mine.cancelable and not ready(native,h.game))
    h.thread=true;h.guard:tick()
    assert(mine.cancelable and native['Cooldown Data'][COOLDOWN]==4 and native[property]==original)
    h.guard:follow(h.r);h.guard:pressed(h.r);h.guard:silence(false)
    local foreign=object('Not our actor')
    function native:GetAvatarActorFromActorInfo()return foreign end
    h.guard=Guard.new(h.options);h.guard:tick()
    assert(native['Cooldown Data'][COOLDOWN]==2,'an instance assigned to a different avatar must not be written by recovery')
end)
test('the post-hook is recognised with a return value in front, without arguments, and not for another unit',function()
    for _,how in ipairs({'returned','bare'})do
        local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r);h:phase('Act')
        h:step({[how]=true});assert(a.cancelable==true and h.sets==2,how)
    end
    local h=fixture();local a=h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r);h:phase('Act')
    local task,post=object('AITask_CancelAbilities_C'),nil
    h.pre(task,h.controller);assert(a.cancelable==false)
    h.post(task,object('BP_SGameAIController_C'));assert(a.cancelable==false,'another unit ran the shared task inside ours')
    h.post(object('AITask_CancelAbilities_C'),h.controller);assert(a.cancelable==false,'another task object')
    h.post(task,h.controller);assert(a.cancelable==true)
    local other={actor=object('BP_Monster_Hun_C',{Controller=object('C')}),name='Hun_2',wep={}};h.guard:follow(other)
    h.pre(task,h.controller);h.post(task,other.actor.Controller);assert(a.cancelable==false,'another followed body')
    h.post(task,h.controller);assert(a.cancelable==true)
end)
test('the first kept actions are logged, with a total when the body leaves',function()
    local h=fixture();h:ability('GA_Hun_Chaos_A_C');h.guard:follow(h.r);h:phase('Act')
    for _=1,30 do h:step();h.guard:settle(h.r,true) end
    local kept,total=0,nil
    for _,l in ipairs(h.logs)do if l:find('立回移动不打断出招',1,true) then kept=kept+1 end end
    assert(kept==10);h.guard:stop(h.r)
    for _,l in ipairs(h.logs)do total=total or l:match('出招保护统计.-保留=(%d+)') end
    assert(total=='30')
end)
print(n..' tests passed')
