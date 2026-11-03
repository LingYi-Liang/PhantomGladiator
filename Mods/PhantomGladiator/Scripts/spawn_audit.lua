-- C++调用前后留下独立持久阶段日志，游戏重启不会覆盖它。只写本Mod明确指定的文件。
local Audit = {}
local function clean(value) return (tostring(value or ""):gsub("[\t\r\n]"," ")) end
function Audit.new(path,log)
    local serial=0
    local instance={}
    function instance:record(stage,unit,detail)
        serial=serial+1
        local line=table.concat({tostring(os.time()),tostring(serial),clean(stage),clean(unit),clean(detail)},"\t").."\n"
        local file,err=io.open(path,"a")
        if not file then if log then log("生成阶段日志无法写入: "..tostring(err)) end; return false end
        local wrote,werr=file:write(line)
        local flushed,ferr=file:flush()
        local closed,cerr=file:close()
        local ok=wrote~=nil and wrote~=false and flushed~=nil and flushed~=false and closed~=nil and closed~=false
        if not ok and log then log("生成阶段日志未确认: "..tostring(werr or ferr or cerr)) end
        return ok
    end
    return instance
end
return Audit
