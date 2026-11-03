-- Experiment (Config.EnableCodexArtProbe): can the game's own codex pictures be saved as PNG on the player's
-- PC? The app may show them only as such a local export, never shipped (docs/DESIGN.md, 头像). Once per load,
-- 20 s after the game is ready, a few codex entries (FCodexEnemyRow WhiteIcon / HighPrecisionTexture /
-- HalfBodyTexture, ProjectPBZ.hpp) have each picture loaded, drawn onto a render target (KismetRenderingLibrary
-- canvas, at most 1024 on the long side) and written to Runtime/codex-art-*.png with ExportRenderTarget.
-- ImageWriteBlueprintLibrary.ExportToDisk wrote nothing in 0.37.17 (texture or drawn target, no error). The
-- first unit also tries ExportTexture2D and a linear (non-sRGB) target to compare. Each try is logged with the
-- file size and the format its first bytes show; Runtime/codex-art-probe.tsv lists them.
-- Soft pointers are only read (GetObjectID/GetAssetPathName); writing one from Lua crashed the game (v0.35.1).
local Probe={}
local KINDS={'WhiteIcon','HighPrecisionTexture','HalfBodyTexture'}
local LABELS={WhiteIcon='白色图标',HighPrecisionTexture='高清图',HalfBodyTexture='半身像'}
-- Units to try first (class path fragments): bosses and mobs of different kinds.
local WANTED={'042_AHua/','MoTian','BP_Monster_FemaleThug_TwinHoe','003_MaleThug/','GuiChai','CanQu_BiHai'}
local SAMPLES,MAX_EDGE,DELAY=6,1024,20
local RGBA8,RGBA8_SRGB=2,3 -- ETextureRenderTargetFormat::RTF_RGBA8 / RTF_RGBA8_SRGB
local TRANSLUCENT=2 -- EBlendMode::BLEND_Translucent

local function valid(v)
    if v==nil then return false end
    local ok,r=pcall(function()return v:IsValid()end)
    return ok and r==true
end
local function kind(v)
    if type(v)~='userdata' and type(v)~='table' then return type(v) end
    local ok,r=pcall(function()return v:type()end)
    return ok and type(r)=='string' and r or type(v)
end
local function unwrap(v)
    local k=kind(v)
    if k=='RemoteUnrealParam' or k=='LocalUnrealParam' then
        local ok,r=pcall(function()return v:get()end)
        return ok and r or nil
    end
    return v
end
local function field(object,name)
    object=unwrap(object)
    if object==nil then return nil end
    local ok,v=pcall(function()return object[name]end)
    return ok and unwrap(v) or nil
end
local function text(v)
    v=unwrap(v)
    if type(v)=='string' then return v end
    if v==nil then return nil end
    local ok,r=pcall(function()return v:ToString()end)
    return ok and type(r)=='string' and r or nil
