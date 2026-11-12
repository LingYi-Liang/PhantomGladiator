-- 随从处决 BOSS: the app switch (set_companion_executions). On, a boss a companion is after can be executed by that
-- companion (arena_executions.lua); off, as in the game, only the player executes it. Off by default; saved in
-- Runtime/companion-executions.tsv.
local Setting={}
local HEADER='CompanionExecutionsV1'
function Setting.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local file=options.path..'/companion-executions.tsv'
    local self={on=false}
    local function readFile()
        local f=fs.open(file,'r');if not f then return nil end
        local value=f:read('*a');f:close();return value
    end
    do
        local saved=readFile()
        if type(saved)=='string' and saved:sub(1,#HEADER+1)==HEADER..'\t' then self.on=saved:find('\ton=1',1,true)~=nil end
    end
    function self:set(value)
        if value~='ON' and value~='OFF' then return {ok=false,message='随从处决开关只接受 ON 或 OFF',spawned_count=0} end
        local wanted=value=='ON'
        local text=HEADER..'\ton='..(wanted and '1' or '0')..'\n'
        local f=fs.open(file,'w')
        local wrote=f and f:write(text)
        local closed=f and f:close()
        local saved=f~=nil and wrote~=nil and wrote~=false and closed==true and readFile()==text
        if saved then self.on=wanted end
        log('[CompanionExecution] 设置 开关='..value..' 保存读回='..tostring(saved)..' 当前='..tostring(self.on))
        return {ok=saved,spawned_count=0,message=saved and (wanted and '随从处决已开启' or '随从处决已关闭') or '随从处决设置没有保存'}
    end
    function self:status()return {on=self.on}end
    return self
end
return Setting
