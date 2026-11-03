-- Spawn stats, chosen in the app's 数值设定 card and saved in Runtime/stat-match-settings.tsv:
--   game    units keep the numbers the game gives them (summon level and difficulty);
--   match   the first unit summoned becomes the baseline and later ones copy its spawn values (v0.27);
--   custom  any of the 223 attributes the player filled in are written at spawn (v0.37); empty fields keep
--           the unit's own value. The values come from Runtime/stat-custom-request.tsv, written by the backend
--           under the revision named in the command, and are kept in the settings file once read back.
-- One write per field at spawn, read back. Matching is all or nothing: any failure rolls the unit back to
-- its own numbers. Custom goes field by field: a field the game does not take is rolled back and named, the
-- rest stay. Never follows damage or heals on a tick.
-- Damage comes from the level-1 values (character_stats.lua Stats.levelOne), so matching copies those too,
-- and a custom HP, Sha-Chi, attack or Sha-Chi damage scales its level-1 value by the same ratio unless the
-- player set that one as well.
local Attributes=require('character_stats')
local Match={}
local RESOURCES={{'Health','Health_Max'},{'Shachi','Shachi_Max'}}
local resources={Health='Health_Max',Shachi='Shachi_Max'}
local positive={Health=true,Shachi=true,Health_Max=true,Shachi_Max=true,Attack=true,ShachiAttack=true}
local strictlyPositive={Health=true,Health_Max=true,Shachi_Max=true,Attack=true}
-- Current values and the maximum that bounds each: custom writes maxima first and currents last, and a
-- maximum rolled back restores its current too.
local BOUND={Health='Health_Max',Shachi='Shachi_Max',Shield='Shield_Max',UltimateCharge='UltimateCharge_Max',
    UltimateChargeCount='UltimateChargeCount_Max',SpiritShadow='SpiritShadow_Max',Awakening='Awakening_Max'}
local CORE={'Health_Max','Shachi_Max','Attack','ShachiAttack'}
local MODES={GAME='game',MATCH='match',CUSTOM='custom'}
local LABEL={Health_Max='血量上限',Shachi_Max='杀气上限',Attack='攻击',ShachiAttack='削杀气'}
Match.core=CORE

