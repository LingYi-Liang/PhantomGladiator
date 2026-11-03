package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Chain=require('execution_chain')
local function object(name,fields)
    fields=fields or {};fields.IsValid=function()return true end
    fields.GetFName=function()return {ToString=function()return name end}end
    return fields
end
local function extension(name,finished)
    local e=object(name,{bFinished=finished,Handle={valid=true}})
    function e:Deactivate()self.deactivated=true;self.Handle.valid=false end
    return e
end
local ended,live,unknown=extension('Ended',true),extension('PlayerActive',false),extension('Unknown',nil)
local world,cls=object('World'),object('UIExtensionSubsystem')
local subsystem=object('UI',{IsValidHandle=function(_,handle)return handle.valid end})
local lib=object('SubsystemLibrary',{GetWorldSubsystem=function(_,w,c)assert(w==world and c==cls);return subsystem end})
local scans,lines=0,{}
local guard=Chain.new({getWorld=function()return world end,staticFind=function(path)
        if path=='/Script/Engine.Default__SubsystemBlueprintLibrary' then return lib end
        assert(path=='/Script/UIExtension.UIExtensionSubsystem');return cls end,
    findAll=function(kind)scans=scans+1;return kind=='RegisterQTEExtensionObj' and {ended,live,unknown} or {} end,
    log=function(s)lines[#lines+1]=s end})
guard:auditExisting()
assert(ended.deactivated and ended.Handle.valid==false,'remove a finished extension whose UI is still registered')
assert(not live.deactivated and live.Handle.valid,'never touch an active player/other QTE')
assert(not unknown.deactivated and unknown.Handle.valid,'unreadable completion is not permission to remove UI')
guard:auditExisting();assert(scans==2,'one bounded startup sweep, no continuous global scanning')
assert(table.concat(lines,'\n'):find('UI句柄仍有效=false',1,true))
print('execution_chain ok: finished orphan cleanup, active/unknown isolation, single sweep, readback')
