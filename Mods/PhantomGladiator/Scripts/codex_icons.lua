-- Codex icons on this PC for the app's unit cards. Game pictures are never shipped (docs/DESIGN.md, 头像):
-- each player's own game provides them. Once per load, 10 s after the game is ready, every codex entry's
-- WhiteIcon (FCodexEnemyRow, ProjectPBZ.hpp; despite the name a 256 px head-and-shoulders bust) that is not
-- on disk yet is drawn onto an sRGB render target and saved as PNG with KismetRenderingLibrary.
-- ExportRenderTarget, two per support tick (ImageWriteBlueprintLibrary.ExportToDisk and ExportTexture2D write
-- nothing in this game; REVERSE_ENGINEERING.md, 图鉴图片本地导出实验). Files go to Runtime/codex-icons/, or
-- to Runtime/codex-icon-*.png if that folder cannot be written; Runtime/codex-icons.tsv maps every unit name,
-- codex aliases included, to its file. Soft pointers are only read (GetObjectID/GetAssetPathName).
-- A later load takes the files that index lists on trust once one of them checks out: opening every PNG at
-- load stalled the game about 0.5 s on a cold start (v0.37.3).
local U=require('ue_observe')
local Icons={}
local SIZE,PER_TICK,DELAY,FAIL_LINES=256,2,10,20
local RGBA8_SRGB,TRANSLUCENT=3,2 -- ETextureRenderTargetFormat::RTF_RGBA8_SRGB, EBlendMode::BLEND_Translucent

-- Codex rows are structs, not UObjects: read without the IsValid check U.field makes.
local function field(object,name)
    object=U.unwrap(object)
    if object==nil then return nil end
    local ok,v=pcall(function()return object[name]end)
    return ok and U.unwrap(v) or nil
end
local function text(v)
    v=U.unwrap(v)
    if type(v)=='string' then return v end
    if v==nil then return nil end
    local ok,r=pcall(function()return v:ToString()end)
    return ok and type(r)=='string' and r or nil