function Match.new(options)
    local adapter=options.adapter or Attributes.new()
    local fields=options.fields or Attributes.fields
    local customFields=options.customFields or Attributes.allFields
    local levelOne=options.levelOne or Attributes.levelOne
    local levelOneFields=options.levelOneFields or Attributes.levelOneFields
    local isLevelOne={};for _,field in pairs(levelOne)do isLevelOne[field]=true end
    local log=options.log or function()end
    local fs=options.io or io
    local settings=options.path..'/stat-match-settings.tsv'
    local request=options.path..'/stat-custom-request.tsv'
    local allowed={};for _,field in ipairs(customFields)do allowed[field]=true end
    local bound,bounded={},{}
    for current,max in pairs(BOUND)do bound[current]=max;bounded[max]=current end
    for _,field in ipairs(customFields)do if field:match('_Accumulation$') then bound[field]='Infliction_Max' end end
    local function phase(field)
        if isLevelOne[field] then return 1 end
        if bounded[field] or field=='Infliction_Max' then return 2 end
        if field=='Health_Min' or field=='Shachi_Min' then return 4 end
        return bound[field] and 5 or 3
    end
    local self={mode='game',custom={},enabled=false,baseline=nil,matched=0,customized=0,failures=0,owned=0,
        rejected={},message='按游戏数值'}
    local function readFile(path)
        local f=fs.open(path,'r');if not f then return nil end
        local text=f:read('*a');f:close();return text
    end
    -- "field\tvalue" lines; only known fields, finite values within the attribute's valid range.
    local function parse(body)
        local values,count={},0
        for line in (body or ''):gmatch('[^\n]+')do
            local field,raw=line:match('^([%w_]+)\t([^\t]+)$')
            local value=tonumber(raw)
            if not field or not allowed[field] then return nil,'未知属性 '..tostring(field or line) end
            if not Attributes.finite(value) then return nil,field..' 不是有效数字' end
            if (strictlyPositive[field] and value<=0) or (positive[field] and value<0) then return nil,field..' 必须大于 0' end
            if values[field]==nil then count=count+1 end
            values[field]=value
        end
        return values,count
    end
    local function encode(mode,custom)
        local lines={'StatMatchV2\t'..mode}
        for _,field in ipairs(customFields)do
            if custom[field]~=nil then lines[#lines+1]=field..'\t'..string.format('%.10g',custom[field]) end
        end
        return table.concat(lines,'\n')..'\n'
    end
    do
        local text=readFile(settings)
        if text=='StatMatchV1\t1\n' then self.mode='match'
        elseif type(text)=='string' then
            local mode,body=text:match('^StatMatchV2\t(%l+)\n(.*)$')
            local values=body and parse(body)
            if mode and values and (mode=='game' or mode=='match' or mode=='custom') then self.mode,self.custom=mode,values end
        end
        self.enabled=self.mode~='game'
        self.message=self.mode=='match' and '已开启，等待第一只可用战斗单位作为基准' or self.mode=='custom' and '自定义数值：之后召唤的单位按设定写入' or '按游戏数值'
    end
    local function count(custom)local n=0;for _ in pairs(custom)do n=n+1 end;return n end
    local function describe(custom)
        local parts={}
        for _,field in ipairs(CORE)do if custom[field] then parts[#parts+1]=LABEL[field]..'='..string.format('%.10g',custom[field]) end end
        local n=count(custom)
        if n>#parts then parts[#parts+1]='其他 '..(n-#parts)..' 项' end
        return #parts>0 and table.concat(parts,'、') or '无'
    end
    local function reset(reason)
        self.baseline=nil;self.matched=0;self.customized=0;self.failures=0;self.rejected={}
        self.message=self.mode=='match' and ('等待首只可用战斗单位作为基准；'..reason)
            or self.mode=='custom' and ('自定义数值：'..describe(self.custom)..'；只影响之后的召唤')
            or '按游戏数值；只影响之后的召唤'
        log('[StatMatch] 设定重置：'..reason..' 模式='..self.mode)
    end
    local function save(mode,custom)
        local text=encode(mode,custom)
        local file=fs.open(settings,'w')
        if not file then return false end
        local wrote=file:write(text);local closed=file:close()
        return wrote~=nil and wrote~=false and closed~=false and readFile(settings)==text
    end
    local function switch(mode,custom,reason)
        if not save(mode,custom) then return {ok=false,message='数值设定保存未读回，未修改',spawned_count=0} end
        self.mode,self.custom=mode,custom;self.enabled=mode~='game'
        reset(reason)
        log('[StatMatch] 设定读回 模式='..mode..' 自定义='..describe(custom))
        return {ok=true,message=self.message,spawned_count=0}
    end
    -- Old switch (toggle_stat_match): between the game's numbers and the first unit's.
    function self:toggle()
        return switch(self.mode=='game' and 'match' or 'game',self.custom,self.mode=='game' and '开关已开启' or '开关已关闭；场上单位保持当前数值')
    end
    -- GAME, MATCH or CUSTOM; CUSTOM reads the backend's request file written under `revision`.
    function self:setMode(token,revision)
        local mode=MODES[token]
        if not mode then return {ok=false,message='数值设定只接受 GAME、MATCH 或 CUSTOM',spawned_count=0} end
        local custom=self.custom
        if mode=='custom' then
            local rev,body=(readFile(request) or ''):match('^StatCustomV1\t(%S+)\n(.*)$')
            if not rev or rev~=revision then return {ok=false,message='没读到这次的自定义数值（可能已被更新的设定替换），未修改',spawned_count=0} end
            local values,n=parse(body)
            if not values then return {ok=false,message='自定义数值无效：'..tostring(n)..'，未修改',spawned_count=0} end
            if n==0 then return {ok=false,message='自定义数值是空的，未修改',spawned_count=0} end
            custom=values
        end
        return switch(mode,custom,mode=='custom' and '自定义数值已更新' or mode=='match' and '改为统一成第一只' or '改为按游戏数值')
    end
    function self:roster(units)
        self.owned=#units
        if self.owned==0 and self.baseline then reset('本Mod单位已全部清空') end
    end
    local function writeAndRead(actor,field,base)
        if not Attributes.finite(base) or (positive[field] and base<0) or (strictlyPositive[field] and base<=0) then return nil,'无法在有效基础值范围内对齐 '..field end
        local ok,why=adapter:writeBase(actor,field,base)
        if not ok then return nil,why end
        return adapter:read(actor,field)
    end
    local function matchValue(actor,field,wanted)
        local before,why=adapter:read(actor,field);if not before then return false,why end
        if Attributes.close(before.current,wanted) then return true end
        local after;after,why=writeAndRead(actor,field,wanted)
        if not after then return false,why end
        if Attributes.close(after.current,wanted) then return true end
        -- Native ongoing modifiers can scale the base. Calibrate at most twice,
        -- with positive probes; never install a permanent override/health lock.
        local delta=after.base-before.base
        if math.abs(delta)<1e-6 then
            before=after
            after,why=writeAndRead(actor,field,after.base+math.max(0.01,math.abs(after.base)*0.01))
            if not after then return false,why end
            delta=after.base-before.base
        end
        local slope=math.abs(delta)>1e-6 and (after.current-before.current)/delta or 0
        if not Attributes.finite(slope) or slope<=1e-6 then return false,'原生覆盖/限值使属性无法对齐: '..field end
        local base=after.base+(wanted-after.current)/slope
        local final;final,why=writeAndRead(actor,field,base)
        if not final or not Attributes.close(final.current,wanted) then return false,why or ('最终属性未对齐: '..field) end
        return true
    end
    local function rollback(actor,original,touched)
        local ok=true
        local function restore(field)
            local before=adapter:read(actor,field)
            if before and Attributes.close(before.base,original[field].base) and Attributes.close(before.current,original[field].current) then return end
            local called=adapter:writeBase(actor,field,original[field].base)
            if not called then ok=false end
        end
        for i=#touched,1,-1 do
            local field=touched[i]
            if not resources[field] then restore(field) end
        end
        -- Restore the bounds first, otherwise the old health/shachi may be clamped
        -- against the temporary smaller maximum and never return to its snapshot.
        for _,field in ipairs({'Health','Shachi'})do restore(field) end
        for _,field in ipairs(touched)do
            local actual=adapter:read(actor,field)
            if not actual or not Attributes.close(actual.base,original[field].base) or not Attributes.close(actual.current,original[field].current) then ok=false end
        end
        return ok
    end
    -- Writes every target in order, reads all of them back and the core ones through the native
    -- getter too; on any failure the unit returns to its snapshot.
    local function apply(actor,unitPath,original,targets,ordered,label)
        local touched={};local failure
        for _,field in ipairs(ordered)do
            touched[#touched+1]=field
            local ok,reason=matchValue(actor,field,targets[field])
            if not ok then failure=reason;break end
        end
        if not failure then
            for _,field in ipairs(ordered)do
                local actual=adapter:read(actor,field)
                if not actual or not Attributes.close(actual.current,targets[field]) then failure='批次读回不一致: '..field;break end
            end
        end
        if not failure then
            for _,field in ipairs(CORE)do
                if targets[field]~=nil then
                    local actual=adapter:nativeValue(actor,field)
                    if not Attributes.close(actual,targets[field]) then failure='原生函数独立读回不一致: '..field;break end
                end
            end
        end
        if failure then
            -- Resource values may also change when a maximum is adjusted.
            for _,field in ipairs({'Health','Shachi'})do
                local found=false;for _,name in ipairs(touched)do if name==field then found=true end end
                if not found then touched[#touched+1]=field end
            end
            local restored=rollback(actor,original,touched)
            self.failures=self.failures+1;self.message=label..'失败：'..tostring(failure)..'；回滚读回='..tostring(restored)
            log('[StatMatch] '..self.message..' unit='..tostring(unitPath))
            return {ok=false,message=self.message,rollback_verified=restored}
        end
        return nil
    end
    local function restoreField(actor,original,field)
        local entry=original[field]
        local now=adapter:read(actor,field)
        if now and Attributes.close(now.base,entry.base) and Attributes.close(now.current,entry.current) then return true end
        adapter:writeBase(actor,field,entry.base)
        now=adapter:read(actor,field)
        return now~=nil and Attributes.close(now.base,entry.base) and Attributes.close(now.current,entry.current)
    end
    -- Maxima, then the other fields, then the minimums, then current values. Each field is written, read back
    -- (field and native getter), and rolled back on its own if the game does not take it; a rolled-back
    -- maximum restores its current value as well.
    local function applyCustom(actor,unitPath)
        local targets,ordered,linked={},{},{}
        -- A custom value moves its level-1 value by the same ratio, so the unit takes and deals hits to match.
        for _,field in ipairs(customFields)do
            local lv1=levelOne[field]
            if lv1 and self.custom[field]~=nil and self.custom[lv1]==nil then
                local own,base=adapter:read(actor,field),adapter:read(actor,lv1)
                if own and base and own.current>0 and Attributes.finite(base.current) then
                    targets[lv1]=base.current*self.custom[field]/own.current
                    linked[#linked+1]=lv1..' '..string.format('%.6g',base.current)..'→'..string.format('%.6g',targets[lv1])
                end
            end
        end
        for step=1,5 do
            for _,field in ipairs(customFields)do
                if self.custom[field]~=nil and phase(field)==step then targets[field]=self.custom[field] end
                if targets[field]~=nil and phase(field)==step then ordered[#ordered+1]=field end
            end
        end
        -- A new HP or Sha-Chi maximum comes with a full bar.
        for _,pair in ipairs(RESOURCES)do
            if targets[pair[2]]~=nil and targets[pair[1]]==nil then targets[pair[1]]=targets[pair[2]];ordered[#ordered+1]=pair[1] end
        end
        local original,rejected,done={},{},{}
        local function reject(field,reason)rejected[#rejected+1]={field=field,reason=tostring(reason)} end
        for _,field in ipairs(ordered)do
            for _,name in ipairs({field,bounded[field]})do
                if not original[name] then original[name]=adapter:read(actor,name) end
            end
        end
        local restored=true
        local function undo(field)
            if not restoreField(actor,original,field) then restored=false end
            local current=bounded[field]
            if current and original[current] and not restoreField(actor,original,current) then restored=false end
        end
        for _,field in ipairs(ordered)do
            if not original[field] then reject(field,'属性不可读')
            else
                local ok,reason=matchValue(actor,field,targets[field])
                if ok then done[#done+1]=field else reject(field,reason);undo(field) end
            end
        end
        -- A later write can move an earlier field (a lower maximum clamps its current value).
        local verified={}
        for _,field in ipairs(done)do
            local actual=adapter:read(actor,field)
            local native=adapter:nativeValue(actor,field)
            if actual and Attributes.close(actual.current,targets[field]) and Attributes.close(native,targets[field]) then
                verified[#verified+1]=field
            else
                reject(field,'写入后读回='..tostring(actual and actual.current)..' 原生='..tostring(native));undo(field)
            end
        end
        self.rejected={};for _,item in ipairs(rejected)do self.rejected[#self.rejected+1]=item.field end
        for _,item in ipairs(rejected)do
            log('[StatMatch] 自定义未生效 '..item.field..' 目标='..string.format('%.10g',targets[item.field])
                ..' 方式='..(adapter.via and adapter:via(item.field) or '?')..' 原因='..item.reason..' unit='..tostring(unitPath))
        end
        if #verified==0 then
            self.failures=self.failures+1
            self.message='自定义数值失败：'..(rejected[1] and (rejected[1].field..' '..rejected[1].reason) or '没有可写入的属性')..'；回滚读回='..tostring(restored)
            log('[StatMatch] '..self.message..' unit='..tostring(unitPath))
            return {ok=false,message=self.message,rollback_verified=restored}
        end
        self.customized=self.customized+1
        self.message='自定义数值已写入并读回 '..#verified..'/'..#ordered..' 项'..(#rejected>0 and ('；'..#rejected..' 项游戏没接受，已恢复原值') or '')
            ..'；已写入 '..self.customized..' 只'
        log('[StatMatch] 自定义应用并读回 unit='..tostring(unitPath)..' verified='..#verified..'/'..#ordered
            ..' rejected='..#rejected..' 回滚读回='..tostring(restored)..' '..describe(self.custom)
            ..(#linked>0 and (' 联动1级值：'..table.concat(linked,'、')) or ''))
        return {ok=true,applied=true,message=self.message,rejected=self.rejected}
    end
    function self:onSpawn(actor,unitPath)
        if self.mode=='game' then return {ok=true,message='按游戏数值'} end
        if self.mode=='custom' then
            if next(self.custom)==nil then return {ok=true,message='自定义数值为空'} end
            return applyCustom(actor,unitPath)
        end
        local original,why=adapter:snapshot(actor)
        if not original then
            self.message='未写入数值：'..tostring(why)
            log('[StatMatch] '..self.message..' unit='..tostring(unitPath))
            return {ok=false,message=self.message,rollback_verified=true}
        end
        local targets,ordered={},{}
        if not self.baseline then
            local snapshot={}
            for _,field in ipairs(fields)do snapshot[field]=original[field].current end
            for _,field in ipairs(levelOneFields)do snapshot[field]=original[field].current end
            self.baseline={unit=unitPath,values=snapshot}
            self.message='已读取首只单位的出生属性，后续召唤按此对齐'
            log('[StatMatch] 基准已捕获 unit='..tostring(unitPath)..' HPmax='..snapshot.Health_Max..' ShachiMax='..snapshot.Shachi_Max
                ..' Attack='..snapshot.Attack..' ShachiAttack='..snapshot.ShachiAttack..' fields='..#fields
                ..' 1级值 HP='..tostring(snapshot.Health_Max_Lv1)..' Attack='..tostring(snapshot.Attack_Lv1))
            return {ok=true,baseline=true,message=self.message}
        end
        for _,field in ipairs(levelOneFields)do targets[field]=self.baseline.values[field];ordered[#ordered+1]=field end
        for _,field in ipairs(fields)do targets[field]=self.baseline.values[field];ordered[#ordered+1]=field end
        for _,pair in ipairs(RESOURCES)do targets[pair[1]]=targets[pair[2]];ordered[#ordered+1]=pair[1] end
        local failed=apply(actor,unitPath,original,targets,ordered,'数值统一')
        if failed then return failed end
        self.matched=self.matched+1
        self.message='后续单位出生属性已读回一致；已有单位不会跟随基准的残血变化'
        log('[StatMatch] 应用并读回 unit='..tostring(unitPath)..' baseline='..self.baseline.unit..' verified='..#ordered..'/'..#ordered
            ..' HP='..targets.Health..' Shachi='..targets.Shachi..' Attack='..targets.Attack..' ShachiAttack='..targets.ShachiAttack
            ..' 1级值 HP='..tostring(targets.Health_Max_Lv1)..' Attack='..tostring(targets.Attack_Lv1))
        return {ok=true,applied=true,message=self.message}
    end
    function self:status()
        local values=self.baseline and self.baseline.values or {}
        return {enabled=self.enabled,mode=self.mode,baseline_unit=self.baseline and self.baseline.unit or '',matched=self.matched,
            customized=self.customized,failures=self.failures,message=self.message,
            health=values.Health_Max,shachi=values.Shachi_Max,attack=values.Attack,shachi_attack=values.ShachiAttack,field_count=#fields,
            custom_count=count(self.custom),custom=self.custom,custom_fields=#customFields,rejected=self.rejected}
    end
    return self
end
return Match
