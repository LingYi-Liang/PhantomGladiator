-- Optional bounded queue. It stores request values, never engine objects or callbacks.
local Queue={}
local CAPACITY=100
local MODES={TIMED=true,SINGLE=true,WAVE=true}
local function integer(n,lo,hi)return type(n)=='number' and n%1==0 and n>=lo and n<=hi end

function Queue.new(options)
    local self={enabled=false,jobs={},revision=0,completed=0,generated=0,message='',mode='TIMED',intervalMs=250,blueSlots=3,redSlots=3}
    local now=options.now or os.clock
    local log=options.log or function()end
    local fs=options.io or io
    local path=options.path and options.path..'/summon-queue-settings.tsv'
    local function valid(mode,ms,blue,red)return MODES[mode] and integer(ms,50,600000) and integer(blue,1,100) and integer(red,1,100) end
    local function read()
        local f=path and fs.open(path,'r');if not f then return nil end
        local text=f:read('*a');f:close();return text
    end
    do
        local mode,ms,blue,red=(read() or ''):match('^SummonQueueSettingsV1\t(%u+)\t(%d+)\t(%d+)\t(%d+)\r?\n$')
        ms,blue,red=tonumber(ms),tonumber(blue),tonumber(red)
        if valid(mode,ms,blue,red) then self.mode,self.intervalMs,self.blueSlots,self.redSlots=mode,ms,blue,red end
    end
    function self:isRelay()return self.mode~='TIMED' end
    function self:reserves()
        local counts={blue=0,red=0}
        for _,job in ipairs(self.jobs)do if counts[job.team] then counts[job.team]=counts[job.team]+job.count end end
        return counts
    end
    local function pending()
        local n=self:reserves()
        if options.pending then options.pending(self.enabled and self:isRelay(),self.relayStarted and n.blue or 0,self.relayStarted and n.red or 0,self.revision) end
    end
    function self:configure(mode,ms,blue,red)
        if not valid(mode,ms,blue,red) then return {ok=false,message='间隔须为0.05–600秒，每批人数须为1–100'} end
        if self.enabled and (mode~=self.mode or blue~=self.blueSlots or red~=self.redSlots) then
            return {ok=false,message='请先关闭排队，再切换模式或每批人数；关闭会取消候补'}
        end
        local text=string.format('SummonQueueSettingsV1\t%s\t%d\t%d\t%d\n',mode,ms,blue,red)
        if path then
            local f=fs.open(path,'w');local wrote=f and f:write(text);local closed=f and f:close()
            if not wrote or not closed or read()~=text then return {ok=false,message='排队设置保存未确认，旧设置继续生效'} end
        end
        self.mode,self.intervalMs,self.blueSlots,self.redSlots=mode,ms,blue,red
        if self.lastDone then self.nextAt=self.lastDone+ms/1000 end
        log('[SummonQueue] 设置保存读回 mode='..mode..' interval_ms='..ms..' blue='..blue..' red='..red)
        return {ok=true,message='排队设置已保存；间隔 '..(ms/1000)..' 秒'}
    end

    function self:epoch()
        return 'SQ_'..self.revision
    end

    function self:cancel(reason)
        local n=#self.jobs
        self.jobs={}
        self.relayStarted=false;self.initial=nil;self.waves={};self.pollAt=nil
        self.nextAt,self.lastDone=now(),nil
        self.revision=self.revision+1
        pending()
        self.message=reason..'，已取消 '..n..' 条待执行召唤'
        log('[SummonQueue] '..self.message..' epoch='..self:epoch())
        return n
    end

    function self:sync(status)
        local session=type(status)=='table' and status.game_ready==true and status.game_session or nil
        if type(session)~='string' or session=='' then session=nil end
        if self.session and self.session~=session then self:cancel('游戏会话变化或尚未就绪') end
        self.session=session
    end

    function self:enqueue(path,team,count,epoch)
        if not self.enabled then return {ok=false,message='排队召唤未开启',spawned_count=0} end
        if epoch and epoch~=self:epoch() then return {ok=false,message='该请求属于已取消的召唤队列',spawned_count=0} end
        if not self.session then return {ok=false,message='游戏尚未就绪，未入队',spawned_count=0} end
        if type(path)~='string' or path=='' or
            (team~='blue' and team~='red' and team~='neutral' and team~='companion') or
            type(count)~='number' or count%1~=0 or count<1 or count>100 then
            return {ok=false,message='单位、队伍或召唤数量无效，未入队',spawned_count=0}
        end
        if #self.jobs>=CAPACITY then
            self.message='召唤队列已满（100 条）'
            return {ok=false,message=self.message,spawned_count=0}
        end
        self.jobs[#self.jobs+1]={path=path,team=team,count=count}
        pending()
        self.message='已入队，待执行 '..#self.jobs..' 条'
        return {ok=true,message=self.message,spawned_count=0}
    end

    local function snapshot()
        local ok,s=pcall(options.state or function()end)
        if not ok or type(s)~='table' or not integer(s.blue_count,0,1000000) or not integer(s.red_count,0,1000000) then return nil end
        for _,field in ipairs({'blue_unreadable','red_unreadable','unreadable_count'})do
            if s[field]~=nil and not integer(s[field],0,1000000) then return nil end
        end
        return s
    end
    local function unread(s,team)return (s[team..'_unreadable'] or s.unreadable_count or 0)>0 end
    local function slots(team)return self.mode=='SINGLE' and 1 or (team=='blue' and self.blueSlots or self.redSlots) end
    function self:startRelay()
        if not self.enabled or not self:isRelay() then return {ok=false,message='接力模式未开启'} end
        if self.relayStarted then return {ok=false,message='接力已开始'} end
        local s=snapshot();local reserves=self:reserves()
        if not s or unread(s,'blue') or unread(s,'red') then return {ok=false,message='参战存活状态未读回，暂不开始接力'} end
        if s.blue_count+reserves.blue==0 or s.red_count+reserves.red==0 then return {ok=false,message='接力需要蓝红双方的首发或候补'} end
        self.relayStarted=true;self.initial=not s.battle_active;self.waves={};self.pollAt=nil
        for _,team in ipairs({'blue','red'})do
            self.waves[team]={budget=s[team..'_count']>0 and 0 or math.min(slots(team),reserves[team]),number=1}
        end
        pending();log('[SummonQueue] 接力开始 mode='..self.mode..' blue='..s.blue_count..' red='..s.red_count)
        return {ok=true,message='接力已开始，首批生成后自动开战；不重置胜方血量'}
    end

    local function relayIndex()
        self.pollAt=now()+0.25
        if not self.relayStarted then
            for i,job in ipairs(self.jobs)do if job.team~='blue' and job.team~='red' then self.pollAt=nil;return i,job.count end end
            return
        end
        local s=snapshot();if not s then self.message='等待存活状态读回';return end
        if not self.initial and s.battle_active==false then self:cancel('战斗已停止，取消剩余接力');return end
        local reserves=self:reserves()
        if self.initial and self.waves.blue.budget==0 and self.waves.red.budget==0 then
            if unread(s,'blue') or unread(s,'red') then return end
            if s.blue_count==0 or s.red_count==0 then self:cancel('首批存活未确认，未自动重复生成');return end
            local revision=self.revision
            local ok,result=pcall(options.begin or function()end)
            if revision~=self.revision or not self.relayStarted then return end
            if not ok or type(result)~='table' or not result.ok then self:cancel('开战未确认，接力停止，已生成单位保留');return end
            self.initial=false;pending();log('[SummonQueue] 首批开战读回=true')
        end
        if not self.initial then
            for _,team in ipairs({'blue','red'})do
                local wave=self.waves[team]
                if s[team..'_count']==0 and not unread(s,team) and wave.budget==0 and reserves[team]==0 then
                    self.relayStarted=false;pending();self.message='接力结束：'..(team=='blue' and '蓝方' or '红方')..'已无在场单位和候补'
                    log('[SummonQueue] '..self.message);return
                end
            end
            for _,team in ipairs({'blue','red'})do
                local wave=self.waves[team]
                if s[team..'_count']>0 or unread(s,team) then wave.emptyAt=nil
                elseif wave.budget==0 and reserves[team]>0 then
                    wave.emptyAt=wave.emptyAt or now()
                    if now()-wave.emptyAt>=math.max(0.25,self.intervalMs/1000) then
                        wave.budget=math.min(slots(team),reserves[team]);wave.number=wave.number+1;wave.emptyAt=nil
                        log('[SummonQueue] 本方全部退场读回 team='..team..' next_wave='..wave.number..' count='..wave.budget)
                    end
                end
            end
        end
        for i,job in ipairs(self.jobs)do
            local wave=self.waves[job.team]
            if not wave then self.pollAt=nil;return i,job.count end
            if wave.budget>0 and not unread(s,job.team) then self.pollAt=nil;return i,1 end
        end
        self.message='接力进行中，等待本方当前批次全部阵亡或退场'
    end

    function self:tick()
        if not self.enabled or self.running or (#self.jobs==0 and not self.relayStarted) then return end
        local relayMode=self:isRelay()
        if not relayMode and self.nextAt and now()<self.nextAt then return end
        if relayMode and self.pollAt and now()<self.pollAt then return end
        local checked,status=pcall(options.session)
        self:sync(checked and status or nil)
        if not self.session then return end

        local index,take=1,nil
        if relayMode then index,take=relayIndex() end
        if self.nextAt and now()<self.nextAt then
            -- Generation pacing must not delay battle start or death observation. Observe at most 4 Hz
            -- while cooling down, waking sooner when the next generation is due.
            if relayMode then self.pollAt=math.min(now()+0.25,self.nextAt) end
            return
        end
        if not index or not self.jobs[index] then return end
        local job=self.jobs[index];take=take or job.count
        local revision=self.revision
        self.running=true
        log('[SummonQueue] 开始一笔 unit='..job.path..' team='..job.team..' count='..take..' request_left='..job.count)
        local called,result=pcall(options.spawn,job.path,job.team,take)
        self.running=false
        if revision~=self.revision then return end
        self.lastDone=now();self.nextAt=self.lastDone+self.intervalMs/1000
        if not called or type(result)~='table' or result.uncertain or result.ok~=true then
            local detail=called and type(result)=='table' and result.message or '生成结果未确认'
            self:cancel('召唤未完成：'..tostring(detail))
            return
        end
        job.count=job.count-take
        if job.count==0 then table.remove(self.jobs,index);self.completed=self.completed+1 end
        self.generated=self.generated+take
        if self:isRelay() and self.waves and self.waves[job.team] then self.waves[job.team].budget=self.waves[job.team].budget-take end
        if self.relayStarted and self.waves and self.waves.blue.budget+self.waves.red.budget>0 then
            self.pollAt=math.min(self.nextAt,self.lastDone+0.25)
        end
        pending()
        self.message=tostring(result.message or '召唤完成')
        log('[SummonQueue] 完成一笔；读回='..self.message..'；剩余='..#self.jobs)
    end

    return self
end

return Queue
