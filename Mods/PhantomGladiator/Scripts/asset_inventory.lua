-- Full current-mounted registry inventory, without asset loads or actor creation.
-- Every returned row is consumed within its query tick. No UScriptStruct proxy
-- crosses frames. Large directories are not silently cut at 10,000 rows.
local Inventory={}
local FIELDS={'asset_path','package_name','package_path','asset_name','asset_type','generated_class','parent_class','native_parent','row_structure'}
local function valid(o) if o==nil then return false end local ok,v=pcall(function() return o:IsValid() end);return ok and v==true end
local function unwrap(v)
    if type(v)~='table' and type(v)~='userdata' then return v end
    local ok,result=pcall(function() return v:get() end);return ok and result or v
end
local function field(v,k) local ok,r=pcall(function() return v[k] end);if ok then return r end end
local function text(v)
    v=unwrap(v);if type(v)=='string' then return v end
    local ok,r=pcall(function() return v:ToString() end);if ok and type(r)=='string' then return r end
end
local function clean(v) if v==nil then return '' end;return (tostring(v):gsub('[\t\r\n]',' ')) end
local function pathof(v)
    local package,name=text(field(v,'PackageName')),text(field(v,'AssetName'))
    if package and name then return package..'.'..name end
end
local function game_thread() local ok,v=pcall(IsInGameThread);return ok and v==true end
local function write(f,s) local ok,v=pcall(function() return f:write(s) end);return ok and v~=nil and v~=false end
local function close(f)
    if not f then return true end
    local a,b=pcall(function() return f:flush() end)
    local c,d=pcall(function() return f:close() end)
    return a and b==true and c and d==true
