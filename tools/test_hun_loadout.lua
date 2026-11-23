package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Loadout=require('hun_loadout')
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end
local GE='/PBZCombatAsset/Prototypes/GameplayEffects/Accessories/New/GE_Accessory_Loot_Lv2.GE_Accessory_Loot_Lv2_C'
local function text(lines)return table.concat(lines,'\n')..'\n'end
-- An in-memory file system that counts how much of each file is read.
local function disk(files)
    local d={files=files or{},full=0,opens=0}
    d.io={open=function(path,mode)
        assert(mode=='rb');d.opens=d.opens+1
        local body=d.files[path];if not body then return nil end
        local at=0
        return {read=function(_,size)local out=body:sub(at+1,at+size);at=at+#out;if size>64 then d.full=d.full+1 end;return out end,
            seek=function(_,whence,offset)assert(whence=='set');at=offset;return at end,close=function()end}
    end}
    return d
end
test('a saved profile parses into count, attribute values, the trial switch and effect classes',function()
    local value=assert(Loadout.parse(text({'HunLoadoutV1\t12','count\t7','attr\tHealth_Max\t123456.5','attr\tLevel\t-3','accessories\ton','ge\t'..GE..'\t1\t盗宝符'})))
    assert(value.revision==12 and value.count==7 and value.attributes.Health_Max==123456.5 and value.attributes.Level==-3)
    assert(value.accessories==true and #value.effects==1 and value.effects[1].path==GE and value.effects[1].level==1 and value.effects[1].label=='盗宝符')
    local plain=assert(Loadout.parse(text({'HunLoadoutV1\t0','count\t1','accessories\toff'})))
    assert(plain.count==1 and next(plain.attributes)==nil and #plain.effects==0 and plain.accessories==false)
end)
test('anything that is not exactly a loadout is refused as a whole',function()
    local bad={
        'HunLoadoutV1\t1\ncount\t7',                                  -- no final newline
        text({'HunLoadoutV2\t1','count\t7'}),text({'HunLoadoutV1\t-1'}),text({'HunLoadoutV1\t2147483647'}),
        text({'HunLoadoutV1\t1','count\t0'}),text({'HunLoadoutV1\t1','count\t101'}),text({'HunLoadoutV1\t1','count\t1.5'}),
        text({'HunLoadoutV1\t1','attr\tHealth Max\t5'}),text({'HunLoadoutV1\t1','attr\tHealth_Max\tnan'}),text({'HunLoadoutV1\t1','attr\tHealth_Max\tinf'}),
        text({'HunLoadoutV1\t1','attr\tAttack\t1','attr\tAttack\t2'}),text({'HunLoadoutV1\t1','accessories\tmaybe'}),
        text({'HunLoadoutV1\t1','ge\t/Game/../Secret.X_C\t1\tx'}),text({'HunLoadoutV1\t1','ge\t/Game/A.B\t1\tx'}),text({'HunLoadoutV1\t1','ge\t'..GE..'\t101\tx'}),
        text({'HunLoadoutV1\t1','ge\t'..GE..'\t1\ta','ge\t'..GE..'\t1\tb'}),text({'HunLoadoutV1\t1','run\tos.exit()'}),'',
    }
    for index,body in ipairs(bad)do local value,why=Loadout.parse(body);assert(value==nil and type(why)=='string','case '..index)end
    local many={'HunLoadoutV1\t1'};for i=1,1025 do many[#many+1]='attr\tF'..i..'\t1'end
    assert(Loadout.parse(text(many))==nil)
end)
test('the file is read in full only when its revision changes',function()
    local d=disk({['rt/hun-loadout.tsv']=text({'HunLoadoutV1\t3','count\t2','accessories\toff'})})
    local logs={};local loadout=Loadout.new({path='rt',io=d.io,log=function(s)logs[#logs+1]=s end})
    local first=loadout:read();assert(first.count==2 and d.full==1 and #logs==1)
    for _=1,50 do assert(loadout:read()==first)end
    assert(d.full==1 and #logs==1,'unchanged revision: header only, no log')
    d.files['rt/hun-loadout.tsv']=text({'HunLoadoutV1\t4','count\t9','accessories\toff'})
    assert(loadout:read().count==9 and d.full==2 and #logs==2)
end)
test('a missing or damaged file gives nothing and is reported once',function()
    local d=disk();local logs={};local loadout=Loadout.new({path='rt',io=d.io,log=function(s)logs[#logs+1]=s end})
    assert(loadout:read()==nil and loadout:read()==nil and #logs==1)
    d.files['rt/hun-loadout.tsv']='HunLoadoutV1\t5\ncount\t999\n'
    assert(loadout:read()==nil and loadout:read()==nil and #logs==2 and logs[2]:find('无效',1,true))
    d.files['rt/hun-loadout.tsv']=text({'HunLoadoutV1\t6','count\t3','accessories\toff'})
    assert(loadout:read().count==3)
end)
test('appearance defaults and independent sources use known values in one kit row',function()
    local header={'HunLoadoutV1\t15','count\t1','kit\t1'}
    assert(assert(Loadout.parse(text(header))).appearance=='player')
    for _,mode in ipairs({'native','default_outfit','clone','snapshot'}) do
        header[4]='appearance\t'..mode
        assert(assert(Loadout.parse(text(header))).appearance==mode)
    end
    header[5]='appearance\tnative';assert(not Loadout.parse(text(header)))
    header[5]=nil;header[4]='appearance\t/Game/Other';assert(not Loadout.parse(text(header)))
end)
test('full profiles retain variant identities, empty pools and zero probabilities',function()
    local id='main_weapon_0123456789abcdef'
    local weapon='weapon\t'..id..'\tTang\t/PBZCombatAsset/ActorData/Players/Hun/Weapon/Tang/Weapon_Hun_Tang.Weapon_Hun_Tang\t12\toff\t0.75\t4\t黑伤'
    local lines={'HunLoadoutV1\t15','kit\t1',weapon,'ai\tred_dodge_chance\t0','resources\tconsume_medicine\toff',
        'survival\tgrab\timmune','phase\tsurvive\t0.25\t'..id..'\t100\ton','param\t近距离进攻概率\t4.5'}
    local p=assert(Loadout.parse(text(lines)))
    assert(p.weapons[1].id==id and p.weapons[1].level==12 and p.weapons[1].soul==false and p.weapons[1].weight==.75)
    assert(#p.shadows==0 and p.ai.red_dodge_chance==0 and p.resources.consume_medicine==false and p.survival.grab=='immune')
    assert(p.phases[1].once and p.phases[1].weapon_id==id and p.ai_parameters['近距离进攻概率']==4.5)
    for _,invalid in ipairs({weapon, 'ai\tred_dodge_chance\t0.5','ai\tunknown\t1','phase\tbad\t2\t'..id..'\t0\toff',
        'param\tRun\t1','kit\t1'}) do
        lines[#lines+1]=invalid;assert(not Loadout.parse(text(lines)),invalid);lines[#lines]=nil
    end
end)
print('hun loadout: PASS '..n..' parse/refusal/re-read checks')
