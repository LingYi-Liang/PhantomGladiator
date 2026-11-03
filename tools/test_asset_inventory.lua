local Inventory=dofile('Mods/PhantomGladiator/Scripts/asset_inventory.lua')
local realOpen=io.open
local files={}
io.open=function(path,mode)
    assert(mode=='w');local lines={};files[path]=lines
    return {write=function(self,s) lines[#lines+1]=s;return self end,flush=function() return true end,close=function() return true end}
end
local function obj(data) data.IsValid=function() return true end;return data end
FName=function(s) return s end
IsInGameThread=function() return true end
LoadAsset=function() error('inventory must never load') end
local data={['/']={},['/Game/Many']={},['/Game/Units']={}}
for i=1,10005 do data['/Game/Many'][i]={PackageName='/Game/Many/T'..i,PackagePath='/Game/Many',AssetName='T'..i,AssetClassPath={PackageName='/Script/Engine',AssetName='Texture2D'}} end
data['/Game/Units'][1]={PackageName='/Game/Units/UnexpectedName',PackagePath='/Game/Units',AssetName='UnexpectedName',AssetClassPath={PackageName='/Script/Engine',AssetName='Blueprint'},
    tags={GeneratedClass="BlueprintGeneratedClass'/Game/Units/UnexpectedName.UnexpectedName_C'",NativeParentClass="Class'/Script/ProjectPBZ.PBZCharacter_NPC'"}}
local count=10006
local registry=obj({GetAllAssets=function(_,out) for i=1,count do out[i]=true end;return true end,
    GetAllCachedPaths=function(_,out) out[1]='/';out[2]='/Game/Many';out[3]='/Game/Units' end,
    GetAssetsByPath=function(_,p,out,recursive,disk) assert(recursive==false and disk==true);for i,v in ipairs(data[p]) do out[i]=v end;return #out>0 end,
    HasAssets=function(_,p) return #data[p]>0 end,IsLoadingAssets=function() return false end})
local helper=obj({GetAssetRegistry=function() return registry end,
    GetTagValue=function(_,row,k,out) local v=row.tags and row.tags[k];out.OutTagValue=v;return v~=nil end})
StaticFindObject=function(p) assert(p=='/Script/AssetRegistry.Default__AssetRegistryHelpers');return helper end
local function run()
    local e=Inventory.new({path='D:/test-inventory',config={PathsPerTick=32}});assert(e:start())
    for _=1,20 do e:tick();if not e:status().active then return e end end
    error('inventory did not finish')
end
local e=run();local s=e:status()
assert(s.complete and s.assets_seen==10006 and s.expected_assets==10006 and s.final_asset_count==10006)
assert(s.large_paths==1 and s.empty_paths==1 and s.query_errors==0 and s.candidates==1)
assert(s.coverage=='CURRENT_MOUNTED_REGISTRY_VERIFIED')
assert(table.concat(files['D:/test-inventory/asset-index-status.tsv']):find('loading_start\tfalse\n',1,true),'false readbacks must not disappear from the manifest')
local output=table.concat(files['D:/test-inventory/asset-index.tsv'])
assert(output:find('/Game/Many/T10005.T10005',1,true),'must preserve rows beyond old 10000 cap')
assert(output:find('/Game/Units/UnexpectedName.UnexpectedName',1,true),'no name heuristic can omit an asset')
assert(e:referencePackages()[1]=='/Game/Units/UnexpectedName')
for line in output:gmatch('([^\n]+)\n') do local _,tabs=line:gsub('\t','');assert(tabs==8) end
count=10007;e=run();assert(not e:status().complete,'independent count mismatch must stay partial')
count=10006;registry.HasAssets=function() return true end;e=run()
assert(e:status().query_errors==1 and not e:status().complete,'false return with claimed assets is not an empty directory')
io.open=realOpen
print('asset_inventory: PASS (10005-row directory, complete raw index, empty-folder readback, independent count mismatch, exact columns, no loading)')
