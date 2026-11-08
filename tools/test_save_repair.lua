package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Repair=require('save_repair')
local Keys=require('longzhu_check').keys
local function object(fields)
    local o=fields or {}
    o.alive=o.alive~=false
    o.IsValid=function(self)return self.alive end
    return o
end
local function harness()
    local h={logs={},marks={},walked={},saved=true,pipelineOn=true,mapOn=true}
    h.longzhu={armed=false,ok=true,line='龙柱',arm=function(self)self.armed=true end,diagnose=function(self)return h.longzhu.ok,h.longzhu.line end}
    h.guard={armed=false,ok=true,line='雷当',arm=function(self)self.armed=true end,
        diagnose=function(self,has)assert(type(has)=='function');return h.guard.ok,h.guard.line end}
    h.map=object({Contains=function(_,key)return h.walked[key]==true end})
    h.pipeline=object({ExecuteNodeGuid=h.map})
    h.repair=Repair.new({log=function(m)h.logs[#h.logs+1]=m end,longzhu=h.longzhu,guard=h.guard,
        has=function(t)return h.marks[t] end,
        pipeline=function()if not h.pipelineOn then return nil end;h.pipeline.ExecuteNodeGuid=h.mapOn and h.map or nil;return h.pipeline end,
        hasSaveData=function(id)assert(id=='LengTu_Combat');return h.saved end})
    for _,t in ipairs(Repair.FIGHT_STARTED)do h.marks[t]=false end
    for _,r in ipairs(Repair.REACTIONS)do
        h.marks[r.tag]=false
        for _,t in ipairs(r.over)do h.marks[t]=false end
    end
    h.saved=false
    function h.all()return table.concat(h.logs,'\n') end
    function h.walk(raw)h.walked[Keys(raw)[1]]=true end
    return h
end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('ok - '..name) end
local function reaction(tag)for _,r in ipairs(Repair.REACTIONS)do if r.tag==tag then return r end end end

test('nothing wrong: one line, and both repairs are armed by the button',function()
    local h=harness()
    local r=h.repair:run()
    assert(r.ok==true and r.message=='没发现模组造成的存档问题（查了龙柱、雷当、冷荼、其他单位写的剧情标记）',r.message)
    assert(h.longzhu.armed and h.guard.armed and h.repair:status().save_repair_armed==true)
    assert(h.all():find('[SaveRepair] 第 1 次：没发现',1,true),h.all())
end)

test('problems first, then what is fine, then what could not be read',function()
    local h=harness()
    h.longzhu.ok,h.longzhu.line=false,'龙柱：卡在龙柱3（戏梦山庄），走到它附近自动补上'
    h.guard.ok,h.guard.line=nil,'雷当'
    local r=h.repair:run()
    assert(r.message=='龙柱：卡在龙柱3（戏梦山庄），走到它附近自动补上；没问题：冷荼、其他单位写的剧情标记；读不到：雷当（进游戏世界几秒后再点）',r.message)
    assert(r.problems==1)
end)

test('冷荼: armed only when her checkpoint is there and her own fight has not started',function()
    local h=harness()
    assert(h.repair:wantsCheckpoint('LengTu_Combat')==false,'nothing before the button')
    h.saved=true
    local r=h.repair:run()
    assert(r.message:find('冷荼：阶段进度是模组写的，下次在竞技场叫出冷荼时清掉',1,true),r.message)
    assert(h.repair:wantsCheckpoint('PhantomGladiator_LengTu')==false and h.repair:wantsCheckpoint('LengTu_Combat')==true)
    h.repair:checkpointDone('LengTu_Combat',true,{})
    assert(h.repair:wantsCheckpoint('LengTu_Combat')==false,'once')
    r=h.repair:run()
    assert(r.message:find('冷荼：已清掉她的阶段进度',1,true) and h.all():find('清掉后读回=[] 已清空',1,true),r.message)
    local g=harness();g.saved=true;g.repair:run()
    g.repair:checkpointDone('LengTu_Combat',false,{'CharacterState.AbilityState.LengTu.Save.P4'})
    assert(g.repair:run().message:find('冷荼：清阶段进度没成功，看日志',1,true))
end)

test('冷荼: her fight started (now or by the time she is summoned), unread, no entry',function()
    local h=harness();h.saved=true
    h.marks['dhy.冷荼入战seq.未完成湖心秘密']=true
    local r=h.repair:run()
    assert(r.message:find('没发现模组造成的存档问题',1,true) and h.repair:wantsCheckpoint('LengTu_Combat')==false,r.message)
    local g=harness();g.saved=true;g.repair:run()
    g.marks['dhy.冷荼入战seq.完成湖心秘密']=true
    assert(g.repair:wantsCheckpoint('LengTu_Combat')==false and g.all():find('剧情里的冷荼战开始了吗=true，不清',1,true),'checked again when she comes')
    local u=harness();u.saved=true;u.repair:run()
    u.marks['dhy.冷荼入战seq.未完成湖心秘密']=nil
    assert(u.repair:wantsCheckpoint('LengTu_Combat')==false and u.all():find('开始了吗=nil，不清',1,true),'unread by then: not cleared')
    local k=harness();k.saved=true;k.marks['dhy.冷荼入战seq.完成湖心秘密']=nil
    r=k.repair:run()
    assert(r.message:find('读不到：冷荼',1,true) and k.repair:wantsCheckpoint('LengTu_Combat')==false,r.message)
    local m=harness();m.saved=nil
    r=m.repair:run()
    assert(r.message:find('冷荼：阶段进度可能是模组写的',1,true) and m.repair:wantsCheckpoint('LengTu_Combat')==true,'an unread entry is cleared anyway: '..r.message)
    local n=harness();n.saved=false
    assert(n.repair:run().message:find('冷荼',1,true) and n.repair:wantsCheckpoint('LengTu_Combat')==false,'no entry, nothing to clear')
end)

test('a mark written before its part of the story: reported when its reaction has not run and that part is not over',function()
    local h=harness()
    local hook=reaction('rzgd.击败.钩者')
    h.marks[hook.tag]=true
    local r=h.repair:run()
    assert(r.message:find('马车战：钩者那段会直接算打败（删不掉）',1,true) and not r.message:find('其他单位写的剧情标记',1,true),r.message)
    h.walk(hook.gate)
    r=h.repair:run()
    assert(not r.message:find('钩者',1,true),'its reaction ran: an ordinary save')
    local mu=reaction('ljc.沐小葵.血量降低到25')
    h.marks[mu.tag]=true
    assert(h.repair:run().message:find('沐小葵',1,true))
    h.marks['hp.击杀.沐小葵二阶段']=true
    assert(not h.repair:run().message:find('沐小葵',1,true),'that fight is over')
    local raw=Keys(hook.gate)[2]
    local g=harness();g.marks[hook.tag]=true;g.walked[raw]=true
    assert(not g.repair:run().message:find('钩者',1,true),'the raw-byte key counts too')
end)

test('a mark or a node that cannot be read is counted as unread',function()
    local h=harness()
    h.marks['rzgd.击败.钩者']=nil
    h.marks['ljc.沐小葵.血量降低到25']=true
    h.mapOn=false
    local r=h.repair:run()
    assert(r.message:find('读不到：其他单位的标记 2 条',1,true),r.message)
    local g=harness()
    g.marks['rzgd.击败.钩者']=true
    g.map.Contains=function()return nil end
    r=g.repair:run()
    assert(r.message:find('读不到：其他单位的标记 1 条',1,true) and not r.message:find('钩者',1,true),'a node that answers neither yes nor no is unread: '..r.message)
end)

test('the reaction nodes are the ones read from the game files',function()
    local want={['ljc.沐小葵.血量降低到25']='235520622930ca4b81cbe1930f25624d',['rzgd.击败.钩者']='7434a89722ce5c4584762a2aeb623a0d',
        ['rzgd.击败.两个枪鬼差']='22c8f7169c07a94b8240ccf3400bf3b7'}
    local n=0
    for _,r in ipairs(Repair.REACTIONS)do n=n+1;assert(want[r.tag]==r.gate,r.tag) end
    assert(n==3)
    assert(Keys('7434a89722ce5c4584762a2aeb623a0d')[1]=='97A83474455CCE222A2A76840D3A62EB','as Conv_GuidToString writes it')
end)

test('the longest report fits the 512-byte reply',function()
    local h=harness()
    h.longzhu.ok,h.longzhu.line=false,'龙柱：卡在龙柱5（梅谷湖遗迹），走到它附近自动补上'
    h.guard.ok,h.guard.line=false,'雷当：已被记成打过（读不到这一战打完没有），到戏梦山庄时关掉一阶段，只打二阶段'
    h.saved=nil
    for _,r in ipairs(Repair.REACTIONS)do h.marks[r.tag]=true end
    local r=h.repair:run()
    assert(#r.message<=512 and r.problems==6,#r.message..' '..r.message)
    h.marks['rzgd.击败.钩者']=nil
    r=h.repair:run()
    assert(#r.message<=512 and r.message:find('读不到：',1,true),#r.message..' '..r.message)
end)

print('save_repair: PASS ('..tests..' groups)')
