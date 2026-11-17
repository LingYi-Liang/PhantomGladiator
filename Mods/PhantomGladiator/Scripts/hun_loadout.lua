-- The Hun profile as the local panel last saved it, in the form the game side reads: how many to summon,
-- the attribute values to write on each new body, and the effect classes of the enabled accessories.
-- Read-only here; the panel owns the file.
local Loadout={}
local MAX_BYTES=262144
local MAX_ROWS=1024

local function finite(value)return type(value)=='number'and value==value and value~=math.huge and value~=-math.huge end

-- Returns the parsed table, or nil and why the text is not a loadout.
function Loadout.parse(text)
    if type(text)~='string'or #text>MAX_BYTES or text:sub(-1)~='\n'then return nil,'文件为空、过大或没有结尾换行'end
    local revision=tonumber(text:match('^HunLoadoutV1\t(%d+)\n'))
    if not revision or revision>2147483646 then return nil,'文件头无效'end
    local out={revision=revision,count=1,attributes={},effects={},accessories=false}
    local rows,first,seen=0,true,{}
    for line in text:gmatch('([^\n]*)\n')do
        if first then first=false
        else
            rows=rows+1
            if rows>MAX_ROWS then return nil,'条目过多'end
            local kind,rest=line:match('^(%a+)\t(.*)$')
            if kind=='count'then
                local count=tonumber(rest)
                if not count or count%1~=0 or count<1 or count>100 then return nil,'数量无效'end
                out.count=count
            elseif kind=='attr'then
                local field,raw=rest:match('^([%w_]+)\t([^\t]+)$')
                local value=tonumber(raw)
                if not field or #field>64 or not finite(value)or out.attributes[field]~=nil then return nil,'属性条目无效'end
                out.attributes[field]=value
            elseif kind=='accessories'then
                if rest~='on'and rest~='off'then return nil,'饰品开关无效'end
                out.accessories=rest=='on'
            elseif kind=='ge'then
                local path,level,label=rest:match('^(/[%w_/%-%.]+%.[%w_%-]+_C)\t(%d+)\t([^\t]*)$')
                level=tonumber(level)
                if not path or #path>512 or path:find('..',1,true)or path:find('//',1,true)or not level or level>100
                    or #label>128 or label:find('%c')or seen[path]then return nil,'饰品效果条目无效'end
                seen[path]=true
                out.effects[#out.effects+1]={path=path,level=level,label=label}
            else return nil,'未知条目'end
        end
    end
    return out
end

function Loadout.new(options)
    local self={revision=nil,value=nil}
    local fs=options.io or io
    local source=options.path..'/hun-loadout.tsv'
    local log=options.log or function()end
    -- The current loadout, re-read only when the file's revision changes; nil while there is no usable file.
    function self:read()
        local file=fs.open(source,'rb')
        if not file then
            if self.revision~=false then self.revision,self.value=false,nil;log('[HunLoadout] 没有方案文件；按默认数量 1、不写属性')end
            return nil
        end
        local header=file:read(64)
        local revision=tonumber((header or''):match('^HunLoadoutV1\t(%d+)\n'))or-1
        if revision==self.revision then file:close();return self.value end
        local text=file:seek('set',0)and file:read(MAX_BYTES+1)or nil
        file:close()
        local value,why=Loadout.parse(text)
        self.revision,self.value=revision,value
        local attributes,n=0,0
        if value then for _ in pairs(value.attributes)do attributes=attributes+1 end;n=#value.effects end
        log('[HunLoadout] 读取方案 revision='..tostring(revision)..'；读回='..(value and('数量='..value.count..' 属性='..attributes..' 项 饰品效果='..n
            ..' 条（'..(value.accessories and'开'or'关')..'）')or('无效：'..tostring(why)..'，未采用')))
        return value
    end
    return self
end
return Loadout
