local Router=require('key_router')
local Keys={}
Keys.actions={'spawn','start','stop','refresh_catalog','toggle_camera','exit_camera','cycle_team','toggle_spectator',
    'recall_companions','toggle_time_stop','toggle_track','track_pick','track_next'}
Keys.labels={spawn='召唤所选单位',start='开始交战',stop='停止并清理',refresh_catalog='刷新单位目录',
    toggle_camera='自由观战（无仇恨＋隐身＋无敌锁血）',exit_camera='退出自由观战并恢复',cycle_team='切换召唤队伍',toggle_spectator='单独切换无仇恨',
    recall_companions='召回随从到身边',toggle_time_stop='时停（游戏暂停，自由视角照常移动）',
    toggle_track='镜头跟踪开关',track_pick='镜头锁定屏幕中央的单位',track_next='镜头跟踪下一个单位'}
-- Actions added after FunctionKeysV2 files were first written: a save or a proposal without one leaves it unbound
-- (otherwise a save from before would count as invalid and every key would come up unbound).
Keys.added={recall_companions=true,toggle_time_stop=true,toggle_track=true,track_pick=true,track_next=true}
local function read(fs,path)
    local f=fs.open(path,'rb');if not f then return nil end
    local value=f:read(65537);f:close();return value and #value<=65536 and value or nil
end
local function write(fs,path,text)
    local f=fs.open(path,'wb');if not f then return false end
    local ok=f:write(text);local flushed=f:flush();local closed=f:close()
    return ok~=nil and flushed~=nil and closed~=nil and read(fs,path)==text
