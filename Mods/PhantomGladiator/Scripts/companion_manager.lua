-- One logical record per directly summoned companion. No UObject is persisted.
local P=require('companion_profile')
local M={}
local function answer(ok,message)return {ok=ok,message=message,spawned_count=0} end
function M.new(o)
    local self={revision=0,settingsRevision=0,profiles={all=P.copy(P.defaults)},customCount=0}
    local settings=o.path..'/companion-profiles.tsv'
    local roster=o.path..'/companion-roster.tsv'
    local read,write=o.read or P.read,o.write or P.write
    local rows,byActor={},{}
    local serial,session,lastPublish,nextPublish=0,nil,nil,0
    local dirty,maintenanceTurn=true,1
    local ioClock=o.ioClock or o.now
    local function load(data)
        if not data then return false end
        local revision,base,role=data:match('^PGCP1\t(%d+)\nall\t([^\n]+)\nmu\t([^\n]+)\n$')
        local global=P.decode(base);local mu=P.decode(role)
        if not global or not (mu or role=='inherit') then return false end
        self.settingsRevision=tonumber(revision);self.profiles={all=global,mu=mu};return true
    end
    if not load(read(settings)) then load(read(settings..'.bak')) end
    local function setting(scope)return self.profiles[scope] or self.profiles.all end
    local function current()local id,ready=o.session();return id,ready==true end
    local function identity(actor)
        local ok,key,name=pcall(o.identity,actor)
        if ok then return key,name end
    end
    local function matches(r)
        if not r or r.session~=session then return false end
        local key,name=identity(r.actor)
        return key==r.key and name==r.name and key~=nil
    end
    local function export(force)
        if not dirty then return end
        local stamp=ioClock()
        if not force and stamp<nextPublish then return end
        local lines={'PGCM1\t'..(session or '')..'\t'..self.settingsRevision,
            'all\t'..P.encode(setting('all')),'mu\t'..P.encode(setting('mu'))..'\t'..(self.profiles.mu and 'own' or 'inherit')}
        local sorted={};for id in pairs(rows)do sorted[#sorted+1]=id end;table.sort(sorted)
        for _,id in ipairs(sorted)do
            local r=rows[id]
            lines[#lines+1]=table.concat({id,r.path,r.rev,r.phase or 0,r.dual and 1 or 0,r.state,
                P.encode(r.p),(r.issue or ''):gsub('%c',' '):sub(1,240)},'\t')
        end
        local data=table.concat(lines,'\n')..'\n'
        if data~=lastPublish then
            if not write(roster,data) then nextPublish=stamp+2;return end
            lastPublish=data;self.revision=self.revision+1
        end
        dirty=false;nextPublish=stamp+.5
    end
    local function drop(r,restore)
        if restore and matches(r) and o.release then
            local ok,cleared=pcall(o.release,r)
            if (not ok or cleared==false) and o.log then o.log('[Companion] 卸载时控制状态未确认 '..r.id) end
        end
        rows[r.id]=nil;byActor[r.key]=nil;dirty=true
    end
    function self:lookup(actor)
        if not next(byActor) then return end
        local key,name=identity(actor);local r=key and byActor[key]
        if r and name==r.name then return r end
    end
    function self:forActor(actor)local r=self:lookup(actor);return r and r.p end
    function self:spawn()
        local p=setting('mu')
        return o.spawn(p.policy=='second' and P.second or P.first)
    end
    local function state(r,s)
        if r.state~=s then r.state=s;dirty=true end
    end
    local function actionReady(r,v)
        if v.canSwitch==nil and o.canAct then v.canSwitch=o.canAct(r.actor)==true end
        return v.canSwitch~=false
    end
    local function switch(r,wanted,why,sample)
        if r.blocked or r.swapping or not matches(r) or not sample.safe or sample.canSwitch==false or sample.hp<=0 then return answer(false,'当前动作或回收状态禁止切换') end
        r.swapping=true;dirty=true
        local called,result=pcall(o.swap,r,wanted,why,sample)
        r.swapping=false
        if not called or not result or not result.ok then
            r.issue=called and result and result.message or '转换返回异常'
            if o.log then o.log('[CompanionForm] '..r.id..' '..tostring(wanted)..' '..why..' 回读失败 '..r.issue) end
            r.blocked=not called or (result and result.uncertain)==true
            r.failures=(r.failures or 0)+1;r.failedPhase=wanted
            r.retryAt=o.now()+math.min(30,4*2^math.min(3,r.failures));r.lastTime=nil;r.quiet=nil
            state(r,r.blocked and 'cleanup' or 'retry')
            return answer(false,r.issue)
        end
        self.replaced=true
        local newKey,newName=result.key,result.name
        if not newKey or not newName then newKey,newName=identity(result.actor) end
        if not newKey or not newName then
            r.blocked=true;r.issue='新形态身份暂不可读';state(r,'cleanup');return answer(false,r.issue)
        end
        byActor[r.key]=nil;r.actor=result.actor;r.key,r.name=newKey,newName
        r.path=wanted==2 and P.second or P.first;r.phase=wanted;r.rev=r.rev+1
        byActor[r.key]=r;r.retryAt=o.now()+2;r.quiet=nil;r.lastTime=nil;r.issue=nil;r.failures=nil;r.failedPhase=nil
        if o.log then o.log('[CompanionForm] '..r.id..' '..why..' 形态读回='..wanted) end
        state(r,'changed');return answer(true,'形态已切换，生命和杀气比例已读回')
    end
    local function down(r,now,mayMaintain)
        r.lastTime=nil;r.quiet=nil;r.waiting=nil
        if not r.downAt or r.releaseAfter and now>=r.releaseAfter then
            r.downAt=r.downAt or now
            if o.release and o.release(r)==false then
                r.releaseDelay=math.min(8,(r.releaseDelay or .5)*2);r.releaseAfter=now+r.releaseDelay
            else r.releaseDelay=nil;r.releaseAfter=nil end
        end
        state(r,'down')
        if mayMaintain and r.phase==2 and o.onDeath and not r.childrenCleared and now>=(r.deathCheck or r.downAt+2) then
            local ok,cleared=pcall(o.onDeath,r)
            r.childrenCleared=ok and cleared==true
            if not r.childrenCleared then
                r.deathDelay=math.min(16,(r.deathDelay or 1)*2)
                r.deathCheck=now+r.deathDelay
            end
            return true
        end
    end
    local function advance(r,now,mayMaintain)
        if not matches(r) then return false,true end
        local p=r.p
        if not r.dual and p.behavior=='active' and p.regen=='game' and p.targetable==1 and not r.lease and not r.hatred and not r.pose and not r.waiting then
            local observed=o.brief and o.brief(r) or 'following'
            if observed=='down' then return down(r,now,mayMaintain) end
            r.downAt=nil;r.deathCheck=nil;r.deathDelay=nil;r.childrenCleared=nil;r.releaseAfter=nil;r.releaseDelay=nil;state(r,observed);return
        end
        local v=o.sample(r,false)
        if not v or type(v.hp)~='number' or v.hp~=v.hp then r.quiet=nil;r.lastTime=nil;state(r,'unknown');return end
        if v.hp<=0 then return down(r,now,mayMaintain) end
        r.downAt=nil;r.deathCheck=nil;r.deathDelay=nil;r.childrenCleared=nil;r.releaseAfter=nil;r.releaseDelay=nil
        if r.blocked then
            if not o.recovered or not o.recovered(r.actor) then state(r,'cleanup');return end
            r.blocked=nil;r.issue=nil;r.retryAt=now+2
        end
        if v.safe and not v.known and o.releaseUnused then o.releaseUnused(r) end
        if not v.safe or not v.known then
            r.quiet=nil;r.lastTime=nil
            if r.pose and o.cancelPose then o.cancelPose(r) end
            state(r,'busy');return
        end
        if r.engaged~=nil and r.engaged~=v.combat then r.failures=nil;r.failedPhase=nil;r.retryAt=nil end
        r.engaged=v.combat
        if o.behave then r.behaviorPending=o.behave(r,v)==false end
        if v.combat then
            r.quiet=nil
            if r.pose and o.cancelPose then o.cancelPose(r) end
            r.waiting=nil
        end
        if r.pose and o.poseEnded and o.poseEnded(r) then r.pose=nil end
        if not v.combat and (not r.quiet or now<r.quiet) then r.quiet=now end
        -- Never pay back healing for a paused simulation, a hitch, travel or a long missing sample.
        local dt=r.lastTime and now-r.lastTime or 0
        if dt<0 or dt>2 then dt=0;r.quiet=nil;if not v.combat then r.quiet=now end end
        r.lastTime=now
        if r.retryAt and now<r.retryAt then state(r,r.issue and 'retry' or 'changed');return end
        local auto=p.policy=='auto_return' or p.policy=='auto_stay'
        if r.dual and not r.pose and not r.waiting then
            local desired
            if p.policy=='first' then desired=1 elseif p.policy=='second' then desired=2
            elseif auto and r.phase==1 and v.combat and v.max>0 and v.hp/v.max*100<=p.threshold then desired=2
            elseif p.policy=='auto_return' and r.phase==2 and r.quiet and now-r.quiet>=p.delay then desired=1 end
            if desired==r.failedPhase and (r.failures or 0)>=3 then state(r,'retry');return end
            if desired and desired~=r.phase then
                if not mayMaintain then state(r,'phase_pending');return end
                if actionReady(r,v) then
                    switch(r,desired,v.combat and 'combat' or 'quiet',v)
                    return true
                end
                state(r,'busy');return
            end
        end
        state(r,r.behaviorPending and 'busy' or r.pose and 'pose' or r.waiting and 'waiting' or v.combat and 'combat' or 'following')
        if not v.combat and not r.pose and r.quiet and now-r.quiet>=p.delay and p.regen=='custom'
            and p.rate>0 and v.hp<v.max and dt>0 and actionReady(r,v) then
            o.heal(r,math.min(v.max,v.hp+v.max*p.rate*dt/100))
        end
    end
    function self:tick(members)
        local id,ready=current()
        if id~=session then
            for _,r in pairs(rows)do drop(r,false) end
            session=id;nextPublish=0;dirty=true;maintenanceTurn=1;self.preferAfter=nil
        end
        if not ready then
            self.customCount=0
            for _,r in pairs(rows)do r.quiet=nil;r.lastTime=nil end
            export();return
        end
        if not next(rows) and (not members or #members==0) then self.customCount=0;export();return end
        local now=o.now();local present,unreadable,ordered={},{},{}
        for _,m in ipairs(members or {})do
            if m.team=='companion' and not m.summoner and not m.stand and not m.reserve and not m.aid then
                local key,name=identity(m.actor)
                if key and name then
                    local r=byActor[key]
                    if r and r.name~=name then drop(r,false);r=nil end
                    if not r then
                        serial=serial+1;local phase=P.phase(m.class_path)
                        r={id='C'..serial..'-'..id,session=id,key=key,name=name,actor=m.actor,path=m.class_path,phase=phase,
                            dual=m.dual==true and phase~=nil,rev=1,p=P.copy(setting(phase and 'mu' or 'all')),state='following'}
                        rows[r.id]=r;byActor[key]=r;dirty=true
                    end
                    present[r.id]=true;ordered[#ordered+1]=r
                elseif m.actor then unreadable[m.actor]=true end
            end
        end
        for _,r in pairs(rows)do
            if not present[r.id] then
                if unreadable[r.actor] then
                    r.lastTime=nil;r.quiet=nil;state(r,'unknown')
                else drop(r,false) end
            end
        end
        self.customCount=0
        local preferred={}
        local count=#ordered
        local first=maintenanceTurn<=count and maintenanceTurn or 1
        local attempted=false
        for offset=0,count-1 do
            local index=(first+offset-1)%count+1
            local r=ordered[index]
            if r.p.regen=='custom' then self.customCount=self.customCount+1 end
            if not r.readRetryAt or now>=r.readRetryAt then
                local ok,worked,invalid=pcall(advance,r,now,not attempted)
                if not ok then
                    if not r.readFailures and o.log then o.log('[Companion] 暂缓此随从的读取 '..r.id..' '..tostring(worked)) end
                    r.readFailures=math.min(5,(r.readFailures or 0)+1)
                    r.readRetryAt=now+2^(r.readFailures-1)
                    r.quiet=nil;r.lastTime=nil;state(r,'unknown')
                else
                    r.readFailures=nil;r.readRetryAt=nil
                    if worked then attempted=true;maintenanceTurn=index%count+1 end
                    if not invalid and r.p.targetable==2 and not r.blocked and r.state~='down' and r.state~='busy'
                        and r.state~='unknown' and r.state~='phase_pending' then preferred[#preferred+1]=r.actor end
                end
            end
        end
        if #preferred>0 and o.prefer and (not self.preferAfter or now>=self.preferAfter) then
            local ok,why=pcall(o.prefer,members,preferred,now)
            if ok then self.preferAfter=nil
            else
                if not self.preferAfter and o.log then o.log('[CompanionAggro] 暂缓优先索敌 '..tostring(why)) end
                self.preferAfter=now+4
            end
        end
        export()
    end
    function self:prepareRecall(actor)
        local r=self:lookup(actor)
        if not r then return true end
        if r.swapping or r.blocked or o.recallSafe and not o.recallSafe(actor) then return false end
        if o.cancelOrder and not o.cancelOrder(r) then return false end
        r.waiting=nil;r.quiet=nil;r.lastTime=nil;r.retryAt=o.now()+1;r.readRetryAt=nil;r.readFailures=nil
        return true
    end
    function self:command(text)
        local who,rev,verb,data=tostring(text):match('^([%w_%-]+)|(%d+)|([a-z]+)|([^|]*)$')
        local id,ready=current()
        if not ready or id~=session then return answer(false,'地图已切换，请重新打开随从设置') end
        local r=rows[who];local defaults=who=='all' or who=='mu'
        if not defaults and (not matches(r) or o.owned and not o.owned(r.actor)) then return answer(false,'这名随从已离场') end
        if tonumber(rev)~=(defaults and self.settingsRevision or r.rev) then return answer(false,'设置已变更，请重新载入') end
        if verb=='save' or verb=='inherit' then
            local p=P.decode(data)
            if verb=='inherit' and who~='mu' or verb=='save' and not p then return answer(false,'配置字段无效') end
            if defaults then
                local base=who=='all' and p or self.profiles.all
                local mu=self.profiles.mu;if who=='mu' then mu=p end
                local nextRev=self.settingsRevision+1
                local bytes='PGCP1\t'..nextRev..'\nall\t'..P.encode(base)..'\nmu\t'..(mu and P.encode(mu) or 'inherit')..'\n'
                if not write(settings,bytes) then return answer(false,'未能验证配置写入') end
                self.profiles={all=base,mu=mu};self.settingsRevision=nextRev
            else
                r.p=p;r.rev=r.rev+1;r.quiet=nil;r.lastTime=nil;r.retryAt=nil;r.failures=nil;r.failedPhase=nil
                r.readRetryAt=nil;r.readFailures=nil
            end
            dirty=true;export(true);return answer(true,defaults and '已保存，下次召唤生效' or '场上实例配置已接收，下次安全时刻执行')
        end
        if not r or not ready or not matches(r) then return answer(false,'选择一名场上随从') end
        local v=o.sample(r)
        local endingOrder=verb=='follow' or verb=='recall' or verb=='pose' and r.pose
        if not v or not v.safe or (not v.known and not endingOrder) or v.hp<=0 or r.blocked then return answer(false,'随从当前无法接受指令') end
        local result
        if verb=='switch' and r.dual and r.p.policy=='manual' and not r.pose and not r.waiting then
            result=switch(r,3-r.phase,'manual',v)
        elseif verb=='recall' then
            if not self:prepareRecall(r.actor) then return answer(false,'召回前动作未结束') end
            result=o.recall(r.actor)
        elseif verb=='follow' or verb=='wait' then
            if v.combat and verb=='wait' then return answer(false,'战斗中无法待命') end
            if r.pose and o.cancelPose and o.cancelPose(r)==false then return answer(false,'合影动作尚未结束') end
            r.waiting=verb=='wait' or nil
            if v.known then result=o.order(r,v)
            elseif r.p.behavior=='active' then
                local ok=not o.cancelOrder or o.cancelOrder(r)
                result=answer(ok==true,ok and '已解除待命' or '原生行为树恢复未确认')
            else result=answer(true,'已解除待命，等战斗状态读回后继续跟随') end
            if not result.ok and verb=='wait' then r.waiting=nil end
        elseif verb=='pose' and r.phase and (r.pose or not v.combat) then
            result=o.pose(r)
        else return answer(false,'当前策略或形态不支持此指令') end
        export(true);return result
    end
    function self:silence(restore)
        for _,r in pairs(rows)do drop(r,restore==true) end
        self.customCount=0
    end
    return self
end
return M