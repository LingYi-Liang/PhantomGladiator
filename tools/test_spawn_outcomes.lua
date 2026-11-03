-- Reproduce native-call ambiguity and ownership loss without running the game.
local Arena=dofile('Mods/PhantomGladiator/Scripts/arena_controller.lua')
local function fixture(mode)
    local actors,calls,synced={},0,{}
    local object={alive=true}
    local catalog={}
    function catalog:refresh() end
    function catalog:selected() return {path='/Test/Unit.Unit_C'} end
    function catalog:resolveSelected() return object end
    local options={catalog=catalog,canSpawn=function() return true end,
        valid=function(o) return o and o.alive==true end,
        name=function() return 'unit' end,hp=function() return 400 end,
        combatReady=function() return true end,
        getPlayer=function() return object end,getWorld=function() return object end,
        getLocation=function() return {X=0,Y=0,Z=0} end,
        getForward=function() return {X=1,Y=0,Z=0} end,
        spawnClass=function()
            calls=calls+1
            local actor={alive=true}; actors[#actors+1]=actor
            if mode=='throws' then error('native call executed; return conversion failed') end
            if mode=='nil' then return nil,'native return unavailable' end
            return actor
        end,
        onUnitsChanged=function(units) synced=units end,
        finishSpawn=function(actor)
            local owned=false
            for _,unit in ipairs(synced) do if unit.actor==actor then owned=true end end
            assert(owned,'ownership must precede FinishSpawn')
            if mode=='finish' then error('FinishSpawn failed') end
            return true
        end,
        activate=function() error('failed/unknown spawn must never activate') end,
        restore=function() return true end,
        destroy=function(actor) actor.alive=false end}
    return Arena.new(options),actors,function() return calls end,options
end
for _,mode in ipairs({'throws','nil'}) do
    local arena,actors,calls=fixture(mode)
    local result=arena:spawn(nil,'blue',3)
    assert(calls()==1,'ambiguous native spawn must stop the batch immediately')
    assert(result.ok==false and result.uncertain==true and result.spawned_count=='unknown',
        'native return failure must not claim zero actors created')
    assert(not arena:spawn().ok and calls()==1,'unknown ownership must block further spawn')
    assert(not arena:start().ok)
    assert(not arena:stop().ok,'cleaning known actors cannot resolve an unowned native result')
    assert(not arena:spawn().ok and calls()==1,'F4 must not clear unknown native results')
end
local arena,actors,calls=fixture('finish')
local result=arena:spawn(nil,'blue',3)
assert(not result.ok and calls()==1 and result.spawned_count==1)
assert(arena:status().owned_records==1,'FinishSpawn failure must retain the actor for cleanup')
assert(not arena:spawn().ok and not arena:start().ok)
assert(arena:stop().ok and not actors[1].alive)
arena,actors,calls,options=fixture('ordinary')
options.activate=function() return true end
options.spawnLimits=function() return {max_count=1,max_live=2} end
assert(not arena:spawn(nil,'blue',2).ok and calls()==0,'test cap must run before native spawn')
assert(arena:spawn(nil,'blue',1).ok and arena:spawn(nil,'red',1).ok)
assert(not arena:spawn(nil,'red',1).ok and calls()==2,'test live cap must block the third actor')
options.canBattle=function() return false,'unit unsuitable for a damage baseline' end
local refused=arena:start()
assert(not refused.ok and refused.message=='unit unsuitable for a damage baseline',
    'excluded baseline must stop before relationship or attack mutations')
assert(arena:stop().ok)
print('spawn_outcomes: PASS (stop ambiguous batches, truthful unknown count, own before finish, retain cleanup)')
