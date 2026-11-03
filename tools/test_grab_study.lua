package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Study=require('grab_study')
local path=assert(arg[1],'isolated existing test directory required')
local ready=false
local calls,loads,cdos,enumerations=0,0,0,0
local objects={}
local function object(name,kind)
    local o={}
    function o:IsValid()return true end
    function o:GetFullName()return kind..' '..name end
    function o:GetAddress()return 100+loads end
    function o:IsAnyClass()return kind=='BlueprintGeneratedClass' end
    function o:GetCDO()
        assert(kind=='BlueprintGeneratedClass','non-class object used as UClass');cdos=cdos+1
        return object(name..'.Default','Object')
    end
    function o:ForEachProperty()end
    return o
end
StaticFindObject=function(name)calls=calls+1;return objects[name]end
LoadAsset=function(name)
    loads=loads+1
    -- Exercise a valid UObject returned where a generated class was expected.
    local kind=loads==1 and 'Blueprint' or 'BlueprintGeneratedClass'
    objects[name]=object(name,kind);return objects[name]
end
FindAllOf=function(name)assert(name=='BP_BulletEvent_Grab_C');enumerations=enumerations+1;return {}end
local logs={}
local study=Study.new({path=path,ready=function()return ready end,log=function(s)logs[#logs+1]=s end})
study:tick();assert(calls==0 and loads==0,'no engine access while the world is unavailable')
ready=true
study:tick();assert(loads==1 and cdos==0,'wrong class must not be queried as a UClass')
study:tick();assert(loads==2 and cdos==1)
study:tick();assert(loads==3 and cdos==2)
study:tick();assert(study.done and enumerations==1)
local lastCalls=calls;study:tick();assert(calls==lastCalls and loads==3)
local f=assert(io.open(path..'/grab-study.tsv','r'));local report=f:read('*a');f:close()
assert(report:find('class_unverified',1,true) and report:find('npc_receiver',1,true))
assert(table.concat(logs,'\n'):find('未触发投技',1,true))
print('grab_study: PASS (ready gate, strict returned class identity, bounded reads, no activation)')
