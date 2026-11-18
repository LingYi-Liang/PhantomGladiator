package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local only=arg[1]
local saved=arg;arg={nil,'fixture'}
local makeArena=assert(loadfile('tools/test_arena_controller.lua'))()
local makeCombat=assert(loadfile('tools/test_combat_continuity.lua'))()
arg=saved
local function check(id,fn)if not only or only==id then fn();print('PASS '..id)end end

check('crowd',function()
    local now,requests,locks,ongoing,wrong=0,0,0,false,0
    local f=makeArena({now=function()return now end})
    f.options.targetProtected=function(a)return a.executing==true or a.offstage==true end
    f.options.keepOpponent=function(a)return a.executing==true end
    f.options.forceAttack=function(a,b)
        if ongoing and (a.executing or b.executing)then wrong=wrong+1 end
        requests=requests+1;a.native=b;return true
    end
    f.options.engagedWith=function(a,b)return a.native==b end
    f.options.holdTarget=function(a)if a.watching and ongoing then locks=locks+1 end end
    f.options.releaseLock=f.options.holdTarget
    f.options.waitForTarget=function()return true end
    f.options.resumeIntent=function()return true end
    assert(f.arena:spawn(nil,'blue',2).ok and f.arena:spawn(nil,'red',2).ok and f.arena:start().ok)
    local observer,other,foe,spare=table.unpack(f.actors)
    local child={name='minion',hp=100,alive=true}
    assert(f.arena:adoptSummon(child,observer,'/Game/Pet.Pet_C','native list').ok)
    f.arena:tickReinforcements()
    local childFoe=f.arena:aggroOpponent(child)
    assert(f.arena:aggroOpponent(observer)==foe and childFoe)
    childFoe.executing=true;foe.executing=true;ongoing=true;observer.watching=true
    for i=1,16 do
        now=i*.25;f.arena:tickReinforcements()
        f.arena:holdSensed(tostring(observer));f.arena:reengage(tostring(observer))
        assert(f.arena:aggroOpponent(observer)==foe and f.arena:aggroOpponent(child)==childFoe,
            'living opponent must remain assigned through an execution even when another enemy is available')
    end
    assert(wrong==0 and locks==0,'execution must keep native actions and locks')
    observer.native=spare -- A native perception event changed its primary target mid-animation.
    ongoing=false;foe.executing=false;childFoe.executing=false
    local before=requests;now=5;f.arena:tickReinforcements()
    assert(observer.native==foe and requests==before+1,'resume the original missing primary once')
    now=6;f.arena:tickReinforcements();assert(requests==before+1)
    foe.executing=true;now=7;f.arena:tickReinforcements();foe.hp=0
    now=8;f.arena:tickReinforcements();assert(f.arena:aggroOpponent(observer)==spare)
    spare.executing=true;now=9;f.arena:tickReinforcements();assert(f.arena:stop().ok)
    before=requests;f.arena:tickReinforcements();assert(requests==before)
end)
check('tags',function()
    local f=makeCombat()
    for _,tag in ipairs({'Ability.Action.Execution','Ability.Executed','CharacterState.Hitreact.State.Executing'})do
        f.boss.tags={[tag]=1};f.c:beginTick(f.members,true)
        assert(f.c:protected(f.boss)==true and f.c:keepOpponent(f.boss)==true,tag)
        assert(f.c:actionBusy(f.boss)==true)
    end
    f.boss.tags={['CharacterState.Unselectable']=1,['CharacterState.Immortal']=1}
    f.c:beginTick(f.members,true);assert(f.c:keepOpponent(f.boss)==true)
    f.boss.tags={['CharacterState.Immortal']=1}
    f.c:beginTick(f.members,true);assert(not f.c:protected(f.boss),'selectable damage immunity does not suspend regular combat')
    f.boss.tags={['AI.Hatred.IgnoreByNPC']=1}
    f.c:beginTick(f.members,true);assert(f.c:protected(f.boss) and not f.c:keepOpponent(f.boss),'scripted absence keeps normal target rotation')
    f.boss.tags={};f.options.executionParticipant=function(a)return a==f.boss end
    f.c:beginTick(f.members,true);assert(f.c:protected(f.boss) and f.c:keepOpponent(f.boss),'managed execution before its native tags arrive')
    f.options.executionParticipant=nil;f.boss.AbilitySystemComponent.HasAnyMatchingGameplayTags=nil
    f.boss.tags={['Ability.Executed']=1};assert(f.c:keepOpponent(f.boss,true),'individual tag fallback')
    f.boss.tags={['CharacterState.Unselectable']=1,['CharacterState.Immortal']=1}
    f.options.stageUntargetable=function()return true end
    assert(not f.c:keepOpponent(f.boss,true),'offstage boss phases may still send attackers to their summons')
end)

