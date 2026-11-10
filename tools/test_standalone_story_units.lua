package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Standalone=require('standalone_story_units')
local Session=require('battle_session')
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
    h.classes={[MENGHUA]=h.dreamClass}
    h.session=Session.new()
    h.null.valid=false
    h.statics=object('GameplayStatics')
    function h.statics:GetActorOfClass(context,class)
        local answer=h.hook and h.hook(remote(self),remote(context),remote(class))
        if h.override and answer~=nil then return answer end
        return h.dream
    end
    h.module=Standalone.new({log=function(line)h.lines[#h.lines+1]=line end,statics=function()return h.statics end,
        staticFind=function(path)return h.classes[path]end,
        fname=function(name)return name end,
        boardOf=function(actor)return actor.board end,
        remember=function(key,restore)return h.session:remember(key,restore)end,
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
    local name='BP_Monster_FengXueDaoKe_NPC'
    local path='/PBZCombatAsset/ActorData/Mobs/FengXueDaoKe/'..name..'.'..name..'_C'
    local manual=object(name..'_C /Test/World.Manual')
    local class=object('BlueprintGeneratedClass '..path)
    function class:GetSuperStruct()return npc end
    function manual:GetClass()return class end
    local yuding='/PBZCombatAsset/ActorData/Mobs/YuDing_00/BP_Monster_FemaleVessel_YuDing_LengTu.BP_Monster_FemaleVessel_YuDing_LengTu_C'
    local yubi='/PBZCombatAsset/ActorData/Mobs/YuBi/BP_Monster_YuBi_LengTu.BP_Monster_YuBi_LengTu_C'
    h.classes[yuding]=object('BlueprintGeneratedClass '..yuding)
    h.classes[yubi]=object('BlueprintGeneratedClass '..yubi)
    local entry=assert(h.module:prepare(manual))
    assert(h.module:matches(manual:GetFullName()))
    assert(entry.lookups==0,'preflight cannot count as the native callback')
    local finishAccepted=h.module:verify(entry)
    local logBefore=table.concat(h.lines,'\n')
    assert(not logBefore:find('延迟剧情查找回调读回',1,true))

    -- Cooked BeginPlay resumes on the next tick after FinishSpawn has returned.
    assert(h.statics:GetActorOfClass(manual,h.classes[yuding])==h.null)
    assert(h.statics:GetActorOfClass(manual,h.classes[yubi])==h.null)
    assert(h.statics:GetActorOfClass(manual,h.dreamClass)==h.dream)
    assert(entry.lookups==2)
    assert(finishAccepted,'verified preflight must let a delayed story aid reach activation')

    local logAfter=table.concat(h.lines,'\n')
    assert(logBefore:find('原生剧情查找待读回',1,true))
    assert(logAfter:find('延迟剧情查找回调读回',1,true))
    assert(logAfter:find('搭档='..yuding..' 回传空Actor',1,true))
    assert(logAfter:find('搭档='..yubi..' 回传空Actor',1,true))
    assert(h.statics:GetActorOfClass(manual,h.classes[yuding])==h.null)
    assert(table.concat(h.lines,'\n')==logAfter,'later matching lookups stay guarded without repeating the diagnostic')
    print('PASS FengXueDaoKe activates before the next tick and isolates both of its original partner branches')
end

do
    local h=fixture()
    local guichai='/PBZCombatAsset/ActorData/Mobs/060_GuiChai_Yellow/'
        ..'BP_Monster_GuiChai_Yellow_MoDao_LengTu.BP_Monster_GuiChai_Yellow_MoDao_LengTu_C'
    local partner=object('BlueprintGeneratedClass '..guichai)
    h.classes[guichai]=partner
    for _,relative in ipairs({'034_EMei/BP_Monster_EMei_Sword_NPC','035_HuaShan/BP_Monster_HuaShan_Blue_NPC'}) do
        local name=relative:match('[^/]+$')
        local path='/PBZCombatAsset/ActorData/Mobs/'..relative..'.'..name..'_C'
        local class=object('BlueprintGeneratedClass '..path)
        function class:GetSuperStruct()return npc end
        local manual=object(name..'_C /Test/World.Manual')
        function manual:GetClass()return class end
        local entry=assert(h.module:prepare(manual))
        assert(entry.lookups==0 and h.module:verify(entry),name..' can activate before its delayed native lookup')
        assert(h.statics:GetActorOfClass(manual,partner)==h.null and entry.lookups==1)
    end
    print('PASS EMei and HuaShan story aids retain verified partner guards while completing synchronous spawn')
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

do
    local h=fixture()
    local bardPath='/PBZCombatAsset/ActorData/Mobs/071_XianZhe/BP_Monster_XianZhe.BP_Monster_XianZhe_C'
    local chilian='/PBZCombatAsset/ActorData/Mobs/065_ChiLian_P2/BP_Monster_ChiLian_P2.BP_Monster_ChiLian_P2_C'
    local bardClass=object('BlueprintGeneratedClass '..bardPath)
    function bardClass:GetSuperStruct()return npc end
    h.classes[chilian]=object('BlueprintGeneratedClass '..chilian)

    local mutations=0
    local function state(actor)
        local faction=object('Faction Component')
        actor['Faction Component']=faction
        actor.faction='Faction.Player'
        actor.hatredBlock=1
        function faction:GetCurrnetFaction()return {TagName=actor.faction}end
        function faction:SetFaction(tag)mutations=mutations+1;actor.faction=tag.TagName end
        actor.AbilitySystemComponent=object('ASC')
        function actor.AbilitySystemComponent:GetGameplayTagCount(tag)
            assert(tag.TagName=='AI.Hatred.CanNotBeHatred')
            return actor.hatredBlock
        end
        actor.board=object('Blackboard')
        return actor
    end

    local abilityUtils=object('AbilityUtils')
    function abilityUtils:SetLooseGameplayTagCount(actor,tag,count)
        assert(tag.TagName=='AI.Hatred.CanNotBeHatred')
        mutations=mutations+1
        actor.hatredBlock=count
    end
    local aiLib=object('SGameAIFunctionLibrary')
    function aiLib:GetValueAsObjectByTag(board,tag)
        assert(tag.TagName=='AI.BlackboardKey.Object.AssignActor1')
        return board.assigned
    end
    function aiLib:SetValueAsObjectByTag(board,tag,target)
        assert(tag.TagName=='AI.BlackboardKey.Object.AssignActor1')
        mutations=mutations+1
        board.assigned=target
    end
    h.classes['/Script/SGameUtils.Default__AbilityUtils']=abilityUtils
    h.classes['/Script/SGameAI.Default__SGameAIFunctionLibrary']=aiLib

    local blue,native=state(xu('Blue')),state(xu('Story'))
    local red=state(object('BP_Monster_XianZhe_C /Test/World.Red'))
    function red:GetClass()return bardClass end
    local original=object('Original target')
    blue.board.assigned=original
    assert(h.module:prepare(blue) and h.module:prepare(red))
    assert(h.module:isTeamActor(blue) and h.module:isTeamActor(red))
    assert(h.module:teamBossName(blue)=='虚空' and h.module:teamBossName(red)=='弦者')
    assert(not h.module:isTeamActor(native) and h.module:teamBossName(native)==nil)
    assert(not h.module:prepareTeamActor(native) and h.module:assignOpponent(native,red) and mutations==0)
    assert(h.module:prepareTeamActor(blue) and h.module:prepareTeamActor(red))
    assert(blue.faction=='Faction.Enemy' and red.faction=='Faction.Enemy')
    assert(blue.hatredBlock==0 and red.hatredBlock==0)
    assert(h.module:assignOpponent(blue,red) and h.module:assignOpponent(red,blue))
    assert(blue.board.assigned==red and red.board.assigned==blue)
    local before=mutations
    assert(h.module:assignOpponent(blue,red) and mutations==before,'unchanged target must not be rewritten')
    assert(h.module:assignOpponent(blue,nil) and blue.board.assigned==h.null)
    assert(h.session:reset())
    assert(blue.faction=='Faction.Player' and red.faction=='Faction.Player')
    assert(blue.hatredBlock==1 and red.hatredBlock==1)
    assert(blue.board.assigned==original and red.board.assigned==h.null)
    assert(native.faction=='Faction.Player' and native.hatredBlock==1 and native.board.assigned==nil)
    print('PASS direct XuKong and XianZhe use the arena target, with faction, hatred and target restored on reset')
end
