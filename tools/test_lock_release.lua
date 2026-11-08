package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Lock=require('lock_release')
local address=0
local function object(name,fields)
    address=address+1;local a=address
    local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()return a end
    o.GetFName=function()return {ToString=function()return name end}end
    return o
end
local function fname(text)return {text=text,ToString=function(self)return self.text end} end
local function unit(name)
    local u=object(name)
    u.Mesh=object(name..'.Mesh',{GetOwner=function()return u end})
    u.RootComponent=object(name..'.Capsule',{GetOwner=function()return u end})
    return u
end
-- A unit with a targeting component locked on lockedOn's part.
local function fighter(name,lockedOn,part,socket)
    local u=unit(name)
    local tc=object(name..'.Targeting',{calls={}})
    tc.LockTarget={Component=lockedOn and (part or lockedOn.Mesh) or nil,SocketName=socket}
    tc.SetLockTarget=function(self,lock)
        self.calls[#self.calls+1]={'set',lock}
        if self.refuse then error('refused') end
        if not self.ignore then self.LockTarget={Component=lock.Component,SocketName=lock.SocketName} end
    end
    tc.StopLockTarget=function(self)self.calls[#self.calls+1]={'stop'};if not self.ignore then self.LockTarget={} end end
    u['Targeting Component']=tc
    return u,tc
end
local function harness()
    local h={logs={},aside={}}
    h.lock=Lock.new({log=function(m)h.logs[#h.logs+1]=m end,fname=fname,untargetable=function(actor)return h.aside[actor]==true end})
    function h.all()return table.concat(h.logs,'\n') end
    return h
end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('ok - '..name) end

test('a lock on the boss nobody is sent at moves to the opponent, same part and socket, read back',function()
    local h=harness()
    local lengtu,scav=unit('BP_Monster_LengTu_C_1'),unit('BP_Monster_Scavenger_LengTu_C_2')
    h.aside[lengtu]=true
    local leidang,tc=fighter('BP_Monster_LeiDang_C_3',lengtu,nil,fname('Lock'))
    assert(h.lock:release(leidang,scav)==true)
    local call=tc.calls[1]
    assert(#tc.calls==1 and call[1]=='set' and call[2].Component==scav.Mesh and call[2].SocketName.text=='Lock','her mesh -> its mesh, same socket')
    assert(h.all():find('[LockRelease] BP_Monster_LeiDang_C_3 锁着打不到的 BP_Monster_LengTu_C_1：改锁派给它的对手 BP_Monster_Scavenger_LengTu_C_2 调用=true 读回锁定=BP_Monster_Scavenger_LengTu_C_2 生效；累计 改锁=1 取消=0 没生效=0',1,true),h.all())
    assert(h.lock:release(leidang,scav)==false and #tc.calls==1,'moved: nothing more to do')
    local s=h.lock:status()
    assert(s.lock_moved==1 and s.lock_stopped==0 and s.lock_failed==0)
end)

test('a lock on her capsule goes to the opponent\'s root; no socket read is None',function()
    local h=harness()
    local lengtu,scav=unit('LengTu'),unit('Scav')
    h.aside[lengtu]=true
    local leidang,tc=fighter('LeiDang',lengtu,lengtu.RootComponent,nil)
    assert(h.lock:release(leidang,scav)==true)
    assert(tc.calls[1][2].Component==scav.RootComponent and tc.calls[1][2].SocketName.text=='None')
end)

test('with no opponent in reach the lock is dropped',function()
    local h=harness()
    local lengtu=unit('LengTu');h.aside[lengtu]=true
    local leidang,tc=fighter('LeiDang',lengtu)
    assert(h.lock:release(leidang,nil)==true and tc.calls[1][1]=='stop')
    assert(h.all():find('没有能打的对手，取消锁定 调用=true 读回锁定=无 生效',1,true),h.all())
    local again,tc2=fighter('LeiDang2',lengtu)
    assert(h.lock:release(again,lengtu)==true and tc2.calls[1][1]=='stop','assigned to her herself: dropped, not moved onto her')
end)

test('a lock on anyone the arena may send units at, or no lock, is the game\'s own',function()
    local h=harness()
    local enemy=unit('Enemy')
    local a,tca=fighter('A',enemy)
    assert(h.lock:release(a,unit('Other'))==false and #tca.calls==0)
    local b,tcb=fighter('B',nil)
    assert(h.lock:release(b,enemy)==false and #tcb.calls==0)
    local c=unit('NoTargeting')
    assert(h.lock:release(c,enemy)==false)
    assert(#h.logs==0)
end)

test('a call that fails or does not read back is counted as not taken',function()
    local h=harness()
    local lengtu,scav=unit('LengTu'),unit('Scav');h.aside[lengtu]=true
    local a,tca=fighter('A',lengtu);tca.refuse=true
    assert(h.lock:release(a,scav)==false and h.all():find('调用=false(',1,true),h.all())
    local b,tcb=fighter('B',lengtu);tcb.ignore=true
    assert(h.lock:release(b,scav)==false and h.all():find('读回锁定=LengTu 没生效',1,true),h.all())
    local c,tcc=fighter('C',lengtu);tcc.ignore=true
    assert(h.lock:release(c,nil)==false and tcc.calls[1][1]=='stop','dropped but still locked: not taken')
    assert(h.lock:status().lock_failed==3)
end)

print('lock_release: PASS ('..tests..' groups)')
