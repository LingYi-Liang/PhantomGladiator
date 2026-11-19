-- 随从处决 BOSS: the app switch (set_companion_executions). On, a boss a companion is after can be executed by that
-- companion (arena_executions.lua); off, as in the game, only the player executes it. Off by default; saved in
-- Runtime/companion-executions.tsv.
-- 随从处决小怪 is a second switch in the same file (set_companion_minion_executions): on, a minion a companion is
-- after is executed by the nearest companion too. Off by default; a file saved before it existed means off.
local Setting={}
local HEADER='CompanionExecutionsV1'
function Setting.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local file=options.path..'/companion-executions.tsv'
    local self={on=false,minions=false}
    local function readFile()
        local f=fs.open(file,'r');if not f then return nil end
        local value=f:read('*a');f:close();return value
    end
    do
        local saved=readFile()
        if type(saved)=='string' and saved:sub(1,#HEADER+1)==HEADER..'\t' then
            self.on=saved:find('\ton=1',1,true)~=nil
            self.minions=saved:find('\tminions=1',1,true)~=nil
        end
    end
    -- The file keeps its old form while the minion switch is off, so an older build reads it as before.
    local function save(on,minions)
        local text=HEADER..'\ton='..(on and '1' or '0')..(minions and '\tminions=1' or '')..'\n'
        local f=fs.open(file,'w')
        local wrote=f and f:write(text)
        local closed=f and f:close()
        return f~=nil and wrote~=nil and wrote~=false and closed==true and readFile()==text
    end
    function self:setMinions(value)
        if value~='ON' and value~='OFF' then return {ok=false,message='随从处决小怪开关只接受 ON 或 OFF',spawned_count=0} end
        local wanted=value=='ON'
        local saved=save(self.on,wanted)
        if saved then self.minions=wanted end
        log('[CompanionExecution] 设置 处决小怪='..value..' 保存读回='..tostring(saved)..' 当前='..tostring(self.minions))
        return {ok=saved,spawned_count=0,message=saved and (wanted and '随从处决小怪已开启' or '随从处决小怪已关闭') or '随从处决小怪的设置没有保存'}
    end
    function self:set(value)
        if value~='ON' and value~='OFF' then return {ok=false,message='随从处决开关只接受 ON 或 OFF',spawned_count=0} end
        local wanted=value=='ON'
        local saved=save(wanted,self.minions)
        if saved then self.on=wanted end
        log('[CompanionExecution] 设置 开关='..value..' 保存读回='..tostring(saved)..' 当前='..tostring(self.on))
        return {ok=saved,spawned_count=0,message=saved and (wanted and '随从处决已开启' or '随从处决已关闭') or '随从处决设置没有保存'}
    end
    function self:status()return {on=self.on,minions=self.minions}end
    return self
end
return Setting
