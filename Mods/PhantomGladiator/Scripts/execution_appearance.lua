-- Opt-in legacy visual behavior for the NPC execution pose driver.
local Files=require('companion_profile')
local Appearance={}
local HEADER='ExecutionAppearanceV1\t'

function Appearance.new(options)
    local path=options.path..'/execution-appearance.tsv'
    local read,write=options.read or Files.read,options.write or Files.write
    local function saved(file)
        local raw=read(file,40)
        if raw==HEADER..'1\n' then return true end
        if raw==HEADER..'0\n' then return false end
    end
    local on=saved(path)
    if on==nil then on=saved(path..'.bak') end
    local self={on=on==true}

    function self:set(value)
        if value~='ON' and value~='OFF' then return {ok=false,message='处决外观选项无效'} end
        local wanted=value=='ON'
        if self.on~=wanted and not write(path,HEADER..(wanted and '1' or '0')..'\n') then
            return {ok=false,message='处决外观设置未保存'}
        end
        self.on=wanted
        return {ok=true,message=wanted and '已开启旧版处决外观' or '已恢复默认处决外观'}
    end
    return self
end

return Appearance
