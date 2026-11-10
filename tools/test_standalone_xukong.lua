package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Standalone=require('standalone_xukong')
local XUKONG='/PBZCombatAsset/ActorData/Mobs/079_XuKong/BP_Monster_XuKong.BP_Monster_XuKong_C'
local MENGHUA='/PBZCombatAsset/ActorData/Mobs/078_MengHua/BP_Monster_MengHua.BP_Monster_MengHua_C'
local address=0
local function object(name)
    address=address+1
    local o={address=address,valid=true}
    function o:IsValid()return self.valid end
    function o:GetFullName()return name end
    function o:GetAddress()return self.address end
    return o
end
local npc=object('Class /Script/ProjectPBZ.PBZCharacter_NPC')
local xuClass=object('BlueprintGeneratedClass '..XUKONG)
function xuClass:GetSuperStruct()return npc end
local function xu(name)
    local a=object('BP_Monster_XuKong_C /Test/World.'..name)
    function a:GetClass()return xuClass end
    return a
end
local function remote(value)
    return {type=function()return 'RemoteUnrealParam' end,get=function()return value end}
end

local function fixture()
    local h={dream=object('Dream'),dreamClass=object('BlueprintGeneratedClass '..MENGHUA),
        null=object('Null'),lines={},inGame=true,override=true,registrations=0}
    h.null.valid=false
    h.statics=object('GameplayStatics')
    function h.statics:GetActorOfClass(context,class)
        local answer=h.hook and h.hook(remote(self),remote(context),remote(class))
        if h.override and answer~=nil then return answer end
        return h.dream
    end
    h.module=Standalone.new({log=function(line)h.lines[#h.lines+1]=line end,statics=function()return h.statics end,
        staticFind=function(path)assert(path==MENGHUA);return h.dreamClass end,
        createInvalidObject=function()return h.null end,inGameThread=function()return h.inGame end,
        registerHook=function(path,callback)
            assert(path=='/Script/Engine.GameplayStatics:GetActorOfClass')
            h.hook=callback;h.registrations=h.registrations+1;return 1,2
        end})
    return h
end

do
    local h=fixture()
    local manual,native=xu('Manual'),xu('Story')
    local entry=assert(h.module:prepare(manual))
    assert(h.registrations==1 and entry.lookups==0)
    assert(h.statics:GetActorOfClass(native,h.dreamClass)==h.dream,'the original story helper is untouched')
    assert(h.statics:GetActorOfClass(manual,xuClass)==h.dream,'another class lookup is untouched')
    assert(h.statics:GetActorOfClass(manual,h.dreamClass)==h.null,'manual BeginPlay cannot claim MengHua')
    assert(h.module:verify(entry))
    assert(h.statics:GetActorOfClass(manual,h.dreamClass)==h.null,'manual OnDead cannot clear the story tags')
    h.module:prune({{actor=manual,class_path=XUKONG}})
    assert(h.statics:GetActorOfClass(manual,h.dreamClass)==h.null)
    local replacement=xu('Replacement')
    replacement.address=manual.address
    assert(h.statics:GetActorOfClass(replacement,h.dreamClass)==h.dream,'address reuse must not inherit the split')
    h.module:prune({})
    assert(h.statics:GetActorOfClass(manual,h.dreamClass)==h.dream)
    print('PASS direct XuKong skips the specific partner lookup in BeginPlay and OnDead, story lookups still resolve')
end

do
    local h=fixture()
    local manual=xu('Unconfirmed')
    h.override=false
    local entry,why=h.module:prepare(manual)
    assert(not entry and why:find('读回未确认',1,true),'native return-slot readback is required')
    h.override=true
    assert(h.statics:GetActorOfClass(manual,h.dreamClass)==h.dream,'failed preflight must forget the actor')
    h.inGame=false
    assert(not h.module:prepare(manual),'a callback outside the game thread must not change a return value')
    h.inGame=true
    entry=assert(h.module:prepare(manual))
    assert(not h.module:verify(entry),'hook registration alone is not evidence of a BeginPlay callback')
    h.module:silence()
    assert(h.statics:GetActorOfClass(manual,h.dreamClass)==h.dream)
    print('PASS fail closed on missing readback and silence on unload')
end
