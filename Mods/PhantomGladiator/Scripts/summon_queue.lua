-- Optional bounded queue. It stores request values, never engine objects or callbacks.
local Queue={}
local CAPACITY=100
local GAP=0.25

function Queue.new(options)
    local self={enabled=false,jobs={},revision=0,completed=0,message=''}
    local now=options.now or os.clock
    local log=options.log or function()end

    function self:epoch()
        return 'SQ_'..self.revision
    end

    function self:cancel(reason)
        local n=#self.jobs
        self.jobs={}
        self.revision=self.revision+1
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
        self.message='已入队，待执行 '..#self.jobs..' 条'
        return {ok=true,message=self.message,spawned_count=0}
    end

    function self:tick()
        if not self.enabled or self.running or #self.jobs==0 or (self.nextAt and now()<self.nextAt) then return end
        local checked,status=pcall(options.session)
        self:sync(checked and status or nil)
        if not self.session or #self.jobs==0 then return end

        local job=table.remove(self.jobs,1)
        local revision=self.revision
        self.running=true
        log('[SummonQueue] 开始一笔 unit='..job.path..' team='..job.team..' count='..job.count)
        local called,result=pcall(options.spawn,job.path,job.team,job.count)
        self.nextAt=now()+GAP
        self.running=false
        if revision~=self.revision then return end
        if not called or type(result)~='table' or result.uncertain or result.ok~=true then
            local detail=called and type(result)=='table' and result.message or '生成结果未确认'
            self:cancel('召唤未完成：'..tostring(detail))
            return
        end
        self.completed=self.completed+1
        self.message=tostring(result.message or '召唤完成')
        log('[SummonQueue] 完成一笔；读回='..self.message..'；剩余='..#self.jobs)
    end

    return self
end

return Queue