check('native_list',function()
    local U=require('ue_observe')
    local Guard=require('arena_aggro_guard')
    local f=makeCombat()
    local a,b,third=f.actor,f.boss,f.ally
    local current=true;local ledger={};local writes=0
    for _,pawn in ipairs({a,b,third})do
        pawn.hm.HatredList={}
        function pawn.hm:GetOwner()return pawn end
        function pawn.hm:RemoveActorFromHatredList(t)
            for i=#self.HatredList,1,-1 do if self.HatredList[i]==t then table.remove(self.HatredList,i)end end
        end
    end
    local arena={aggroOpponent=function(_,unit)if current and unit==a and a.hp>0 and b.hp>0 then return b end end}
    local support={combatContinuity=f.c}
    local env=setmetatable({arena=arena,arenaSupport=support,GetCurrentWorld=function()return f.world end,UEObserve=U,
        FName=function(t)return t end,safeValid=U.valid,engineValid=U.valid,checked=function(v)assert(U.valid(v))end,
        GetHatredComp=function(actor)return actor.hm end,battle={remember=function(_,key,cb)ledger[key]=ledger[key] or cb end}}, {__index=_G})
    local file=assert(io.open('Mods/PhantomGladiator/Scripts/main.lua','r'));local s=file:read('*a');file:close()
    local from=assert(s:find('local function HatredListContains',1,true));local to=assert(s:find('local function AddHatred',from,true))
    local start=assert(s:find('function arenaSupport:restoreProtectedHatred',1,true));local last=assert(s:find('arenaSupport.aggroGuard=require',start,true))
    local has=assert(load(s:sub(from,to-1)..s:sub(start,last-1)..'\nreturn HatredListContains','protected hatred writer','t',env))()
    local o={clock=function()return f.now end,opponent=function(actor)return arena:aggroOpponent(actor)end,aiOf=function(actor)return actor.ai end,
        keepOpponent=function(actor,fresh)return f.c:keepOpponent(actor,fresh)end,protected=function(actor)return f.c:protected(actor)end,
        threatProtected=function(actor,fresh)return f.c:threatProtected(actor,fresh)end,
        hates=function(actor,target)return has(actor.hm,target)end,
        repairHatred=function(actor,target)writes=writes+1;return support:restoreProtectedHatred(actor,target) end}
    local guard=Guard.new(o)
    for _,side in ipairs({a,b})do
        for _,state in ipairs({'Ability.Action.Execution','Ability.Executed','CharacterState.Hitreact.State.Executing'})do
            a.tags={};b.tags={};side.tags={[state]=1};a.hm.HatredList={third}
            assert(guard:onHatredRemoved(a,b) and #a.hm.HatredList==2 and a.hm.HatredList[1]==third and has(a.hm,b))
            assert(not guard:onHatredRemoved(a,b) and #a.hm.HatredList==2)
        end
    end
    a.tags={};b.tags={['CharacterState.Immortal']=1};a.hm.HatredList={}
    assert(guard:onHatredRemoved(a,b) and not f.c:protected(b),'selectable immunity retains hatred without disabling ordinary targeting')
    a.tags={};b.tags={['Ability.Executed']=1}
    a.hm.HatredList={};assert(not guard:onHatredRemoved(a,third) and #a.hm.HatredList==0)
    f.c:beginTick(f.members,true);guard:sync(f.members,true);assert(has(a.hm,b),'missed native callback must be recovered at the support tick')
    for _,invalid in ipairs({'dead','left','wrongOwner','wrongWorld','immuneEnded'})do
        local owner=a.hm.GetOwner;local outer=b.outer;a.hm.HatredList={}
        if invalid=='dead' then b.tags['CharacterState.Dead']=1
        elseif invalid=='left' then current=false
        elseif invalid=='wrongOwner' then a.hm.GetOwner=function()return third end
        elseif invalid=='wrongWorld' then b.outer=nil
        else b.tags={} end
        f.now=f.now+1
        assert(not guard:onHatredRemoved(a,b) and #a.hm.HatredList==0,invalid)
        a.hm.GetOwner=owner;b.outer=outer;current=true;b.tags={['Ability.Executed']=1}
    end
    f.now=f.now+1;assert(guard:onHatredRemoved(a,nil));current=false
    for _,restore in pairs(ledger)do assert(restore())end
    assert(#a.hm.HatredList==0 and writes>=8)
end)
