package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local P=require('companion_profile')
local M=require('companion_manager')
local files,store={},{}
local now,world,ready=0,'session1',true
local nameSerial,swaps,heals,refuse,uncertain=0,0,0,false,false
local current,held={},{}
local function body(phase)
    nameSerial=nameSerial+1
    return {key=tostring(nameSerial),name='npc'..nameSerial,hp=100,max=100,safe=true,known=true,canSwitch=true,combat=false,phase=phase}
end
local function row(phase,dual)
    local x={actor=body(phase),team='companion',class_path=phase==1 and P.first or P.second,dual=dual}
    current[#current+1]=x;return x
end
local o={path='runtime',read=function(f)return files[f]end,write=function(f,d)if store.fail then return false end;files[f]=d;return true end,
    identity=function(a)return a.key,a.name end,session=function()return world,ready end,now=function()return now end,
    spawn=function(path)held.spawn=path;return {ok=true} end,sample=function(r)return r.actor end,
    release=function(r)r.pose=nil;r.lease=nil end,order=function()return {ok=true}end,
    heal=function(r,h)heals=heals+1;r.actor.hp=h end,recall=function(a)held.recalled=a;return {ok=true}end,
    pose=function(r)r.pose={};return {ok=true}end,cancelPose=function(r)r.pose=nil end,
    swap=function(r,phase,why)
        swaps=swaps+1;if refuse then return {ok=false,uncertain=uncertain,message='staged activation refused'} end
        for _,u in ipairs(current)do if u.actor==r.actor then
            local n=body(phase);n.hp=r.actor.hp;n.combat=r.actor.combat;u.actor=n;u.class_path=phase==1 and P.first or P.second
            return {ok=true,actor=n}
        end end
    end}
local m=M.new(o)
local function tick(n)for i=1,n or 1 do now=now+1;m:tick(current) end end
local function cmd(r,verb,v)return m:command(table.concat({r.id,r.rev,verb,v or ''},'|'))end
local function save(r,changes)local p=P.copy(r.p);for k,v in pairs(changes)do p[k]=v end;return cmd(r,'save',P.encode(p))end
assert(P.decode(P.encode(P.defaults)).distance==5 and not P.decode('active,5,1,3,game,1,manual,50,2'))
local a,b,c=row(1,true),row(1,true),row(2,false)
local vanilla={actor=body(1),team='blue',class_path=P.first};current[#current+1]=vanilla
local helper={actor=body(2),team='companion',class_path=P.second,summoner=b.actor,stand=true};current[#current+1]=helper
tick()
local ra,rb,rc=m:lookup(a.actor),m:lookup(b.actor),m:lookup(c.actor)
assert(ra.id~=rb.id and not m:lookup(vanilla.actor) and not m:lookup(helper.actor))
local oldId=ra.id;local original=a.actor
a.actor.combat=true;a.actor.hp=51;tick();assert(swaps==0)
a.actor.hp=50;a.actor.canSwitch=false;tick();assert(swaps==0)
a.actor.canSwitch=true;tick();assert(swaps==1 and ra.phase==2 and ra.actor.hp==50 and ra.id==oldId and not m:lookup(original))
tick(4);assert(swaps==1)
a.actor.combat=false;tick(8);a.actor.combat=true;tick();a.actor.combat=false;tick(9);assert(swaps==1)
tick(2);assert(swaps==2 and ra.phase==1 and rc.phase==2)
assert(save(rb,{policy='auto_stay',delay=2}).ok)
b.actor.combat=true;b.actor.hp=20;tick();assert(rb.phase==2)
b.actor.combat=false;tick(5);assert(rb.phase==2)
assert(not cmd(rb,'switch').ok)
assert(save(rb,{policy='manual'}).ok and cmd(rb,'switch').ok);assert(rb.phase==1)
local stale=rb.rev;assert(save(rb,{regen='custom',rate=5,delay=2}).ok)
assert(not m:command(rb.id..'|'..stale..'|save|'..P.encode(P.defaults)).ok)
b.actor.hp=50;tick(3);assert(b.actor.hp==55)
b.actor.known=false;tick(3);assert(b.actor.hp==55)
b.actor.known=true;b.actor.safe=false;tick(2);assert(b.actor.hp==55 and not cmd(rb,'switch').ok)
b.actor.safe=true;tick(3);assert(b.actor.hp==60)
now=now+500;tick();assert(b.actor.hp==60)
b.actor.hp=0;tick(3);assert(b.actor.hp==0 and rb.state=='down' and not cmd(rb,'recall').ok)
b.actor.hp=30;assert(cmd(rb,'wait').ok and rb.waiting);assert(cmd(rb,'follow').ok and not rb.waiting)
assert(cmd(rb,'pose').ok);b.actor.combat=true;tick();assert(not rb.pose)
b.actor.combat=false;assert(cmd(rb,'recall').ok and held.recalled==b.actor)
assert(save(rb,{policy='second'}).ok);tick();assert(rb.phase==2);assert(save(rb,{policy='first'}).ok);tick();assert(rb.phase==1)
assert(save(rb,{policy='manual'}).ok)
refuse=true;local old=b.actor;assert(not cmd(rb,'switch').ok and b.actor==old and m:lookup(old).id==rb.id)
uncertain=true;assert(not cmd(rb,'switch').ok and rb.blocked);local attempted=swaps;tick(30);assert(swaps==attempted and not cmd(rb,'switch').ok)
local p=P.copy(P.defaults);p.policy='second';p.distance=12
assert(m:command('mu|0|save|'..P.encode(p)).ok and m:spawn().ok and held.spawn==P.second)
assert(ra.p.distance==5 and m.settingsRevision==1)
local fresh=row(2,true);tick();assert(m:lookup(fresh.actor).p.distance==12)
assert(not m:command('all|0|save|'..P.encode(p)).ok)
store.fail=true;assert(not m:command('mu|1|inherit|').ok and m.settingsRevision==1);store.fail=false
local nextM=M.new(o);assert(nextM.settingsRevision==1 and nextM.profiles.mu.distance==12)
assert(m:command('mu|1|inherit|').ok and not m.profiles.mu)
local oldCommand=rb.id..'|'..rb.rev..'|recall|'
current={};world='session2';tick();assert(not m:command(oldCommand).ok and not m:lookup(old))
ready=false;assert(not m:command('all|2|save|'..P.encode(p)).ok)
print('PASS companion lifecycle: five policies, independent cards, ownership, duplicate/unknown outcomes, cancellation, healing, scopes, persistence and session fencing')