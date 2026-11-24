-- Count work at the boundaries used on the game thread. No game process or user files are needed.
package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Profile=require('companion_profile')
local Manager=require('companion_manager')
local failures=0
local function test(label,fn)
    local ok,why=pcall(fn)
    print((ok and 'PASS ' or 'FAIL ')..label..(ok and '' or ': '..tostring(why)))
    if not ok then failures=failures+1 end
end
local function harness(count,dual)
    local h={members={},now=0,wall=0,world='scene',ready=true,writes=0,swaps=0}
    local function actor(i)
        return {id=i,name='npc'..i,hp=100,max=100,safe=true,known=true,canSwitch=true,combat=false}
    end
    for i=1,count do h.members[i]={team='companion',actor=actor(i),class_path=Profile.first,dual=dual} end
    local options={path='fixture',read=function()end,write=function()h.writes=h.writes+1;return not h.failWrite end,
        session=function()return h.world,h.ready end,now=function()return h.now end,ioClock=function()return h.wall end,
        sample=function(r)
            h.samples=(h.samples or 0)+1
            if r.actor==h.broken then h.errors=(h.errors or 0)+1;error('unreadable AI component') end
            return r.actor
        end,identity=function(a)if h.noIdentity==a then error('object changing world') end;return a.id,a.name end,
        onDeath=function()h.deathChecks=(h.deathChecks or 0)+1;return true end,
        swap=function(r,phase)
            h.swaps=h.swaps+1
            if h.refuse and r.actor==h.refuse then return {ok=false,message='busy'} end
            for _,m in ipairs(h.members)do
                if m.actor==r.actor then
                    local new=actor(10000+h.swaps);new.hp=m.actor.hp;new.combat=m.actor.combat
                    m.actor=new;m.class_path=phase==2 and Profile.second or Profile.first
                    return {ok=true,actor=new}
                end
            end
            error('missing source')
        end}
    h.manager=Manager.new(options)
    function h:tick(dt)
        self.now=self.now+(dt or .2);self.wall=self.wall+(dt or .2)
        self.manager:tick(self.members)
    end
    return h
end
test('unchanged roster avoids encoding and disk writes',function()
    local h=harness(50,false)
    local encode=Profile.encode;local encoded=0
    Profile.encode=function(...)encoded=encoded+1;return encode(...)end
    h:tick();encoded=0
    for _=1,2000 do h:tick() end
    Profile.encode=encode
    print(('MEASURE stable roster: encodes=%d writes=%d'):format(encoded,h.writes))
    assert(encoded==0 and h.writes==1)
    local r=h.manager:lookup(h.members[1].actor)
    local p=Profile.copy(r.p);p.distance=12
    assert(h.manager:command(r.id..'|'..r.rev..'|save|'..Profile.encode(p)).ok and h.writes==2)
end)
test('failed publication backs off while unready and recovers with a frozen game clock',function()
    local h=harness(0,false);h.ready=false;h.failWrite=true
    for _=1,120 do h.wall=h.wall+.1;h.manager:tick({}) end
    print('MEASURE locked roster: attempts for 12 seconds='..h.writes)
    assert(h.writes>=1 and h.writes<=7)
    h.failWrite=false;h.wall=h.wall+3;h.manager:tick({})
    assert(h.manager.revision==1)
    for _=1,20 do h.wall=h.wall+1;h.manager:tick({}) end
    assert(h.manager.revision==1)
end)
test('simultaneous automatic transitions are spread and deferred requests are re-evaluated',function()
    local h=harness(24,true);h:tick()
    for _,m in ipairs(h.members)do m.actor.combat=true;m.actor.hp=40 end
    local last=h.members[#h.members].actor
    h:tick();local first=h.swaps
    print('MEASURE 24 eligible: synchronous replacements in first pass='..first)
    assert(first==1)
    last.hp=90
    for _=1,60 do local before=h.swaps;h:tick();assert(h.swaps-before<=1) end
    assert(h.swaps==23 and h.manager:lookup(last).phase==1)
    -- Combat returning while the other units are waiting to revert cancels that unit's return.
    for _,m in ipairs(h.members)do m.actor.combat=false end
    local firstReturn
    for _=1,70 do
        local before=h.swaps;h:tick();assert(h.swaps-before<=1)
        if h.swaps>before and not firstReturn then
            for _,m in ipairs(h.members)do if h.manager:lookup(m.actor).phase==2 then firstReturn=m.actor;firstReturn.combat=true;break end end
        end
    end
    for _=1,60 do h:tick() end
    assert(firstReturn and h.manager:lookup(firstReturn).phase==2 and h.swaps==45)
end)
test('one repeatedly refused replacement yields to other eligible companions',function()
    local h=harness(8,true);h:tick();h.refuse=h.members[1].actor
    for _,m in ipairs(h.members)do m.actor.combat=true;m.actor.hp=40 end
    for _=1,50 do local before=h.swaps;h:tick();assert(h.swaps-before<=1) end
    for i=2,8 do assert(h.manager:lookup(h.members[i].actor).phase==2) end
    assert(h.manager:lookup(h.refuse).phase==1)
end)
test('an exception from one AI cannot stop the other companions or spin on every tick',function()
    local h=harness(2,true);h:tick()
    h.broken=h.members[1].actor;h.members[2].actor.hp=40;h.members[2].actor.combat=true
    local returned=0
    for _=1,100 do if pcall(h.tick,h,.1) then returned=returned+1 end end
    print(('MEASURE faulty actor: completed passes=%d/100, faulty samples=%d'):format(returned,h.errors))
    assert(returned==100 and h.swaps==1 and h.errors<=5)
    h.broken=nil;h.members[1].actor.hp=40;h.members[1].actor.combat=true
    for _=1,12 do h:tick(1) end
    assert(h.swaps==2)
end)
test('temporary identity failure on one owned actor preserves its instance and the rest of the roster',function()
    local h=harness(2,true);h:tick()
    local a=h.members[1].actor;local id=h.manager:lookup(a).id;h.noIdentity=a
    h.members[2].actor.hp=30;h.members[2].actor.combat=true
    assert(pcall(h.tick,h) and h.swaps==1,'a bad name read must not halt later actors')
    assert(not h.manager:command(id..'|1|recall|').ok)
    h.noIdentity=nil;h:tick();assert(h.manager:lookup(a).id==id)
end)
test('oversized profile input is bounded before parsing',function()
    local old=io.open;local requested
    io.open=function()
        return {read=function(_,n)requested=n;return string.rep('x',type(n)=='number' and n or 1024*1024)end,close=function()return true end}
    end
    local ok,data=pcall(Profile.read,'virtual',512)
    io.open=old
    print('MEASURE oversized profile read request='..tostring(requested))
    assert(ok and not data and type(requested)=='number' and requested<=513)
end)
test('simultaneous deaths release all helper pools without a burst of world scans',function()
    local h=harness(16,true)
    for _,m in ipairs(h.members)do m.class_path=Profile.second;m.actor.hp=0 end
    local peak=0
    for _=1,80 do local before=h.deathChecks or 0;h:tick();peak=math.max(peak,(h.deathChecks or 0)-before) end
    print(('MEASURE 16 deaths: peak helper cleanups per pass=%d total=%d'):format(peak,h.deathChecks or 0))
    assert(peak==1 and h.deathChecks==16)
end)
assert(failures==0,tostring(failures)..' failed companion workload checks')