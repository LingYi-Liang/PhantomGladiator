-- Some of the game's moves write story progress. A GAA_FlowTag action (MagCombatAbilities/Actions/GAA_FlowTag) adds its
-- Tags to the EventPipelineManager when it begins, whoever plays the move and wherever. In the game files three abilities
-- have one: GA_Hun_BEx_MoYuan (魔渊's special finisher, the end of the fifth 龙柱 trial: lz.龙柱.战斗胜利5 at 0 s),
-- GA_ZuoShang_CA_GEx_01 (ddsd) and the player's GA_Hun_Tang_HorseCartCombat_SpecialDodge_Red.
-- The finishers this mod starts (arena_executions.lua) used 魔渊's: each one marked the fifth trial as won, so the trial's
-- ending ran as soon as the trial opened and not after the fight.
-- A finisher whose move writes story tags is allowed only when every one of them is already in the story, so playing it
-- changes nothing; otherwise the mod does without that finisher. The tags are read from the move's own GAA_FlowTag
-- objects, so no Chinese names are built from text. A move known to write tags whose actions cannot be read is refused.
--
-- Units that write story progress themselves are listed in Writes.UNITS (game files, every subclass included): their own
-- blueprint, the AI config their actor config names, or a move their behaviour tree plays. Summoned while one of those
-- marks is not in the story yet, such a unit writes it as if that part of the story had been played (a summoned 雷当
-- did that to 戏梦山庄). The mod summons one only when every mark it can write is in the story already.
local U=require('ue_observe')
local Writes={}
Writes.ACTION='GAA_FlowTag_C'
-- Abilities found with a GAA_FlowTag in the game files (class names).
Writes.KNOWN={GA_Hun_BEx_MoYuan_C=true,GA_ZuoShang_CA_GEx_01_C=true,GA_Hun_Tang_HorseCartCombat_SpecialDodge_Red_C=true}
local RIDER='/PBZCombatAsset/ActorData/Mobs/037_GuiChai/Blueprints/Rider/'
local CART=RIDER..'HorseCartCombat/'
local LEIDANG='/PBZCombatAsset/ActorData/Mobs/047_LeiDang/'
local NORMAL='/Game/RenewalContent/Actors/Mobs/Normal/'
local LENGTU='/PBZCombatAsset/ActorData/Mobs/077_LengTu/'
local function class(dir,name)return dir..name..'.'..name..'_C' end
-- The horse-cart gunners' moves 01/05 show the player a QTE whose success ability (GA_Hun_Tang_HorseCartCombat_SpecialDodge_
-- Blue/Red) writes these.
local GUN={tags={'rzgd.马车战.抵挡射击2','rzgd.马车战.抵挡射击3','rzgd.击败.两个枪鬼差'},how='玩家接住它开枪的 QTE 时'}
-- 雷当's phase-end move GA_LeiDang_CA (BT_LeiDang_SwitchPhase, in every 雷当 AI config) tells the player he is killed.
local LEI={tags={'qsd.击杀.雷当'},how='转阶段时'}
Writes.UNITS={
    [class(RIDER,'BP_Monster_GuiChai_Black_Gun_Rider')]=GUN,
    [class(CART,'BP_Monster_GuiChai_Black_Gun_Rider_HorseCartCombat_L')]=GUN,
    [class(CART,'BP_Monster_GuiChai_Black_Gun_Rider_HorseCartCombat_R')]=GUN,
    -- AIConfig_GuiChai_Black_TwinBlade_P3: AIScript_AddTagOnHealthPercentageAfterBeAttack at 20 %.
    [class(CART,'BP_Monster_GuiChai_Black_TwinBlade_HorseCartCombat')]={tags={'rzgd.击败.一个上车刀鬼差'},how='血量降到 20% 时'},
    -- Their own blueprints, when their death component fires.
    [class(CART,'BP_Monster_GuiChai_Black_TwinBlade_Rider_HorseCartCombat_L')]={tags={'rzgd.马车战.击杀追兵1'},how='死亡时'},
    [class(CART,'BP_Monster_GuiChai_Black_TwinBlade_Rider_HorseCartCombat_R')]={tags={'rzgd.马车战.击杀追兵2'},how='死亡时'},
    [class(LEIDANG,'BP_Monster_LeiDang')]=LEI,
    [class(LEIDANG,'BP_Monster_LeiDang_ForSeq')]=LEI,
    [class(LEIDANG,'BP_Monster_LeiDang_JYX')]=LEI,
    [class(LEIDANG,'BP_Monster_LeiDang_NPC')]=LEI,
    [class(NORMAL,'BP_Monster_LeiHuang')]=LEI,
    [class(NORMAL,'BP_Monster_LeiMing')]=LEI,
    -- AIConfig_HookMan_HorseCartCombat: AIScript_AddTagOnHealthPercentage at 50 %.
    [class('/PBZCombatAsset/ActorData/Mobs/048_HookMan/','BP_Monster_HookMan_HorseCartCombat')]={tags={'rzgd.击败.钩者'},how='血量降到 50% 时'},
    [class('/PBZCombatAsset/ActorData/Mobs/054_ZuoShang/','BP_Monster_ZuoShang')]={tags={'zlgw.雨夜左殇.死亡'},how='死亡时'},
    -- AIConfig_MuXiaoKui_P2: AIScript_AddTagToEventPipelineManagerOnHealthPercentageChanged at 25 %.
    [class('/PBZCombatAsset/ActorData/Mobs/064_MuXiaoKui_P2/','BP_Monster_MuXiaoKui_P2')]={tags={'ljc.沐小葵.血量降低到25'},how='血量降到 25% 时'},
    -- ActorC_MoTian_LongZhu_01: GA_MoYuan_Passive_LongZhu_01 calls BP_FlowUtils.AddFlowTags.
    [class('/PBZCombatAsset/ActorData/Mobs/067_MoTian/','BP_Monster_MoTian_LongZhu_01')]={tags={'lz.魔天1.台词结束'},how='开场台词说完时'},
    -- Her fifth round (GA_LengTu_SummonPassive_P5_LeiDang) calls in BP_Monster_LeiDang_NPC.
    [class(LENGTU,'BP_Monster_LengTu')]={tags=LEI.tags,how='第五阶段叫来的雷当转阶段时'},
    [class(LENGTU,'BP_Monster_LengTu_Preview')]={tags=LEI.tags,how='第五阶段叫来的雷当转阶段时'},
}
local RESCAN=10     -- seconds before a known move whose actions were not loaded is looked for again
local LINES=40

