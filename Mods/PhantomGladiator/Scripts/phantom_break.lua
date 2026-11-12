-- 虚化. These units take no physical, Shachi, fire or lightning damage (GA_*_Passive.ModifyHitDamage on
-- GameplayEvent.Damage.Pretake) unless the hit is chaos, or they carry GE_Chaos or Stand.Break, or it comes from the player's
-- perfect dodge or their own orb deflected by the player (TrueDamage). No NPC does any of that, so in a fight between units
-- nobody could hurt them and the fight could not end. 玉簪's GA_YuZan_DeflectOrb_Passive is 烟千岁's check for physical and
-- Shachi damage (the same TrueDamage tag, its counter made from the player's weapon on the player's deflect): once her
-- posture is back, no NPC can hurt her or break it again.
-- A unit of blue, red or the companions has it taken away once it is out, unless its card says keep (unit_rules.lua):
--   琴女人偶, 冰雪琴女, 烟千岁, 玉簪: the check is the passive itself, so the passive is cancelled and its effect removed
--   (玉簪 has none of her own).
--   骨婉约: her check asks for CharacterState.Phantom, which her effect gives; the passive also runs her fog and stays. In the
--   fog (CharacterState.AbilityState.GuWanYue.Invulnerable, at most 25 s) she is still out of reach.
-- A unit with no team is fought by the player, who can break it the game's way: left alone.
local U=require('ue_observe')
local Break={}
local XUKONG='BP_Monster_XuKong'
local XUKONG_PATH='/PBZCombatAsset/ActorData/Mobs/079_XuKong/BP_Monster_XuKong.BP_Monster_XuKong_C'
local DODGE_CLASS='/PBZCombatAsset/Prototypes/GameplayEffects/GE_DodgeInvulnerable.GE_DodgeInvulnerable_C'
local DODGE_TAG='CharacterState.Stand.Invulnerable.Dodge'
local QIN={passive='GA_QinNv_Passive_C',
    effect='/PBZCombatAsset/ActorData/Mobs/FemaleDoll/GameplayEffects/GE_FemaleDoll_QinNv_Phantom.GE_FemaleDoll_QinNv_Phantom_C'}
Break.KINDS={
    BP_Monster_FemaleDoll_QinNv=QIN,
    BP_Monster_FemaleDoll_QinNv_Ice=QIN,
    BP_Monster_FemaleDoll_QinNv_Ice_Special=QIN,
    BP_Monster_YanQianSui={passive='GA_YanQianSui_Passive_C',
        effect='/PBZCombatAsset/ActorData/Mobs/073_YanQianSui/GameplayEffects/GE_YanQianSui_Phantom.GE_YanQianSui_Phantom_C'},
    BP_Monster_GuWanYue={
        effect='/PBZCombatAsset/ActorData/Mobs/061_GuWanYue/GameplayEffects/GE_GuWanYue_Invulnerable.GE_GuWanYue_Invulnerable_C'},
    BP_Monster_FemaleVessel_YuZan={passive='GA_YuZan_DeflectOrb_Passive_C'},
}
local TEAMS={blue=true,red=true,companion=true}
local TRIES=10   -- support ticks to wait for the passive or the effect's class

local function className(actor)
    local name=U.className(actor)
    return name and (name:gsub('_C$','')) or nil
end

