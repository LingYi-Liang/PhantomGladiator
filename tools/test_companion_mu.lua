package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local U=require('ue_observe')
local P=require('companion_profile')
local Mu=require('companion_mu')
local serial=0
local function obj(path,cls,outer)
    serial=serial+1
    local o={path=path,cls=cls,parent=outer,key=serial}
    function o:IsValid()return true end
    function o:GetAddress()return self.key end
    function o:GetOuter()return self.parent end
    function o:GetClass()return self.cls end
    function o:GetFullName()return self.path end
    function o:GetFName()return {ToString=function()return self.path end}end
    return o
end
local C=obj('config');C.cls=C
local base=obj('Class /Script/ProjectPBZ.PBZCharacter_NPC',C)
local class=obj('BlueprintGeneratedClass '..P.second,C);function class:GetSuperStruct()return base end
local story=obj('AIScript_AddTagToEventPipelineManagerOnHealthPercentageChanged_C',C)
local default='AIConfig  Default';local root=P.second:match('(.*/)')
local preset=obj('PDA '..root..'ActorData/ActorC_MuXiaoKui_P2.ActorC_MuXiaoKui_P2',C)
local ai=obj('PDA '..root..'AIConfig/AIConfig_MuXiaoKui_P2.AIConfig_MuXiaoKui_P2',C)
local script=obj('subobject',story,ai)
ai.InstancedAIScripts={InstancedAIScripts={script}}
preset[default]=ai
local function pawn()local a=obj('actor',class);a['Actor Config']=preset;return a end
local lib=obj('library',C)
function lib:DuplicateObject(src,outer)
    local new=obj('private',C,outer)
    if src==preset then new[default]=ai else new.InstancedAIScripts={InstancedAIScripts={script}} end
    return new
end
local a,b=pawn(),pawn();assert(Mu.isolate(a,lib));assert(Mu.isolate(b,lib))
assert(a['Actor Config']~=b['Actor Config'] and a['Actor Config'][default]~=ai and a['Actor Config'][default]~=b['Actor Config'][default])
assert(preset[default]==ai and ai.InstancedAIScripts.InstancedAIScripts[1]==script)
local comp=obj('ai',C);comp.AIConfig=a['Actor Config'][default];assert(Mu.attached(a,comp));assert(not Mu.attached(b,comp))
local foreign=obj('unowned',C);foreign['Actor Config']=preset;assert(not Mu.isolate(foreign,lib) and foreign['Actor Config']==preset)
local x=pawn();lib.DuplicateObject=function(_,src)return src end;assert(not Mu.isolate(x,lib) and x['Actor Config']==preset)
ai.InstancedAIScripts.InstancedAIScripts[2]=script;assert(not Mu.isolate(x,lib) and #ai.InstancedAIScripts.InstancedAIScripts==2)
print('PASS Mu: private configuration, shared assets and two actors, unknown layouts and duplicate refusal')