local function text(name)
    if type(name)=='string' then return name end
    local ok,value=pcall(function()return name:ToString()end)
    return ok and type(value)=='string' and value or nil
end
local function nameOf(object)
    if not U.valid(object) then return nil end
    local ok,value=pcall(function()return object:GetFName():ToString()end)
    return ok and type(value)=='string' and value or nil
end
local function fullName(object)
    local ok,value=pcall(function()return object:GetFullName()end)
    return ok and type(value)=='string' and value or ''
end
-- An action of this move: its outer chain names the move's package (the class's own timeline,
-- <package>/GA_X.GA_X_C:ExecutionTimeline.GAA_FlowTag_C_0) or an instance of the move (….GA_X_C_0.….GAA_FlowTag_C_0).
local function belongs(full,className)
    local base=className:gsub('_C$','')
    return full:find('/'..base..'.',1,true)~=nil or full:find('.'..className..'_',1,true)~=nil
end

function Writes.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local findAll=options.findAll or function(name)return FindAllOf(name)end
    local self={allowed=0,refused=0}
    local lines,said=0,{}
    local found={}      -- class name -> {tags={{name,text}}} once its actions were read; {tags={}} when it has none
    local missedAt={}   -- class name -> when its actions were last looked for and not found
    local function say(key,message)
        if said[key]==message or lines>=LINES then return end
        said[key]=message;lines=lines+1;log('[StoryWrites] '..message)
    end
    -- The tags a move's GAA_FlowTag actions write, each text once.
    local function tagsOf(className)
        if found[className] then return found[className].tags end
        if missedAt[className] and clock()-missedAt[className]<RESCAN then return nil,'它写剧情的动作没加载' end
        local ok,list=pcall(findAll,Writes.ACTION)
        local tags,seen,actions={},{},0
        for _,action in ipairs(ok and type(list)=='table' and list or {})do
            if U.valid(action) and belongs(fullName(action),className) then
                actions=actions+1
                for _,tag in ipairs(U.array(U.struct(U.field(action,'Tags'),'GameplayTags')) or {})do
                    local name=U.struct(tag,'TagName');local t=text(name)
                    if name~=nil and t and t~='None' and not seen[t] then seen[t]=true;tags[#tags+1]={name=name,text=t} end
                end
            end
        end
        if actions==0 then
            if Writes.KNOWN[className] then missedAt[className]=clock();return nil,'它写剧情的动作没加载' end
            found[className]={tags={}}
            return found[className].tags
        end
        found[className]={tags=tags}
        return tags
    end
    -- Whether a finisher with this move (the ability class) may be started by the mod; false with the reason.
    function self:allows(ability)
        local className=nameOf(ability)
        if not className then self.refused=self.refused+1;return false,'读不到招式的类' end
        local tags,why=tagsOf(className)
        if tags==nil then
            self.refused=self.refused+1
            say(className,className..'：'..why..'，这个处决会给剧情加标记，先不用它')
            return false,why
        end
        if #tags==0 then self.allowed=self.allowed+1;return true end
        local pipeline=options.pipeline and options.pipeline()
        if not U.valid(pipeline) then
            self.refused=self.refused+1
            say(className,className..'：读不到剧情系统，这个处决会给剧情加标记，先不用它')
            return false,'读不到剧情系统'
        end
        local missing,present={},{}
        for _,tag in ipairs(tags)do
            local ok,has=pcall(function()return pipeline:HasTagWithOutSource({TagName=tag.name})end)
            has=ok and U.unwrap(has)
            if has==true then present[#present+1]=tag.text
            else missing[#missing+1]=tag.text..((ok and type(has)=='boolean') and '' or '（读不到）') end
        end
        if #missing>0 then
            self.refused=self.refused+1
            local reason='会给剧情加 ['..table.concat(missing,',')..']，剧情里还没有'
            say(className,className..' '..reason..'：模组的处决不用它（卡在锁血线时照常按倒下收尾）')
            return false,reason
        end
        self.allowed=self.allowed+1
        say(className,className..' 写的剧情标记 ['..table.concat(present,',')..'] 剧情里已有，用它处决不改变剧情')
        return true
    end
    -- A story mark by its text: the name is used only when it reads back as the same text.
    local names={}
    local function nameFor(t)
        if names[t]==nil then
            local ok,name=pcall(options.fname or function(value)return FName(value)end,t)
            names[t]=ok and name~=nil and text(name)==t and name or false
        end
        return names[t] or nil
    end
    -- Whether the story holds this mark: true, false, or nil when it cannot be told.
    function self:has(t)
        local pipeline=options.pipeline and options.pipeline()
        local name=nameFor(t)
        if not U.valid(pipeline) or name==nil then return nil end
        local ok,value=pcall(function()return pipeline:HasTagWithOutSource({TagName=name})end)
        if ok then value=U.unwrap(value) else value=nil end
        if type(value)=='boolean' then return value end
        return nil
    end
    -- Whether the mod may summon a unit of this class (its full class path); false with the reason.
    function self:allowsUnit(path)
        local unit=type(path)=='string' and Writes.UNITS[path]
        if not unit then return true end
        local short=path:match('%.([^%.]+)$') or path
        local missing,unread={},false
        for _,t in ipairs(unit.tags)do
            local has=self:has(t)
            if has~=true then missing[#missing+1]=t;unread=unread or has==nil end
        end
        if #missing==0 then
            self.unitsAllowed=(self.unitsAllowed or 0)+1
            say('unit:'..short,short..' 会写的剧情标记 ['..table.concat(unit.tags,',')..'] 剧情里都有，召唤它不改变剧情')
            return true
        end
        self.unitsRefused=(self.unitsRefused or 0)+1
        local why=unread and '读不到剧情里有没有 ['..table.concat(missing,',')..']，这个单位'..unit.how..'会写它，先不召唤'
            or '这个单位'..unit.how..'会写剧情 ['..table.concat(missing,',')..']，存档里还没有：剧情打过这段之前不召唤它，免得坏档'
        say('unit:'..short,short..'：'..why)
        return false,why
    end
    function self:status()return {allowed=self.allowed,refused=self.refused,units_allowed=self.unitsAllowed or 0,units_refused=self.unitsRefused or 0}end
    return self
end
return Writes