function Break.new(options)
    local log=options.log or function()end
    local findAll=options.findAll or function(name)return FindAllOf(name)end
    local find=options.find or function(path)return StaticFindObject(path)end
    local self={broken=0}
    local records={}   -- unit address -> {done=true} or {tries=n}
    local function say(line)log('[Phantom] '..line) end
    -- The unit's running instance of the passive.
    local function passiveOf(actor,name)
        local ok,all=pcall(findAll,name)
        local key=U.key(actor)
        for _,ability in ipairs(ok and U.array(all) or {})do
            if U.valid(ability) then
                local got,avatar=pcall(function()return ability:GetAvatarActorFromActorInfo()end)
                avatar=got and U.unwrap(avatar) or nil
                if U.valid(avatar) and U.key(avatar)==key and U.field(ability,'bIsActive')==true then return ability end
            end
        end
    end
    local function cancel(ability)
        pcall(function()ability:K2_CancelAbility()end)
        if U.field(ability,'bIsActive')==true then pcall(function()ability:K2_EndAbility()end) end
        return U.field(ability,'bIsActive')~=true
    end
    local function effectCount(asc,effect)
        local ok,count=pcall(function()return asc:GetGameplayEffectCount(effect,nil,false)end)
        count=ok and U.unwrap(count) or nil
        return type(count)=='number' and count or nil
    end
    local function tagCount(asc,tag)
        if not U.valid(asc) or FName==nil then return nil end
        local ok,count=pcall(function()return asc:GetGameplayTagCount({TagName=FName(tag)})end)
        count=ok and U.unwrap(count) or nil
        return type(count)=='number' and count or nil
    end
    -- True once there is nothing more to do for this unit.
    local function attempt(actor,kind,record,name)
        local asc=U.field(actor,'AbilitySystemComponent')
        if not U.valid(asc) then return false end
        local effect
        if kind.effect then
            local ok,found=pcall(find,kind.effect)
            effect=ok and U.valid(found) and found or nil
        end
        local ability=kind.passive and passiveOf(actor,kind.passive) or nil
        if (kind.passive and not ability or kind.effect and not effect) and record.tries<TRIES then return false end
        local stopped='不用取消'
        if kind.passive then stopped=ability and tostring(cancel(ability)) or '没找到' end
        local before,removed,after='?',false,'?'
        if effect then
            before=effectCount(asc,effect)
            removed=pcall(function()asc:RemoveActiveGameplayEffectBySourceEffect(effect,nil,-1)end)
            after=effectCount(asc,effect)
        end
        self.broken=self.broken+1
        say(string.format('虚化解除 单位=%s 被动=%s 已停=%s 效果=%s 移除调用=%s 数量 %s -> %s 虚化标签=%s',name,tostring(kind.passive or '留着'),stopped,
            effect and 'found' or (kind.effect and '没找到' or '无'),tostring(removed),tostring(before),tostring(after),tostring(tagCount(asc,'CharacterState.Phantom'))))
        return true
    end
    -- ActorConfig adds the infinite effect during initialization. Only this direct spawn path runs
    -- before ActivateAI. Timed dodge actions grant the same class, so never remove it in tick().
    function self:beforeActivate(actor,path,escort)
        if path~=XUKONG_PATH or escort or not options.rule or options.rule(XUKONG)~='off' then return true end
        local asc=U.field(actor,'AbilitySystemComponent')
        local before=tagCount(asc,DODGE_TAG)
        local ok,cls=pcall(find,DODGE_CLASS)
        local named,name=false,nil
        if ok and U.valid(cls) then named,name=pcall(function()return cls:GetFullName()end) end
        local exact=named and name=='BlueprintGeneratedClass '..DODGE_CLASS
        local called=false
        if before==1 and exact and U.valid(actor) and U.valid(asc) and U.valid(cls) then
            called=pcall(function()asc:RemoveActiveGameplayEffectBySourceEffect(cls,nil,1)end)
        end
        local after=tagCount(asc,DODGE_TAG)
        local removed=called and after==0
        if removed then self.broken=self.broken+1 end
        say(string.format('虚空登场前关闭常驻无敌 类=%s 移除调用=%s 标签=%s -> %s 读回=%s',
            tostring(exact),tostring(called),tostring(before),tostring(after),tostring(removed)))
        if removed or (before==0 and after==0) then return true end
        return false,'虚空常驻无敌未读回解除'
    end

    function self:tick()
        local present={}
        for _,member in ipairs(options.members() or {})do
            local actor=member.actor
            local key=U.key(actor)
            local name=key and TEAMS[member.team] and className(actor)
            local kind=name and Break.KINDS[name]
            if kind then
                present[key]=true
                local record=records[key]
                if not record then record={tries=0};records[key]=record end
                if not record.done then
                    if options.rule and options.rule(actor)=='keep' then
                        record.done=true
                        say('虚化保持原版 单位='..name)
                    else
                        record.tries=record.tries+1
                        if attempt(actor,kind,record,name) then record.done=true end
                    end
                end
            end
        end
        for key in pairs(records)do
            if not present[key] then records[key]=nil end
        end
    end
    return self
end
return Break