end
function Inventory.new(options)
    local root=assert(options.path)
    local cfg=options.config or {}
    local pathsPerTick=math.max(1,math.min(64,tonumber(cfg.PathsPerTick) or 32))
    local maxSeconds=tonumber(cfg.MaxSeconds) or 1800
    local registry,helper,output,ledger
    local paths,seen,unitPackages={}, {},{}
    local state={active=false,complete=false,reason='not_started',paths_done=0,paths_total=0,candidates=0,
        assets_seen=0,assets_reported=0,query_errors=0,row_errors=0,tag_errors=0,duplicates=0,
        empty_paths=0,large_paths=0,truncated=false,coverage='UNKNOWN',started_at=0}
    local instance={}
    local function log(s) if options.log then pcall(options.log,'[AssetInventory] '..s) end end
    local function safe_call(o,key,...)
        if not valid(o) then return false,nil end
        local args=table.pack(...);return pcall(function() return o[key](o,table.unpack(args,1,args.n)) end)
    end
    local function loading()
        local ok,v=safe_call(registry,'IsLoadingAssets');if ok and type(v)=='boolean' then return v end;return 'unknown'
    end
    local function all_count()
        local list={};local ok,result=safe_call(registry,'GetAllAssets',list,true)
        local count=#list
        log('独立总量读回 GetAllAssets(onDisk=true)：call='..tostring(ok)..' result='..tostring(result)..' rows='..count)
        if ok and type(result)=='boolean' and (result==true or count==0) then return count end
    end
    local function manifest()
        local lines={'schema_version\t1\n','scope\tcurrent_mounted_on_disk_registry\n'}
        local keys={};for k,v in pairs(state) do if type(v)~='table' then keys[#keys+1]=k end end;table.sort(keys)
        for _,k in ipairs(keys) do lines[#lines+1]=k..'\t'..clean(state[k])..'\n' end
        local file=io.open(root..'/asset-index-status.tsv','w')
        if file then local ok=write(file,table.concat(lines));return close(file) and ok end
        return false
    end
    local function finish(reason)
        state.active=false;state.reason=reason
        local filesOK=close(output);filesOK=close(ledger) and filesOK;output,ledger=nil,nil
        state.io_complete=filesOK
        if not filesOK then state.complete=false;state.coverage='UNKNOWN';state.reason='io_unconfirmed' end
        if not manifest() then state.complete=false;state.coverage='UNKNOWN';state.reason='manifest_unconfirmed' end
        log('完成 reason='..state.reason..' assets='..state.assets_seen..' expected='..tostring(state.expected_assets)
            ..' paths='..state.paths_done..'/'..state.paths_total..' errors='..state.query_errors..'/'..state.row_errors
            ..' coverage='..state.coverage..'；不等于未挂载内容/全部地图刷怪配置完整')
        registry,helper=nil,nil
    end
    local function tag(row,name)
        local out={};local ok,found=safe_call(helper,'GetTagValue',row,FName(name),out)
        if not ok then state.tag_errors=state.tag_errors+1;return '' end
        return found==true and (text(out.OutTagValue) or '') or ''
    end
    local function row(data)
        local asset=pathof(data)
        if not asset or asset:sub(1,1)~='/' then state.row_errors=state.row_errors+1;return end
        if seen[asset] then state.duplicates=state.duplicates+1;return end
        seen[asset]=true
        local t=pathof(field(data,'AssetClassPath')) or text(field(data,'AssetClass')) or ''
        local values={asset_path=asset,package_name=text(field(data,'PackageName')),package_path=text(field(data,'PackagePath')),
            asset_name=text(field(data,'AssetName')),asset_type=t,generated_class='',parent_class='',native_parent='',row_structure=''}
        if t:lower():find('blueprint',1,true) or t=='/Script/CoreUObject.Class' then
            values.generated_class=tag(data,'GeneratedClass');values.parent_class=tag(data,'ParentClass');values.native_parent=tag(data,'NativeParentClass')
            state.blueprints=(state.blueprints or 0)+1
            if values.native_parent:find('PBZCharacter_NPC',1,true) then state.candidates=state.candidates+1 end
            local hint=(values.native_parent..' '..values.parent_class..' '..values.asset_name):lower()
            if hint:find('character',1,true) or hint:find('pawn',1,true) or hint:find('monster',1,true) or hint:find('npc',1,true) then
                unitPackages[values.package_name]=true
            end
        end
        if t=='/Script/Engine.DataTable' then values.row_structure=tag(data,'RowStructure') end
        local cells={};for _,k in ipairs(FIELDS) do cells[#cells+1]=clean(values[k]) end
        if not write(output,table.concat(cells,'\t')..'\n') then error('inventory_write_failed') end
        state.assets_seen=state.assets_seen+1
    end
    function instance:status() local copy={};for k,v in pairs(state) do copy[k]=v end;return copy end
    function instance:referencePackages() local out={};for package in pairs(unitPackages) do out[#out+1]=package end;table.sort(out);return out end
    function instance:start()
        if state.active then return false,self:status() end
        if not game_thread() then state.reason='requires_game_thread';return false,self:status() end
        if not root:match('^[A-Za-z]:[/\\]') and root:sub(1,1)~='/' then state.reason='absolute_path_required';return false,self:status() end
        local ok,h=pcall(StaticFindObject,'/Script/AssetRegistry.Default__AssetRegistryHelpers')
        if not ok or not valid(h) then state.reason='helpers_unavailable';return false,self:status() end
        helper=h;local got,r=safe_call(helper,'GetAssetRegistry')
        if not got or not valid(r) then state.reason='registry_unavailable';return false,self:status() end;registry=r
        state={active=false,complete=false,reason='running',paths_done=0,paths_total=0,candidates=0,assets_seen=0,
            assets_reported=0,query_errors=0,row_errors=0,tag_errors=0,duplicates=0,empty_paths=0,large_paths=0,
            truncated=false,coverage='UNKNOWN',started_at=os.time()}
        paths,seen,unitPackages={}, {},{}
        state.loading_start=loading();state.expected_assets=all_count()
        local raw={};local pathOK=safe_call(registry,'GetAllCachedPaths',raw)
        if not pathOK then state.reason='paths_unavailable';return false,self:status() end
        local unique={}
        for _,v in ipairs(raw) do
            local p=text(v)
            if p and p:sub(1,1)=='/' and not p:find('%c') and not unique[p] then unique[p]=true;paths[#paths+1]=p
            elseif not p or p:sub(1,1)~='/' then state.row_errors=state.row_errors+1 end
        end
        table.sort(paths);state.paths_total=#paths
        if #paths==0 then state.reason='empty_paths';return false,self:status() end
        output=io.open(root..'/asset-index.tsv','w');ledger=io.open(root..'/asset-path-audit.tsv','w')
        if not output or not ledger then close(output);close(ledger);state.reason='output_unavailable';return false,self:status() end
        if not write(output,table.concat(FIELDS,'\t')..'\n') or not write(ledger,'package_path\treturned\texported\tstatus\n') then
            finish('header_write_failed');return false,self:status()
        end
        state.active=true;manifest()
        log('开始完整元数据枚举；路径='..#paths..'，独立总量='..tostring(state.expected_assets)..'；每tick路径上限='..pathsPerTick..'；单路径不丢弃尾部，不LoadAsset')
        return true,self:status()
    end
    function instance:tick()
        if not state.active then return self:status() end
        if not game_thread() then finish('requires_game_thread');return self:status() end
        if os.time()-state.started_at>maxSeconds then state.truncated=true;finish('time_limit');return self:status() end
        local tickStart=os.clock()
        for _=1,pathsPerTick do
            local path=paths[state.paths_done+1]
            if not path then
                state.loading_end=loading();state.final_asset_count=all_count()
                state.complete=state.query_errors==0 and state.row_errors==0 and state.tag_errors==0 and state.duplicates==0
                    and state.loading_start==false and state.loading_end==false
                    and state.expected_assets==state.assets_seen and state.final_asset_count==state.assets_seen
                state.coverage=state.complete and 'CURRENT_MOUNTED_REGISTRY_VERIFIED' or 'UNKNOWN'
                finish(state.complete and 'inventory_verified' or 'inventory_partial');break
            end
            local list={};local ok,result=safe_call(registry,'GetAssetsByPath',FName(path),list,false,true)
            local before=state.assets_seen;local status='ok'
            state.assets_reported=state.assets_reported+#list
            if not ok or type(result)~='boolean' then status='query_error'
            elseif result==false and #list==0 then
                local checked,has=safe_call(registry,'HasAssets',FName(path),false)
                if checked and has==false then status='empty_verified';state.empty_paths=state.empty_paths+1 else status='query_error' end
            elseif result==false then status='query_error' end
            if status=='query_error' then state.query_errors=state.query_errors+1;log('查询未确认：'..path..' return='..tostring(result))
            else
                if #list>10000 then state.large_paths=state.large_paths+1;log('大目录完整处理：'..path..' rows='..#list) end
                for _,v in ipairs(list) do
                    local readOK,err=pcall(row,unwrap(v))
                    if not readOK then
                        state.row_errors=state.row_errors+1
                        if tostring(err):find('inventory_write_failed',1,true) then finish('inventory_write_failed');return self:status() end
                    end
                end
            end
            if not write(ledger,clean(path)..'\t'..#list..'\t'..(state.assets_seen-before)..'\t'..status..'\n') then
                finish('ledger_write_failed');break
            end
            state.paths_done=state.paths_done+1
            if os.clock()-tickStart>=0.015 then break end
        end
        if output then output:flush() end;if ledger then ledger:flush() end
        if state.active and state.paths_done%128<pathsPerTick then manifest() end
        return self:status()
    end
    function instance:silence(reason)
        if state.active then finish(reason or 'cancelled') end
    end
    function instance:cancel(reason) self:silence(reason);return self:status() end
    return instance
end
return Inventory
