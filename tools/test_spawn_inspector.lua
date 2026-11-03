local Inspector=dofile('Mods/PhantomGladiator/Scripts/spawn_inspector.lua')
local function fixture()
    local lookups,logs=0,{}
    local nextID=0
    local function object(name,fields)
        nextID=nextID+1
        local o=fields or {};o.id=nextID;o.alive=true
        function o:IsValid() return self.alive end
        function o:GetAddress() assert(self.alive);return self.id end
        function o:GetFullName() assert(self.alive);return name end
        return o
    end
    local path='/Test/Unit.Unit_C'
    local cls=object('BlueprintGeneratedClass '..path,{IsAnyClass=function() return true end})
    local world,other=object('World'),object('Other')
    local row={ToString=function() return 'ActualRow17' end}
    local actor=object('Actor',{CharacterName=row,GetClass=function() return cls end,
        IsActorBeingDestroyed=function(self) return self.destroying or false end})
    local subsystem=object('Subsystem',{GetOuter=function() return world end,
        GetNPCClassByName=function(_,name) assert(name==row);lookups=lookups+1;return cls end})
    local candidates={subsystem}
    local inspector=Inspector.new({canSpawn=function(p) return p==path end,
        findAll=function(kind) assert(kind=='PBZSpawnSubsystem');return candidates end,
        log=function(line) logs[#logs+1]=line end})
    return {inspector=inspector,actor=actor,cls=cls,world=world,other=other,subsystem=subsystem,
        candidates=candidates,logs=logs,calls=function() return lookups end}
end
local f=fixture()
local ok,row,path=f.inspector:inspect(f.actor,f.world)
assert(ok and row=='ActualRow17' and path=='/Test/Unit.Unit_C' and f.calls()==1)
assert(table.concat(f.logs,'\n'):find('exact_match=true',1,true))
f=fixture();f.actor.CharacterName={ToString=function() return 'None' end}
assert(not f.inspector:inspect(f.actor,f.world) and f.calls()==0,'never guess a character row')
f=fixture();f.subsystem.GetOuter=function() return f.other end
assert(not f.inspector:inspect(f.actor,f.world) and f.calls()==0,'never query a different World subsystem')
f=fixture();f.actor.destroying=true
f.actor.GetClass=function() error('must not access destroying actor') end
assert(not f.inspector:inspect(f.actor,f.world) and f.calls()==0)
f=fixture();f.cls.alive=false
assert(not f.inspector:inspect(f.actor,f.world) and f.calls()==0)
f=fixture();f.subsystem.GetNPCClassByName=function() return f.other end
assert(not f.inspector:inspect(f.actor,f.world),'non-class return must not validate mapping')
f=fixture();f.subsystem.GetNPCClassByName=function() error('return conversion unavailable') end
assert(not f.inspector:inspect(f.actor,f.world),'failed mapping must remain unknown')
f=fixture();f.actor.alive=false
f.inspector:combat(f.actor,f.actor,'invalid')
assert(f.calls()==0)
print('spawn_inspector: PASS (real row only, exact class, current World, invalid/destroying guards, unknown returns)')
