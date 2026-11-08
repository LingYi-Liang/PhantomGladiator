-- Where the ending of the fifth 龙柱 trial stands in the story, logged when it changes; and one repair.
--
-- The ending (flow graphs QuestFlowGraph/LongZhu): with lz.龙柱.试炼5 and lz.龙柱.战斗胜利5, BPF_MoTian adds 胜利5Seq
-- (a one-time node); BPF_LongZhu_Center plays the victory scene (one-time) and adds 胜利5站桩开始; the 魔渊 NPC
-- (BPF_Npc_MoTian_End5, one-time) talks and adds 战斗结算5 and Seq21; the centre adds 龙柱结算Seq5 (one-time), takes the
-- last 魔渊 away, starts the last scene (胜利5站桩消失) and, when it ends, writes the cached flow tags (SetTag with
-- UseCacheTags: EventPipelineManager.FlowTags).
-- Each trial starts at one of five pillars (BPF_LongZhu_1..5: 悲泣溪谷, 血色森林, 戏梦山庄, 庞镇, 梅谷湖遗迹), which adds
-- 点位N and caches 崩塌N. With 崩塌N the pillar plays its fall (one-time), adds 崩塌加载N, plays the next scene
-- (one-time), adds 崩塌结束N; then for the fifth trial (战斗结算5 without 龙柱试炼完成5, one-time) it hands out TU_17001,
-- adds 龙柱试炼完成5, begins the side quest 血脉觉醒, adds the ending condition dhy.结局条件.血脉觉醒 and saves.
-- When the arena's 魔渊 finishers had written 战斗胜利5 early (story_writes.lua), the centre's part ran before the fifth
-- trial was started anywhere, so the 崩塌N cached when it was started is never written: the pillar does not fall and
-- nothing after the fight comes.
--
-- Repair, once armed (the app's save-repair button, save_repair.lua): in a world whose story already holds exactly that
-- state the first time its 龙柱 tags read back (so it came from the save, not from a scene still playing), once that
-- pillar's flow is loaded (the player is near it), 崩塌N is added with the pillar's own tag container (one of its CacheTags
-- nodes), as the centre would have done; read back after.
-- Only then: 战斗结算5, 龙柱结算Seq5 and 胜利5站桩消失 are there, 龙柱试炼完成5 is not, the centre's last one-time node has
-- run, exactly one pillar has 点位N without 崩塌N, and its fall, next scene and reward nodes have not run.
--
-- A one-time node that has run is a key of EventPipelineManager.ExecuteNodeGuid. These nodes all have
-- ExecuteOnlyOneAsset, so the key is the node GUID as Conv_GuidToString writes it: four little-endian words, %08X each
-- (the raw bytes in upper case are tried too). Tag names come from loaded objects that carry them, otherwise one built
-- from text is used when it reads back as the same text.
local U=require('ue_observe')
local Check={}
local LZ='lz.龙柱.'
Check.ENDING={'试炼5','龙柱试炼开启5','龙柱进战Seq5','战斗胜利5','胜利5Seq','胜利5站桩开始','胜利5站桩结束','战斗结算5','Seq21',
    '龙柱结算Seq5','胜利5站桩消失','龙柱试炼完成4','龙柱试炼完成5'}
Check.PILLAR_TAGS={'点位','崩塌','崩塌加载','崩塌结束','龙柱结算'}
Check.BLOODLINE='dhy.结局条件.血脉觉醒'
-- Centre and NPC one-time nodes: label, node GUID as the asset stores it (16 raw bytes, hex).
Check.GATES={{'开第五战','1459a5af05196848b1de74a894c8f2d5'},{'进战过场','0b71c592b9d57b48b6a06f6493a94689'},
    {'记胜利5Seq','fbf784f59bb5644985cf7e626e2053df'},{'胜利过场','e639246d2372194b846a0ac1eed4f0d5'},
    {'NPC对话','803b88abb879964a8bf4f69e2e8c042d'},{'结算过场','40dba0b005868e47b3fff51c0952ff71'}}
-- Each pillar's one-time nodes after 崩塌N (fall), after 崩塌加载N (next scene) and for the fifth trial's reward.
Check.PILLARS={
    {map='悲泣溪谷',fall='69a2269cc9c0a34482b4a9579f294298',scene='1ca554c8fb0b764baec9e676040719a6',reward='9914299dde584440854a7289704981d8'},
    {map='血色森林',fall='ecde97485a8b0d45a9b67242d8795320',scene='8f60ad7750b07045bbca6a31f9553f26',reward='063fac7be6302b43a56765ab8548a9fa'},
    {map='戏梦山庄',fall='08d6479bf52b5d478ed81f2701c589a9',scene='3925183155995341a5e1116771b59d6c',reward='97d8226ef875ca4a97d514746edca861'},
    {map='庞镇',fall='42492d753a491a4ebb2386583b5103db',scene='a12f28260ef5ee4d81122455febb7f4f',reward='97c2b3ebe3d2ea41bf0653cda9b68c9f'},
    {map='梅谷湖遗迹',fall='d70c5c7e5f982044a4d8d27a150049ef',scene='856103ef456da24e95ec945d5065c60b',reward='d5fe530f85b41046bf12e2586c4497a4'}}
-- Objects that carry the tags and the field holding them (a gameplay tag container).
Check.SOURCES={{'GAA_FlowTag_C','Tags','处决动作'},{'AIScript_AddTagOnDead_C','EventTag','刷怪点脚本'},
    {'SetTag_C','AddTags','剧情节点'},{'CacheTags_C','Tags','剧情节点'},
    {'FlowNode_HasWithSourceTag','ObserveTags','剧情节点'},{'FlowNode_HasWithSourceTag','BlockTags','剧情节点'}}
local EVERY=5           -- seconds between reads
local HARVEST_EVERY=15  -- seconds between looks for objects carrying names still missing
local SCAN_CAP=6000     -- objects looked at per class and look
local LINES=30

local function text(name)
    if type(name)=='string' then return name end
    local ok,value=pcall(function()return name:ToString()end)
    return ok and type(value)=='string' and value or nil
end
local function fullName(object)
    local ok,value=pcall(function()return object:GetFullName()end)
    return ok and type(value)=='string' and value or ''
end
local function label(tag)
    if tag==Check.BLOODLINE then return '结局条件血脉觉醒' end
    return tag:sub(1,#LZ)==LZ and tag:sub(#LZ+1) or tag
end
-- Save keys for a node GUID stored as raw bytes: the Conv_GuidToString form first, then the raw bytes in upper case.
function Check.keys(raw)
    local words={}
    for i=0,3 do
        local w=raw:sub(i*8+1,i*8+8)
        words[#words+1]=(w:sub(7,8)..w:sub(5,6)..w:sub(3,4)..w:sub(1,2)):upper()
    end
    return {table.concat(words),raw:upper()}
end
-- Every tag read, in the order logged.
function Check.allTags()
    local list={}
    for _,short in ipairs(Check.ENDING)do list[#list+1]=LZ..short end
    for n=1,#Check.PILLARS do for _,base in ipairs(Check.PILLAR_TAGS)do list[#list+1]=LZ..base..n end end
    list[#list+1]=Check.BLOODLINE
    return list
end

function Check.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local findAll=options.findAll or function(name)return FindAllOf(name)end
    local fname=options.fname or function(value)return FName(value)end
    local self={reads=0,repaired=0,armed=options.repair==true}
    local names={}          -- tag text -> {name=FName,source=label}
    local lines,lastEnding,lastPillars,nextRead,nextHarvest=0,nil,nil,0,0
    local worldKey,baseline,attempted=nil,nil,false
    local TAGS=Check.allTags()
    local function say(message)
        if lines<LINES then lines=lines+1;log('[LongZhu] '..message) end
    end
    local function wanted()
        local list={}
        for _,t in ipairs(TAGS)do if not names[t] then list[t]=true end end
        return list
    end
    local function harvest()
        local missing=wanted()
        if not next(missing) then return end
        for _,source in ipairs(Check.SOURCES)do
            local ok,list=pcall(findAll,source[1])
            for i,object in ipairs(ok and type(list)=='table' and list or {})do
                if i>SCAN_CAP then break end
                if U.valid(object) then
                    for _,tag in ipairs(U.array(U.struct(U.field(object,source[2]),'GameplayTags')) or {})do
                        local name=U.struct(tag,'TagName');local t=text(name)
                        if t and missing[t] then names[t]={name=name,source=source[3]};missing[t]=nil end
                    end
                end
            end
            if not next(missing) then return end
        end
        for t in pairs(missing)do
            local ok,name=pcall(fname,t)
            if ok and name~=nil and text(name)==t then names[t]={name=name,source='按名字'} end
        end
    end
    local function hasTag(pipeline,t)
        local entry=names[t]
        if not entry then return nil end
        local ok,value=pcall(function()return pipeline:HasTagWithOutSource({TagName=entry.name})end)
        if ok then value=U.unwrap(value) else value=nil end
        if type(value)=='boolean' then return value end
        return nil
    end
    local function gate(map,raw)
        local state='读不到'
        for _,key in ipairs(Check.keys(raw))do
            local ok,value=pcall(function()return map:Contains(key)end)
            if ok then value=U.unwrap(value) else value=nil end
            if value==true then return '已走' elseif value==false then state='没走' end
        end
        return state
    end
    local function read(pipeline)
        local has,any={},false
        for _,t in ipairs(TAGS)do
            has[t]=hasTag(pipeline,t)
            if has[t]==true and t:sub(1,#LZ)==LZ then any=true end
        end
        local map=U.field(pipeline,'ExecuteNodeGuid')
        local gates={}
        for _,g in ipairs(Check.GATES)do gates[g[1]]=gate(map,g[2]) end
        local pillars={}
        for n,p in ipairs(Check.PILLARS)do pillars[n]={fall=gate(map,p.fall),scene=gate(map,p.scene),reward=gate(map,p.reward)} end
        return {has=has,any=any,gates=gates,pillars=pillars}
    end
    local function show(value)return value==nil and '?' or tostring(value) end
    local function lines2(state)
        local parts={}
        for _,short in ipairs(Check.ENDING)do parts[#parts+1]=short..'='..show(state.has[LZ..short]) end
        local g={}
        for _,item in ipairs(Check.GATES)do g[#g+1]=item[1]..'='..state.gates[item[1]] end
        local fromObjects,byText,unknown=0,0,0
        for _,t in ipairs(TAGS)do
            local entry=names[t]
            if not entry then unknown=unknown+1 elseif entry.source=='按名字' then byText=byText+1 else fromObjects=fromObjects+1 end
        end
        local ending=table.concat(parts,' ')..'；只执行一次的节点：'..table.concat(g,' ')
            ..string.format('；标签名 来自对象=%d 按名字=%d 没找到=%d',fromObjects,byText,unknown)
        local p={}
        for n,pillar in ipairs(Check.PILLARS)do
            local tags={}
            for _,base in ipairs(Check.PILLAR_TAGS)do tags[#tags+1]=base..'='..show(state.has[LZ..base..n]) end
            local s=state.pillars[n]
            p[#p+1]=string.format('%d%s[%s 塌=%s 塌后过场=%s 第五战奖励=%s]',n,pillar.map,table.concat(tags,' '),s.fall,s.scene,s.reward)
        end
        return ending,table.concat(p,' ')..'；'..label(Check.BLOODLINE)..'='..show(state.has[Check.BLOODLINE])
    end
    -- The pillar the fifth trial was started at whose fall was never written, or nil and why not.
    local function stuck(state)
        local has=state.has
        if not (has[LZ..'战斗结算5']==true and has[LZ..'龙柱结算Seq5']==true and has[LZ..'胜利5站桩消失']==true) then
            return nil,'第五战的结尾还没走到最后一段'
        end
        if has[LZ..'龙柱试炼完成5']~=false then return nil,'龙柱试炼完成5 不是"没有"' end
        if state.gates['结算过场']~='已走' then return nil,'中心流程最后一个只执行一次的节点不是"已走"' end
        local found
        for n=1,#Check.PILLARS do
            local spot,fall=has[LZ..'点位'..n],has[LZ..'崩塌'..n]
            if spot==nil or fall==nil then return nil,'龙柱'..n..'的标记读不到' end
            if spot and not fall then
                if found then return nil,'不止一根龙柱开过战没塌' end
                found=n
            end
        end
        if not found then return nil,'没有开过战没塌的龙柱' end
        local s=state.pillars[found]
        if s.fall~='没走' or s.scene~='没走' or s.reward~='没走' then return nil,'龙柱'..found..'的塌、塌后过场、奖励节点不是都没走' end
        return found
    end
    -- The pillar's own container holding just 崩塌N (one of its CacheTags nodes), while its flow is loaded.
    local function container(n)
        local ok,list=pcall(findAll,'CacheTags_C')
        for i,object in ipairs(ok and type(list)=='table' and list or {})do
            if i>SCAN_CAP then break end
            if U.valid(object) and fullName(object):find('BPF_LongZhu_'..n..'[^%d]') then
                local tags=U.field(object,'Tags')
                local list2=U.array(U.struct(tags,'GameplayTags')) or {}
                if #list2==1 and text(U.struct(list2[1],'TagName'))==LZ..'崩塌'..n then return tags end
            end
        end
        return nil
    end
    local function repair(pipeline,state)
        local n=stuck(state)
        if not n or n~=baseline or attempted then return end
        local tags=container(n)
        if tags==nil then return end
        attempted=true
        local tag=LZ..'崩塌'..n
        local before=hasTag(pipeline,tag)
        local called,err=pcall(function()pipeline:AddTags(tags)end)
        local after=hasTag(pipeline,tag)
        local how='龙柱流程自带的标签容器'
        if after~=true and names[tag] then
            how=how..'没读回，改用拼的容器'
            called,err=pcall(function()pipeline:AddTags({GameplayTags={{TagName=names[tag].name}},ParentTags={}})end)
            after=hasTag(pipeline,tag)
        end
        if after==true then self.repaired=self.repaired+1 end
        say(string.format('补档 龙柱%d（%s）：第五战在这里开的，结尾那段把缓存写进剧情的一步提前走掉了，这根龙柱一直没塌。按原版补写 [%s]：方式=%s 调用=%s%s 读回 写前=%s 写后=%s%s',
            n,Check.PILLARS[n].map,tag,how,tostring(called),called and '' or ('('..tostring(err)..')'),show(before),show(after),
            after==true and '；接下来由这根龙柱自己的流程放塌的过场、给奖励、写完成和结局条件、存档' or '；没写进去，不再试'))
    end
    function self:tick()
        local now=clock()
        if now<nextRead then return end
        nextRead=now+EVERY
        local pipeline=options.pipeline and options.pipeline()
        if not U.valid(pipeline) then return end
        local key=U.key(pipeline)
        if key~=worldKey then worldKey=key;baseline=nil end
        if now>=nextHarvest and next(wanted()) then nextHarvest=now+HARVEST_EVERY;harvest() end
        local state=read(pipeline)
        self.reads=self.reads+1
        if baseline==nil and state.any then
            local n,why=stuck(state)
            baseline=n or false
            if n then
                say(string.format('这个存档卡在龙柱%d（%s）：第五战在这里开的、打完了，但这根龙柱没塌，奖励、龙柱试炼完成5、结局条件都没写。%s',
                    n,Check.PILLARS[n].map,self.armed and '走到这根龙柱附近时补写 崩塌'..n or '助手里点"修复存档"后，走到这根龙柱附近会补写 崩塌'..n))
            elseif options.verbose then say('不用补档：'..tostring(why)) end
        end
        local ending,pillars=lines2(state)
        if ending~=lastEnding then
            lastEnding=ending
            say((state.any and '第五战结尾 读回：' or '第五战结尾 读回（这条线还没开始）：')..ending)
        end
        if pillars~=lastPillars then lastPillars=pillars;say('龙柱 读回：'..pillars) end
        if self.armed and baseline then repair(pipeline,state) end
    end
    -- From the save-repair button: the repair above may run from now on.
    function self:arm()self.armed=true end
    -- For the save-repair report, from what this world's save held when it was entered: true when there is nothing to
    -- do (false when there is, nil when unread) and a short line.
    function self:diagnose()
        if worldKey==nil then return nil,'龙柱' end
        if self.repaired>0 then return false,'龙柱：已补好，那根龙柱会自己塌、给奖励' end
        if attempted then return false,'龙柱：补写没成功，看日志' end
        if not baseline then return true,'龙柱' end
        return false,string.format('龙柱：卡在龙柱%d（%s），走到它附近自动补上',baseline,Check.PILLARS[baseline].map)
    end
    return self
end
return Check
