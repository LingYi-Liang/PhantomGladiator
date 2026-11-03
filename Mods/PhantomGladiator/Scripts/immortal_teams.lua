-- 不倒下: the units of a team switched on keep their health. Each one gets a native Health_Min floor at
-- the HP it had when it was locked, written the way the free camera locks the player's HP
-- (observer_guard.lua, v0.28.2), so the unit still takes hits, loses Sha-Chi and gets broken but never
-- goes down. Should its HP still drop below the floor, it is filled back and the breach is counted.
-- Turning the team off puts each unit's own floor back; a unit that leaves the arena is forgotten.
-- Locked units and their original floors are kept in Runtime/immortal-floors.tsv, so after a mod reload
-- the next Lua instance can put back the floors of the units the old ledger left standing.
local U=require('ue_observe')
local Stats=require('character_stats')
local Immortal={}
Immortal.teams={'blue','red','companion'}
local LABEL={blue='蓝方',red='红方',companion='随从'}
local SETTINGS='ImmortalTeamsV1'
local JOURNAL='ImmortalFloorsV1'
local EPS=0.5       -- HP: a floor or health this close to the target counts as the target
local RETRIES=3     -- lock attempts per unit before it counts as a failure
local LOG_CAP=40    -- repeated lines (relocks, health below the floor) per Lua lifetime

local function short(actor)
    if not U.valid(actor) then return '?' end
    local ok,cls=pcall(function()return actor:GetClass():GetFName():ToString()end)
    return ok and type(cls)=='string' and (cls:gsub('_C$','')) or '?'
end
local function fmt(v)return v and string.format('%.1f',v) or 'nil' end

