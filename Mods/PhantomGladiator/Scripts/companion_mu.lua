local U=require('ue_observe')
local P=require('companion_profile')
local M={}
local root=P.second:match('(.*/)')
local actorConfig=root..'ActorData/ActorC_MuXiaoKui_P2.ActorC_MuXiaoKui_P2'
local aiConfig=root..'AIConfig/AIConfig_MuXiaoKui_P2.AIConfig_MuXiaoKui_P2'
local scriptClass='AIScript_AddTagToEventPipelineManagerOnHealthPercentageChanged_C'
local defaultSlot='AIConfig  Default'
local nightmareSlot='AIConfig Nightmare'
local function path(v)
    if not U.valid(v) then return end
    local ok,name=pcall(function()return v:GetFullName()end)
    return ok and type(name)=='string' and name:match(' (/.+)$') or nil
end
local function private(lib,source,outer)
    local copy=lib:DuplicateObject(source,outer)
    if not U.key(copy) or U.key(copy)==U.key(source) or U.key(copy:GetOuter())~=U.key(outer)
        or U.key(copy:GetClass())~=U.key(source:GetClass()) then return nil end
    return copy
end
local function scripts(config)
    local field=U.field(config,'InstancedAIScripts')
    local arr=U.struct(field,'InstancedAIScripts')
    return U.array(arr),arr,field
end
-- Only the single, audited instanced story script exists in this build. Any change to that layout
-- requires another audit. The native strategy, ability pool and default scripts are left in place.
function M.isolate(pawn,lib)
    if U.npcPath(pawn)~=P.second or not U.valid(lib) then return false,'铁玉女王的类或复制接口未确认' end
    local ok,done=pcall(function()
        local source=U.field(pawn,'Actor Config')
        local ai=U.field(source,defaultSlot)
        if path(source)~=actorConfig or path(ai)~=aiConfig then return false end
        local night,known=U.field(source,nightmareSlot)
        if not known or U.valid(night) and U.key(night)~=U.key(ai) then return false end
        local original=scripts(ai)
        if not original or #original~=1 or U.className(original[1])~=scriptClass then return false end
        local config=private(lib,source,pawn)
        local filtered=config and private(lib,ai,config)
        if not filtered then return false end
        local entries,arr,field=scripts(filtered)
        if not entries or #entries~=1 or U.className(entries[1])~=scriptClass then return false end
        if U.kind(arr)=='TArray' then arr:Empty() else field.InstancedAIScripts={} end
        local after=scripts(filtered);local unchanged=scripts(ai)
        if not after or #after~=0 or not unchanged or #unchanged~=1 or U.key(unchanged[1])~=U.key(original[1]) then return false end
        config[defaultSlot]=filtered
        if U.valid(night) then config[nightmareSlot]=filtered end
        if U.key(U.field(config,defaultSlot))~=U.key(filtered) or U.key(U.field(source,defaultSlot))~=U.key(ai) then return false end
        pawn['Actor Config']=config
        return U.key(U.field(pawn,'Actor Config'))==U.key(config)
    end)
    return ok and done==true,'未确认角色私有 AI 配置，已中止生成'
end
function M.attached(pawn,ai)
    local config=U.field(pawn,'Actor Config');local privateAI=U.field(config,defaultSlot)
    if not U.valid(config) or not U.valid(privateAI) or not U.valid(ai) then return false end
    local ok,result=pcall(function()
        local list=scripts(privateAI)
        return U.key(config:GetOuter())==U.key(pawn) and U.key(privateAI:GetOuter())==U.key(config)
            and U.key(U.field(ai,'AIConfig'))==U.key(privateAI) and list~=nil and #list==0
    end)
    return ok and result==true
end
return M