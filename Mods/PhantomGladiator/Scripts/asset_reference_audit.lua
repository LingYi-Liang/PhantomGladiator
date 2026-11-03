-- Registry references are package evidence, NOT proof of an authored spawn.
local Audit={}
local function valid(o) if o==nil then return false end local ok,v=pcall(function() return o:IsValid() end);return ok and v==true end
local function call(o,key,...)
    if not valid(o) then return false,nil end
    local args=table.pack(...);return pcall(function() return o[key](o,table.unpack(args,1,args.n)) end)
end
local function text(v)
    if type(v)=='string' then return v end
    local ok,r=pcall(function() return v:get() end);if ok then v=r end
    if type(v)=='string' then return v end
    ok,r=pcall(function() return v:ToString() end);if ok and type(r)=='string' then return r end
end
local function clean(v) if v==nil then return '' end;return (tostring(v):gsub('[\t\r\n]',' ')) end
function Audit.new(options)
    local registry,output,queries
    local targets,index={},1
    local state={active=false,complete=false,targets=0,processed=0,edges=0,errors=0,empty=0,reason='not_started'}
    local deps={bIncludeSoftPackageReferences=true,bIncludeHardPackageReferences=true,bIncludeGamePackageReferences=true,
        bIncludeEditorOnlyPackageReferences=true,bIncludeSearchableNames=false,bIncludeSoftManagementReferences=false,bIncludeHardManagementReferences=false}
    local instance={}
    local function log(s) if options.log then pcall(options.log,'[ReferenceAudit] '..s) end end
    local function save()
        local f=io.open(options.path..'/reference-audit-status.tsv','w')
        if f then for k,v in pairs(state) do f:write(clean(k)..'\t'..clean(v)..'\n') end;f:flush();f:close() end
    end
    local function finish(reason)
        state.active=false;state.reason=reason
        for _,f in ipairs({output,queries}) do
            if f then local a=f:flush();local b=f:close();if a~=true or b~=true then state.complete=false;state.reason='io_unconfirmed' end end
        end
        output,queries,registry=nil,nil,nil;save()
        log('结束 processed='..state.processed..'/'..state.targets..' edges='..state.edges..' empty='..state.empty..' errors='..state.errors
            ..'；零引用不能排除实际刷怪，cooked依赖可能未保留')
    end
    function instance:status() local copy={};for k,v in pairs(state) do copy[k]=v end;return copy end
    function instance:start(packages)
        if state.active then return false end
        local thread,yes=pcall(IsInGameThread);if not thread or yes~=true then return false end
        local got,h=pcall(StaticFindObject,'/Script/AssetRegistry.Default__AssetRegistryHelpers')
        local ok,r;if got then ok,r=call(h,'GetAssetRegistry') end
        if not ok or not valid(r) then return false end;registry=r
        targets,index={},1
        for _,p in ipairs(packages or {}) do if type(p)=='string' and p:sub(1,1)=='/' and not p:find('[%c.]') then targets[#targets+1]=p end end
        state={active=true,complete=false,targets=#targets,processed=0,edges=0,errors=0,empty=0,reason='running'}
        output=io.open(options.path..'/asset-references.tsv','w');queries=io.open(options.path..'/reference-queries.tsv','w')
        if not output or not queries then finish('open_failed');return false end
        output:write('package\treferenced_by\n');queries:write('package\treturned\tstatus\n')
        log('开始对实际目录包查询硬/软引用；targets='..#targets..'；不加载任何包，不判定是否真实刷怪');save();return true
    end
    function instance:tick()
        if not state.active then return end
        local thread,yes=pcall(IsInGameThread);if not thread or yes~=true then finish('requires_game_thread');return end
        for _=1,4 do
            local package=targets[index]
            if not package then state.complete=state.errors==0;finish('finished');return end
            local refs={};local ok,result=call(registry,'K2_GetReferencers',FName(package),deps,refs)
            local status='ok'
            if not ok or type(result)~='boolean' then state.errors=state.errors+1;status='query_error'
            else
                if #refs==0 then state.empty=state.empty+1;status='empty_or_stripped' end
                for _,item in ipairs(refs) do
                    local p=text(item)
                    if p and p:sub(1,1)=='/' and not p:find('%c') then
                        local wrote=output:write(clean(package)..'\t'..clean(p)..'\n')
                        if not wrote then finish('write_failed');return end
                        state.edges=state.edges+1
                    else state.errors=state.errors+1 end
                end
            end
            queries:write(clean(package)..'\t'..#refs..'\t'..status..'\n')
            index=index+1;state.processed=state.processed+1
            if state.errors>=8 then finish('query_errors');return end
        end
        output:flush();queries:flush()
        if state.processed%64==0 then save() end
    end
    function instance:silence(reason) if state.active then finish(reason or 'cancelled') end end
    return instance
end
return Audit
