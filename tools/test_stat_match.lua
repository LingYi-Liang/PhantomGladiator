package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Match=require('stat_match')
local Fields={'Attack','ShachiAttack','Resistance_Physical','Health_Max','Shachi_Max'}
local function harness()
    local h={files={},writes={},snapshots=0,logs={}}
    local fs={open=function(name,mode)
        if mode=='w' and h.failSave then return nil end
        if mode=='r' and not h.files[name] then return nil end
        local text=h.files[name] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[name]=text end;return true end}
    end}
    function h:actor(hp,shachi,attack)
        local actor={values={},mods={}}
        -- Level-1 values as a level-10ish unit would have them: what the game works out damage from.
        for field,value in pairs({Health=hp,Health_Max=hp,Shachi=shachi,Shachi_Max=shachi,Attack=attack,ShachiAttack=15,Resistance_Physical=0.2,
                Health_Max_Lv1=hp/10,Shachi_Max_Lv1=shachi/5,Attack_Lv1=attack/2,ShachiAttack_Lv1=10,Infliction_Max_Lv1=80})do
            actor.values[field]={base=value,current=value}
        end
        return actor
    end
    local adapter={}
    function adapter:read(actor,field)
        local v=actor.values[field]
        return v and {base=v.base,current=v.current} or nil,'missing '..field
    end
    function adapter:snapshot(actor)
        h.snapshots=h.snapshots+1
        local result={}
        for field,v in pairs(actor.values)do result[field]={base=v.base,current=v.current}end
        return result
    end
    function adapter:writeBase(actor,field,value)
        h.writes[#h.writes+1]={actor=actor,field=field,value=value}
        local mod=actor.mods[field] or {}
        if field=='Health' then value=math.min(value,actor.values.Health_Max.current)end
        if field=='Shachi' then value=math.min(value,actor.values.Shachi_Max.current)end
        actor.values[field]={base=value,current=mod.fixed or value*(mod.mul or 1)+(mod.add or 0)}
        if field=='Health_Max' and actor.values.Health.current>value then actor.values.Health.current=value;actor.values.Health.base=value end
        if field=='Shachi_Max' and actor.values.Shachi.current>value then actor.values.Shachi.current=value;actor.values.Shachi.base=value end
        return true
    end
    function adapter:nativeValue(actor,field)
        if h.failNative then return nil end
        return actor.values[field].current
    end
    h.options={path='memory',io=fs,adapter=adapter,fields=Fields,log=function(s)h.logs[#h.logs+1]=s end}
    h.match=Match.new(h.options);return h
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('default off, persisted switch, immutable first-spawn snapshot and full new resources',function()
    local h=harness();local a=h:actor(100,80,20);local b=h:actor(300,200,60)
    assert(h.match:onSpawn(a,'A').ok and h.snapshots==0 and #h.writes==0)
    assert(h.match:toggle().ok and h.match:onSpawn(a,'A').baseline)
    a.values.Health.current=30;a.values.Attack.current=100
    assert(h.match:onSpawn(b,'B').applied)
    assert(b.values.Health.current==100 and b.values.Shachi.current==80 and b.values.Attack.current==20)
    assert(a.values.Health.current==30 and a.values.Attack.current==100,'matching cannot mutate the baseline actor')
    local writes=#h.writes;b.values.Health.current=75
    h.match:roster({a,b});assert(#h.writes==writes and b.values.Health.current==75,'no periodic healing')
    local reloaded=Match.new(h.options);assert(reloaded:status().enabled and reloaded:status().baseline_unit=='','only switch persists')
end)
test('active multipliers are compensated without permanent override effects',function()
    local h=harness();h.match:toggle();h.match:onSpawn(h:actor(100,80,20),'A')
    local b=h:actor(100,80,10);b.mods.Attack={mul=2,add=5};b.values.Attack.current=25
    assert(h.match:onSpawn(b,'B').applied and math.abs(b.values.Attack.base-7.5)<0.0001 and b.values.Attack.current==20)
end)
test('unchanged base with a scaled current value uses a bounded calibration',function()
    local h=harness();h.match:toggle();h.match:onSpawn(h:actor(100,80,70),'A')
    local b=h:actor(100,80,70);b.mods.Attack={mul=1.2};b.values.Attack.current=84
    assert(h.match:onSpawn(b,'B').applied and math.abs(b.values.Attack.current-70)<0.001)
    local writes=0;for _,item in ipairs(h.writes)do if item.field=='Attack' then writes=writes+1 end end
    assert(writes<=3)
end)
test('clear resets the baseline; partial cleanup and switch-off do not rewrite actors',function()
    local h=harness();h.match:toggle();local a=h:actor(100,80,20);h.match:onSpawn(a,'A')
    h.match:roster({a});assert(h.match:status().baseline_unit=='A')
    h.match:roster({});assert(h.match:status().baseline_unit=='')
    local b=h:actor(200,150,45);assert(h.match:onSpawn(b,'B').baseline)
    h.match:toggle();local writes=#h.writes
    local c=h:actor(300,90,60);assert(h.match:onSpawn(c,'C').ok and #h.writes==writes and c.values.Health.current==300)
end)
test('unreachable native override fails and restores the original base',function()
    local h=harness();h.match:toggle();h.match:onSpawn(h:actor(100,80,20),'A')
    local b=h:actor(300,200,60);b.mods.Attack={fixed=90};b.values.Attack.current=90
    local result=h.match:onSpawn(b,'B')
    assert(not result.ok and result.rollback_verified and b.values.Attack.base==60 and b.values.Attack.current==90)
    assert(h.match:status().matched==0)
end)
test('failed independent readback restores maxima before restoring clamped resources',function()
    local h=harness();h.match:toggle();h.match:onSpawn(h:actor(100,80,20),'A')
    local b=h:actor(300,200,60);h.failNative=true
    local result=h.match:onSpawn(b,'B')
    assert(not result.ok and result.rollback_verified,'all modified values must roll back')
    assert(b.values.Health.current==300 and b.values.Shachi.current==200)
end)
test('failed settings readback cannot enable matching',function()
    local h=harness();h.failSave=true
    assert(not h.match:toggle().ok and not h.match:status().enabled)
end)
test('custom values come from the request of the named revision, are validated and persist',function()
    local h=harness()
    h.files['memory/stat-custom-request.tsv']='StatCustomV1\tR1\nHealth_Max\t50000\nAttack\t120\n'
    assert(not h.match:setMode('CUSTOM','R0').ok and h.match:status().mode=='game','another revision is refused')
    local r=h.match:setMode('CUSTOM','R1')
    assert(r.ok and r.message:find('血量上限=50000、攻击=120',1,true),r.message)
    local s=h.match:status()
    assert(s.mode=='custom' and s.enabled and s.custom_count==2 and s.custom.Health_Max==50000)
    assert(h.files['memory/stat-match-settings.tsv']=='StatMatchV2\tcustom\nHealth_Max\t50000\nAttack\t120\n',h.files['memory/stat-match-settings.tsv'])
    local reloaded=Match.new(h.options)
    assert(reloaded:status().mode=='custom' and reloaded:status().custom.Attack==120,'mode and values persist')
    for _,bad in ipairs({'Bogus\t5\n','Health_Max\t0\n','Attack\tabc\n','ShachiAttack\t-1\n',''})do
        h.files['memory/stat-custom-request.tsv']='StatCustomV1\tR2\n'..bad
        assert(not h.match:setMode('CUSTOM','R2').ok and h.match:status().custom.Health_Max==50000,'refused: '..bad)
    end
    assert(not h.match:setMode('ALL','').ok)
    -- Back to the game's numbers keeps the custom values for next time; the old switch goes to the first unit.
    assert(h.match:setMode('GAME','').ok and h.match:status().mode=='game' and h.match:status().custom_count==2)
    assert(h.match:toggle().ok and h.match:status().mode=='match')
    assert(h.match:toggle().ok and h.match:status().mode=='game')
end)
test('custom mode writes only the filled fields, with full bars for new maxima, field by field',function()
    local h=harness()
    h.files['memory/stat-custom-request.tsv']='StatCustomV1\tR1\nHealth_Max\t5000\nAttack\t33\n'
    assert(h.match:setMode('CUSTOM','R1').ok)
    local a=h:actor(100,80,20)
    local result=h.match:onSpawn(a,'A')
    assert(result.ok and result.applied and h.match:status().customized==1,result.message)
    assert(a.values.Health_Max.current==5000 and a.values.Health.current==5000 and a.values.Attack.current==33)
    assert(a.values.Shachi_Max.current==80 and a.values.ShachiAttack.current==15 and a.values.Resistance_Physical.current==0.2,'unfilled fields keep the unit value')
    -- A field the game holds (a fixed override) is rolled back and named; the others stay.
    local b=h:actor(300,200,60);b.mods.Attack={fixed=90};b.values.Attack.current=90
    local partial=h.match:onSpawn(b,'B')
    assert(partial.ok and partial.applied and partial.rejected[1]=='Attack' and #partial.rejected==1,partial.message)
    assert(b.values.Health_Max.current==5000 and b.values.Health.current==5000 and b.values.Attack.base==60 and b.values.Attack.current==90)
    assert(partial.message:find('1 项游戏没接受',1,true) and h.match:status().rejected[1]=='Attack')
    -- Nothing read back: every field is rolled back, maxima before their current values.
    h.failNative=true
    local c=h:actor(1000,500,70);local failed=h.match:onSpawn(c,'C')
    assert(not failed.ok and failed.rollback_verified and failed.message:find('自定义数值失败',1,true),failed.message)
    assert(c.values.Health_Max.current==1000 and c.values.Health.current==1000 and c.values.Attack.current==70)
    h.failNative=false
    -- Companions are excluded by main.lua; a later unit gets the same values.
    local d=h:actor(1000,500,70);assert(h.match:onSpawn(d,'D').applied and d.values.Health.current==5000)
end)
test('custom fields beyond the matched ones: maxima first, an explicit current kept, unreadable ones named',function()
    local h=harness()
    h.files['memory/stat-custom-request.tsv']='StatCustomV1\tR1\nHealth\t100\nShield\t50\nHealth_Max\t5000\n'
    assert(h.match:setMode('CUSTOM','R1').ok and h.match:status().custom_count==3 and h.match:status().custom_fields==223)
    local a=h:actor(300,80,20);local r=h.match:onSpawn(a,'A')
    assert(r.ok and a.values.Health_Max.current==5000 and a.values.Health.current==100,'the maximum is written before the current value')
    assert(#r.rejected==1 and r.rejected[1]=='Shield','an attribute this unit cannot read is named, not fatal')
    local wrote={};for _,w in ipairs(h.writes)do wrote[#wrote+1]=w.field end
    assert(table.concat(wrote,',')=='Health_Max_Lv1,Health_Max,Health',table.concat(wrote,','))
end)
test('custom HP and attack move their level-1 values by the same ratio; an explicit level-1 value wins',function()
    local h=harness()
    h.files['memory/stat-custom-request.tsv']='StatCustomV1\tR1\nHealth_Max\t5000\nAttack\t33\n'
    assert(h.match:setMode('CUSTOM','R1').ok)
    local a=h:actor(100,80,20);local r=h.match:onSpawn(a,'A')
    assert(r.ok and a.values.Health_Max_Lv1.current==500 and math.abs(a.values.Attack_Lv1.current-16.5)<1e-9,r.message)
    assert(a.values.Shachi_Max_Lv1.current==16 and a.values.ShachiAttack_Lv1.current==10,'untouched values keep their level-1 values')
    local linked;for _,s in ipairs(h.logs)do if s:find('联动1级值',1,true) then linked=s end end
    assert(linked and linked:find('Health_Max_Lv1 10→500',1,true),linked)
    h.files['memory/stat-custom-request.tsv']='StatCustomV1\tR2\nHealth_Max\t5000\nHealth_Max_Lv1\t7\n'
    assert(h.match:setMode('CUSTOM','R2').ok)
    local b=h:actor(100,80,20);assert(h.match:onSpawn(b,'B').ok and b.values.Health_Max_Lv1.current==7 and b.values.Health_Max.current==5000)
end)
test('equal stats copies the level-1 values, so matched units take and deal the same hits',function()
    local h=harness();h.match:toggle()
    local a=h:actor(100,80,20);assert(h.match:onSpawn(a,'A').baseline)
    local b=h:actor(300,200,60);assert(h.match:onSpawn(b,'B').applied)
    for _,field in ipairs({'Health_Max_Lv1','Shachi_Max_Lv1','Attack_Lv1','ShachiAttack_Lv1','Infliction_Max_Lv1'})do
        assert(b.values[field].current==a.values[field].current,field)
    end
end)
test('the v1 switch file still reads as matching',function()
    local h=harness();h.files['memory/stat-match-settings.tsv']='StatMatchV1\t1\n'
    assert(Match.new(h.options):status().mode=='match')
end)
print('stat_match: PASS ('..count..' lifecycle, calibration and rollback regressions)')
