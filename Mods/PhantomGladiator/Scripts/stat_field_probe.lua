-- Experiment (Config.EnableStatFieldProbe): can every attribute of a summoned unit be set? On the first
-- blue/red unit summoned after the mod loads, each of character_stats.allFields is written to a test value,
-- held for one support tick, read back (field and native getter) and restored, a chunk of fields at a time.
-- A current value whose maximum is too low for its test value gets the maximum raised for the test; those
-- go last, so a raised maximum never overlaps that maximum's own test. One log line per field, a summary,
-- then the whole set compared with its state before the probe (side effects), restoring what moved.
local Attributes=require('character_stats')
local Probe={}
local BOUND={Health='Health_Max',Shachi='Shachi_Max',Shield='Shield_Max',UltimateCharge='UltimateCharge_Max',
    UltimateChargeCount='UltimateChargeCount_Max',SpiritShadow='SpiritShadow_Max',Awakening='Awakening_Max'}

function Probe.new(options)
    local adapter=options.adapter or Attributes.new()
    local fields=options.fields or Attributes.allFields
    local log=options.log or function()end
    local perTick=options.perTick or 16
    local bound={};for current,max in pairs(BOUND)do bound[current]=max end
    for _,field in ipairs(fields)do if field:match('_Accumulation$') then bound[field]='Infliction_Max' end end
    local chunks={}
    local function chunked(list)
        for i=1,#list,perTick do
            local chunk={};for j=i,math.min(i+perTick-1,#list)do chunk[#chunk+1]=list[j] end
            chunks[#chunks+1]=chunk
        end
    end
    local free,tail={},{}
    for _,field in ipairs(fields)do if bound[field] then tail[#tail+1]=field else free[#free+1]=field end end
    chunked(free);chunked(tail)
    local self={state='idle',counts={},restoreFailed=0}
    local close=Attributes.close
    local function fmt(v)return type(v)=='number' and string.format('%.6g',v) or tostring(v) end
    local function testValue(field,current)
        if bound[field] then return current>0 and current*0.5 or 1 end
        return current~=0 and current*1.5 or 1
    end
    local function stop(state,why)
        self.state=state
        log('[StatProbe] '..(state=='aborted' and '中止：' or '')..why)
    end
    function self:start(actor,unitPath)
        if self.state~='idle' then return false end
        self.actor,self.unit,self.state,self.chunk,self.step=actor,unitPath,'snapshot',0,'write'
        log('[StatProbe] 开始：'..#fields..' 项属性逐项写入测试值、隔一拍读回再恢复；每拍 '..perTick..' 项 unit='..tostring(unitPath))
        return true
    end
    local function snapshot()
        local result,missing={},{}
        for _,field in ipairs(fields)do
            local entry=adapter:read(self.actor,field)
            if entry then result[field]=entry else missing[#missing+1]=field end
        end
        return result,missing
    end
    local function write()
        local pending,raised={},{}
        for _,field in ipairs(chunks[self.chunk])do
            local before,why=adapter:read(self.actor,field)
            if not before then
                if not adapter:read(self.actor,'Health_Max') then return stop('aborted','单位已失效或属性集不可读：'..tostring(why)) end
                self.counts.unreadable=(self.counts.unreadable or 0)+1
                log('[StatProbe] '..field..' 不可读：'..tostring(why))
            else
                local want=testValue(field,before.current)
                local max=bound[field]
                if max and not raised[max] then
                    local limit=adapter:read(self.actor,max)
                    if limit and limit.current<want*2 then
                        raised[max]=limit
                        local ok,err=adapter:writeBase(self.actor,max,want*2)
                        log('[StatProbe] 为测试 '..field..' 临时把 '..max..' 从 '..fmt(limit.current)..' 提到 '..fmt(want*2)..' 写入='..tostring(ok)..(err and (' '..tostring(err)) or ''))
                    end
                end
                local ok,err=adapter:writeBase(self.actor,field,want)
                local now=adapter:read(self.actor,field)
                pending[#pending+1]={field=field,before=before,want=want,ok=ok,err=err,now=now}
            end
        end
        self.pending,self.raised=pending,raised
        self.step='check'
    end
    local function check()
        if not adapter:read(self.actor,'Health_Max') then return stop('aborted','单位已失效或属性集不可读（测试值未恢复）') end
        for _,item in ipairs(self.pending)do
            local field,want=item.field,item.want
            local held=adapter:read(self.actor,field)
            local native=adapter:nativeValue(self.actor,field)
            local result
            if not item.ok then result='error'
            elseif held and close(held.current,want) and close(native,want) then result='ok'
            elseif held and close(held.base,want) then result='base_only'
            elseif item.now and close(item.now.current,want) then result='reverted'
            else result='unchanged' end
            adapter:writeBase(self.actor,field,item.before.base)
            local back=adapter:read(self.actor,field)
            local restored=back~=nil and close(back.base,item.before.base) and close(back.current,item.before.current)
            if not restored then self.restoreFailed=self.restoreFailed+1 end
            self.counts[result]=(self.counts[result] or 0)+1
            log('[StatProbe] '..field..' 方式='..(adapter.via and adapter:via(field) or '?')..' 原值='..fmt(item.before.base)..'/'..fmt(item.before.current)
                ..' 写入='..fmt(want)..' 立即读回='..(item.now and (fmt(item.now.base)..'/'..fmt(item.now.current)) or 'nil')
                ..' 隔拍读回='..(held and (fmt(held.base)..'/'..fmt(held.current)) or 'nil')..' 原生='..fmt(native)
                ..' 恢复='..tostring(restored)..' 结果='..result..(item.err and (' 错误='..tostring(item.err)) or ''))
        end
        for max,limit in pairs(self.raised)do
            adapter:writeBase(self.actor,max,limit.base)
            local back=adapter:read(self.actor,max)
            local restored=back~=nil and close(back.base,limit.base) and close(back.current,limit.current)
            if not restored then self.restoreFailed=self.restoreFailed+1 end
            log('[StatProbe] 恢复 '..max..' 到 '..fmt(limit.base)..' 读回='..(back and fmt(back.current) or 'nil')..' 恢复='..tostring(restored))
        end
        self.pending,self.raised=nil,nil
        self.step='write'
    end
    local function finish()
        local parts={}
        for _,name in ipairs({'ok','base_only','reverted','unchanged','error','unreadable'})do parts[#parts+1]=name..'='..(self.counts[name] or 0) end
        log('[StatProbe] 汇总：'..table.concat(parts,' ')..' 恢复失败='..self.restoreFailed..'（共 '..#fields..' 项）')
        local moved={}
        local after=snapshot()
        for _,field in ipairs(fields)do
            local was,now=self.before[field],after[field]
            if was and now and not (close(now.base,was.base) and close(now.current,was.current)) then
                adapter:writeBase(self.actor,field,was.base)
                local back=adapter:read(self.actor,field)
                moved[#moved+1]=field..' '..fmt(was.current)..'→'..fmt(now.current)..' 恢复后='..(back and fmt(back.current) or 'nil')
            end
        end
        log('[StatProbe] 与测试前对比：'..(#moved==0 and '全部一致' or (#moved..' 项不同：'..table.concat(moved,'；'))))
        stop('done','结束')
    end
    function self:tick()
        if self.state=='idle' or self.state=='done' or self.state=='aborted' then return end
        if self.state=='snapshot' then
            local start,missing=snapshot()
            if not start.Health_Max then return stop('aborted','单位已失效或属性集不可读') end
            self.before,self.state=start,'running'
            log('[StatProbe] 测试前读取 '..(#fields-#missing)..'/'..#fields..' 项'..(#missing>0 and ('，不可读：'..table.concat(missing,',')) or ''))
            return
        end
        if self.step=='check' then return check() end
        self.chunk=self.chunk+1
        if self.chunk>#chunks then return finish() end
        write()
    end
    function self:status()return {state=self.state,counts=self.counts,restore_failed=self.restoreFailed}end
    return self
end
return Probe
