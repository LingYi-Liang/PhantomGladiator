package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Difficulty=require('spawn_difficulty')
local SLOTS={'Handicapped','Easy','Normal','Hard','Nightmare'}
local nextAddress=0
local function object(fields)
    nextAddress=nextAddress+1;local address=nextAddress
    fields.IsValid=function()return true end
    fields.GetAddress=function()return address end
    return fields
end
local configs={};for _,slot in ipairs(SLOTS)do configs[slot]=object({name=slot})end
-- A unit like BP_RenewalNPC_C: five slots, each pointing at its own difficulty's config.
local function unit(options)
    options=options or {}
    local fields={}
    if not options.noSlots then for _,slot in ipairs(SLOTS)do fields['Global Config '..slot]=configs[slot]end end
    local actor=object({})
    return setmetatable(actor,{__index=fields,__newindex=function(_,k,v)
        if options.stuck then return end
        fields[k]=v
    end})
end
local function harness()
    local h={files={},lines={}}
    h.io={open=function(name,mode)
        if mode=='w' and h.failSave then return nil end
        if mode=='r' and not h.files[name] then return nil end
        local text=h.files[name] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[name]=text end;return true end}
    end}
    h.adapter={read=function(_,_,field)return {base=100,current=({Health_Max=9000,Shachi_Max=400,Attack=70,ShachiAttack=33})[field]}end}
    function h.new()
        return Difficulty.new({path='R',io=h.io,log=function(s)h.lines[#h.lines+1]=s end,adapter=h.adapter,
            ready=function()return true end,getWorld=function()return object({})end,clock=function()return 0 end})
    end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end
StaticFindObject=function(path)
    assert(path=='/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary')
    return object({GetDiffcultMode=function()return 1 end})
end
local function test(name,fn)fn();print('ok - '..name)end

test('follows the game by default and touches nothing',function()
    local h=harness();local d=h.new();local a=unit()
    assert(d:status().level=='FOLLOW' and d:status().game=='Easy')
    local r=d:prepare(a,'/Game/A.A_C')
    assert(r.ok and not r.applied)
    for _,slot in ipairs(SLOTS)do assert(a['Global Config '..slot]==configs[slot])end
    d:verify(a,'/Game/A.A_C')
    assert(h.all():find('难度=游戏Easy',1,true) and h.all():find('Attack=70',1,true),'stats are logged for comparison')
end)

test('a chosen difficulty points every slot at that config and reads back after spawn',function()
    local h=harness();local d=h.new()
    local r=d:set('HARD')
    assert(r.ok and h.files['R/spawn-difficulty.tsv']=='SpawnDifficultyV1\tHARD\n')
    local a=unit();r=d:prepare(a,'/Game/A.A_C')
    assert(r.ok and r.applied)
    for _,slot in ipairs(SLOTS)do assert(a['Global Config '..slot]==configs.Hard,slot)end
    d:verify(a,'/Game/A.A_C')
    assert(h.all():find('槽位=5/5',1,true) and h.all():find('生成后槽位读回=5/5',1,true))
    assert(d:status().applied==1 and d:status().level=='HARD')
    assert(h.new():status().level=='HARD','the choice survives a mod reload')
end)

test('units without per-difficulty configs and unknown tokens are left alone',function()
    local h=harness();local d=h.new();d:set('EASY')
    local r=d:prepare(unit({noSlots=true}),'/Game/B.B_C')
    assert(r.ok and not r.applied and d:status().skipped==1)
    r=d:set('INSANE');assert(not r.ok and d:status().level=='EASY')
end)

test('a write that does not read back is undone and the spawn keeps the game difficulty',function()
    local h=harness();local d=h.new();d:set('NIGHTMARE')
    local a=unit({stuck=true});local r=d:prepare(a,'/Game/C.C_C')
    assert(not r.ok and not r.applied and r.rollback_verified and d:status().failures==1)
    for _,slot in ipairs(SLOTS)do assert(a['Global Config '..slot]==configs[slot])end
end)

test('a save that fails does not switch',function()
    local h=harness();local d=h.new();h.failSave=true
    assert(not d:set('HARD').ok and d:status().level=='FOLLOW')
    h.failSave=false;h.files['R/spawn-difficulty.tsv']='garbage';assert(h.new():status().level=='FOLLOW')
end)
print('spawn_difficulty: PASS')
