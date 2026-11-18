package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Guard=require('arena_aggro_guard')
local C,I='AI.State.Combat','AI.State.Idle'
local id=0
local function obj(label)
    id=id+1;local key=id
    return {IsValid=function(a)return not a.gone end,GetAddress=function()return key end,
        GetFullName=function()return 'Object /Game/Arena.'..label..key end}
end
local function tag(s)return {TagName=s}end
local function fixture()
    local h={active=true,now=0,clears=0,writes=0,recalls=0,known={},roster={},objects={},shared={}}
    function h.shared:GetSharedVariable(k)return self[k]end
    function h.shared:SetSharedVariable(k,v)self[k]=v end
    function h:add(team)
        local a=obj('fighter');local ai=obj('brain');local asc=obj('asc')
        local map={rows={}}
        function map:ForEach(fn)for k,v in pairs(self.rows)do fn(tag(k),tag(v))end end
        function map:Contains(k)return self.rows[k.TagName]~=nil end
        function map:Find(k)return tag(self.rows[k.TagName])end
        function map:Add(k,v)self.rows[k.TagName]=v.TagName;h.writes=h.writes+1 end
        function map:Remove(k)self.rows[k.TagName]=nil end
        ai.Pawn=a;ai.bAIStarted=true;ai.StateBlockMap=map
        ai.CurrentStateTag=tag(C);ai.DesiredStateTag=tag(C)
        asc.tags={[C]=1};function asc:GetGameplayTagCount(k)return self.tags[k.TagName] or 0 end
        ai.AbilitySystemComponent=asc;a.AbilitySystemComponent=asc;a.ai=ai;a.hp=100
        for _,o in ipairs({a,ai})do h.objects[o:GetFullName():match(' (.+)$')]=o end
        h.roster[#h.roster+1]={actor=a,team=team}
        -- BP_SGameAIComponent.Set Current State writes desired, checks the map and the ASC,
        -- then changes the current state. AIScript_HatredManage clears hatred on leaving combat.
        ai['Set Current State']=function(self,new)
            if self.CurrentStateTag.TagName==new.TagName then return end
            self.DesiredStateTag=new
            if self.bAIStarted~=true or asc.tags[map.rows[new.TagName]]==1 then return end
            asc.tags[self.CurrentStateTag.TagName]=nil;asc.tags[new.TagName]=1
            self.CurrentStateTag=new
            if new.TagName==I then a.foe=nil;h.clears=h.clears+1 end
        end
        return a
    end
    h.o={fname=function(n)return n end,clock=function()return h.now end,aiOf=function(a)return a.ai end,
        opponent=function(a)local b=h.known[a];if h.active and a.hp>0 and b and b.hp>0 then return b end end,
        hates=function(a,b)return a.foe==b end,protected=function(a)return a.scripted==true end,
        find=function(p)return h.objects[p]end,shared=h.shared,log=function()end}
    function h:pair(a,b)self.known[a]=b;a.foe=b end
    function h:drop(a)
        local ai=a.ai
        if ai.DesiredStateTag.TagName==C then ai['Set Current State'](ai,tag(I)) end
        if not self.g:onDrop(a,ai) then self.recalls=self.recalls+1 end
    end
    h.g=Guard.new(h.o);return h
end
local h=fixture();local fighters={}
for n=1,48 do fighters[n]=h:add(n%2==0 and 'red' or 'blue')end
for n,a in ipairs(fighters)do h:pair(a,fighters[n%2==0 and n-1 or n+1])end
h.g:sync(h.roster,true)
for i=1,3 do
    for _,a in ipairs(fighters)do h:drop(a)
        assert(a.foe==h.known[a] and a.ai.CurrentStateTag.TagName==C and a.ai.DesiredStateTag.TagName==C)
    end
    h.now=i;h.g:sync(h.roster,true)
end
assert(h.clears==0 and h.recalls==0 and h.writes==48)
local a,b=fighters[1],fighters[2];b.hp=0;h.g:sync(h.roster,true)
h:drop(a);assert(a.foe==nil and a.ai.CurrentStateTag.TagName==I)
local other=h:add('red');h:pair(a,other);a.ai['Set Current State'](a.ai,tag(C))
h.now=10;h.g:sync(h.roster,true);h:drop(a);assert(a.foe==other)
assert(h.g:stop());h:drop(a);assert(a.foe==nil)
print('PASS 48 fighters x 3 native exit attempts: 144 retained, 0 clears, 0 re-engages; opponent death, rejoin and stop verified')

-- Negative control, using the same decoded state/hatred boundary without an installed rule.
local old=fixture();local first,second=old:add('blue'),old:add('red');old:pair(first,second)
for i=1,144 do
    old:drop(first)
    assert(first.foe==nil and first.ai.CurrentStateTag.TagName==I)
    first.ai['Set Current State'](first.ai,tag(C));first.foe=second
end
assert(old.clears==144 and old.recalls==144)
print('PASS negative control: 144 exits cleared hatred before the recovery callback')

local function duel()
    local f=fixture();local a,b=f:add('blue'),f:add('red')
    f:pair(a,b);return f,a,b
end
for _,kind in ipairs({'native','protected','disabled','unknown','no-hatred','foreign-asc','foreign-pawn','no-tag'})do
    local f,a,b=duel();local map=a.ai.StateBlockMap
    if kind=='native' then map.rows[I]='AI.DisableSearch'
    elseif kind=='protected' then a.scripted=true
    elseif kind=='disabled' then a.ai.bAIStarted=false
    elseif kind=='unknown' then map.ForEach=function()error('unreadable')end
    elseif kind=='no-hatred' then a.foe=nil
    elseif kind=='foreign-asc' then a.ai.AbilitySystemComponent=b.AbilitySystemComponent
    elseif kind=='foreign-pawn' then a.ai.Pawn=b
    else a.AbilitySystemComponent.tags[C]=nil end
    f.g:sync(f.roster,true);assert(f.writes==0,kind)
    assert(f.g:stop() and map.rows[I]==(kind=='native' and 'AI.DisableSearch' or nil))
end
do
    local f,a=duel();f.g:sync(f.roster,true)
    local oldMap=a.ai.StateBlockMap;oldMap.rows[I]='AI.SomeOtherRule'
    assert(f.g:stop() and oldMap.rows[I]=='AI.SomeOtherRule','an external replacement must stand')
end
do
    local f,a=duel();f.g:sync(f.roster,true)
    a.ai['Set Current State'](a.ai,tag(I));assert(a.ai.CurrentStateTag.TagName==C)
    f.active=false;f.g:sync(f.roster,false)
    assert(a.ai.CurrentStateTag.TagName==I and a.foe==nil,'honor the outstanding native idle request after combat')
end
do
    local f,a=duel();f.g:sync(f.roster,true)
    local map=a.ai.StateBlockMap;local remove=map.Remove;map.Remove=function()end
    assert(not f.g:stop() and map.rows[I]==C);map.Remove=remove
    assert(f.g:stop() and map.rows[I]==nil)
end
do
    local f,a=duel();f.g:sync(f.roster,true)
    local ai=a.ai
    local touches=0;local original=ai.IsValid
    ai.IsValid=function(...)touches=touches+1;return original(...)end
    f.g:silence(false);assert(touches==0 and ai.StateBlockMap.rows[I]==C)
    f.g=Guard.new(f.o);f.active=false;f.g:sync({},false)
    assert(ai.StateBlockMap.rows[I]==nil,'next game-thread load restores the private rule')
end
do
    local f,a,b=duel();f.g:sync(f.roster,true)
    local old=a.ai;a.ai=b.ai;f.g:sync(f.roster,true)
    assert(old.StateBlockMap.rows[I]==nil and b.ai.StateBlockMap.rows[I]==nil)
end
print('PASS private component boundaries, native rules, stopped AI, partial cleanup, pending idle and non-game-thread reload')
do
    local f,a=duel();local map=a.ai.StateBlockMap;map.ForEach=nil
    f.g:sync(f.roster,true);assert(map.rows[I]==C)
    a.foe=nil;f:drop(a);assert(f.g.retained==0 and f.recalls==1,'a list cleared by another path is not a confirmed hold')
    assert(f.g:stop() and map.rows[I]==nil)
end

do
    local saved=arg;arg={nil,'fixture'}
    local makeArena=assert(loadfile('tools/test_arena_controller.lua'))();arg=saved
    local f=fixture();local actors={}
    for i=1,48 do local u=f:add(i%2==0 and 'red' or 'blue');u.alive=true;u.name='unit'..i;actors[i]=u end
    local births={actors[1],actors[2]}
    local arena=makeArena({maxUnits=0,now=function()return f.now end,spawnClass=function()return table.remove(births,1)end,
        hp=function(a)return a.hp end,forceAttack=function(a,b)a.foe=b;return true end,
        onAssigned=function(a,b)f.g:arm(a,b)end}).arena
    f.o.opponent=function(a)return arena:aggroOpponent(a)end
    assert(arena:spawn(nil,'blue',1).ok and arena:spawn(nil,'red',1).ok and arena:start().ok)
    assert(actors[1].ai.StateBlockMap.rows[I]==C and actors[2].ai.StateBlockMap.rows[I]==C)
    for i=3,48 do assert(arena:adoptSummon(actors[i],actors[i%2==0 and 2 or 1],'/Game/Pet.Pet_C','native list').ok)end
    for tick=1,50 do f.now=tick*.5;arena:tickReinforcements();f.g:sync(arena:members(),true)end
    for wave=1,3 do for _,a in ipairs(actors)do
        local before=a.foe;assert(before and a.ai.StateBlockMap.rows[I]==C)
        f:drop(a);assert(a.foe==before and a.ai.CurrentStateTag.TagName==C)
    end end
    assert(f.g.retained==144 and f.clears==0 and f.recalls==0)
    local previous=actors[1].foe;previous.hp=0;arena:tickReinforcements();f.g:sync(arena:members(),true)
    assert(actors[1].foe~=previous and previous.ai.StateBlockMap.rows[I]==nil)
    print('PASS arena assignment and reinforcement entry points: 2 summoners + 46 summons; continuous original hatred and native retarget after death')
end