end
local function items(v)
    v=unwrap(v)
    local out={}
    if kind(v)=='table' then for _,item in ipairs(v)do out[#out+1]=unwrap(item) end;return out end
    pcall(function()v:ForEach(function(_,item)out[#out+1]=unwrap(item)end)end)
    return out
end
-- The asset path a soft pointer names, read from its value only (nothing is resolved or loaded here).
local function softPath(reference)
    reference=unwrap(reference)
    if reference==nil then return nil end
    local ok,id=pcall(function()return reference:GetObjectID()end)
    if not ok or id==nil then return nil end
    local okName,name=pcall(function()return id:GetAssetPathName()end)
    local path=okName and text(name) or nil
    if not path or path=='' or path=='None' then return nil end
    return path
end

function Probe.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local clock=options.clock or os.clock
    local staticFind=options.staticFind or function(path)return StaticFindObject(path)end
    local loadAsset=options.loadAsset or function(path)return LoadAsset(path)end
    local findAll=options.findAll or function(name)return FindAllOf(name)end
    local self={state='waiting',results={}}
    local function say(message)log('[CodexArt] '..message)end
    -- Size and format of a written file, from its first bytes.
    local function written(path)
        local f=fs.open(path,'rb')
        if not f then return 0,'无文件' end
        local head=f:read(10) or ''
        local size=f:seek('end') or 0
        f:close()
        local format=head:sub(1,4)=='\137PNG' and 'PNG' or head:sub(1,2)=='#?' and 'HDR'
            or head:sub(1,4)=='\118\47\49\1' and 'EXR' or (size>0 and '未知' or '空')
        return size,format
    end
    local function subsystem(world)
        local ok,list=pcall(findAll,'PBZCodexSubsystem')
        if not ok or type(list)~='table' then return nil end
        if not valid(world) then return nil end
        local okWorld,key=pcall(function()return world:GetAddress()end)
        if not okWorld then return nil end
        for _,candidate in ipairs(list)do
            if valid(candidate) then
                local okOuter,outer=pcall(function()return candidate:GetOuter()end)
                if okOuter and valid(outer) then
                    local okKey,outerKey=pcall(function()return outer:GetAddress()end)
                    if okKey and outerKey==key then return candidate end
                end
            end
        end
        return nil
    end
    local function texture(path)
        local found=staticFind(path)
        if not valid(found) then pcall(loadAsset,path);found=staticFind(path) end
        return valid(found) and found or nil
    end
    local function size(tex)
        local okX,x=pcall(function()return tex:Blueprint_GetSizeX()end)
        local okY,y=pcall(function()return tex:Blueprint_GetSizeY()end)
        return okX and tonumber(unwrap(x)) or nil,okY and tonumber(unwrap(y)) or nil
    end
    -- Drawn onto a render target of the picture's size (at most MAX_EDGE on the long side) and exported.
    local function exportDrawn(krl,world,tex,dir,name,w,h,format)
        local scale=math.min(1,MAX_EDGE/math.max(w,h))
        local rw,rh=math.max(1,math.floor(w*scale)),math.max(1,math.floor(h*scale))
        local okRt,rt=pcall(function()return krl:CreateRenderTarget2D(world,rw,rh,format,{R=0,G=0,B=0,A=0},false,false)end)
        rt=okRt and unwrap(rt) or nil
        if not valid(rt) then return false,'创建渲染目标失败' end
        local out={}
        local okBegin=pcall(function()krl:BeginDrawCanvasToRenderTarget(world,rt,out,out,out)end)
        local canvas=unwrap(out.Canvas)
        local drew=false
        if okBegin and valid(canvas) then
            drew=pcall(function()canvas:K2_DrawTexture(tex,{X=0,Y=0},{X=rw,Y=rh},{X=0,Y=0},{X=1,Y=1},{R=1,G=1,B=1,A=1},TRANSLUCENT,0,{X=0.5,Y=0.5})end)
        end
        if okBegin then pcall(function()krl:EndDrawCanvasToRenderTarget(world,out.Context)end) end
        local ok,err=false,'画布不可用 begin='..tostring(okBegin)..' canvas='..tostring(valid(canvas))
        if drew then ok,err=pcall(function()krl:ExportRenderTarget(world,rt,dir,name)end) end
        pcall(function()krl:ReleaseRenderTarget2D(rt)end)
        return ok,err,rw,rh
    end

    local function pick(entries)
        local rows={}
        for _,row in ipairs(entries)do
            local class=softPath(field(row,'EnemyClass'))
            local pictures={}
            for _,k in ipairs(KINDS)do pictures[k]=softPath(field(row,k)) end
            if class and (pictures.WhiteIcon or pictures.HighPrecisionTexture or pictures.HalfBodyTexture) then
                rows[#rows+1]={class=class,name=text(field(row,'Enemy_CH_Hans_Name')) or '?',pictures=pictures,boss=field(row,'bIsBoss')==true}
            end
        end
        local chosen,used={},{}
        for _,fragment in ipairs(WANTED)do
            for i,row in ipairs(rows)do
                if not used[i] and row.class:find(fragment,1,true) then chosen[#chosen+1]=row;used[i]=true;break end
            end
        end
        for i,row in ipairs(rows)do
            if #chosen>=SAMPLES then break end
            if not used[i] then chosen[#chosen+1]=row;used[i]=true end
        end
        return chosen,#rows
    end

    local function run()
        local world=options.getWorld and options.getWorld()
        local codex=subsystem(world)
        if not codex then say('当前World的图鉴子系统没找到，未导出');return end
        local okEntries,entries=pcall(function()return codex:GetAllEnemyCodexEntries()end)
        if not okEntries then say('读取图鉴失败 '..tostring(entries));return end
        local chosen,total=pick(items(entries))
        local krl=staticFind('/Script/Engine.Default__KismetRenderingLibrary')
        say('图鉴 '..total..' 条有图，试导出 '..#chosen..' 只；渲染函数库='..tostring(valid(krl)))
        if not valid(krl) or not valid(world) then return end
        local rows={'index\tname\tclass\tkind\ttexture\twidth\theight\tmethod\tbytes\tformat\tfile'}
        local function record(index,row,k,path,w,h,method,file)
            local bytes,format=written(options.path..'/'..file)
            self.results[#self.results+1]={name=row.name,kind=k,method=method,bytes=bytes,format=format}
            rows[#rows+1]=table.concat({index,row.name,row.class,k,path,tostring(w),tostring(h),method,tostring(bytes),format,file},'\t')
            return bytes,format
        end
        for index,row in ipairs(chosen)do
            local short=row.class:match('%.([^.]+)$') or ('unit'..index)
            for _,k in ipairs(KINDS)do
                local path=row.pictures[k]
                if path then
                    local tex=texture(path)
                    local w,h=nil,nil
                    if tex then w,h=size(tex) end
                    local base='codex-art-'..index..'-'..short..'-'..k
                    local detail=''
                    if tex and w and h then
                        local ok,err,rw,rh=exportDrawn(krl,world,tex,options.path,base..'.png',w,h,RGBA8_SRGB)
                        local bytes,format=record(index,row,k,path,w,h,'canvas-srgb',base..'.png')
                        detail=' 画布导出调用='..tostring(ok)..(ok and '' or (' '..tostring(err)))..' 尺寸='..tostring(rw)..'x'..tostring(rh)..' 字节='..bytes..' 格式='..format
                        if index==1 then
                            -- The first unit only: a linear target, and the texture exported as it is.
                            local okL=exportDrawn(krl,world,tex,options.path,base..'-linear.png',w,h,RGBA8)
                            local bytesL,formatL=record(index,row,k,path,w,h,'canvas-linear',base..'-linear.png')
                            local okT,errT=pcall(function()krl:ExportTexture2D(world,tex,options.path,base..'-texture2d.png')end)
                            local bytesT,formatT=record(index,row,k,path,w,h,'texture2d',base..'-texture2d.png')
                            detail=detail..' 线性画布='..tostring(okL)..'/'..bytesL..'/'..formatL..' 直接导出='..tostring(okT)..(okT and '' or (' '..tostring(errT)))..'/'..bytesT..'/'..formatT
                        end
                    end
                    say(row.name..' '..LABELS[k]..' 贴图='..path..' 加载='..tostring(tex~=nil)..' 原尺寸='..tostring(w)..'x'..tostring(h)..detail)
                end
            end
        end
        local out=fs.open(options.path..'/codex-art-probe.tsv','w')
        if out then out:write(table.concat(rows,'\n')..'\n');out:close() end
        say('导出结束，清单写入 codex-art-probe.tsv')
    end

    function self:tick()
        if self.state=='done' then return end
        if options.ready and not options.ready() then return end
        local now=clock()
        self.at=self.at or now+DELAY
        if now<self.at then return end
        self.state='done'
        local ok,err=pcall(run)
        if not ok then say('导出中断 '..tostring(err)) end
    end
    return self
end
return Probe
