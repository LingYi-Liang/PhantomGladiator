package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Watch=require('fight_watch')
local address=0
local function object(name,fields)
    address=address+1;local a=address
    local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()return a end
    local class={GetFName=function()return {ToString=function()return name end}end,IsValid=function()return true end}
    o.GetClass=function()return class end
    return o
end
local function harness()
    local h={t=0,logs={},members={},at={},read={},hp={},camera={X=0,Y=0,Z=0},scripts={}}
    h.watch=Watch.new({log=function(m)h.logs[#h.logs+1]=m end,clock=function()return h.t end,members=function()return h.members end,
        location=function(actor)return h.at[actor] end,read=function(actor)return h.read[actor] or {mode=1,blocked=0,state='AI.State.Combat'} end,
        hp=function(actor)return h.hp[actor] end,camera=function()return h.camera end,scripts=function(actor)return h.scripts[actor] end})
    function h.step(seconds)h.t=h.t+(seconds or 1);h.watch:tick() end
    function h.all()return table.concat(h.logs,'\n') end
    function h.count(text)
        local n,from=0,1
        while true do
            local at=h.all():find(text,from,true)
            if not at then return n end
            n,from=n+1,at+#text
        end
    end
    function h.unit(team,x,y,z)
        local actor=object('BP_Monster_'..team..'_C')
        h.at[actor]={X=x or 0,Y=y or 0,Z=z or 0};h.hp[actor]=100
        h.members[#h.members+1]={actor=actor,team=team}
        return actor
    end
    return h
end

do -- a quiet unit logs nothing; the check looks once a second
    local h=harness();h.unit('blue',100,0,0)
    for _=1,5 do h.step() end
    assert(#h.logs==0,h.all())
    assert(h.watch:status().events==0)
end

do -- the things that make a unit vanish are logged when they happen
    local h=harness();local u=h.unit('red',100,0,0)
    h.step()
    h.at[u]={X=4000,Y=0,Z=0};h.step()
    assert(h.all():find('一秒内移动 39m',1,true),h.all())
    h.at[u]={X=4000,Y=0,Z=-1000};h.read[u]={mode=3,blocked=0,state='AI.State.Combat'};h.step()
    assert(h.all():find('一秒内下降 10m',1,true),h.all())
    h.read[u]={mode=5,blocked=1,state='AI.State.Idle'};h.step()
    assert(h.all():find('进战斗被封锁 AI.DisableCombatAI 模式=飞行',1,true),h.all())
    h.read[u]={mode=1,blocked=0,hidden=true};h.step()
    assert(h.all():find('被隐藏',1,true),h.all())
    h.at[u]={X=7000,Y=0,Z=-1000};h.step()
    assert(h.all():find('距镜头 60米内 -> 60~128米（71m）',1,true),h.all())
end

do -- health gone at a stroke, and a unit that leaves with health left: its last seconds
    local h=harness();local u=h.unit('blue',100,0,0);h.unit('red',300,0,0)
    h.step();h.hp[u]=0;h.read[u]={mode=3,blocked=0};h.step()
    assert(h.all():find('血量 100 -> 0（最高 100）',1,true),h.all())
    table.remove(h.members,1);h.step()
    assert(not h.all():find('还有血就退场',1,true),'a dead unit leaving says nothing more')
    h.step();table.remove(h.members,1);h.step()
    assert(h.all():find('BP_Monster_red_C 还有血就退场（对象失效或被清理） team=red',1,true),h.all())
    assert(h.all():find('1s前 位置=(300,0,0) 模式=走路 距镜头=3m HP=100',1,true),h.all())
    assert(h.watch:status().exits==1)
    local count=#h.logs;h.step();assert(#h.logs==count,'told once')
end

do -- a crowd of one class says each thing a few times, so what comes later is still heard
    local h=harness();local units={}
    for i=1,50 do units[i]=h.unit('blue',0,0,0) end
    h.step()
    for i=1,50 do h.at[units[i]]={X=3000,Y=0,Z=0} end
    h.step()
    assert(h.count('一秒内移动')==6,h.all())
    assert(h.watch:status().events==50)
    local lone=h.unit('red',0,0,0);h.step();h.at[lone]={X=3000,Y=0,Z=0};h.step()
    assert(h.all():find('BP_Monster_red_C 一秒内移动',1,true),h.all())
end

do -- only the fighting sides; a companion is not followed
    local h=harness();h.unit('companion',0,0,0)
    h.step();h.at[h.members[1].actor]={X=9000,Y=0,Z=0};h.step()
    assert(#h.logs==0,h.all())
end

do -- which ground check a class runs, once per class
    local h=harness();local u=h.unit('blue',100,0,0)
    h.scripts[u]={object('AIScript_Other_C'),object('AIScript_GroundCheck_C',{ForceFlyingDistance=12800,FallSafetyDistance=6000,GroundRecoveryTrustDistance=1000,GroundCheckDistance=5})}
    h.step()
    assert(h.all():find('的 AI 脚本 2 个；地面检测：AIScript_GroundCheck_C 强制飞行=12800 下落安全=6000 信任地面=1000 检测=5',1,true),h.all())
    local second=h.unit('blue',100,0,0);h.scripts[second]=h.scripts[u]
    local count=#h.logs;h.step();assert(#h.logs==count,'the same class is not read again')
end

print('fight_watch: PASS')
