-- Read currently loaded spawn configurations. This never opens a map, loads a
-- class, calls Spawn/Save/Activate, or treats a package reference as a spawn.
local Survey={}
local function valid(o) if o==nil then return false end local ok,v=pcall(function() return o:IsValid() end);return ok and v==true end
local function call(o,k,...)
    if not valid(o) then return false,nil end
    local args=table.pack(...);return pcall(function() return o[k](o,table.unpack(args,1,args.n)) end)
end
local function read(o,k) if not valid(o) then return nil end local ok,v=pcall(function() return o[k] end);if ok then return v end end
local function field(v,k) local ok,r=pcall(function() return v[k] end);if ok then return r end end
local function unwrap(v)
    if v==nil then return nil end
    local ok,t=pcall(function() return v:type() end)
    if ok and (t=='RemoteUnrealParam' or t=='LocalUnrealParam') then local got,r=pcall(function() return v:get() end);return got and r or nil end
    return v
end
local function text(v) v=unwrap(v);if type(v)=='string' then return v end local ok,r=pcall(function() return v:ToString() end);if ok and type(r)=='string' then return r end end
local function name(o) local ok,v=call(o,'GetFullName');return ok and type(v)=='string' and v or '' end
local function key(o) local ok,v=call(o,'GetAddress');if ok and v~=nil then return tostring(v) end end
local function clean(v) return (tostring(v or ''):gsub('[\t\r\n]',' ')) end
local function soft(v)
    if v==nil then return '' end
    local ok,id=pcall(function() return v:GetObjectID() end)
    if not ok or id==nil then return '' end
    local got,a,s=pcall(function() return id:GetAssetPathName(),id:GetSubPathString() end)
    local path,sub=got and text(a),got and text(s)
    if not path or path=='' or path=='None' or sub==nil then return '' end
    return path..(sub~='' and ':'..sub or '')
end
local function classpath(c)
    local ok,yes=call(c,'IsAnyClass');if not ok or yes~=true then return '' end
    return name(c):match(' (/.+)$') or ''
end
local function array(v,cap)
    local out,total={},0
    if type(v)=='table' then total=#v;for i=1,math.min(total,cap) do out[#out+1]=unwrap(v[i]) end
    elseif v~=nil then
        local ok=pcall(function()
            total=#v;v:ForEach(function(_,item) if #out>=cap then return true end out[#out+1]=unwrap(item) end)
        end)
        if not ok then return {},true end
    end
    return out,total>cap