end
function Keys.new(options)
    local fs=options.io or io;local oslib=options.os or os
    local self={entries={},active={},errors={},revision=0,alive=true,message='功能快捷键默认未绑定'}
    self.epoch='functionkeys-'..os.time()..'-'..tostring({}):gsub('[^%w]','')
    local path=options.path..'/function-keybinds.tsv';local statePath=options.path..'/function-keybinds-state.tsv'
    local log=options.log or function()end
    local function defaults()local out={};for _,name in ipairs(Keys.actions)do out[name]={key_code=0,modifiers=0}end;return out end
    local function validate(proposal)
        local out,seen={},{}
        for _,name in ipairs(Keys.actions)do
            local value=proposal[name]
            if value==nil and Keys.added[name] then value={key_code=0,modifiers=0} end
            local entry=type(value)=='string' and Router.parse(value) or value
            if type(entry)~='table' or not Router.valid(entry.key_code,entry.modifiers) then return nil,'无效快捷键：'..Keys.labels[name]end
            local vk,mask=entry.key_code,entry.key_code==0 and 0 or entry.modifiers
            if vk>0 then
                local blocked=Router.reserved(vk,mask);if blocked then return nil,Router.label(vk,mask)..' 已被「'..blocked..'」占用'end
                if seen[vk] then return nil,Router.label(vk,mask)..' 的主键同时用于「'..Keys.labels[seen[vk]]..'」和「'..Keys.labels[name]..'」'end
                seen[vk]=name
            end
            out[name]={key_code=vk,modifiers=mask}
        end
        for name in pairs(proposal)do if not Keys.labels[name]then return nil,'未知快捷键功能'end end
        return out
    end
    local function parse(text)
        if not text then return nil end
        local revision=tonumber(text:match('^FunctionKeysV2\t(%d+)\r?\n'))
        if not revision or revision>2147483646 then return nil end
        local values={}
        for line in text:gmatch('[^\r\n]+')do if not line:match('^FunctionKeysV2\t')then
            local name,vk,mask=line:match('^([%w_]+)\t(%d+)\t(%d+)$')
            if not name or values[name]then return nil end
            values[name]={key_code=tonumber(vk),modifiers=tonumber(mask)}
        end end
        local checked=validate(values);return checked,revision
    end
    self.entries=defaults()
    local source=read(fs,path);local entries,revision=parse(source)
    if not entries then entries,revision=parse(read(fs,path..'.bak'))end
    if entries then self.entries=entries;self.revision=revision
    elseif source then self.message='功能快捷键文件无效，保持未绑定';log('[FunctionKeys] '..self.message)
    else
        -- Only explicit old saves migrate. Former hard-coded/default keys do not.
        local legacy=read(fs,options.path..'/keybinds.tsv')
        if legacy then
            local proposal=defaults();local count=0;local seen={}
            local legacyActions={spawn=true,start=true,stop=true,refresh_catalog=true}
            for action,key in legacy:gmatch('([^\t\r\n]+)\t([^\t\r\n]+)')do
                if not legacyActions[action] or seen[action]then count=-999;break end
                seen[action]=true;proposal[action]=Router.parse(key);count=count+1
            end
            local checked=count==4 and validate(proposal)
            if checked then self.entries=checked;self.message='已保留旧版保存的四项绑定；其余功能未绑定' end
        end
    end
    local function serialize(values,rev)
        local lines={'FunctionKeysV2\t'..rev}
        for _,name in ipairs(Keys.actions)do local e=values[name];lines[#lines+1]=name..'\t'..e.key_code..'\t'..e.modifiers end
        return table.concat(lines,'\n')..'\n'
    end
    local function persist(text)
        local temp,backup=path..'.tmp',path..'.bak'
        if not write(fs,temp,text)then return false end
        local old=read(fs,path)
        if old then
            if read(fs,backup) and not oslib.remove(backup)then return false end
            if not oslib.rename(path,backup)then return false end
        end
        local moved=oslib.rename(temp,path)
        if not moved or read(fs,path)~=text then
            if moved then oslib.remove(path)end
            if old then oslib.rename(backup,path)end
            return false
        end
        return true
    end
    local function publish()
        local lines={'FunctionKeyStateV2\t'..self.revision..'\t'..self.epoch}
        for _,name in ipairs(Keys.actions)do
            lines[#lines+1]=name..'\t'..(self.active[name] and '1' or '0')..'\t'..(self.errors[name] or ''):gsub('[\t\r\n]',' ')
        end
        write(fs,statePath,table.concat(lines,'\n')..'\n')
    end
    function self:owner(vk)
        for _,name in ipairs(Keys.actions)do if self.entries[name].key_code==vk and vk>0 then return name,Keys.labels[name]end end
    end
    function self:start()
        self.active,self.errors={},{}
        for _,name in ipairs(Keys.actions)do
            local e=self.entries[name]
            if e.key_code>0 then
                local ok,why=options.router:ensure(e.key_code,e.modifiers)
                if ok then self.active[name]=true else self.errors[name]=why end
                log('[FunctionKeys] 注册读回 action='..name..' key='..Router.label(e.key_code,e.modifiers)..' active='..tostring(ok)..(ok and '' or (' error='..tostring(why))))
            end
        end
        publish();log('[FunctionKeys] 已载入；默认空白，revision='..self.revision)
    end
    function self:configure(proposal)
        local checked,why=validate(proposal)
        if not checked then return {ok=false,message=why,spawned_count=0}end
        for _,name in ipairs(Keys.actions)do
            local e=checked[name]
            if e.key_code>0 then
                local unit=options.unitOwner and options.unitOwner(e.key_code)
                if unit then return {ok=false,message=Router.label(e.key_code,e.modifiers)..' 已被单位「'..unit..'」占用',spawned_count=0}end
                local ok,reason=options.router:ensure(e.key_code,e.modifiers)
                if not ok then return {ok=false,message=Keys.labels[name]..'：'..tostring(reason),spawned_count=0}end
            end
        end
        local rev=self.revision+1
        if not persist(serialize(checked,rev))then return {ok=false,message='快捷键保存未确认，旧绑定继续生效',spawned_count=0}end
        self.entries,self.revision=checked,rev;self.active,self.errors={},{}
        for _,name in ipairs(Keys.actions)do if checked[name].key_code>0 then self.active[name]=true end end
        self.message='快捷键已保存并在游戏端生效';publish()
        log('[FunctionKeys] 保存读回成功 revision='..rev..'；旧绑定与旧排队请求已失效')
        for _,name in ipairs(Keys.actions)do local e=checked[name];log('[FunctionKeys] 当前 action='..name..' key='..Router.label(e.key_code,e.modifiers)..' active='..tostring(self.active[name]==true))end
        return {ok=true,message=self.message,spawned_count=0}
    end
    function self:press(vk,mask)
        local action=self:owner(vk)
        if not action or not self.active[action] or self.entries[action].modifiers~=mask then return false end
        local revision=self.revision
        local queue=(action=='spawn' and options.queueSpawn) or options.queue or ExecuteInGameThread
        queue(function()
            if not self.alive or revision~=self.revision then return end
            local e=self.entries[action]
            if self.active[action] and e.key_code==vk and e.modifiers==mask then options.dispatch(action)end
        end)
        return true
    end
    function self:token(action)
        return self.active[action] and Router.token(self.entries[action]) or ''
    end
    function self:status()return {epoch=self.epoch,revision=self.revision,message=self.message}end
    function self:silence()self.alive=false end
    return self
end
return Keys
