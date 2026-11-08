-- The app's save-repair button: puts right, with the game's own steps, what earlier versions of this mod did to saves,
-- and reports what it found. Nothing here writes until the button is pressed.
--  1. 龙柱 (longzhu_check.lua): the arena's 魔渊 finisher wrote lz.龙柱.战斗胜利5, so the fifth trial's ending ran before the
--     trial and the pillar it was then started at never fell. Armed: that pillar gets 崩塌N once the player is near it.
--  2. 雷当 (story_guard.lua): a summoned 雷当's phase-end move wrote qsd.击杀.雷当, so in 戏梦山庄 phase two comes out
--     with phase one still to fight. Armed: phase one's spawner is turned off as the game does when Seq123-4 starts.
--  3. 冷荼 (boss_stages.lua): a summoned 冷荼 wrote her phase checkpoint under LengTu_Combat, the ID of her own fight in
--     断魂崖. Armed, and only while that fight has not started (neither dhy.冷荼入战seq tag, both written as its opening
--     scene Seq144 starts): the next 冷荼 summoned in the arena clears it with her own ResetTags.
--  4. Other story marks summoned units wrote (story_writes.lua's list) cannot be taken out: the story system has no call
--     that removes one. A mark whose story reaction has not run yet (its one-time node is not in ExecuteNodeGuid, and
--     nothing says that part is over) is reported with what will happen.
local U=require('ue_observe')
local Keys=require('longzhu_check').keys
local Repair={}
Repair.CHECKPOINT_ID='LengTu_Combat'
Repair.FIGHT_STARTED={'dhy.冷荼入战seq.完成湖心秘密','dhy.冷荼入战seq.未完成湖心秘密'}
-- A mark a summoned unit writes, the one-time node its story reaction starts with (GUID as the asset stores it), and the
-- marks that say that part of the story is over.
Repair.REACTIONS={
    {tag='ljc.沐小葵.血量降低到25',gate='235520622930ca4b81cbe1930f25624d',          -- BPF_MuXiaoKuiDeath SetExcuteType_C_2
        over={'ljc.沐小葵.战斗结束','hp.击杀.沐小葵','hp.击杀.沐小葵二阶段'},
        what='沐小葵：她 25% 血的结尾过场可能一开打就放'},
    {tag='rzgd.击败.钩者',gate='7434a89722ce5c4584762a2aeb623a0d',over={},        -- BPF_HookMan_Dead SetExcuteType_C_0
        what='马车战：钩者那段会直接算打败'},
    {tag='rzgd.击败.两个枪鬼差',gate='22c8f7169c07a94b8240ccf3400bf3b7',over={},  -- BPF_play005_1 SetExcuteType_C_3
        what='马车战：两个枪鬼差那段会直接算打败'},
}
local LINES=30

function Repair.new(options)
    local log=options.log or function()end
    local has=options.has or function()return nil end
    local self={runs=0,armed=false,checkpoint='idle'}
    local lines=0
    local function say(message)
        if lines<LINES then lines=lines+1;log('[SaveRepair] '..message) end
    end
    -- Whether a one-time node has run: true, false, or nil when it cannot be read.
    local function walked(raw)
        local pipeline=options.pipeline and options.pipeline()
        local map=U.valid(pipeline) and U.field(pipeline,'ExecuteNodeGuid') or nil
        if map==nil then return nil end
        local state
        for _,key in ipairs(Keys(raw))do
            local ok,value=pcall(function()return map:Contains(key)end)
            if ok then value=U.unwrap(value) else value=nil end
            if value==true then return true elseif value==false then state=false end
        end
        return state
    end
    -- Whether 冷荼's own fight has started: true, false, or nil.
    local function fightStarted()
        local result=false
        for _,t in ipairs(Repair.FIGHT_STARTED)do
            local value=has(t)
            if value==true then return true end
            if value==nil then result=nil end
        end
        return result
    end
    -- 冷荼's checkpoint: true when there is nothing to do (false when there is, nil when unread) and a short line.
    local function checkpointCheck()
        if self.checkpoint=='cleared' then return false,'冷荼：已清掉她的阶段进度' end
        if self.checkpoint=='failed' then return false,'冷荼：清阶段进度没成功，看日志' end
        local saved=options.hasSaveData and options.hasSaveData(Repair.CHECKPOINT_ID)
        if saved==false then self.checkpoint='idle';return true,'冷荼' end
        local started=fightStarted()
        if started==true then self.checkpoint='idle';return true,'冷荼' end
        if started==nil then self.checkpoint='idle';return nil,'冷荼' end
        self.checkpoint='armed'
        return false,'冷荼：阶段进度'..(saved==true and '' or '可能')..'是模组写的，下次在竞技场叫出冷荼时清掉'
    end
    -- Marks other units wrote before their part of the story: what will happen, one line each.
    local function reactionChecks()
        local out,unread={},0
        for _,r in ipairs(Repair.REACTIONS)do
            local present=has(r.tag)
            if present==nil then unread=unread+1
            elseif present then
                local done=false
                for _,t in ipairs(r.over)do if has(t)==true then done=true end end
                if not done then
                    local ran=walked(r.gate)
                    if ran==nil then unread=unread+1 elseif ran==false then out[#out+1]=r.what..'（删不掉）' end
                end
            end
        end
        return out,unread
    end

    -- The button: arms the repairs and returns the report as one message (it travels in a 512-byte reply), parts split
    -- by '；': what is wrong and what happens about it, then what was checked and found fine, then what could not be read.
    function self:run()
        self.runs=self.runs+1
        self.armed=true
        if options.longzhu then options.longzhu:arm() end
        if options.guard then options.guard:arm() end
        local problems,fine,unread={},{},{}
        local function add(ok,line,name)
            if ok==true then fine[#fine+1]=name elseif ok==nil then unread[#unread+1]=name else problems[#problems+1]=line end
        end
        if options.longzhu then local ok,line=options.longzhu:diagnose();add(ok,line,'龙柱') else add(nil,nil,'龙柱') end
        if options.guard then local ok,line=options.guard:diagnose(has);add(ok,line,'雷当') else add(nil,nil,'雷当') end
        local ok,line=checkpointCheck();add(ok,line,'冷荼')
        local found,missed=reactionChecks()
        for _,item in ipairs(found)do problems[#problems+1]=item end
        if #found==0 and missed==0 then fine[#fine+1]='其他单位写的剧情标记' end
        if missed>0 then unread[#unread+1]='其他单位的标记 '..missed..' 条' end
        local parts={}
        if #problems==0 and #unread==0 then parts[1]='没发现模组造成的存档问题（查了'..table.concat(fine,'、')..'）'
        else
            for _,p in ipairs(problems)do parts[#parts+1]=p end
            if #fine>0 then parts[#parts+1]='没问题：'..table.concat(fine,'、') end
            if #unread>0 then parts[#parts+1]='读不到：'..table.concat(unread,'、')..'（进游戏世界几秒后再点）' end
        end
        local message=table.concat(parts,'；')
        say('第 '..self.runs..' 次：'..message)
        return {ok=true,message=message,problems=#problems}
    end
    -- boss_stages.lua asks before a summoned 冷荼 moves to the mod's ID: clear this ID's checkpoint first?
    function self:wantsCheckpoint(id)
        if id~=Repair.CHECKPOINT_ID or self.checkpoint~='armed' then return false end
        local started=fightStarted()
        if started~=false then
            say('冷荼：清阶段进度前再查，剧情里的冷荼战开始了吗='..tostring(started)..'，不清')
            self.checkpoint='idle'
            return false
        end
        return true
    end
    -- boss_stages.lua after she was born under that ID: ok when what she read there is empty.
    function self:checkpointDone(id,ok,read)
        self.checkpoint=ok and 'cleared' or 'failed'
        say(string.format('冷荼：存档里 %s 的阶段进度 清掉后读回=[%s] %s',id,read and table.concat(read,',') or '读不到',ok and '已清空' or '没清空'))
    end
    function self:status()return {save_repair_runs=self.runs,save_repair_armed=self.armed,save_repair_checkpoint=self.checkpoint}end
    return self
end
return Repair
