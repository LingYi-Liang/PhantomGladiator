package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Scan=require('attack_faction_scan')
local writes=0
local function object(full,fields)
    local inner=fields or {}
    inner.IsValid=function()return true end
    inner.GetFullName=function()return full end
    return setmetatable({},{__index=inner,__newindex=function()writes=writes+1 end})
end
local function tag(name)return {TagName={ToString=function()return name end}} end
local function map(entries)
    return {ForEach=function(_,fn)for _,e in ipairs(entries)do fn(e[1],e[2]) end end}
end
local function data(id,target,canSelf,damage)
    local class=object('Class /Script/PBZCombatAsset.PBZ_SweepTraceBulletData')
    return object('PBZ_SweepTraceBulletData /PBZCombatAsset/ActorData/Mobs/042_AHua/Bullet/'..id..'.'..id,{
        GetClass=function()return class end,FactionTarget=target,FactionCanTargetSelf=canSelf,
        DamageData=map(damage or {}),AttackType=tag('AttackType.Melee'),DamageCause=tag('DamageCause.Hit')})
end
local function harness()
    local h={logs={},files={},now=0,ready=true}
    h.list={data('BD_Swing',0,false,{{tag('Damage.Physical'),1.5}}),
        data('B_Hun_KnockPush',1,false,{}),
        data('BD_Quake',2,false,{{tag('Damage.Physical'),2},{tag('Damage.Shachi'),0.5}}),
        data('BD_Self',0,true,{{tag('Damage.Physical'),1}}),
        object('PBZ_ProjectileEmitterData /PBZCombatAsset/Common/Emitter.Emitter',{GetClass=function()return object('Class /Script/X.PBZ_ProjectileEmitterData')end})}
    local fs={open=function(name,mode)
        if mode=='r' then return h.files[name] and {close=function()end} or nil end
        local text=''
        return {write=function(_,s)text=text..s;return true end,close=function()h.files[name]=(h.files[name] or '')..text;return true end}
    end}
    h.scan=Scan.new({log=function(s)h.logs[#h.logs+1]=s end,path='rt',io=fs,clock=function()return h.now end,
        ready=function()return h.ready end,findAll=function(name)assert(name=='BulletDataBase');return h.list end,
        firstDelay=15,interval=60,perTick=2})
    function h:run(times)for _=1,times do self.scan:tick() end end
    -- The first tick starts the 15 s wait; the first pass then reads the five, two per tick.
    function h:start()self.now=0;self:run(1);self.now=15;self:run(3)end
    function h:line(pattern)for _,s in ipairs(self.logs)do if s:find(pattern,1,true) then return s end end end
    return h
end
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
test('waits for the game and the first delay, then reads the list a chunk per tick',function()
    local h=harness();h.ready=false;h.now=100;h:run(3);assert(#h.logs==0 and not h.files['rt/attack-faction-scan.tsv'])
    h.ready=true;h:run(1);h.now=114;h:run(1);assert(h.scan:status().pass==0,'first pass after 15 s')
    h.now=115;h:run(1);assert(h.scan:status().pass==1 and not h:line('第1轮'),'two of five read on the first tick')
    h:run(2);local summary=assert(h:line('[AttackScan] 第1轮：已加载子弹数据 5 个，新增 5 个（写入 attack-faction-scan.tsv=true）'))
    assert(summary:find('只打敌人 2、只打友方 1、都打 1、都不打 0、读不到 1；能打同阵营 1；能打到友方的 3 个，其中带伤害 2 个',1,true),summary)
end)
test('attacks that can reach an ally are logged with family and damage; every one goes into the table',function()
    local h=harness();h:start()
    local push=assert(h:line('数据=B_Hun_KnockPush'))
    assert(push:find('族=042_AHua',1,true) and push:find('打谁=只打友方',1,true) and push:find('伤害=无',1,true),push)
    assert(h:line('数据=BD_Quake 打谁=都打 能打同阵营=false 伤害=Damage.Physical=2;Damage.Shachi=0.5'))
    assert(h:line('数据=BD_Self 打谁=只打敌人 能打同阵营=true'))
    assert(not h:line('数据=BD_Swing'),'enemy-only attacks are not logged')
    local tsv=h.files['rt/attack-faction-scan.tsv']
    assert(tsv:sub(1,5)=='pass\t' and select(2,tsv:gsub('\n',''))==6,tsv)
    assert(tsv:find('1\t/PBZCombatAsset/ActorData/Mobs/042_AHua/Bullet/BD_Swing.BD_Swing\tPBZ_SweepTraceBulletData\t042_AHua\t只打敌人\tfalse\tDamage.Physical=1.5\tAttackType.Melee\tDamageCause.Hit',1,true),tsv)
    -- Data without the faction fields (an emitter here) is still listed, with what could not be read as '?'.
    assert(tsv:find('/PBZCombatAsset/Common/Emitter.Emitter\tPBZ_ProjectileEmitterData\tPBZCombatAsset/Common\t?\t?\t?',1,true),tsv)
end)
test('later passes add only what was not seen, without a second header',function()
    local h=harness();h:start()
    h.list[#h.list+1]=data('BD_New',2,false,{{tag('Damage.Physical'),3}})
    h.now=50;h:run(5);assert(h.scan:status().pass==1,'next pass a minute later')
    h.now=81;h:run(4)
    assert(h:line('第2轮：已加载子弹数据 6 个，新增 1 个') and h:line('数据=BD_New 打谁=都打'))
    local tsv=h.files['rt/attack-faction-scan.tsv']
    assert(select(2,tsv:gsub('pass\tpath',''))==1 and select(2,tsv:gsub('\n',''))==7,tsv)
    h.now=150;h:run(4);assert(not h:line('第3轮'),'a pass with nothing new is quiet')
    assert(writes==0,'nothing in the game is written')
end)
print('attack_faction_scan: PASS ('..count..' timing, logging, table and read-only regressions)')
