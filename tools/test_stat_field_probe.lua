package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Probe=require('stat_field_probe')
local Fields={'Level','Health','Health_Max','Shield','Shield_Max','Attack','FinalWalkSpeed','Locked','Ignite_Accumulation','Infliction_Max','Shy'}
local function harness()
    local h={logs={},writes={},alive=true}
    local unit={Level=0,Health=100,Health_Max=100,Shield=0,Shield_Max=0,Attack=20,FinalWalkSpeed=300,Locked=7,
        Ignite_Accumulation=0,Infliction_Max=100,Shy=2}
    h.unit=unit
    local adapter={}
    function adapter:read(_,field)
        if not h.alive or unit[field]==nil or field=='Shy' then return nil,'missing '..field end
        return {base=unit[field],current=unit[field]}
    end
    function adapter:writeBase(_,field,value)
        h.writes[#h.writes+1]=field..'='..value
        if field=='Locked' then return true end                       -- the game ignores it
        if field=='Health' then value=math.min(value,unit.Health_Max) end
        if field=='Shield' then value=math.min(value,unit.Shield_Max) end
        unit[field]=value
        if field=='Level' and value~=0 then unit.Attack=unit.Attack+1 end  -- a side effect on another field
        return true
    end
    function adapter:nativeValue(_,field)return unit[field] end
    function adapter:via(field)return field=='Attack' and 'field' or 'effect' end
    h.probe=Probe.new({adapter=adapter,fields=Fields,perTick=4,log=function(s)h.logs[#h.logs+1]=s end})
    function h:run(n)for _=1,n do self.probe:tick()end end
    function h:line(pattern)for _,s in ipairs(self.logs)do if s:find(pattern,1,true) then return s end end end
    return h
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('every field written, held a tick, read back and restored; summary and side-effect diff',function()
    local h=harness()
    h:run(3);assert(h.probe:status().state=='idle' and #h.writes==0,'nothing before a unit')
    assert(h.probe:start({},'A') and not h.probe:start({},'B'),'one unit per load')
    h:run(3);assert(h.probe:start({},'C')==false,'a later summon while the probe runs is left alone')
    h:run(40)
    assert(h.probe:status().state=='done',h.logs[#h.logs])
    assert(h.probe:start({},'D')==false,'a later summon after the probe is left alone')
    -- Level's side effect lands before Attack's own test in the same chunk.
    assert(h:line('Attack 方式=field 原值=21/21 写入=31.5'):find('结果=ok',1,true))
    assert(h:line('Locked '):find('结果=unchanged',1,true))
    assert(h:line('Shy 不可读'),'unreadable fields are named')
    -- Bounded currents go last; a zero maximum is raised for the test and restored.
    assert(h:line('临时把 Shield_Max 从 0 提到 2'),'Shield gets room for its test value')
    assert(h:line('Shield 方式=effect 原值=0/0 写入=1'):find('结果=ok',1,true))
    assert(h:line('恢复 Shield_Max 到 0 读回=0 恢复=true'))
    assert(h:line('Health 方式=effect 原值=100/100 写入=50'):find('结果=ok',1,true))
    assert(h.unit.Health==100 and h.unit.Shield==0 and h.unit.Shield_Max==0 and h.unit.Level==0)
    local summary=h:line('汇总')
    assert(summary:find('ok=9',1,true) and summary:find('unchanged=1',1,true) and summary:find('unreadable=1',1,true),summary)
    -- Writing Level moved Attack; the diff names it and puts it back.
    assert(h:line('与测试前对比：1 项不同：Attack 20→21 恢复后=20') and h.unit.Attack==20)
    local free=0;for i,w in ipairs(h.writes)do if w:find('^Shield=') or w:find('^Health=') or w:find('^Ignite_Accumulation=') then free=i;break end end
    for i=1,free-1 do assert(not h.writes[i]:find('^Health=') ,'bounded currents come after the other fields')end
end)
test('a unit that goes away stops the probe',function()
    local h=harness();h.probe:start({},'A');h:run(2);h.alive=false;h:run(3)
    assert(h.probe:status().state=='aborted' and h:line('中止'))
end)
print('stat_field_probe: PASS ('..count..' write, hold, readback, restore and abort regressions)')
