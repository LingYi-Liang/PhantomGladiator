package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
FName=setmetatable({},{__call=function(_,s)return s end})
local Break=require('phantom_break')
local serial=0
local function object(name,fields)
    serial=serial+1;local address=serial
    local o=fields or {};o.live=true
    o.IsValid=function(self)return self.live end
    o.GetAddress=function()return address end
    o.GetFName=function()return {ToString=function()return name end}end
    return o
end
local function harness()
    local h={lines={},members={},rules={},abilities={},classes={},removed={},cancels=0}
    function h.unit(class,team)
        local actor=object(class)
        actor.GetClass=function()return {GetFName=function()return {ToString=function()return class..'_C' end}end}end
        actor.effects=1
        actor.AbilitySystemComponent=object('ASC',{
            GetGameplayEffectCount=function(_,effect,instigator,ongoing)
                assert(instigator==nil and ongoing==false,'counts one kept out by its requirements too')
                return actor.effects
            end,
            RemoveActiveGameplayEffectBySourceEffect=function(_,effect,instigator,stacks)
                assert(instigator==nil and stacks==-1)
                h.removed[#h.removed+1]=effect;actor.effects=0
            end,
            GetGameplayTagCount=function(_,tag)assert(tag.TagName=='CharacterState.Phantom');return actor.effects end})
        h.members[#h.members+1]={actor=actor,team=team or 'blue'}
        return actor
    end
    function h.passive(actor,class,fields)
        local ability=object(class,fields)
        ability.bIsActive=true
        ability.GetAvatarActorFromActorInfo=function()return actor end
        ability.K2_CancelAbility=ability.K2_CancelAbility or function(self)h.cancels=h.cancels+1;self.bIsActive=false end
        h.abilities[class]=h.abilities[class] or {}
        table.insert(h.abilities[class],ability)
        return ability
    end
    h.mod=Break.new({log=function(s)h.lines[#h.lines+1]=s end,members=function()return h.members end,
        findAll=function(name)return h.abilities[name] or {} end,
        find=function(path)return h.classes[path] end,
        rule=function(actor)return h.rules[actor] end})
    function h.all()return table.concat(h.lines,'\n')end
    return h
end
local QIN='/PBZCombatAsset/ActorData/Mobs/FemaleDoll/GameplayEffects/GE_FemaleDoll_QinNv_Phantom.GE_FemaleDoll_QinNv_Phantom_C'
local GU='/PBZCombatAsset/ActorData/Mobs/061_GuWanYue/GameplayEffects/GE_GuWanYue_Invulnerable.GE_GuWanYue_Invulnerable_C'

-- 冰雪琴女 on a team: her passive stops and her effect goes, read back, once. Another unit's passive is not touched.
do
    local h=harness()
    h.classes[QIN]=object('GE_FemaleDoll_QinNv_Phantom_C')
    local doll=h.unit('BP_Monster_FemaleDoll_QinNv_Ice','red')
    local other=h.unit('BP_Monster_FemaleDoll_QinNv','neutral')
    local theirs=h.passive(other,'GA_QinNv_Passive_C')
    local passive=h.passive(doll,'GA_QinNv_Passive_C')
    h.mod:tick()
    assert(passive.bIsActive==false and theirs.bIsActive==true and h.cancels==1)
    assert(#h.removed==1 and h.removed[1]==h.classes[QIN] and doll.effects==0 and other.effects==1)
    assert(h.all():find('虚化解除 单位=BP_Monster_FemaleDoll_QinNv_Ice 被动=GA_QinNv_Passive_C 已停=true 效果=found 移除调用=true 数量 1 -> 0 虚化标签=0',1,true),h.all())
    h.mod:tick();assert(h.cancels==1 and #h.removed==1 and #h.lines==1,'once')
end
-- A unit with no team is the player's to break: left alone. Other classes are not looked at.
do
    local h=harness()
    h.classes[QIN]=object('GE')
    local doll=h.unit('BP_Monster_FemaleDoll_QinNv','neutral')
    local passive=h.passive(doll,'GA_QinNv_Passive_C')
    h.unit('BP_Monster_MoTian','blue')
    h.mod:tick()
    assert(passive.bIsActive==true and doll.effects==1 and #h.lines==0)
end
-- Companions lose it too; the card can keep it, once said.
do
    local h=harness()
    h.classes[QIN]=object('GE')
    local mate=h.unit('BP_Monster_FemaleDoll_QinNv','companion')
    local matePassive=h.passive(mate,'GA_QinNv_Passive_C')
    local kept=h.unit('BP_Monster_FemaleDoll_QinNv','blue')
    local keptPassive=h.passive(kept,'GA_QinNv_Passive_C')
    h.rules[kept]='keep'
    h.mod:tick();h.mod:tick()
    assert(matePassive.bIsActive==false and keptPassive.bIsActive==true and kept.effects==1)
    local _,said=h.all():gsub('虚化保持原版 单位=BP_Monster_FemaleDoll_QinNv','')
    assert(said==1,h.all())
end
-- 骨婉约: only the effect goes. Her passive runs her fog.
do
    local h=harness()
    h.classes[GU]=object('GE_GuWanYue_Invulnerable_C')
    local boss=h.unit('BP_Monster_GuWanYue','blue')
    local passive=h.passive(boss,'GA_GuWanYue_Passive_C')
    h.mod:tick()
    assert(passive.bIsActive==true and boss.effects==0)
    assert(h.all():find('被动=留着 已停=不用取消 效果=found',1,true),h.all())
end
-- Not ready yet: waits for the passive and the effect's class, then does what it can and says so.
do
    local h=harness()
    local doll=h.unit('BP_Monster_FemaleDoll_QinNv','blue')
    for _=1,3 do h.mod:tick() end
    assert(#h.lines==0 and doll.effects==1,'waits')
    h.classes[QIN]=object('GE')
    local passive=h.passive(doll,'GA_QinNv_Passive_C')
    h.mod:tick()
    assert(passive.bIsActive==false and doll.effects==0 and #h.lines==1)
    local late=h.unit('BP_Monster_FemaleDoll_QinNv','blue')
    for _=1,12 do h.mod:tick() end
    assert(h.all():find('被动=GA_QinNv_Passive_C 已停=没找到 效果=found',1,true) and late.effects==0,h.all())
    local _,said=h.all():gsub('虚化解除','')
    assert(said==2)
end
-- A cancel that does not take: the ability is ended instead, and the read-back says what happened.
do
    local h=harness()
    h.classes[QIN]=object('GE')
    local doll=h.unit('BP_Monster_FemaleDoll_QinNv','blue')
    local ended=false
    local passive=h.passive(doll,'GA_QinNv_Passive_C',{K2_CancelAbility=function()end,K2_EndAbility=function(self)ended=true;self.bIsActive=false end})
    h.mod:tick()
    assert(ended and passive.bIsActive==false and h.all():find('已停=true',1,true))
    local stuck=harness()
    stuck.classes[QIN]=object('GE')
    local other=stuck.unit('BP_Monster_FemaleDoll_QinNv','blue')
    stuck.passive(other,'GA_QinNv_Passive_C',{K2_CancelAbility=function()end,K2_EndAbility=function()end})
    stuck.mod:tick()
    assert(stuck.all():find('已停=false',1,true),stuck.all())
end
-- A unit that left is forgotten; an address used again counts as new.
do
    local h=harness()
    h.classes[QIN]=object('GE')
    local doll=h.unit('BP_Monster_FemaleDoll_QinNv','blue')
    h.passive(doll,'GA_QinNv_Passive_C')
    h.mod:tick()
    h.members[1]=nil
    h.mod:tick()
    h.members[1]={actor=doll,team='blue'}
    doll.effects=1
    h.passive(doll,'GA_QinNv_Passive_C')
    h.mod:tick()
    assert(doll.effects==0)
end
-- 玉簪 on a team: her passive is the check and she has no effect of her own, so it stops on the first look, without waiting
-- for an effect. With her card on keep it stays.
do
    local h=harness()
    local yuzan=h.unit('BP_Monster_FemaleVessel_YuZan','red')
    local passive=h.passive(yuzan,'GA_YuZan_DeflectOrb_Passive_C')
    h.mod:tick()
    assert(passive.bIsActive==false and h.cancels==1 and #h.removed==0,h.all())
    assert(h.all():find('虚化解除 单位=BP_Monster_FemaleVessel_YuZan 被动=GA_YuZan_DeflectOrb_Passive_C 已停=true 效果=无',1,true),h.all())
    h.mod:tick();assert(h.cancels==1,'once')
    local kept=harness()
    local other=kept.unit('BP_Monster_FemaleVessel_YuZan','blue')
    local hers=kept.passive(other,'GA_YuZan_DeflectOrb_Passive_C')
    kept.rules[other]='keep'
    kept.mod:tick()
    assert(hers.bIsActive==true and kept.all():find('虚化保持原版 单位=BP_Monster_FemaleVessel_YuZan',1,true),kept.all())
end
print('phantom_break: PASS')
