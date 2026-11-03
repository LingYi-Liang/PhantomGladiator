local Audit=dofile('Mods/PhantomGladiator/Scripts/asset_reference_audit.lua')
local realOpen=io.open;local files={}
io.open=function(path)files[path]='';return {write=function(self,s)files[path]=files[path]..s;return self end,flush=function()return true end,close=function()return true end}end
local registry={IsValid=function()return true end,K2_GetReferencers=function(_,p,opts,out)
    assert(opts.bIncludeHardPackageReferences and opts.bIncludeSoftPackageReferences)
    if p=='/Game/Unit' then out[1]='/Game/__ExternalActors__/Maps/Test/Spawner';return true end
    return false
end}
StaticFindObject=function()return {IsValid=function()return true end,GetAssetRegistry=function()return registry end}end
FName=function(s)return s end;IsInGameThread=function()return true end
LoadAsset=function()error('must not load')end
local audit=Audit.new({path='D:/test-refs'});assert(audit:start({'/Game/Unit','/Game/Empty'}));audit:tick()
assert(audit:status().complete and audit:status().edges==1 and audit:status().empty==1)
assert(files['D:/test-refs/reference-queries.tsv']:find('empty_or_stripped',1,true))
assert(files['D:/test-refs/asset-references.tsv']:find('/Game/Unit\t/Game/__ExternalActors__/Maps/Test/Spawner',1,true))
io.open=realOpen
print('asset_reference_audit: PASS (readonly package edges, explicit empty/stripped boundary, no load)')
