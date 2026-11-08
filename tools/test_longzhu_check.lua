package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Check=require('longzhu_check')
local function object(fields)
    local o=fields or {}
    o.alive=o.alive~=false
    o.IsValid=function(self)return self.alive end
    return o
end
local function fname(text)return {text=text,ToString=function(self)return self.text end} end
local function container(tags)
    local list={}
    for _,t in ipairs(tags)do list[#list+1]={TagName=fname(t)} end
    return {GameplayTags=list}
end
local L='lz.龙柱.'
local function harness(opts)
    opts=opts or {}
    local h={logs={},now=0,present={},gates={},objects={},asked={},containsThrows=false,built={},added={},world=1,addTakes=true}
    h.map={Contains=function(_,key)
        if h.containsThrows then error('unsupported key type') end
        h.asked[#h.asked+1]=key;return h.gates[key]==true end}
    h.pipeline=object({ExecuteNodeGuid=h.map,GetAddress=function()return h.world end,
        HasTagWithOutSource=function(_,tag)return h.present[tag.TagName.text]==true end,
        AddTags=function(_,c)
            h.added[#h.added+1]=c
            if h.addTakes or (h.tableTakes and c.ParentTags) then
                for _,tag in ipairs(c.GameplayTags)do h.present[tag.TagName.text]=true end
            end
        end})
    h.check=Check.new({log=function(m)h.logs[#h.logs+1]=m end,clock=function()return h.now end,repair=opts.repair~=false,
        findAll=function(kind)return h.objects[kind] or {} end,
        fname=function(t)h.built[#h.built+1]=t;return h.fname and h.fname(t) or fname(t) end,
        pipeline=function()return h.on~=false and h.pipeline or nil end})
    function h.all()return table.concat(h.logs,'\n') end
    function h.tick(dt)h.now=h.now+(dt or 5);h.check:tick() end
    function h.key(raw)return Check.keys(raw)[1] end
    return h
end
-- The state this save is in: the fifth trial started at the 戏梦山庄 pillar (3), its ending run early, the pillar not fallen.
local function stuckSave(h)
    for _,t in ipairs({'试炼5','龙柱试炼开启5','龙柱进战Seq5','战斗胜利5','胜利5Seq','胜利5站桩开始','胜利5站桩结束','战斗结算5','Seq21',
        '龙柱结算Seq5','胜利5站桩消失','龙柱试炼完成4'})do h.present[L..t]=true end
    for n=1,5 do h.present[L..'点位'..n]=true;if n~=3 then h.present[L..'崩塌'..n]=true end end
    for _,g in ipairs(Check.GATES)do h.gates[h.key(g[2])]=true end
end
local function pillar3Node(h,tags)
    h.objects['CacheTags_C']={object({GetFullName=function()return 'CacheTags_C /Game/PBZContent/Blueprint/FlowGraph/QuestFlowGraph/LongZhu/BPF_LongZhu_4.BPF_LongZhu_4:CacheTags_C_0' end,
            Tags=container({L..'崩塌4'})}),
        object({GetFullName=function()return 'CacheTags_C /Game/PBZContent/Blueprint/FlowGraph/QuestFlowGraph/LongZhu/BPF_LongZhu_3.BPF_LongZhu_3:CacheTags_C_4' end,
            Tags=container({L..'触摸3',L..'龙柱结算3'})}),
        object({GetFullName=function()return 'CacheTags_C /Game/PBZContent/Blueprint/FlowGraph/QuestFlowGraph/LongZhu/BPF_LongZhu_3.BPF_LongZhu_3:CacheTags_C_0' end,
            Tags=tags or container({L..'崩塌3'})})}
    return h.objects['CacheTags_C'][3].Tags
end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('ok - '..name) end

test('a node GUID as the asset stores it becomes the save key Conv_GuidToString writes',function()
    local keys=Check.keys('fbf784f59bb5644985cf7e626e2053df')
    assert(keys[1]=='F584F7FB4964B59B627ECF85DF53206E' and keys[2]=='FBF784F59BB5644985CF7E626E2053DF',keys[1])
    assert(#Check.allTags()==13+25+1)
end)

test('the ending and the pillars are read, logged when they change, and nothing is written without a stuck save',function()
    local h=harness()
    h.objects['GAA_FlowTag_C']={object({Tags=container({L..'战斗胜利5'})})}
    h.objects['SetTag_C']={object({AddTags=container({L..'胜利5Seq'})}),object({AddTags=container({L..'胜利5站桩开始',L..'战斗结算5'})})}
    h.objects['FlowNode_HasWithSourceTag']={object({ObserveTags=container({L..'试炼5'}),BlockTags=container({L..'胜利5站桩结束'})})}
    h.present[L..'试炼5']=true;h.present[L..'战斗胜利5']=true;h.present[L..'胜利5Seq']=true
    h.gates['F584F7FB4964B59B627ECF85DF53206E']=true   -- 记胜利5Seq: BPF_MoTian SetExcuteType_C_18
    h.tick()
    assert(#h.logs==2,h.all())
    local ending,pillars=h.logs[1],h.logs[2]
    assert(ending:find('[LongZhu] 第五战结尾 读回：',1,true)==1,ending)
    assert(ending:find('战斗胜利5=true 胜利5Seq=true 胜利5站桩开始=false 胜利5站桩结束=false 战斗结算5=false',1,true),ending)
    assert(ending:find('记胜利5Seq=已走',1,true) and ending:find('胜利过场=没走',1,true),ending)
    assert(ending:find('标签名 来自对象=6 按名字=33 没找到=0',1,true),ending)
    assert(h.asked[1]=='AFA5591448681905A874DEB1D5F2C894','the Conv_GuidToString form is asked first: '..h.asked[1])
    assert(pillars:find('[LongZhu] 龙柱 读回：1悲泣溪谷[点位=false 崩塌=false 崩塌加载=false 崩塌结束=false 龙柱结算=false 塌=没走 塌后过场=没走 第五战奖励=没走]',1,true)==1,pillars)
    assert(pillars:find('3戏梦山庄[',1,true) and pillars:find('；结局条件血脉觉醒=false',1,true),pillars)
    h.tick()
    assert(#h.logs==2,'no change, no line')
    h.present[L..'胜利5站桩开始']=true
    h.tick()
    assert(#h.logs==3 and h.logs[3]:find('胜利5站桩开始=true',1,true),h.all())
    assert(#h.added==0,'nothing written')
end)

test('names not carried by a loaded object are built from text only when they read back the same',function()
    local h=harness()
    h.fname=function(t)if t:find('结算',1,true) then return fname(t..'?') end;return fname(t) end
    h.tick()
    local line=h.logs[1]
    assert(line:find('（这条线还没开始）',1,true),line)
    assert(line:find('战斗结算5=?',1,true) and line:find('龙柱结算Seq5=?',1,true) and line:find('战斗胜利5=false',1,true),line)
    assert(line:find('按名字=32 没找到=7',1,true),line)
    local n=#h.built
    h.tick(5)
    assert(#h.built==n,'not built again before the next look')
    h.tick(15)
    assert(#h.built>n,'the missing ones are tried again later')
end)

test('a map that cannot be asked reads as unknown; a failed answer is unknown; without the story system nothing is read',function()
    local h=harness()
    h.containsThrows=true
    h.pipeline.HasTagWithOutSource=function(_,tag)if tag.TagName.text==L..'战斗胜利5' then error('no') end;return false end
    h.tick()
    assert(h.logs[1]:find('开第五战=读不到',1,true),h.all())
    assert(h.logs[1]:find('战斗胜利5=? ',1,true) and h.logs[1]:find('胜利5Seq=false',1,true),h.all())
    assert(h.logs[2]:find('塌=读不到',1,true),h.all())
    local g=harness()
    g.on=false
    g.tick();g.tick()
    assert(#g.logs==0)
end)

test('only 龙柱 tags count as the line having started',function()
    local h=harness()
    h.present[Check.BLOODLINE]=true
    h.tick()
    assert(h.logs[1]:find('（这条线还没开始）',1,true) and h.logs[2]:find('结局条件血脉觉醒=true',1,true),h.all())
end)

test('the raw form of the key is tried when the first is not there',function()
    local h=harness()
    h.gates['0B71C592B9D57B48B6A06F6493A94689']=true
    h.tick()
    assert(h.logs[1]:find('进战过场=已走',1,true),h.all())
end)

test('a stuck save gets its pillar\'s fall written once, with the pillar\'s own container, when that flow is loaded',function()
    local h=harness()
    stuckSave(h)
    h.tick()
    assert(h.all():find('这个存档卡在龙柱3（戏梦山庄）',1,true),h.all())
    assert(#h.added==0,'waits for the pillar')
    h.objects['CacheTags_C']={object({GetFullName=function()return 'CacheTags_C /X/BPF_LongZhu_4.BPF_LongZhu_4:CacheTags_C_0' end,Tags=container({L..'崩塌4'})})}
    h.tick()
    assert(#h.added==0,'another pillar\'s container is not used')
    local own=pillar3Node(h)
    -- A container with the same tag in another flow (the debug flow names these tags too) is not the pillar's.
    table.insert(h.objects['CacheTags_C'],1,object({GetFullName=function()return 'CacheTags_C /Game/PBZContent/Blueprint/FlowGraph/DebugUI/FlowLogic/FlowLogicPlaySeqTable.FlowLogicPlaySeqTable:CacheTags_C_9' end,
        Tags=container({L..'崩塌3'})}))
    h.tick()
    assert(#h.added==1 and h.added[1]==own,'the pillar\'s own container, as it is')
    assert(h.present[L..'崩塌3']==true)
    assert(h.all():find('补档 龙柱3（戏梦山庄）',1,true) and h.all():find('补写 ['..L..'崩塌3]：方式=龙柱流程自带的标签容器 调用=true 读回 写前=false 写后=true',1,true),h.all())
    h.present[L..'崩塌3']=false
    h.tick(5)
    assert(#h.added==1,'never twice')
end)

test('when the container does not take, a built one is tried once; a state that is not exactly stuck is left alone',function()
    local h=harness()
    stuckSave(h);pillar3Node(h)
    h.addTakes=false;h.tableTakes=true
    h.tick()
    assert(#h.added==2 and h.added[2].ParentTags and h.present[L..'崩塌3']==true,h.all())
    assert(h.all():find('方式=龙柱流程自带的标签容器没读回，改用拼的容器',1,true),h.all())
    local cases={
        function(g)g.present[L..'龙柱试炼完成5']=true end,
        function(g)g.present[L..'崩塌5']=false end,                      -- two pillars not fallen
        function(g)g.gates[g.key(Check.PILLARS[3].reward)]=true end,     -- reward node already run
        function(g)g.gates[g.key(Check.GATES[6][2])]=false end,          -- the centre's last node not run
        function(g)g.present[L..'胜利5站桩消失']=false end,
    }
    for i,change in ipairs(cases)do
        local g=harness();stuckSave(g);change(g);pillar3Node(g)
        table.insert(g.objects['CacheTags_C'],object({GetFullName=function()return 'CacheTags_C /X/BPF_LongZhu_5.BPF_LongZhu_5:CacheTags_C_0' end,
            Tags=container({L..'崩塌5'})}))
        g.tick();g.tick()
        assert(#g.added==0,'case '..i..': '..g.all())
    end
    -- The pillar found when the world came is the only one repaired, even if another looks stuck later.
    local moved=harness();stuckSave(moved)
    moved.tick()
    moved.present[L..'崩塌3']=true;moved.present[L..'崩塌5']=false
    moved.objects['CacheTags_C']={object({GetFullName=function()return 'CacheTags_C /X/BPF_LongZhu_5.BPF_LongZhu_5:CacheTags_C_0' end,
        Tags=container({L..'崩塌5'})})}
    moved.tick();moved.tick()
    assert(#moved.added==0,moved.all())
    local off=harness({repair=false});stuckSave(off);pillar3Node(off)
    off.tick();off.tick()
    assert(#off.added==0,'repair switched off')
end)

test('only a state that came with the world is repaired, not one reached while it plays',function()
    local h=harness()
    stuckSave(h)
    h.present[L..'崩塌3']=true
    h.tick()                                   -- first read of this world: not stuck
    h.present[L..'崩塌3']=false;pillar3Node(h)
    h.tick();h.tick()
    assert(#h.added==0,'stuck only during play: left to the game')
    h.world=2
    h.tick()
    assert(#h.added==1,'the same state loaded in a new world is repaired')
    local early=harness()
    early.tick()                               -- tags not loaded yet: no baseline taken
    stuckSave(early);pillar3Node(early)
    early.tick()
    assert(#early.added==1,'the first read with 龙柱 tags is the baseline')
end)

test('without the save-repair button nothing is written; pressed later, the stuck pillar is repaired',function()
    local h=harness({repair=false})
    stuckSave(h);pillar3Node(h)
    h.tick();h.tick()
    assert(#h.added==0 and h.all():find('助手里点"修复存档"后，走到这根龙柱附近会补写 崩塌3',1,true),h.all())
    assert(h.check.armed==false)
    h.check:arm()
    h.tick()
    assert(#h.added==1 and h.present[L..'崩塌3']==true,'the baseline taken before the button still counts')
end)

test('the report line: unread, nothing to do, stuck, repaired, failed',function()
    local h=harness({repair=false})
    local ok,line=h.check:diagnose()
    assert(ok==nil and line=='龙柱','nothing read yet')
    h.tick()
    ok,line=h.check:diagnose();assert(ok==true and line=='龙柱','this line has not started')
    local s=harness({repair=false});stuckSave(s);s.tick()
    ok,line=s.check:diagnose()
    assert(ok==false and line=='龙柱：卡在龙柱3（戏梦山庄），走到它附近自动补上',line)
    s.check:arm();pillar3Node(s);s.tick()
    ok,line=s.check:diagnose()
    assert(ok==false and line=='龙柱：已补好，那根龙柱会自己塌、给奖励',line)
    local f=harness();stuckSave(f);pillar3Node(f);f.addTakes=false
    f.tick()
    ok,line=f.check:diagnose()
    assert(ok==false and line=='龙柱：补写没成功，看日志',line)
    local fine=harness({repair=false});stuckSave(fine);fine.present[L..'崩塌3']=true;fine.tick()
    ok,line=fine.check:diagnose();assert(ok==true,'not stuck')
end)

print('longzhu_check: PASS ('..tests..' groups)')
