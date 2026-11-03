local data=assert(loadfile('Mods/PhantomGladiator/Scripts/execution_data.lua'))()
local contract=assert(loadfile('tools/execution_coverage_contract.lua'))()
local count,variants=0,0
local function check(def)
    assert(type(def.clip)=='string' and def.clip:sub(1,1)=='/' and def.clip_to>def.clip_from and def.rate>0)
    assert(def.segments==1 and def.executor>0)
    if def.camera then
        assert(#def.camera.frames>0 and def.camera.duration>0)
        local last=-math.huge
        for _,f in ipairs(def.camera.frames)do assert(#f==11 and f[1]>=last);last=f[1] end
    end
end
for name,entry in pairs(data)do
    count=count+1
    if entry.dynamic then
        local n=0
        for montage,def in pairs(entry.variants)do n=n+1;variants=variants+1;assert(def.montage:match('%.([^%.]+)$')==montage);check(def)end
        assert(n>1)
    else check(entry) end
end
for name in pairs(contract.executors)do assert(data[name],'missing configured execution: '..name)end
assert(count==35 and variants==6,'35 base/counter/continuation classes, with four rider and two doll branches')
assert(data.GA_Hun_BDEx_Common_LionDancer_01_C and data.GA_Hun_BEx_ZuoSHang_P2_Skill_20_C)
assert(data.GA_Hun_BEx_Common_EMei_EMeiCi_01_B_C.clip_from==5.36)
if arg[1] then
    local old=assert(loadfile(arg[1]))()
    local function equalOld(a,b,path)
        assert(type(a)==type(b),'type changed '..path)
        if type(a)=='table' then for k,v in pairs(a)do equalOld(v,b[k],path..'.'..tostring(k))end
        else assert(a==b,'accepted data changed '..path)end
    end
    local n=0;for name,entry in pairs(old)do equalOld(entry,data[name],name);n=n+1 end
    print('accepted execution data preserved: '..n)
end
print('execution_coverage ok: '..contract.entries..' configured entries / '..contract.actor_configs..' configs, '..count..' classes, '..variants..' native branches')
