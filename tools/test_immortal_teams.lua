package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Immortal=require('immortal_teams')
local address=0
local function actor(name)
    address=address+1;local a=address
    return {IsValid=function()return true end,GetAddress=function()return a end,
        GetClass=function()return {GetFName=function()return {ToString=function()return name..'_C' end}end}end}
end
local function harness(files)
    local h={files=files or {},lines={},writes={},attrs={},members={},ready=true}
    h.io={open=function(path,mode)
        if mode=='w' and h.failSave then return nil end
        if mode=='r' and h.files[path]==nil then return nil end
        local text=h.files[path] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[path]=text end;return true end}
    end}
    -- Per-actor attributes; a stuck field ignores writes, like a floor the game holds elsewhere.
    function h.unit(name,hp,floor)
        local a=actor(name)
        h.attrs[a]={Health={base=hp,current=hp},Health_Min={base=floor or 0,current=floor or 0}}
        return a
    end
    h.stats={read=function(_,a,field)local v=h.attrs[a] and h.attrs[a][field];return v and {base=v.base,current=v.current} end,
        writeBase=function(_,a,field,value)
            h.writes[#h.writes+1]=field..'='..value
            if h.stuck==field then return true end
            h.attrs[a][field]={base=value,current=value};return true
        end}
    function h.new()
        return Immortal.new({path='R',io=h.io,attributes=h.stats,log=function(s)h.lines[#h.lines+1]=s end,
            members=function()return h.members end,collect=function()return h.npcs or {} end,ready=function()return h.ready end})
    end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end

-- Settings: off by default, saved with readback, a failed save keeps the old value, bad input refused.
do
    local h=harness()
    local im=h.new()
    local s=im:status()
    assert(not s.blue and not s.red and not s.companion and s.locked==0)
    local r=im:set('blue','ON')
    assert(r.ok and r.message=='蓝方不倒下已开启' and im:status().blue)
    assert(h.files['R/immortal-teams.tsv']=='ImmortalTeamsV1\tblue=1\tred=0\tcompanion=0\n',h.files['R/immortal-teams.tsv'])
    assert(not im:set('neutral','ON').ok,'no-team units are not offered')
    assert(not im:set('red','YES').ok)
    h.failSave=true
    assert(not im:set('red','ON').ok and not im:status().red,'a failed save keeps the old value')
    h.failSave=false
    assert(h.new():status().blue,'a new Lua instance reads the saved switch')
end

-- Locking: a unit of a switched-on team gets a floor at its HP, read back and journaled; the other
-- team and no-team units are left alone; a dead or unreadable unit waits.
local h=harness()
local im=h.new()
local mob=h.unit('BP_Monster_BaiheDisciple_Knife',640)
local boss=h.unit('BP_Monster_AHua_GuiTouDao',104652)
local solo=h.unit('BP_Monster_MoTian',12000)
local fallen=h.unit('BP_Monster_MaleThug',0)
h.members={{actor=mob,team='blue'},{actor=boss,team='red'},{actor=solo,team='neutral'},{actor=fallen,team='blue'}}
assert(im:set('blue','ON').ok)
im:tick()
assert(h.attrs[mob].Health_Min.base==640 and h.attrs[boss].Health_Min.base==0 and h.attrs[solo].Health_Min.base==0)
assert(h.attrs[fallen].Health_Min.base==0,'a fallen unit is not locked')
assert(im:status().locked==1,h.all())
assert(h.all():find('锁定 蓝方 unit=BP_Monster_BaiheDisciple_Knife HP=640.0 原下限=0.0 写入=true 读回=640.0',1,true),h.all())
local key=tostring(mob.GetAddress())
assert(h.files['R/immortal-floors.tsv']=='ImmortalFloorsV1\n'..key..'\t0.000\t640.000\n',h.files['R/immortal-floors.tsv'])
local writes=#h.writes
im:tick()
assert(#h.writes==writes,'a held floor is not written again')

-- Holding: a floor the game lowered is raised again; health that got below the floor is filled back.
h.attrs[mob].Health_Min={base=640,current=1}
im:tick()
assert(h.attrs[mob].Health_Min.current==640 and im:status().relocks==1,h.all())
h.attrs[mob].Health={base=300,current=300}
im:tick()
assert(h.attrs[mob].Health.current==640 and im:status().breaches==1,h.all())
assert(h.all():find('血量低于下限 unit=BP_Monster_BaiheDisciple_Knife HP=300.0',1,true))

-- Units joining later are locked on the next tick; a unit that leaves is forgotten.
local late=h.unit('BP_Monster_BaiheDisciple_FishRod',700)
h.members[#h.members+1]={actor=late,team='blue'}
im:tick()
assert(im:status().locked==2 and h.attrs[late].Health_Min.base==700)
table.remove(h.members)
im:tick()
assert(im:status().locked==1 and h.all():find('单位已离场，不再跟踪 unit=BP_Monster_BaiheDisciple_FishRod',1,true))
assert(not h.files['R/immortal-floors.tsv']:find(tostring(late.GetAddress())..'\t',1,true))

-- Turning the team off restores each unit's own floor.
assert(im:set('blue','OFF').ok)
im:tick()
assert(h.attrs[mob].Health_Min.base==0 and im:status().locked==0,h.all())
assert(h.files['R/immortal-floors.tsv']=='ImmortalFloorsV1\n')
assert(h.all():find('恢复（已关闭不倒下）unit=BP_Monster_BaiheDisciple_Knife 下限→0.0 写入=true 读回=0.0',1,true))

-- Companions can be locked too.
local follower=h.unit('BP_Monster_MoTian',12000)
h.members={{actor=follower,team='companion'}}
assert(im:set('companion','ON').ok)
im:tick()
assert(h.attrs[follower].Health_Min.base==12000 and im:status().locked==1)

-- A floor that never reads back: the original is put back after each try, three tries, one failure.
do
    local s=harness()
    local stuck=s.unit('BP_Monster_Vessel_Child',400)
    s.members={{actor=stuck,team='red'}}
    s.stuck='Health_Min'
    local x=s.new()
    assert(x:set('red','ON').ok)
    for _=1,5 do x:tick() end
    local tries=0
    for _,w in ipairs(s.writes)do if w=='Health_Min=400' then tries=tries+1 end end
    assert(tries==3 and x:status().failures==1 and x:status().locked==0,s.all())
    assert(s.all():find('放弃锁定 unit=BP_Monster_Vessel_Child',1,true))
end

-- Nothing happens before the game is ready.
do
    local s=harness()
    local unit=s.unit('BP_Monster_MaleThug',500)
    s.members={{actor=unit,team='blue'}}
    s.ready=false
    local x=s.new();x:set('blue','ON');x:tick()
    assert(s.attrs[unit].Health_Min.base==0 and #s.writes==0)
end

-- After a reload: units the old journal names that still carry exactly the raised floor get their own
-- floor back; one whose floor changed since is left alone; the journal is emptied either way.
do
    local s=harness()
    local left=s.unit('BP_Monster_BaiheDisciple_Knife',640,640)
    local changed=s.unit('BP_Monster_AHua_GuiTouDao',9000,5)
    s.files['R/immortal-floors.tsv']='ImmortalFloorsV1\n'..tostring(left.GetAddress())..'\t0.000\t640.000\n'
        ..tostring(changed.GetAddress())..'\t0.000\t9000.000\n'..'999999\t0.000\t100.000\n'
    s.npcs={left,changed}
    local x=s.new()
    x:tick()
    assert(s.attrs[left].Health_Min.base==0 and s.attrs[changed].Health_Min.base==5,s.all())
    assert(s.files['R/immortal-floors.tsv']=='')
    assert(s.all():find('检查上次留下的不倒下单位：记录3只，恢复1只',1,true),s.all())
    local count=#s.lines
    x:tick()
    assert(#s.lines==count,'the journal is checked once per Lua lifetime')
end

-- With a health reader, a locked unit at its lock costs one read per tick and no attribute reads; once
-- its health is below the lock the full check refills it.
do
    local s=harness()
    local unit=s.unit('BP_Monster_FemaleThug_TwinHoe',19767.6)
    s.members={{actor=unit,team='blue'}}
    local reads=0
    local real=s.stats.read
    s.stats.read=function(...)reads=reads+1;return real(...)end
    local x=Immortal.new({path='R',io=s.io,attributes=s.stats,log=function(l)s.lines[#s.lines+1]=l end,
        members=function()return s.members end,ready=function()return true end,
        hp=function(actor)return s.attrs[actor].Health.current end})
    x:set('blue','ON');x:tick()
    local afterLock=reads
    for _=1,5 do x:tick() end
    assert(reads==afterLock,'five ticks at the lock: no attribute reads')
    s.attrs[unit].Health={base=900,current=900}
    x:tick()
    assert(reads>afterLock and s.attrs[unit].Health.current==19767.6 and x:status().breaches==1,s.all())
end

-- Unloading writes nothing; the instance stops.
do
    local s=harness()
    local unit=s.unit('BP_Monster_MaleThug',500)
    s.members={{actor=unit,team='blue'}}
    local x=s.new();x:set('blue','ON');x:silence();x:tick()
    assert(#s.writes==0)
end
print('immortal_teams: PASS (settings, lock, hold, refill, join/leave, release, companions, retries, ready gate, reload journal, unload)')
