-- One local override of the current map's UDW actor; the native transition owns the visual effects.
local U=require('ue_observe')
local W={}
W.presets={'Clear_Skies','Partly_Cloudy','Cloudy','Overcast','Foggy','Rain_Light','Rain','Rain_Thunderstorm','Snow_Light','Snow','Snow_Blizzard','Sand_Dust_Calm','Sand_Dust_Storm'}
W.commands={'previous','next','restore'}
for _,p in ipairs(W.presets)do table.insert(W.commands,p:lower())end
local base='/Weather/UltraDynamicSky/Blueprints/Weather_Effects/Weather_Presets/'
local function assetPath(p)return base..p..'.'..p end
local function full(obj)
    if not U.valid(obj) then return end
    local ok,name=pcall(function()return obj:GetFullName()end)
    if ok then return name end
end
-- UDW's Get New Target Global Weather State uses IsValid(Weather) to choose its manual branch.
-- UE4SS can expose an empty object property as an invalid UObject wrapper instead of Lua nil.
local function readPreset(actor)
    local v,read=U.field(actor,'Weather')
    if not read or v==nil or U.valid(v) then return v,read end
    local ok,valid=pcall(function()return v:IsValid()end)
    if ok and valid==false then return nil,true end
    return nil,false
end
local modes={NewEnumerator3=0,NewEnumerator0=1,NewEnumerator1=2,NewEnumerator2=3}
local function timing(actor)
    local v=U.field(actor,'Random Weather Variation')
    if type(v)=='number' then return v end
    if U.kind(v)=='FName' then local ok,name=pcall(function()return v:ToString()end);if ok then v=name end end
    if type(v)=='string' then return modes[v:match('([^:]+)$')] or tonumber(v) end
end
local function reply(ok,message)return {ok=ok,message=message,spawned_count=0}end
function W.new(o)
    local self={};local lease
    local function current()
        if not lease then return end
        local world=o.world()
        if not U.valid(world) or U.key(world)~=lease.world or not U.inWorld(lease.actor,world) or full(lease.actor)~=lease.name then lease=nil;return end
        local preset,read=readPreset(lease.actor);local mode=timing(lease.actor)
        if read and type(mode)=='number' and (mode~=0 or U.key(preset)~=lease.applied) then lease=nil end
        return lease
    end
    function self:status()local r=current();return r and r.id or 'map' end
    function self:set(id)
        local r=current()
        if id=='restore' and not r then return reply(true,'weather.map') end
        local world=o.world();if not U.valid(world) then return reply(false,'weather.noWorld') end
        local actor=r and r.actor
        if not actor then
            local ok,rows=pcall(o.findAll,'Ultra_Dynamic_Weather_C')
            for _,a in ipairs(ok and U.array(rows) or {})do
                if U.inWorld(a,world) then
                    if actor then return reply(false,'weather.ambiguous') end
                    actor=a
                end
            end
            if not actor and o.mapActor then
                local got,candidate=pcall(o.mapActor,world)
                if got and U.inWorld(candidate,world) then actor=candidate end
            end
        end
        if not U.valid(actor) then return reply(false,'weather.unavailable') end
        local before,read=readPreset(actor);local mode=timing(actor)
        if not read or type(mode)~='number' or mode%1~=0 or mode<0 or mode>3 then
            o.log('[Weather] 原状态不可读 actor='..tostring(full(actor))..' presetRead='..tostring(read)..' timing='..tostring((U.field(actor,'Random Weather Variation'))));return reply(false,'weather.unread') end
        local name=full(actor);local worldKey=U.key(world)
        if not name or not worldKey then return reply(false,'weather.unread') end
        local preset,index
        local originalName=not r and full(before)
        for i,p in ipairs(W.presets)do
            if id==p:lower() then preset=p end
            if (r and r.id==p:lower()) or (originalName and originalName:match('^%S+ (.+)$')==assetPath(p)) then index=i end
        end
        if id=='previous' or id=='next' then
            local n=#W.presets
            preset=W.presets[id=='next' and ((index or 0)%n+1) or (((index or 1)-2)%n+1)]
        end
        if id=='restore' then
            if r.mode==0 and r.original~=nil and not U.valid(r.original) then return reply(false,'weather.unread') end
            local ok=pcall(function()
                if r.mode~=0 then actor['Change to Random Weather Variation'](actor,0,r.mode)
                else actor['Change Weather'](actor,r.original,0) end
            end)
            local after,got=readPreset(actor)
            local restored=ok and got and timing(actor)==r.mode and (r.mode~=0 or (r.original==nil and after==nil) or (r.original~=nil and U.key(after)==U.key(r.original)))
            o.log('[Weather] 恢复 '..name..' 原模式='..r.mode..' 读回='..tostring(restored))
            if restored then lease=nil end
            return reply(restored,restored and 'weather.map' or 'weather.unconfirmed')
        end
        if not preset then return reply(false,'weather.invalid') end
        if U.field(actor,'Currently in a Weather Override Volume')==true then return reply(false,'weather.volume') end
        local path=assetPath(preset);local loaded,asset=pcall(o.load,path)
        if not loaded or not U.valid(asset) or full(asset)~='UDS_Weather_Settings_C '..path or not U.key(asset) then return reply(false,'weather.noPreset') end
        if not U.inWorld(actor,o.world()) or full(actor)~=name then return reply(false,'weather.noWorld') end
        local ok=pcall(function()actor['Change Weather'](actor,asset,1.0)end)
        local after=U.field(actor,'Weather')
        local owned=U.key(after)==U.key(asset)
        if owned then
            lease=r or {actor=actor,name=name,world=worldKey,mode=mode,original=before}
            lease.id=preset:lower();lease.applied=U.key(asset)
        end
        local confirmed=ok and owned and timing(actor)==0
        o.log('[Weather] 切换 '..name..' '..preset..' 读回='..tostring(confirmed))
        return reply(confirmed,confirmed and 'weather.applied' or 'weather.unconfirmed')
    end
    function self:silence(onGameThread)
        if onGameThread and lease then self:set('restore') end
        lease=nil
    end
    return self
end
return W
