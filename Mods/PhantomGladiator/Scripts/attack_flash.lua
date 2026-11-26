-- Spectate preferences for the four original red and blue alert systems used by the shared cue.
local U=require('ue_observe')
local Files=require('companion_profile')
local Flash={}
local HEADER='AttackFlashV1'
local SYSTEMS={
    NS_AttackAlert_Red_001='red',
    NS_AttackAlert_Red_004='red',
    NS_AttackAlert_Blue_001='blue',
    NS_AttackAlert_Blue_002='blue',
}
local DIRECTORY='/PBZVFXPack/VFX/BattleFX/Common/'

function Flash.new(options)
    local path=options.path..'/attack-flash.tsv'
    local read,write=options.read or Files.read,options.write or Files.write
    local function load(file)
        local saved=read(file,40)
        if type(saved)~='string' then return end
        local red,blue=saved:match('^'..HEADER..'\t([01])\t([01])\n$')
        if red then return {red=red=='1',blue=blue=='1'} end
    end
    local enabled=load(path) or load(path..'.bak') or {red=false,blue=false}
    local self={}

    function self:set(color,token)
        if enabled[color]==nil or (token~='ON' and token~='OFF') then
            return {ok=false,message='预警颜色或开关无效'}
        end
        local wanted={red=enabled.red,blue=enabled.blue}
        wanted[color]=token=='ON'
        local data=HEADER..'\t'..(wanted.red and '1' or '0')..'\t'..(wanted.blue and '1' or '0')..'\n'
        if not write(path,data) then return {ok=false,message='未能保存招式预警设置'} end
        enabled=wanted
        if options.log then
            options.log('[AttackFlash] 保存预警设置，读回红光='..tostring(enabled.red)..' 蓝光='..tostring(enabled.blue))
        end
        return {ok=true,message='招式预警设置已保存'}
    end

    function self:status()
        return {red=enabled.red,blue=enabled.blue}
    end

    function self:colorFor(action)
        if not enabled.red and not enabled.blue then return end
        local asset=U.field(action,'NiagaraEffect')
        if not U.valid(asset) then return end
        local ok,full=pcall(function()return asset:GetFullName()end)
        if not ok or type(full)~='string' then return end
        local path=full:match('^NiagaraSystem (.+)$')
        local name=path and path:match('/([^/.]+)%.[^/.]+$')
        local color=SYSTEMS[name]
        if color and enabled[color] and path==DIRECTORY..name..'.'..name then return color end
    end
    return self
end

return Flash