end
function Survey.new(options)
    local instance={}
    local function log(s) if options.log then pcall(options.log,'[SpawnCatalog] '..s) end end
    function instance:export()
        local inThread,yes=pcall(IsInGameThread);if not inThread or yes~=true then return {ok=false,message='requires_game_thread'} end
        local wOK,world=pcall(options.getWorld);local wid=wOK and key(world)
        if not wid then return {ok=false,message='world_unavailable'} end
        local rows,stats,actorClasses={}, {actors=0,spawners=0,configured=0,unresolved=0,truncated=false,errors=0},{}
        local function find(class)
            local ok,list=pcall(FindAllOf,class)
            if ok and list==nil then stats.empty_loaded_classes=(stats.empty_loaded_classes or 0)+1;return {} end
            if not ok or type(list)~='table' then stats.errors=stats.errors+1;return {} end
            if #list>8192 then stats.truncated=true end
            return list
        end
        local function inWorld(actor)
            if not valid(actor) or name(actor):find('Default__',1,true) then return false end
            local good,destroying=call(actor,'IsActorBeingDestroyed');if not good or destroying~=false then return false end
            local outer=actor
            for _=1,8 do
                if key(outer)==wid then return true end
                local ok,nextOuter=call(outer,'GetOuter');if not ok or not valid(nextOuter) then return false end
                outer=nextOuter
            end
            return false
        end
        local mapSubsystem
        for _,s in ipairs(find('MapSubsystem')) do
            local ok,outer=call(s,'GetOuter')
            if ok and key(outer)==wid then if mapSubsystem then mapSubsystem=nil;break else mapSubsystem=s end end
        end
        local function location(actor)
            local got,pos=call(actor,'K2_GetActorLocation')
            if not got or pos==nil then return '',nil end
            local ok,map=call(mapSubsystem,'GetMapIDByLocation',pos)
            local mapid=ok and text(map) or ''
            return mapid~='None' and mapid or '',pos
        end
        local function append(actor,kind,property,class,reference,extra)
            local map,pos=location(actor)
            local item={evidence_kind=kind,source_actor=name(actor),world_path=name(world),map_id=map or '',
                class_path=class or '',property=property,reference=reference or '',detail=extra or '',
                x=pos and field(pos,'X') or '',y=pos and field(pos,'Y') or '',z=pos and field(pos,'Z') or ''}
            rows[#rows+1]=item
            if kind=='configured_spawn' then stats.configured=stats.configured+1 end
            if item.class_path=='' then stats.unresolved=stats.unresolved+1 end
        end
        -- A loaded pawn occurrence is distinct from an authored spawn config.
        for i,a in ipairs(find('PBZCharacter_NPC')) do
            if i>8192 then break end
            if inWorld(a) then
                local got,c=call(a,'GetClass');local cp=got and classpath(c) or ''
                local ap=name(a):match(' (/.+)$')
                if ap and cp~='' then actorClasses[ap]=cp end
                stats.actors=stats.actors+1
                append(a,'loaded_actor_observation','GetClass',cp,ap,'not_proof_of_authored_spawn')
            end
        end
        for _,typeName in ipairs({'AISpawner','PBZNarrativeMonsterParty','PBZMonsterPartySpawner'}) do
            for i,a in ipairs(find(typeName)) do
                if i>8192 then break end
                if inWorld(a) then
                    stats.spawners=stats.spawners+1
                    if typeName=='AISpawner' then
                        local cp=soft(read(a,'Class'))
                        if cp~='' then append(a,'configured_spawn','Class',cp,cp,'AAISpawner.Class') end
                        local random,truncated=array(read(a,'RandomSpawnClasses'),256);stats.truncated=stats.truncated or truncated
                        for _,c in ipairs(random) do local p=soft(c);append(a,'configured_spawn','RandomSpawnClasses',p,p,'random_choice_not_actual_spawn') end
                    elseif typeName=='PBZNarrativeMonsterParty' then
                        local list,truncated=array(read(a,'SpawnInfos'),1024);stats.truncated=stats.truncated or truncated
                        for _,entry in ipairs(list) do
                            local cp=classpath(field(entry,'MonsterClass'))
                            append(a,'configured_spawn','SpawnInfos.MonsterClass',cp,soft(field(entry,'SpawnPoint')),'party_actor_map;spawn_point_may_differ')
                        end
                    else
                        local first,truncated=array(read(a,'FirstWaveMonsters'),1024);stats.truncated=stats.truncated or truncated
                        for _,ref in ipairs(first) do
                            local p=soft(ref);append(a,'configured_actor_reference','FirstWaveMonsters',actorClasses[p] or '',p,'only_resolved_against_current_loaded_actor')
                        end
                        local waves,cut=array(read(a,'MonsterWaves'),256);stats.truncated=stats.truncated or cut
                        for _,wave in ipairs(waves) do
                            local points,cutPoints=array(field(wave,'SpawnPoints'),1024);stats.truncated=stats.truncated or cutPoints
                            for _,point in ipairs(points) do
                                append(a,'unresolved_character_name','MonsterWaves.SpawnPoints','',soft(field(point,'SpawnPoint')),
                                    text(field(point,'CharacterName')) or 'UNKNOWN')
                            end
                        end
                    end
                end
            end
        end
        local fields={'evidence_kind','source_actor','world_path','map_id','class_path','property','reference','detail','x','y','z'}
        local lines={table.concat(fields,'\t')..'\n'}
        for _,r in ipairs(rows) do local v={};for _,k in ipairs(fields) do v[#v+1]=clean(r[k]) end;lines[#lines+1]=table.concat(v,'\t')..'\n' end
        local file=io.open(options.path..'/spawn-config.tsv','w')
        if not file then return {ok=false,message='output_unavailable'} end
        local wrote=file:write(table.concat(lines));local flushed=file:flush();local closed=file:close()
        stats.ok=wrote~=nil and flushed==true and closed==true
        -- Index loaded DataTables without executing any of their rows.
        local tableLines={'table_path\trow_struct\trows\n'}
        for i,dt in ipairs(find('DataTable')) do
            if i>8192 then break end
            if valid(dt) and not name(dt):find('Default__',1,true) then
                local ok,rs=call(dt,'GetRowStruct')
                local countOK,count=pcall(function() if not valid(dt) then error('invalid') end;return #dt end)
                tableLines[#tableLines+1]=clean(name(dt))..'\t'..clean(ok and name(rs) or '')..'\t'..clean(countOK and count or '')..'\n'
            end
        end
        local tf=io.open(options.path..'/loaded-datatables.tsv','w')
        if tf then tf:write(table.concat(tableLines));tf:flush();tf:close() end
        log('读回 loaded_actors='..stats.actors..' spawners='..stats.spawners..' configured_classes='..stats.configured
            ..' unresolved='..stats.unresolved..' truncated='..tostring(stats.truncated)..' errors='..stats.errors..' written='..tostring(stats.ok)
            ..'；范围仅当前已加载World分区，不代表全部地图')
        return stats
    end
    return instance
end
return Survey