function Immortal.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local stats=options.attributes or Stats.new()
    local settings=options.path..'/immortal-teams.tsv'
    local journal=options.path..'/immortal-floors.tsv'
    local self={alive=true,on={blue=false,red=false,companion=false},failures=0,relocks=0,breaches=0,message=''}
    local locked={}     -- actor key -> {team, original floor base, target HP, unit name}
    local tries={}      -- actor key -> lock attempts that did not read back
    local lines=0
    local orphansChecked=false
    local function say(m)log('[Immortal] '..m)end
    local function again(m)if lines<LOG_CAP then lines=lines+1;say(m)end end
    local function readFile(path)
        local f=fs.open(path,'r');if not f then return nil end
        local text=f:read('*a');f:close();return text
    end
    local function writeFile(path,text)
        local f=fs.open(path,'w');if not f then return false end
        local wrote=f:write(text);local closed=f:close()
        return wrote~=nil and wrote~=false and closed~=false and readFile(path)==text
    end
    do
        local text=readFile(settings)
        if type(text)=='string' and text:sub(1,#SETTINGS+1)==SETTINGS..'\t' then
            for team,value in text:gmatch('(%l+)=([01])')do
                if self.on[team]~=nil then self.on[team]=value=='1' end
            end
        end
    end
    local function save()
        local parts={SETTINGS}
        for _,team in ipairs(Immortal.teams)do parts[#parts+1]=team..'='..(self.on[team] and '1' or '0') end
        return writeFile(settings,table.concat(parts,'\t')..'\n')
    end
    local function saveJournal()
        local keys={}
        for key in pairs(locked)do keys[#keys+1]=key end
        table.sort(keys)
        local rows={JOURNAL}
        for _,key in ipairs(keys)do
            local r=locked[key]
            rows[#rows+1]=key..'\t'..string.format('%.3f',r.original)..'\t'..string.format('%.3f',r.target)
        end
        return writeFile(journal,table.concat(rows,'\n')..'\n')
    end

    -- After a mod reload the old ledger is gone but its units may still stand. Put back the floors the
    -- journal says were raised, only on units that still carry exactly that raised floor.
    local function restoreOrphans()
        local text=readFile(journal)
        if type(text)~='string' or text=='' then return end
        local rows,count={},0
        for key,original,target in text:gmatch('\n(%S+)\t([%-%d%.]+)\t([%-%d%.]+)')do
            rows[key]={original=tonumber(original),target=tonumber(target)};count=count+1
        end
        if count>0 then
            local restored=0
            for _,actor in ipairs(options.collect and options.collect() or {})do
                local key=U.key(actor)
                local row=key and rows[key]
                if row then
                    rows[key]=nil
                    local floor=stats:read(actor,'Health_Min')
                    if floor and math.abs(floor.base-row.target)<=EPS then
                        local ok,err=stats:writeBase(actor,'Health_Min',row.original)
                        local after=stats:read(actor,'Health_Min')
                        if ok and after and math.abs(after.base-row.original)<=EPS then restored=restored+1 else self.failures=self.failures+1 end
                        say(string.format('恢复上次留下的单位 unit=%s 下限 %s→%s 写入=%s 读回=%s %s',short(actor),fmt(floor.base),fmt(row.original),
                            tostring(ok),after and fmt(after.base) or 'nil',err and ('错误='..tostring(err)) or ''))
                    else
                        say('上次记录的单位下限已经变了，未改 unit='..short(actor)..' 下限='..(floor and fmt(floor.base) or 'nil'))
                    end
                end
            end
            say(string.format('检查上次留下的不倒下单位：记录%d只，恢复%d只',count,restored))
        end
        writeFile(journal,'')
    end

    local function lock(actor,team,key)
        local health=stats:read(actor,'Health');local floor=stats:read(actor,'Health_Min')
        -- Not readable yet (just spawned) or already down: nothing to lock this tick.
        if not health or not floor or health.current<=0 then return false end
        local target=health.current
        local ok,err=stats:writeBase(actor,'Health_Min',target)
        local after=stats:read(actor,'Health_Min')
        local good=ok and after and after.current>=target-EPS
        say(string.format('锁定 %s unit=%s HP=%s 原下限=%s 写入=%s 读回=%s %s',LABEL[team],short(actor),fmt(target),fmt(floor.base),
            tostring(ok),after and fmt(after.current) or 'nil',err and ('错误='..tostring(err)) or ''))
        if good then
            locked[key]={team=team,original=floor.base,target=target,name=short(actor)}
            tries[key]=nil
            return true
        end
        -- Not held: put the original floor back and try again on a later tick, a few times at most.
        if ok then stats:writeBase(actor,'Health_Min',floor.base) end
        tries[key]=(tries[key] or 0)+1
        if tries[key]>=RETRIES then
            self.failures=self.failures+1;self.message=short(actor)..' 没能锁住血量'
            say('放弃锁定 unit='..short(actor)..'：'..RETRIES..' 次写入都没有读回')
        end
        return false
    end
    local function hold(record,actor)
        -- Health at the lock means the floor holds: one read, not two full attribute reads per unit.
        if options.hp then
            local ok,hp=pcall(options.hp,actor)
            if ok and type(hp)=='number' and hp>=record.target-EPS then return end
        end
        local floor=stats:read(actor,'Health_Min');local health=stats:read(actor,'Health')
        if floor and floor.current<record.target-EPS then
            local ok=stats:writeBase(actor,'Health_Min',record.target)
            local after=stats:read(actor,'Health_Min')
            self.relocks=self.relocks+1
            again(string.format('重新锁定 unit=%s 下限 %s→%s 写入=%s 读回=%s',record.name,fmt(floor.current),fmt(record.target),
                tostring(ok),after and fmt(after.current) or 'nil'))
        end
        if health and health.current<record.target-EPS then
            -- The floor did not stop this damage. Fill the unit back while it still stands.
            self.breaches=self.breaches+1
            local filled=health.current>0 and stats:writeBase(actor,'Health',record.target)
            local after=stats:read(actor,'Health')
            again(string.format('血量低于下限 unit=%s HP=%s 下限=%s 目标=%s 补回=%s 读回=%s',record.name,fmt(health.current),
                floor and fmt(floor.current) or 'nil',fmt(record.target),tostring(filled),after and fmt(after.current) or 'nil'))
        end
    end
    local function release(record,actor,reason)
        local ok,err=stats:writeBase(actor,'Health_Min',record.original)
        local after=stats:read(actor,'Health_Min')
        if not ok or not after or math.abs(after.base-record.original)>EPS then self.failures=self.failures+1 end
        say(string.format('恢复（%s）unit=%s 下限→%s 写入=%s 读回=%s %s',reason,record.name,fmt(record.original),tostring(ok),
            after and fmt(after.base) or 'nil',err and ('错误='..tostring(err)) or ''))
    end

    -- Saved and read back here; the units are locked or released on the next tick.
    function self:set(team,value)
        team=type(team)=='string' and team:lower() or ''
        if self.on[team]==nil then return {ok=false,message='不倒下只支持蓝方、红方和随从',spawned_count=0} end
        if value~='ON' and value~='OFF' then return {ok=false,message='不倒下开关只接受 ON 或 OFF',spawned_count=0} end
        local before=self.on[team]
        self.on[team]=value=='ON'
        local saved=save()
        if not saved then self.on[team]=before end
        say(string.format('设置 %s=%s 保存读回=%s',team,value,tostring(saved)))
        return {ok=saved,spawned_count=0,message=saved and (LABEL[team]..'不倒下'..(self.on[team] and '已开启' or '已关闭')) or '不倒下设置没能保存'}
    end
    -- Every support tick (0.5 s): lock new units of a switched-on team, keep the locked ones, release the
    -- ones whose team was switched off and forget the ones that left.
    function self:tick()
        if not self.alive or (options.ready and not options.ready()) then return end
        if not orphansChecked then orphansChecked=true;restoreOrphans() end
        local seen,changed={},false
        for _,member in ipairs(options.members())do
            local actor=member.actor
            local key=U.key(actor)
            if key then
                seen[key]=true
                local record=locked[key]
                if record and not self.on[member.team] then
                    release(record,actor,'已关闭不倒下');locked[key]=nil;changed=true
                elseif record then hold(record,actor)
                elseif self.on[member.team] and (tries[key] or 0)<RETRIES then
                    changed=lock(actor,member.team,key) or changed
                end
            end
        end
        for key,record in pairs(locked)do
            if not seen[key] then locked[key]=nil;tries[key]=nil;changed=true;say('单位已离场，不再跟踪 unit='..record.name) end
        end
        if changed then saveJournal() end
    end
    function self:status()
        local n=0
        for _ in pairs(locked)do n=n+1 end
        return {blue=self.on.blue,red=self.on.red,companion=self.on.companion,locked=n,failures=self.failures,
            breaches=self.breaches,relocks=self.relocks,message=self.message}
    end
    -- On unload nothing is written to the game; the journal lets the next instance put the floors back.
    function self:silence()self.alive=false end
    return self
end
return Immortal