end
local function items(v)
    v=U.unwrap(v)
    local out={}
    if U.kind(v)=='table' then for _,item in ipairs(v)do out[#out+1]=U.unwrap(item) end;return out end
    pcall(function()v:ForEach(function(_,item)out[#out+1]=U.unwrap(item)end)end)
    return out
end
local function softPath(reference)
    reference=U.unwrap(reference)
    if reference==nil then return nil end
    local ok,id=pcall(function()return reference:GetObjectID()end)
    if not ok or id==nil then return nil end
    local okName,name=pcall(function()return id:GetAssetPathName()end)
    local path=okName and text(name) or nil
    return path and path~='' and path~='None' and path or nil
end
-- "/P/BP_X.BP_X_C" -> "BP_X" (the app's unit id); "/P/T_X_w.T_X_w" -> "T_X_w"
local function shortName(classPath)return classPath and classPath:match('/([%w_]+)%.[%w_]+$') end
local function assetName(path)return path and path:match('%.([%w_]+)$') end

function Icons.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local clock=options.clock or os.clock
    local staticFind=options.staticFind or function(path)return StaticFindObject(path)end
    local loadAsset=options.loadAsset or function(path)return LoadAsset(path)end
    local findAll=options.findAll or function(name)return FindAllOf(name)end
    local root=options.path
    local self={state='waiting',made=0,had=0,failed=0,units=0,flat=false,failLines=0}
    local function say(message)log('[CodexIcons] '..message)end
    -- Where a file lives, relative to Runtime: the folder first, flat names after a folder failure.
    local function relative(name)return self.flat and ('codex-icon-'..name..'.png') or ('codex-icons/'..name..'.png') end
    local function present(file)
        local f=fs.open(root..'/'..file,'rb')
        if not f then return false end
        local size=f:seek('end') or 0
        f:close()
        return size>0
    end
    -- Texture name -> file, from the index the last pass wrote.
    local function readIndex()
        local listed={}
        local f=fs.open(root..'/codex-icons.tsv','r')
        if not f then return listed end
        local text=f:read('*a') or ''
        f:close()
        for file in text:gmatch('[^\t\r\n]*\t([^\r\n]+)')do
            local name=file:match('([%w_]+)%.png$')
            if name and not listed[name] then listed[name]=file end
        end
        return listed
    end
    local function subsystem(world)
        if not U.valid(world) then return nil end
        local key=U.key(world)
        local ok,list=pcall(findAll,'PBZCodexSubsystem')
        if not ok or type(list)~='table' then return nil end
        for _,candidate in ipairs(list)do
            if U.valid(candidate) then
                local okOuter,outer=pcall(function()return candidate:GetOuter()end)
                if okOuter and U.key(outer)==key then return candidate end
            end
        end
        return nil
    end
    -- Every unit name (main class and aliases) with its icon texture, and the textures still to save.
    local function collect(world)
        local codex=subsystem(world)
        if not codex then return nil,'当前World的图鉴子系统没找到' end
        local ok,entries=pcall(function()return codex:GetAllEnemyCodexEntries()end)
        if not ok then return nil,'读取图鉴失败 '..tostring(entries) end
        local units,textures,order={},{},{}
        for _,row in ipairs(items(entries))do
            local path=softPath(field(row,'WhiteIcon'))
            local name=assetName(path)
            if name then
                if not textures[name] then textures[name]=path;order[#order+1]=name end
                local unit=shortName(softPath(field(row,'EnemyClass')))
                if unit then units[unit]=name end
                for _,alias in ipairs(items(field(row,'AliasEnemyClasses')))do
                    local other=shortName(softPath(alias))
                    if other and not units[other] then units[other]=name end
                end
            end
        end
        return {units=units,textures=textures,order=order}
    end
    local function target(krl,world)
        if U.valid(self.rt) then return self.rt end
        local ok,rt=pcall(function()return krl:CreateRenderTarget2D(world,SIZE,SIZE,RGBA8_SRGB,{R=0,G=0,B=0,A=0},false,false)end)
        self.rt=ok and U.unwrap(rt) or nil
        return U.valid(self.rt) and self.rt or nil
    end
    -- The icon drawn to fit the square (bottom-aligned, as the busts fade out at the bottom), then saved.
    local function save(krl,world,name,path)
        local tex=staticFind(path)
        if not U.valid(tex) then pcall(loadAsset,path);tex=staticFind(path) end
        if not U.valid(tex) then return false,'贴图加载失败' end
        local rt=target(krl,world)
        if not rt then return false,'创建渲染目标失败' end
        local okW,w=pcall(function()return tex:Blueprint_GetSizeX()end)
        local okH,h=pcall(function()return tex:Blueprint_GetSizeY()end)
        w,h=okW and tonumber(U.unwrap(w)) or SIZE,okH and tonumber(U.unwrap(h)) or SIZE
        local scale=SIZE/math.max(w,h,1)
        local dw,dh=w*scale,h*scale
        pcall(function()krl:ClearRenderTarget2D(world,rt,{R=0,G=0,B=0,A=0})end)
        local out={}
        local okBegin=pcall(function()krl:BeginDrawCanvasToRenderTarget(world,rt,out,out,out)end)
        local canvas=U.unwrap(out.Canvas)
        local drew=false
        if okBegin and U.valid(canvas) then
            drew=pcall(function()canvas:K2_DrawTexture(tex,{X=(SIZE-dw)/2,Y=SIZE-dh},{X=dw,Y=dh},{X=0,Y=0},{X=1,Y=1},{R=1,G=1,B=1,A=1},TRANSLUCENT,0,{X=0.5,Y=0.5})end)
        end
        if okBegin then pcall(function()krl:EndDrawCanvasToRenderTarget(world,out.Context)end) end
        if not drew then return false,'画布绘制失败' end
        local file=relative(name)
        local folder,leaf=file:match('^(.-)/?([^/]+)$')
        local ok,err=pcall(function()krl:ExportRenderTarget(world,rt,folder=='' and root or (root..'/'..folder),leaf)end)
        if not ok then return false,'导出调用失败 '..tostring(err) end
        return present(file),'没有写出文件'
    end
    local function finish(job)
        if U.valid(self.rt) and job.krl then pcall(function()job.krl:ReleaseRenderTarget2D(self.rt)end) end
        self.rt=nil
        local lines,count={'unit\tfile'},0
        for unit,name in pairs(job.units)do
            local file=job.saved[name]
            if file then count=count+1;lines[#lines+1]=unit..'\t'..file end
        end
        table.sort(lines,function(a,b)return a=='unit\tfile' or (b~='unit\tfile' and a<b)end)
        local out=fs.open(root..'/codex-icons.tsv','w')
        local written=false
        if out then written=out:write(table.concat(lines,'\n')..'\n')~=nil;out:close() end
        self.units=count
        self.state='done'
        say(string.format('完成：图标 %d 张（本次新存 %d、已有 %d、失败 %d），对应单位 %d 个，索引写入=%s%s；用时 %.1f 秒',
            #job.order,self.made,self.had,self.failed,count,tostring(written),self.flat and '（存在 Runtime 根目录）' or '',clock()-job.started))
    end

    function self:tick()
        if self.state=='done' then return end
        if options.ready and not options.ready() then return end
        local now=clock()
        if self.state=='waiting' then
            self.at=self.at or now+DELAY
            if now<self.at then return end
            local world=options.getWorld and options.getWorld()
            local found,why=collect(world)
            if not found then self.state='done';say('未导出：'..why);return end
            found.saved,found.queue,found.started,found.world={},{},now,world
            local listed,sample,trusted=readIndex(),nil,0
            for _,name in ipairs(found.order)do
                if listed[name] then sample=listed[name];break end
            end
            if sample and not present(sample) then listed={} end
            for _,name in ipairs(found.order)do
                local file=relative(name)
                if listed[name] then
                    found.saved[name]=listed[name];self.had=self.had+1;trusted=trusted+1
                elseif present(file) or present('codex-icon-'..name..'.png') then
                    found.saved[name]=present(file) and file or ('codex-icon-'..name..'.png')
                    self.had=self.had+1
                else found.queue[#found.queue+1]=name end
            end
            found.krl=staticFind('/Script/Engine.Default__KismetRenderingLibrary')
            self.job=found;self.state='saving'
            say('图鉴 '..#found.order..' 张图标，已有 '..self.had..'，待导出 '..#found.queue..'；其中按索引认定 '..trusted)
            if #found.queue>0 and not U.valid(found.krl) then self.failed=#found.queue;found.queue={};say('渲染函数库不可用') end
        end
        local job=self.job
        if not U.valid(job.world) then self.state='done';say('World 已变化，本次停止；下次加载接着导出');return end
        for _=1,PER_TICK do
            local name=table.remove(job.queue,1)
            if not name then break end
            local ok,why=save(job.krl,job.world,name,job.textures[name])
            if not ok and not self.flat and self.made==0 then
                -- The first save into the folder failed: try the same picture as a flat file.
                self.flat=true
                local okFlat=save(job.krl,job.world,name,job.textures[name])
                if okFlat then ok=true;say('codex-icons 文件夹写不进去，改存在 Runtime 根目录') else self.flat=false end
            end
            if ok then self.made=self.made+1;job.saved[name]=relative(name)
            else
                self.failed=self.failed+1
                if self.failLines<FAIL_LINES then self.failLines=self.failLines+1;say('未导出 '..name..'：'..tostring(why)) end
            end
        end
        if #job.queue==0 then finish(job) end
    end
    function self:status()return {state=self.state,made=self.made,had=self.had,failed=self.failed,units=self.units}end
    return self
end
return Icons
