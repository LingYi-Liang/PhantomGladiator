package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Report=require('match_report')
local serial=0
local function object(extra)
    local o=extra or {}
    serial=serial+1
    local id=serial
    function o:IsValid()return not self.dead end
    function o:GetAddress()return id end
    return o
end
local function fname(value)return { ToString=function()return value end } end
local function rows(entries)
    return {ForEach=function(_,callback)for _,row in ipairs(entries)do callback(row[1],row[2]) end end}
end

local reads,levelSamples=0,0
local gameConfig=object({GetFName=function()return fname('GlobalConfig_Combat_Normal')end,
    ['Global Mob Attribute Modifiers']=rows({{{AttributeName='Attack'},{Type=0,Value=3}}}),
    ['Difficulty Settings By Mob Type']=rows({{{TagName='CharacterType.Difficulty.Standard'},
        {AttributeModifiers=rows({{{AttributeName='Attack'},{Type=1,Value=2}}})}}})})
local actorConfig=object({['Difficulty Tag']={TagName='CharacterType.Difficulty.Standard'},
    ['Attribute Data']={Attack=object({GetValue=function(_,level)levelSamples=levelSamples+1;return level*8 end})}})
local npc=object({GetFullName=function()return 'Class /Script/ProjectPBZ.PBZCharacter_NPC'end})
local function actor(path)
    return object({Level=50,['Actor Config']=actorConfig,
        GetClass=function()return object({GetFullName=function()return 'BlueprintGeneratedClass '..path end,
            GetSuperStruct=function()return npc end})end,
        GetCombatLevel=function()return 8 end,
        GetGlobalCombatConfig=function()return gameConfig end,
        K2_GetActorLocation=function()return {X=2,Y=5,Z=9}end})
end
local bluePath='/Game/Blue.Blue_C'
local redPath='/Game/Red.Red_C'
local blue,red=actor(bluePath),actor(redPath)
local attributes={}
function attributes:readMany(unit,fields)
    assert(unit and #fields==18)
    reads=reads+1
    return {Attack={base=134,current=138},Attack_Lv1={base=30,current=30},ShachiAttack_Lv1={base=20,current=20},
        Health_Max={base=1000,current=1200},Health_Max_Lv1={base=200,current=200},Shachi_Max={base=350,current=400},Resistance_ImpactShachi={base=0.75,current=0.5}}
end
local writes={}
local report=Report.new({path='test',build='fixture',attributes=attributes,
    context=function()return {map='红"庄\n',saveCycle=2,levelMode='HOME',statsMode='custom',defaultDifficulty='Normal'}end,
    stamp=function()return '2026-11-26T10:45:00Z'end,
    difficultyOf=function(unit)return unit==red and 'Hard' or nil end,
    storyLinkOf=function(unit)return unit==blue and 'skip' or 'unreadable' end,
    write=function(path,data)assert(path=='test/match-report.json');writes[#writes+1]=data;return true end})
report:rememberLevel(blue,{levelSource='native',requestedLevel=70,preparedLevel=70,levelBase=20,
    cycle=2,cycleExempt=false,cycleBonus=50,levelWriteVerified=true})
report:rememberLevel(red,{levelSource='custom',requestedLevel=15,preparedLevel=50,levelWriteVerified=false})
report:rememberStats(blue,'custom')
assert(report:capture({{actor=blue,team='blue',slot=1,class_path=bluePath,formation=false},
    {actor=red,team='red',slot=2,class_path=redPath,escort=true}}, {enabled=true,blue=2,red=1}))
assert(reads==2 and #writes==1 and levelSamples==1,'count each opening actor once and share identical native curve reads')
local first=writes[1]
for _,token in ipairs({
        '"schema":1','"saveNg":3','"ng":3','"levelBase":20','"formation":false','"escort":true','"spawnDifficulty":"Hard"',
        '"difficulty":"Normal"','"spawnLevel":50','"combatLevel":8','"requestedLevel":70','"levelWriteVerified":false',
        '"map":"红\\"庄\\u000a"','"Attack":{"base":134,"current":138}','"Attack":{"adjusted":134,"level":8,"mods"',
        '"npcPhysicalBase":180','"npcShachiBase":120','"npcPhysicalBase":"target.Health_Max.current',
        '"Resistance_ImpactShachi":{"base":0.75,"current":0.5}',
    })do assert(first:find(token,1,true),token) end
local _,links=first:gsub('"storyLink":','')
assert(links==1 and first:find('"storyLink":"skip"',1,true))
local _,cycles=first:gsub('"ng":','')
assert(cycles==1,'custom/failure must not inherit the save cycle as a per-unit fact')
assert(not first:find('"Shachi_Min"',1,true),'unreadable fields stay absent')
assert(math.abs(tonumber(first:match('"npcShachiRatio":([%d.]+)'))-.3)<1e-10,'display the current target Sha-Chi bar proportion')
assert(report:finish({seconds=20,winner='blue',blueAlive=1,redAlive=0,reason='completed'}))
assert(not report:finish({winner='red'}) and #writes==2 and reads==2)
assert(writes[2]:find('"result":{"blueAlive":1,"reason":"completed","redAlive":0,"seconds":20,"winner":"blue"}',1,true))
local many={}
for i=1,90 do
    many[i]={actor=blue,team='blue',slot=i,class_path=bluePath}
end
many[#many+1]={actor=red,team='red',slot=1,class_path=redPath}
assert(report:capture(many))
assert(writes[3]:find('"counts":{"blue":90,"red":1}',1,true) and writes[3]:find('"truncated":true',1,true),
    'the bound for a crowded side must still represent the other side and preserve total counts')
assert(reads==67 and levelSamples==2)
print('match_report: PASS (opening/readback, numeric provenance, ratio example, per-side caps, result-only save)')
