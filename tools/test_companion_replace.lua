package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local P=require('companion_profile')
arg[2]='fixture';local fixture=dofile('tools/test_arena_controller.lua');arg[2]=nil
local function trial(cause)
    local time=0;local f=fixture({now=function()return time end});local o=f.options;local children={};local destroyed={};local serial=0
    f.catalog.registerPath=function(_,p)return {path=p}end
    f.catalog.resolvePath=function(_,p)return f.cls,nil,{path=p}end
    o.getWorld=function()return f.world end
    o.activate=function(a,p,team,escort,spec)
        assert(team=='companion' and spec);return cause~='activate' or serial==1
    end
    o.spawnClass=function(_,t,w,entry,team)
        assert(w==f.world and team=='companion')
        serial=serial+1
        if serial==2 and cause=='story' then return nil,'story gate','not_started' end
        if serial==2 and cause=='uncertain' then return nil,'native result missing','uncertain' end
        return {alive=true,name='unit'..serial,path=entry.path}
    end
    o.finishSpawn=function(a)return cause~='finish' or a.name=='unit1' end
    o.companionTransfer=function(r,w)return {transform={Translation={X=10,Y=0,Z=0}}}end
    o.companionRestore=function()return cause~='resources' and cause~='rollback-pending','health readback failed' end
    o.companionCommitReady=function()return cause~='late-hit' end
    o.companionChildren=function(who)return children[who] or {} end
    o.destroy=function(a)
        if cause=='old-kept' and a.name=='unit1' or cause=='rollback-pending' and a.name=='unit2' then return end
        a.alive=false;destroyed[a]=true
    end
    assert(f.arena:spawn(P.first,'companion',1,true,true).ok)
    assert(#f.arena:companionSquad()==1 and f.arena:companionSquad()[1].dual)
    local original=f.arena:members()[1];assert(original.dual and original.class_path==P.first)
    local child={name='stand',alive=true};children[original.actor]={child}
    local result=f.arena:replaceCompanion(original,2,'manual',{})
    local members=f.arena:members();assert(#members==1)
    if not cause then
        assert(result.key==tostring(result.actor) and result.name==result.actor.name)
        assert(result.ok and members[1].actor==result.actor and members[1].class_path==P.second and destroyed[original.actor] and destroyed[child])
    else
        assert(not result.ok and members[1].actor==original.actor and original.actor.alive and child.alive)
        if cause=='uncertain' or cause=='rollback-pending' then assert(result.uncertain) end
        if cause=='rollback-pending' then
            assert(not f.arena:recoverCompanionCleanup());time=2
            local calls=0
            o.destroy=function(a)
                calls=calls+1
                if calls<5 then f.arena:recoverCompanionCleanup() end
                a.alive=false
            end
            assert(f.arena:recoverCompanionCleanup())
            print('MEASURE reentrant destruction: native destroy requests='..calls)
            assert(calls==1)
        end
    end
end
trial()
for _,problem in ipairs({'story','uncertain','finish','activate','resources','late-hit','old-kept','rollback-pending'})do trial(problem) end
do
    local f=fixture();local o=f.options
    local queens,children={},{};local groups,scans,now=0,0,0
    f.catalog.registerPath=function(_,path)return {path=path} end
    f.catalog.resolvePath=function(_,path)return f.cls,nil,{path=path} end
    o.getWorld=function()return f.world end;o.now=function()return now end
    local fail=false
    o.companionChildren=function(actor)scans=scans+1;if fail then return nil end;return children[actor] end
    o.companionChildGroups=function(actors,world)
        assert(world==f.world);groups=groups+1;if fail then return nil end
        local out={}
        for _,actor in ipairs(actors)do out[tostring(actor)]=children[actor] end
        return out
    end
    for _=1,12 do
        assert(f.arena:spawn(P.second,'companion',1,true,true).ok)
        local actor=f.actors[#f.actors];queens[#queens+1]=actor
        children[actor]={{alive=true,name='stand '..#queens}}
    end
    fail=true
    assert(not f.arena:clearCompanions().ok)
    for _=1,10 do f.arena:recoverCompanionCleanup() end
    print(('MEASURE 12 queens, failed group scan: group scans=%d single scans=%d'):format(groups,scans))
    assert(groups==1 and scans==0)
    for _,actor in ipairs(queens)do assert(actor.alive and children[actor][1].alive) end
    fail=false;now=5;assert(f.arena:recoverCompanionCleanup())
    assert(groups==2 and scans==0)
    for _,actor in ipairs(queens)do assert(not actor.alive and not children[actor][1].alive) end
    assert(#f.arena:members()==0)
end
print('PASS companion actor replacement, children, story refusal, and every staged rollback')