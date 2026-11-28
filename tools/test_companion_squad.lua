package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Squad=require('companion_squad')
local P=require('companion_profile')
local A='/Game/One/BP_One.BP_One_C'
local B='/Game/Two/BP_Two.BP_Two_C'
local pref,party='rt/companion-squad-settings.tsv','rt/companion-squad.tsv'
local first,second=string.rep('a',24),string.rep('b',24)
local files,now,world,ready,live,calls,reads={},100,'process1-map1',true,{},{},0
local squad,refusal,uncertain,failWrite,busy
local function summon(path,dual)
    live[#live+1]={path=path,dual=dual}
    squad:added(path,dual,1)
end
local function make()
    return Squad.new({path='rt',clock=function()return now end,
        session=function()return {game_ready=ready,game_world=world}end,
        members=function()reads=reads+1;return live end,
        read=function(k)return files[k]end,write=function(k,v)
            if failWrite then return false end
            files[k]=v;return true
        end,busy=function()return busy end,spawn=function(path,dual)
            calls[#calls+1]={path,dual}
            if uncertain then return {ok=false,uncertain=true,spawned_count='unknown'} end
            if path==refusal then return {ok=false,spawned_count=0,message='native condition'} end
            summon(path,dual);return {ok=true,spawned_count=1}
        end})
end
local function step(n)for _=1,n do now=now+1;squad:tick() end end
local function newWorld(key)world=key;live={};calls={} end
local function enable(gen)files[pref]='PGCR1\t1\t'..gen..'\n' end
local function copies(path,dual)
    local n=0;for _,r in ipairs(calls)do if r[1]==path and r[2]==dual then n=n+1 end end
    return n
end
squad=make();step(5);summon(A,false)
assert(not squad.enabled and not files[party] and reads==0)
enable(first);step(2)
assert(squad.enabled and squad.total==1 and reads==1 and #calls==0)
summon(A,false);summon(P.second,true);summon(P.second,false);summon(B,false)
assert(squad.total==5 and files[party]:find('dual\t1\t'..P.first,1,true))
-- Pruning, a dead player and several seconds of an empty current world do not wipe the party or revive it.
local saved=files[party];live={};ready=false;step(4);ready=true;step(5)
assert(#calls==0 and files[party]==saved and reads==1)
-- Map transition, manual summons of the same kind, and a busy camera before automatic replay.
newWorld('process1-map2');summon(A,false);busy=true;step(5)
assert(#calls==0 and squad.total==5)
busy=false;step(1);assert(#calls==1)
step(9)
assert(copies(A,false)==1 and copies(P.first,true)==1 and copies(P.second,false)==1 and copies(B,false)==1)
assert(#calls==4 and squad.total==5 and squad.state=='remembered')
-- A survivor can arrive after the first ready heartbeat during seamless travel.
newWorld('process1-stream');step(1)
live={{path=A,dual=false},{path=P.second,dual=true}}
step(8)
assert(#calls==3 and copies(A,false)==1 and copies(P.first,true)==0)
-- The stable world key is shared by a Lua hot reload. Lost actor handles must not cause a second team.
squad=make();live={};step(6);assert(#calls==3 and squad.total==5)
newWorld('process2-map1');refusal=B;step(10)
assert(#calls==5 and squad.state=='partial' and squad.total==5);step(15);assert(#calls==5)
refusal=nil;newWorld('process2-map2');uncertain=true;step(8)
assert(#calls==1 and squad.state=='uncertain');step(10);assert(#calls==1)
-- A confirmed dismissal cancels an in-progress restoration and survives the next process.
uncertain=false;newWorld('process3-map1');step(3);assert(#calls==1)
assert(squad:dismiss() and squad.total==0);live={};step(5);assert(#calls==1)
squad=make();newWorld('process4-map1');step(8);assert(#calls==0 and squad.total==0)
-- A write failure cannot cause automatic spawns before the new world's claim is durable.
summon(B,false);newWorld('process4-map2');failWrite=true;step(7)
assert(#calls==0 and squad.state=='save_error')
failWrite=false;step(7);assert(#calls==1 and squad.total==1)
-- Switching off just before the next spawn, even with a large queue, takes effect on that step.
summon(A,false);newWorld('process5-map1');step(3);assert(#calls==1)
files[pref]='PGCR1\t0\t'..second..'\n';step(1);assert(not squad.enabled and #calls==1)
newWorld('process6-map1');enable(string.rep('c',24));step(9);assert(#calls==0 and squad.total==0)
-- A damaged matching-generation snapshot is never partially replayed.
files[party]='PGCS1\t'..string.rep('c',24)..'\told\nunit\t2\t'..A..'\nunit\t1\t../broken\n'
squad=make();step(8);assert(squad.state=='read_error' and #calls==0)
-- Direct summons from the actual controller include neither escorts nor adopted actors or another team.
arg[2]='fixture';local fixture=dofile('tools/test_arena_controller.lua');arg[2]=nil
local entries={}
local f=fixture({onCompanionSummoned=function(path,dual,n)entries[#entries+1]={path,dual,n}end})
f.catalog.resolvePath=function(_,path)return f.cls,nil,{path=path}end
f.options.escortsFor=function()return {{path=B,count=2}}end
f.options.resolveEscort=function(path)return f.cls,nil,{path=path}end
assert(f.arena:spawn(A,'companion',2,true).ok)
assert(#entries==1 and entries[1][1]==A and entries[1][3]==2)
assert(#f.arena:companionSquad()==2 and #f.actors==6)
assert(f.arena:adoptSummon({alive=true,name='skill helper'},f.actors[1],B,'fixture').ok)
assert(f.arena:spawn(A,'red',1,true).ok)
assert(#entries==1 and #f.arena:companionSquad()==2)
f.options.activate=function()return false end
assert(not f.arena:spawn(A,'companion',1,true).ok and #entries==1 and #f.arena:companionSquad()==2)
local other={alive=true}
f.options.getWorld=function()return other end
assert(#f.arena:companionSquad()==0)
f.options.inCompanionWorld=function(actor)return actor==f.actors[1]end
assert(#f.arena:companionSquad()==1,'owned companions that survive streaming must count in the new world')
print('companion_squad: opt-in, same-world reload, ready gate, duplicate counts, dual variants, cancellation, persistence and partial failures passed')
