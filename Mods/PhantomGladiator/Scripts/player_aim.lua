-- 招式锁玩家（二）: attacks that ask GameplayStatics for "the player" (GetPlayerCharacter / GetPlayerPawn) and aim at
-- or lock onto what they get, outside the targeting system. In a fight they went for the player, hidden and out of
-- everyone's hatred as the player was. Every such call in the game was read offline and sorted by what its result
-- is used for: only the attacks that turn to, warp to, shoot at
-- or lock onto the player are changed, listed below by the class that makes the call (it passes itself as the world
-- context). Everything else keeps the player, including what already works in a fight (summons placed by the
-- player, as 冷荼's were), executions and their QTE, death, input checks and the AI framework.
-- While a fight runs, a listed call made for one of the mod's blue or red units gets that unit's opponent back. The
-- context is followed to its unit: an action's or ability's avatar, a bullet's BulletOwnerAvatar, an actor's Owner or
-- Instigator, else its outer. A pre-hook's return value replaces the result, the
-- way GetDifficulty is answered in ai_difficulty.lua (verified in v0.33.1). The hooks exist only while a fight
-- runs; on install one call is made with a unit as the context (its class let through for that call) and the
-- answer read back.
-- 招式锁玩家（三）: 28 skills (17 of them new in game build 26367565) override RequestLockTarget: when
-- PBZPlayerAbilityTargetLibrary.ShouldForcePlayerAbilityTarget says so they call ResolvePlayerAbilityTarget instead of
-- the normal lock. The disassembled start of its condition checks that the player is alive and walks the caster's
-- HatredList. For a fighting unit's ability the hook answers false, so the skill takes the normal lock. The first call
-- for each class also asks the function with the hook out of the way and through it, and logs both answers.
-- IsPlayerInCasterHatredList is called natively from it, so a hook there would not be reached.
-- 招式锁玩家（四）: 左殇's GA_ZuoShang_Skill_19 (five golden rings shooting swords). Its bullet is a PBZ_ParticleBullet with no
-- target selector: the swords are particles of NS_ZuoShang_SwordShooting_001, whose System.PS_TargetPos reads the Niagara
-- parameter collection value NPC_CharInfo_001.CharRootPos. The native player class writes that value (the strings
-- CharRootPos and CharVel sit next to PBZCharacter_Player.cpp in PBZ.exe), so these swords go for the player's body whatever
-- the unit, its hatred or its lock target say, and nothing above sees them. The effect has a user switch,
-- UE_UseTestTargetPos with UE_TestTargetPos, so while such a bullet of a fighting unit runs, the switch is on and the
-- position follows the unit's opponent. The bullet's launcher (GAA_DelayDeflectProjectileBullet.Go go go) says when to look.
-- 招式锁玩家（五）: other effects with their own hit traces read the same value and have no switch (see EFFECT_SKILLS). While
-- such a skill of a fighting unit runs, the world's NPC_CharInfo_001 instance gets the opponent's position each frame, the
-- same SetVectorParameter the player class uses. Collections push to the systems before actors tick, and this runs before
-- the world ticks, so the effects see this value instead of the one the player class wrote last frame. Everything else that
-- reads it (fish, flowers) follows along for those seconds. The player class writes its own again as soon as this stops.
local U=require('ue_observe')
local Aim={}
local STATICS='/Script/Engine.GameplayStatics:'
Aim.paths={character=STATICS..'GetPlayerCharacter',pawn=STATICS..'GetPlayerPawn',
    force='/Script/PBZAbilityTargetRuntime.PBZPlayerAbilityTargetLibrary:ShouldForcePlayerAbilityTarget',
    lock='/MagCombatAbilities/Abilities/BP_ActionAbilityBase.BP_ActionAbilityBase_C:Request Lock Target',
    bullet='/SGameCombatSystem/Bullet/TargetSelector/BP_BulletTargetSelector_LockTarget.BP_BulletTargetSelector_LockTarget_C:SelectTarget',
    bulletAbility='/PBZCombatAsset/Prototypes/Bullet/TargetSelector/BP_BulletTargetSelector_FromAbility.BP_BulletTargetSelector_FromAbility_C:SelectTarget'}
local ORDER={'character','pawn','force','lock','bullet','bulletAbility'}
local LABEL={character='取玩家角色',pawn='取玩家Pawn',force='强制锁玩家',lock='锁定落在玩家',bullet='子弹目标',bulletAbility='子弹目标(招式)',flying='飞行中目标'}
-- 左殇's flying weapons: the target the bullet actually holds once it starts (ABulletActorBase.CurrentTarget), and where it ends.
local FLYING_DIR='/PBZCombatAsset/ActorData/Mobs/054_ZuoShang/Weapon/'
local FLYING={}
for _,name in ipairs({'FlyingSword','FlyingSpear','FlyingHammer_Big','FlyingGun'})do
    local class='BP_Bullet_ZuoShang_'..name
    local start,finish=name..'Start',name..'End'
    Aim.paths[start]=FLYING_DIR..class..'.'..class..'_C:Received_PostStart'
    Aim.paths[finish]=FLYING_DIR..class..'.'..class..'_C:Received_Deactivate'
    FLYING[start]='start';FLYING[finish]='finish'
    ORDER[#ORDER+1]=start;ORDER[#ORDER+1]=finish
    LABEL[start]=name..'起飞';LABEL[finish]=name..'结束'
end
local RETRY_SECONDS=5
local UNHOOK_SECONDS,LINES,SUMMARY_SECONDS=10,12,10
local CACHE_SECONDS,DEPTH=20,8
local STEPS={'Pawn','BulletOwnerAvatar','Owner','Instigator','Source Ability'}
local LOCK_SECONDS,UNLISTED_LINES,BULLET_LINES,FLIGHT_LINES,FLIGHT_PER_KIND=5,40,60,240,3
-- Particle bullets that aim through their effect: bullet data -> the effect's user switch and position.
local EFFECT_AIMS={BD_ZuoShang_Skill_19={use='UE_UseTestTargetPos',pos='UE_TestTargetPos'}}
Aim.effectAims=EFFECT_AIMS
Aim.paths.launch='/PBZDeflectSystem/Actions/GAA_DelayDeflectProjectileBullet.GAA_DelayDeflectProjectileBullet_C:Go go go'
ORDER[#ORDER+1]='launch';LABEL.launch='特效目标'
local PARTICLE_CLASS,EFFECT_MS,EFFECT_SCANS,EFFECT_SECONDS,READY,RUNNING='PBZ_ParticleBullet',50,3,15,1,2
-- Skills whose bullet data plays an effect that reads CharRootPos and traces hits along its particles (read offline).
local EFFECT_SKILLS={
    GA_ZuoShang_P2_Skill_17_C=true,                          -- 龙体左殇 BD_ZuoShang_P2_SwordRain_Burst
    GA_MengHua_CA_03_C=true,                                 -- 梦华 BD_MengHua_CA_03
    GA_LengTu_CA_02_C=true,                                  -- 冷荼 BD_LengTu_CA_02
    GA_HuaShan_JianOu_CriticalArt_C=true,                    -- 华山剑偶 BulletData_HuaShan_JianOu_CriticalArt_01
    GA_YingMei_RedShadowBoneBlade_Attack_MaskBuff_C=true,    -- 影魅 mask rings
    GA_YingMei_RedShadowBoneBlade_Skill_Sword_2Hit_A_C=true,
    GA_YingMei_Cyan_Attack_MaskBuff_C=true,
}
Aim.effectSkills=EFFECT_SKILLS
Aim.paths.skillStart='/MagCombatAbilities/Abilities/BP_ActionAbilityBase_Simple.BP_ActionAbilityBase_Simple_C:K2_ActivateAbility'
ORDER[#ORDER+1]='skillStart';LABEL.skillStart='全局位置'
local CHAR_INFO='/PBZVFXPack/VFX/A_Niagara/CommonNPC/NPC_CharInfo_001.NPC_CharInfo_001'
local NIAGARA_LIB='/Script/Niagara.Default__NiagaraFunctionLibrary'
local ABILITY_LIB='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
local CHAR_ROOT,SPOOF_SECONDS,SPOOF_GRACE,SPOOF_CHECK='CharRootPos',20,6,0.25
-- Attacks that aim at or lock onto the player (the call's world context is an object of the class or a subclass).
local AIMS={}
for _,name in ipairs({
    'BP_ZuoShang_Bullet_SpinningBlade_C','BP_ZuoShang_GroundWeapon_Base_C',               -- 左殇: spinning blade's contact, ground weapons turn
    'BP_Bullet_Eye_C','BP_Bullet_EyeDelay_C','BP_Bullet_EyeSP1_C','BP_Bullet_EyeSP3_C',   -- 独眼弓客's laser eyes
    'BP_Bullet_EyeSP3_01_C','BP_Bullet_EyeSP3_02_C','BP_Bullet_EyeSP3_03_C','BP_Bullet_EyeSP3_04_C','BP_Bullet_EyeSP4_C',
    'BP_Bullet_EyeSP4_L_C','BP_Bullet_EyeSP5_L_C','BP_Bullet_EyeSP5_L_01_C','BP_Bullet_EyeSP5_R_C','BP_Bullet_EyeSP5_R_01_C',
    'GA_ChiLian_P2_Skill_04_C',                                                           -- 献祭之蛇
    'GA_MoTian_Skill_08_C',                                                               -- 魔渊
    'GA_XianZhe_EnterCombat_C','GA_XianZhe_Skill_01_C','GA_XianZhe_Skill_07_C',            -- 贤者
    'GA_ZuoShang_P2_Skill_23_C','BP_Monster_ZuoShang_P2_C','BP_ZuoShang_P2_DragonPillarBullet_C', -- 龙体左殇, dragon pillars
    'BP_Bullet_LengTu_BigHand_FallingHand_C',                                             -- 冷荼's falling hand
    'GA_MengHua_IceShield_Passive_C',                                                     -- 梦华's ice shield faces it
    'GA_XuKong_Skill_04_C',                                                               -- 虚空
    'GA_DangHui_SwitchSelf_C',                                                            -- 荡秽's swap dodge
    'GAA_ForceLockTarget_C',                                                              -- the shared "force lock target" action
})do AIMS[name]=true end
Aim.aims=AIMS

local function addr(object)
    if object==nil then return nil end
    local ok,key=pcall(function()return object:GetAddress()end)
    return ok and key~=nil and tostring(key) or nil
end
local function className(object)
    local ok,name=pcall(function()return object:GetClass():GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end

function Aim.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local self={alive=true,state='idle',redirected=0,passed=0,message='没有进行中的战斗',counts={},window={}}
    for _,name in ipairs(ORDER)do self.counts[name]=0;self.window[name]=0 end
    self.counts.flying=0;self.window.flying=0
    local hooks={}
    local fighters={}     -- unit address -> true, for this mod's blue and red units in a fight
    local cache,cacheAt={},nil   -- context address -> unit address or false
    local seenLines,lines={},0
    local quietSince,summaryAt,passedWindow=nil,nil,0
    local probe=nil       -- a class let through during the install check only
    local listed={}       -- class name -> whether it or a parent class is listed (左殇's knives run the base's code)
    local function aims(object,cls)
        if listed[cls]~=nil then return listed[cls] end
        local found=false
        local okClass,class=pcall(function()return object:GetClass()end)
        for _=1,8 do
            if not okClass or not U.valid(class) then break end
            local okName,name=pcall(function()return class:GetFName():ToString()end)
            if okName and AIMS[name] then found=true;break end
            okClass,class=pcall(function()return class:GetSuperStruct()end)
        end
        listed[cls]=found
        return found
    end
    local function say(text)log('[PlayerAim] '..text)end

    -- One step from an object toward the unit it acts for: an action's or ability's own avatar first (an action may
    -- be a shared template whose outer is its class), then the fields, then the outer.
    local function step(object)
        local cls=className(object)
        local getter=(cls:find('^GAA?_') or cls:find('^LGAAction')) and (cls:find('^GA_') and 'GetAvatarActorFromActorInfo' or 'GetAvatarActor')
        if getter then
            local ok,avatar=pcall(function()return object[getter](object)end)
            avatar=ok and U.unwrap(avatar) or nil
            if U.valid(avatar) and addr(avatar)~=addr(object) then return avatar end
        end
        for _,field in ipairs(STEPS)do
            local value=U.field(object,field)
            if U.valid(value) then return value end
        end
        local ok,outer=pcall(function()return object:GetOuter()end)
        return ok and U.valid(outer) and outer or nil
    end
    local function unitOf(object)
        local first=addr(object)
        if not first then return nil end
        local now=clock()
        if not cacheAt or now-cacheAt>=CACHE_SECONDS then cache,cacheAt={},now end
        local known=cache[first]
        if known~=nil then return known or nil end
        local current,visited=object,{}
        for _=1,DEPTH do
            local key=addr(current)
            if not key or visited[key] then break end
            visited[key]=true
            if fighters[key] then cache[first]=key;return key end
            current=step(current)
            if not current then break end
        end
        cache[first]=false
        return nil
    end

    -- A caller outside the list that acts for a fighting unit keeps the player; it is named once in the log, so a skill
    -- that still goes for the player can be found. A few tries per class, since the first object may act for nobody.
    local unlistedTries,unlistedLines={},0
    local function noteUnlisted(object,cls,name)
        local tries=unlistedTries[cls] or 0
        if tries>=3 or unlistedLines>=UNLISTED_LINES then return end
        unlistedTries[cls]=tries+1
        if unitOf(object) then
            unlistedTries[cls]=3;unlistedLines=unlistedLines+1
            say('没改写的取玩家调用 调用方='..cls..' 函数='..LABEL[name])
        end
    end
    local function callback(name)
        return function(_,context)
            if not self.alive or not next(fighters) then return nil end
            local object=U.unwrap(context)
            if not U.valid(object) then return nil end
            local cls=className(object)
            if cls~=probe and not aims(object,cls) then noteUnlisted(object,cls,name);return nil end
            local unit=unitOf(object)
            if not unit or (options.paused and options.paused()) then self.passed=self.passed+1;passedWindow=passedWindow+1;return nil end
            local ok,target=pcall(options.opponentOf,unit)
            if not ok or not U.valid(target) then self.passed=self.passed+1;passedWindow=passedWindow+1;return nil end
            if cls==probe and not AIMS[cls] then return target end
            self.redirected=self.redirected+1
            self.counts[name]=self.counts[name]+1;self.window[name]=self.window[name]+1
            local where=className(object)
            if lines<LINES and not seenLines[name..where] then
                seenLines[name..where]=true;lines=lines+1
                say(string.format('改写 %s 调用方=%s → %s（不再是玩家） 累计=%d',LABEL[name],where,className(target),self.counts[name]))
            end
            return target
        end
    end

    local asking=nil      -- while the hook's own check runs: 'game' lets the call through, 'hook' answers it
    local function askForce(object,mode)
        local okLib,lib=pcall(function()return options.abilityTargets()end)
        if not okLib or not U.valid(lib) then return '函数库不可用' end
        asking=mode
        local ok,got=pcall(function()return lib:ShouldForcePlayerAbilityTarget(object)end)
        asking=nil
        return ok and tostring(got) or '错误:'..tostring(got)
    end
    local function forced(_,ability)
        if asking=='game' then return nil end
        if asking=='hook' then return false end
        if not self.alive or not next(fighters) then return nil end
        local object=U.unwrap(ability)
        if not U.valid(object) then return nil end
        local unit=unitOf(object)
        if not unit or (options.paused and options.paused()) then self.passed=self.passed+1;passedWindow=passedWindow+1;return nil end
        self.redirected=self.redirected+1
        self.counts.force=self.counts.force+1;self.window.force=self.window.force+1
        local where=className(object)
        if lines<LINES and not seenLines['force'..where] then
            seenLines['force'..where]=true;lines=lines+1
            local game=options.abilityTargets and askForce(object,'game') or '未读'
            local hook=options.abilityTargets and askForce(object,'hook') or '未读'
            say(string.format('不强制锁玩家 调用方=%s 游戏原本=%s 挂钩后=%s 累计=%d',where,game,hook,self.counts.force))
        end
        return false
    end

    -- 万剑归宗 (左殇 GA_ZuoShang_CA_02): each ground weapon fires a bullet whose target selector
    -- (BP_BulletTargetSelector_LockTarget) asks the source ability for its lock target, and the bullet starts toward that
    -- and homes for its first 0.2 s. The ability keeps the first target it selects (Request Lock Target), which comes from
    -- the AI's targeting and can be the player when the blackboard is empty during the phase change. FlyUp hands the weapon
    -- the ability before any bullet is made, so there the ability's lock goes to the unit's opponent.
    local lockedAt={}
    function self:lockAbilityOf(actor)
        if not self.alive or not U.valid(actor) then return false end
        local ability=U.field(actor,'Source Ability')
        if not U.valid(ability) then return false end
        local key=addr(ability)
        local now=clock()
        if key and lockedAt[key] and now-lockedAt[key]<LOCK_SECONDS then return true end
        local unit=unitOf(ability)
        if not unit then return false end
        local okTarget,target=pcall(options.opponentOf,unit)
        if not okTarget or not U.valid(target) then say('招式锁定没改：'..className(ability)..' 没有对手');return false end
        local root=U.field(target,'RootComponent')
        if not U.valid(root) then say('招式锁定没改：'..className(target)..' 没有根组件');return false end
        if key then lockedAt[key]=now end
        local beforeLock=U.field(ability,'Lock Target')
        local before=beforeLock and U.struct(beforeLock,'Component')
        local beforeOwner=U.valid(before) and (function()local ok,o=pcall(function()return before:GetOwner()end);return ok and U.valid(o) and className(o) or '?' end)() or '空'
        local okSet,err=pcall(function()
            ability['Lock Target']={Component=root,SocketName=FName('None')}
            ability['Lock Target Selected']=true
        end)
        local lock=U.field(ability,'Lock Target')
        local back=lock and U.struct(lock,'Component')
        local good=addr(back)==addr(root) and U.field(ability,'Lock Target Selected')==true
        say(string.format('招式锁定 %s：原目标=%s -> %s 写入=%s%s 读回=%s',className(ability),beforeOwner,className(target),tostring(okSet),okSet and '' or '('..tostring(err)..')',good and '生效' or '没生效'))
        return good
    end

    -- Any skill: the ability's own lock (BP_ActionAbilityBase.Request Lock Target; a blueprint hook's callback runs after the
    -- function) came out on the player, for one of this mod's fighting units. The stored lock and the answer go to its
    -- opponent, and the skill is named, so the log shows which skills were doing it.
    local function isPlayer(actor)
        if className(actor):find('^BP_RenewalPlayer') then return true end
        local ok,player=pcall(function()return options.player and options.player()end)
        return ok and U.valid(player) and addr(player)==addr(actor)
    end
    local lockLines={}
    local function relock(context,_,_,out)
        if not self.alive or not next(fighters) then return nil end
        local ability=U.unwrap(context)
        if not U.valid(ability) then return nil end
        local lock=U.field(ability,'Lock Target')
        local comp=lock and U.struct(lock,'Component')
        if not U.valid(comp) then return nil end
        local okOwner,owner=pcall(function()return comp:GetOwner()end)
        if not okOwner or not U.valid(owner) or not isPlayer(owner) then return nil end
        local unit=unitOf(ability)
        if not unit or (options.paused and options.paused()) then return nil end
        local okTarget,target=pcall(options.opponentOf,unit)
        if not okTarget or not U.valid(target) then return nil end
        local root=U.field(target,'RootComponent')
        if not U.valid(root) then return nil end
        local okSet=pcall(function()ability['Lock Target']={Component=root,SocketName=FName('None')} end)
        local okOut=out~=nil and pcall(function()out:set({Component=root,SocketName=FName('None')})end)
        self.redirected=self.redirected+1
        self.counts.lock=self.counts.lock+1;self.window.lock=self.window.lock+1
        local where=className(ability)
        if (lockLines[where] or 0)<2 then
            lockLines[where]=(lockLines[where] or 0)+1
            local back=U.field(ability,'Lock Target')
            say(string.format('招式的锁定落在玩家，改成对手 招式=%s -> %s 写入=%s 返回值=%s 读回=%s 累计=%d',where,className(target),tostring(okSet),tostring(okOut),
                addr(back and U.struct(back,'Component'))==addr(root) and '生效' or '没生效',self.counts.lock))
        end
        return nil
    end

    -- Where a bullet gets its target: its data's selector, called natively (UBulletTargetSelectorBase.SelectTarget), which
    -- fills the Target out parameter. 左殇's flying swords hover (BulletMovementData_Rotation), home for 0.2 s toward that
    -- target, then fly straight, so it decides where they all go. A bullet of a fighting unit aimed at anything but another
    -- fighting unit goes to the unit's opponent, and each skill is named once with what it had, on the player or not.
    local bulletLines,bulletSeen=0,{}
    local function retarget(_,avatar,_,ability,_,_,out)
        if not self.alive or not next(fighters) then return nil end
        local owner=U.unwrap(avatar)
        if not U.valid(owner) then return nil end
        local key=U.key(owner)
        if not key or not fighters[key] or (options.paused and options.paused()) then return nil end
        local okTarget,target=pcall(options.opponentOf,key)
        if not okTarget or not U.valid(target) then return nil end
        local root=U.field(target,'RootComponent')
        if not U.valid(root) then return nil end
        local current=out and U.unwrap(out)
        local comp=current and U.struct(current,'Component')
        local had='空'
        if U.valid(comp) then
            local okOwner,hit=pcall(function()return comp:GetOwner()end)
            if okOwner and U.valid(hit) then
                had=className(hit)
                if fighters[U.key(hit)] then
                    local where=U.valid(U.unwrap(ability)) and className(U.unwrap(ability)) or '?'
                    if not bulletSeen['ok'..where] and bulletLines<BULLET_LINES then
                        bulletSeen['ok'..where]=true;bulletLines=bulletLines+1
                        say('子弹目标 招式='..where..' 目标='..had..'（参战单位，不改）')
                    end
                    return nil
                end
            end
        end
        local okSet,err=pcall(function()out:set({Component=root,SocketName=FName('None')})end)
        self.redirected=self.redirected+1
        self.counts.bullet=self.counts.bullet+1;self.window.bullet=self.window.bullet+1
        local where=U.valid(U.unwrap(ability)) and className(U.unwrap(ability)) or '?'
        if not bulletSeen[where] and bulletLines<BULLET_LINES then
            bulletSeen[where]=true;bulletLines=bulletLines+1
            local back=out and U.unwrap(out)
            local after=back and U.struct(back,'Component')
            say(string.format('子弹目标改成对手 招式=%s 原目标=%s -> %s 写入=%s%s 读回=%s 累计=%d',where,had,className(target),tostring(okSet),okSet and '' or '('..tostring(err)..')',
                addr(after)==addr(root) and '生效' or '没读回',self.counts.bullet))
        end
        return true
    end

    -- Once a flying weapon starts: a target that is not a fighting unit becomes the opponent, on the bullet itself. When it
    -- ends: where it is against the player, its target and its caster, which says what it really flew at.
    local function place(actor)
        local ok,at=pcall(function()return actor:K2_GetActorLocation()end)
        return ok and at or nil
    end
    local function metres(a,b)
        local okA,ax,ay,az=pcall(function()return a.X,a.Y,a.Z end)
        local okB,bx,by,bz=pcall(function()return b.X,b.Y,b.Z end)
        if not okA or not okB or type(ax)~='number' or type(bx)~='number' then return '?' end
        return string.format('%.1fm',math.sqrt((ax-bx)^2+(ay-by)^2+(az-bz)^2)/100)
    end
    local function holderOf(bullet)
        local field=U.field(bullet,'CurrentTarget')
        local comp=field and U.struct(field,'Component')
        if not U.valid(comp) then return nil,nil end
        local ok,hit=pcall(function()return comp:GetOwner()end)
        return comp,ok and U.valid(hit) and hit or nil
    end
    local flightLines,flightSeen=0,{}
    local function flight(kind,context)
        if not self.alive or not next(fighters) then return nil end
        local bullet=U.unwrap(context)
        if not U.valid(bullet) then return nil end
        local owner=U.field(bullet,'BulletOwnerAvatar')
        local key=U.valid(owner) and U.key(owner)
        if not key or not fighters[key] then return nil end
        local okTarget,target=pcall(options.opponentOf,key)
        target=okTarget and U.valid(target) and target or nil
        local _,hit=holderOf(bullet)
        local note=''
        if kind=='start' and target and not (hit and fighters[U.key(hit)]) and not (options.paused and options.paused()) then
            local root=U.field(target,'RootComponent')
            if U.valid(root) then
                local had=hit and className(hit) or '空'
                local okSet=pcall(function()bullet.CurrentTarget={Component=root,SocketName=FName('None')} end)
                local comp=holderOf(bullet)
                self.redirected=self.redirected+1
                self.counts.flying=self.counts.flying+1;self.window.flying=self.window.flying+1
                note=string.format(' 原目标=%s 改成对手 写入=%s 读回=%s',had,tostring(okSet),addr(comp)==addr(root) and '生效' or '没生效')
            end
        end
        local source=U.field(bullet,'BulletSourceAbility')
        source=U.valid(source) and className(source) or '?'
        -- A few lines per bullet class and skill: one busy skill must not use up the log for the rest of the fight.
        local line=className(bullet)..'|'..source..'|'..kind
        flightSeen[line]=(flightSeen[line] or 0)+1
        if flightSeen[line]>FLIGHT_PER_KIND or flightLines>=FLIGHT_LINES then return nil end
        flightLines=flightLines+1
        local at=place(bullet)
        local okPlayer,player=pcall(function()return options.player and options.player()end)
        local _,now=holderOf(bullet)
        say(string.format('%s %s 招式=%s 当前目标=%s 距玩家=%s 距对手=%s 距施法者=%s%s',className(bullet),kind=='start' and '起飞' or '结束',
            source,now and className(now) or '空',
            okPlayer and U.valid(player) and metres(at,place(player)) or '?',target and metres(at,place(target)) or '?',metres(at,place(owner)),note))
        return nil
    end

    -- One call with a unit as the world context: the hook must answer with its opponent, not the player.
    local function selfCheck()
        local lib=options.statics and options.statics()
        local unit
        for key in pairs(fighters)do unit=key;break end
        local actor=unit and options.actorOf and options.actorOf(unit)
        if not U.valid(lib) or not U.valid(actor) then say('自检跳过：函数库或参战单位不可用');return end
        local okWant,wanted=pcall(options.opponentOf,unit)
        probe=className(actor)
        local ok,got=pcall(function()return lib:GetPlayerCharacter(actor,0)end)
        probe=nil
        got=ok and U.unwrap(got) or nil
        local same=okWant and U.valid(wanted) and addr(got)==addr(wanted)
        say(string.format('自检（临时放行该单位的类）：以 %s 为上下文取玩家角色 → %s；应为对手 %s；改写生效=%s%s',className(actor),
            U.valid(got) and className(got) or '空',okWant and U.valid(wanted) and className(wanted) or '无',tostring(same),
            ok and '' or ' 错误='..tostring(got)))
    end

    local effects,effectLoop,effectScans={},nil,0   -- bullet address -> what is being aimed; the fast loop runs only while one flies
    local function nameOf(object)
        local ok,name=pcall(function()return object:GetFName():ToString()end)
        return ok and type(name)=='string' and name or '?'
    end
    local function stopEffectLoop()
        if effectLoop then pcall(CancelDelayedAction,effectLoop);effectLoop=nil end
    end
    local function statusOf(bullet)
        return U.valid(bullet) and U.unwrap(U.field(bullet,'BulletStatus')) or nil
    end
    local function scanEffects()
        local ok,list=pcall(FindAllOf,PARTICLE_CLASS)
        if not ok or type(list)~='table' then return end
        for _,bullet in ipairs(list)do
            local key=addr(bullet)
            if key and not effects[key] then
                local status=statusOf(bullet)
                if status==RUNNING or status==READY then
                    local owner=U.field(bullet,'BulletOwnerAvatar')
                    local ownerKey=U.valid(owner) and U.key(owner)
                    local data=U.field(bullet,'BulletData')
                    local dataName=U.valid(data) and nameOf(data) or nil
                    local comp=U.field(bullet,'ParticleComponent')
                    if ownerKey and fighters[ownerKey] and dataName and EFFECT_AIMS[dataName] and U.valid(comp) then
                        effects[key]={bullet=bullet,comp=comp,owner=ownerKey,data=dataName,spec=EFFECT_AIMS[dataName],since=clock(),writes=0}
                    end
                end
            end
        end
    end
    local function aimEffect(item)
        -- The bullet outlives its effect component now and then; the same bullet may also have a new one.
        if not U.valid(item.comp) then
            item.comp=U.field(item.bullet,'ParticleComponent')
            if not U.valid(item.comp) then return end
            item.switched=nil
        end
        local okTarget,target=pcall(options.opponentOf,item.owner)
        if not okTarget or not U.valid(target) then return end
        local at=place(target)
        local okRead,x,y,z=pcall(function()return at.X,at.Y,at.Z end)
        if not okRead or type(x)~='number' then return end
        local spot={X=x,Y=y,Z=z}
        -- Which of the two the effect declared cannot be read offline; setting the other only adds an unused value.
        local okPosition=pcall(function()item.comp:SetVariablePosition(FName(item.spec.pos),spot)end)
        local okVector=pcall(function()item.comp:SetVariableVec3(FName(item.spec.pos),spot)end)
        item.writes=item.writes+1
        if not item.switched then
            local okUse=pcall(function()item.comp:SetVariableBool(FName(item.spec.use),true)end)
            item.switched=okUse
            self.redirected=self.redirected+1
            self.counts.launch=self.counts.launch+1;self.window.launch=self.window.launch+1
            local okPlayer,player=pcall(function()return options.player and options.player()end)
            local from=place(item.bullet)
            say(string.format('特效目标改成对手 子弹=%s 招式=%s 对手=%s 开关=%s 写入=%s 坐标写入=%s/%s 发射点距对手=%s 距玩家=%s',item.data,
                U.valid(U.field(item.bullet,'BulletSourceAbility')) and className(U.field(item.bullet,'BulletSourceAbility')) or '?',
                className(target),item.spec.use,tostring(okUse),tostring(okPosition),tostring(okVector),metres(from,at),
                okPlayer and U.valid(player) and metres(from,place(player)) or '?'))
        end
    end
    local function releaseEffect(item)
        local ok=U.valid(item.comp) and pcall(function()item.comp:SetVariableBool(FName(item.spec.use),false)end)
        say(string.format('特效目标还原 子弹=%s 跟随对手写入=%d次 关开关=%s',item.data,item.writes,tostring(ok==true)))
    end
    local function effectTick()
        if not self.alive then stopEffectLoop();return end
        if effectScans>0 then effectScans=effectScans-1;scanEffects() end
        local now=clock()
        for key,item in pairs(effects)do
            local status=statusOf(item.bullet)
            if (status==RUNNING or status==READY) and now-item.since<EFFECT_SECONDS then
                if not (options.paused and options.paused()) then aimEffect(item) end
            else
                releaseEffect(item);effects[key]=nil
            end
        end
        if effectScans<=0 and not next(effects) then stopEffectLoop() end
    end
    local function launched(context)
        if not self.alive or not next(fighters) then return nil end
        local action=U.unwrap(context)
        if not U.valid(action) then return nil end
        local data=U.field(action,'Bullet Data')
        if not U.valid(data) or not EFFECT_AIMS[nameOf(data)] or not unitOf(action) then return nil end
        effectScans=EFFECT_SCANS
        if not effectLoop then
            local ok,handle=pcall(LoopInGameThreadWithDelay,EFFECT_MS,effectTick)
            if ok then effectLoop=handle else say('特效目标循环启动失败：'..tostring(handle)) end
        end
        return nil
    end

    local spoof,spoofLoop=nil,nil   -- the skill whose effects are being pointed at its unit's opponent
    local effectSkillClass={}       -- class name -> whether it or a parent is in EFFECT_SKILLS
    -- There is one value and two effects may want it: the newest skill has it, and the one it took over from gets it back
    -- when that ends, instead of the player's position.
    local function closeSpoof(reason)
        say(string.format('全局角色位置还原 招式=%s 写入=%d次（%s）',spoof.name,spoof.writes,reason))
        spoof=spoof.previous
    end
    local function stopSpoof(reason)
        if spoofLoop then pcall(CancelDelayedAction,spoofLoop);spoofLoop=nil end
        while spoof do closeSpoof(reason) end
    end
    local function charInfo()
        local okLib,lib=pcall(StaticFindObject,NIAGARA_LIB)
        local okNpc,npc=pcall(StaticFindObject,CHAR_INFO)
        local world=options.world and options.world()
        if not okLib or not okNpc or not U.valid(lib) or not U.valid(npc) or not U.valid(world) then return nil end
        local ok,instance=pcall(function()return lib:GetNiagaraParameterCollection(world,npc)end)
        instance=ok and U.unwrap(instance) or nil
        return U.valid(instance) and instance or nil
    end
    local function skillActive(ability)
        local ok,lib=pcall(StaticFindObject,ABILITY_LIB)
        if not ok or not U.valid(lib) or not U.valid(ability) then return false end
        local okAsk,value=pcall(function()return lib:IsGameplayAbilityActive(ability)end)
        return okAsk and U.unwrap(value)==true
    end
    -- The value lives at the actor's feet (its name says root); a character's mesh sits there.
    local function rootOf(actor)
        local mesh=U.field(actor,'Mesh')
        if U.valid(mesh) then
            local ok,at=pcall(function()return mesh:K2_GetComponentLocation()end)
            if ok and at and type(at.X)=='number' then return {X=at.X,Y=at.Y,Z=at.Z} end
        end
        local at=place(actor)
        local ok,x,y,z=pcall(function()return at.X,at.Y,at.Z end)
        return ok and type(x)=='number' and {X=x,Y=y,Z=z} or nil
    end
    local function spoofTick()
        if not self.alive or not spoof then stopSpoof('已停止');return end
        local now=clock()
        while spoof and now-spoof.since>=SPOOF_SECONDS do closeSpoof('到时') end
        if spoof and now>=spoof.checkAt then
            spoof.checkAt=now+SPOOF_CHECK
            if skillActive(spoof.ability) then spoof.endedAt=nil else spoof.endedAt=spoof.endedAt or now end
            if spoof.endedAt and now-spoof.endedAt>=SPOOF_GRACE then closeSpoof('招式结束') end
        end
        if not spoof then stopSpoof('已停止');return end
        if options.paused and options.paused() then return end
        local okTarget,target=pcall(options.opponentOf,spoof.owner)
        if not okTarget or not U.valid(target) then return end
        local spot=rootOf(target)
        if not spot then return end
        if not U.valid(spoof.instance) then
            spoof.instance=charInfo()
            if not spoof.instance then
                if not spoof.noted then spoof.noted=true;say('全局角色位置改不了：取不到 NPC_CharInfo_001 招式='..spoof.name) end
                return
            end
        end
        local detail=spoof.writes<2
        local playerAt=nil
        if detail then
            local okPlayer,player=pcall(function()return options.player and options.player()end)
            playerAt=okPlayer and U.valid(player) and place(player) or nil
        end
        local before=detail and select(2,pcall(function()return spoof.instance:GetVectorParameter(CHAR_ROOT)end)) or nil
        before=before and U.unwrap(before) or nil
        local okSet=pcall(function()spoof.instance:SetVectorParameter(CHAR_ROOT,spot)end)
        spoof.writes=spoof.writes+1
        if detail then
            local _,after=pcall(function()return spoof.instance:GetVectorParameter(CHAR_ROOT)end)
            after=after and U.unwrap(after) or nil
            say(string.format('全局角色位置改成对手 招式=%s 第%d次 对手=%s 写入前距玩家=%s 距对手=%s 写入=%s 读回距对手=%s',spoof.name,spoof.writes,className(target),
                playerAt and before and metres(before,playerAt) or '?',before and metres(before,spot) or '?',tostring(okSet),after and metres(after,spot) or '?'))
        end
    end
    local function skillStarted(context)
        if not self.alive or not next(fighters) then return nil end
        local ability=U.unwrap(context)
        if not U.valid(ability) then return nil end
        local name=className(ability)
        if effectSkillClass[name]==nil then
            -- A skill's subclasses play the same effect (GA_ZuoShang_P2_Skill_17_NoCD, ..._Sword_2Hit_A_FastCancel).
            local found=false
            local okClass,class=pcall(function()return ability:GetClass()end)
            for _=1,8 do
                if not okClass or not U.valid(class) then break end
                local okName,parent=pcall(function()return class:GetFName():ToString()end)
                if okName and EFFECT_SKILLS[parent] then found=true;break end
                okClass,class=pcall(function()return class:GetSuperStruct()end)
            end
            effectSkillClass[name]=found
        end
        if not effectSkillClass[name] then return nil end
        local unit=unitOf(ability)
        if not unit then return nil end
        self.redirected=self.redirected+1
        self.counts.skillStart=self.counts.skillStart+1;self.window.skillStart=self.window.skillStart+1
        local older=spoof
        if older and older.owner==unit then older=older.previous end
        spoof={ability=ability,name=name,owner=unit,since=clock(),checkAt=clock()+SPOOF_CHECK,writes=0,instance=spoof and spoof.instance or nil,previous=older}
        if not spoofLoop then
            local ok,handle=pcall(LoopInGameThreadWithDelay,1,spoofTick)
            if ok then spoofLoop=handle else say('全局角色位置循环启动失败：'..tostring(handle)) end
        end
        return nil
    end

    -- A blueprint that is not loaded yet (a selector comes in with the first bullet data) is tried again while the fight runs.
    local missing,retryAt={},nil
    local function register(name)
        local path=Aim.paths[name]
        local okFind,found=pcall(StaticFindObject,path)
        if not okFind or not U.valid(found) then
            if not missing[name] then say('还没找到函数，稍后再试 '..path) end
            missing[name]=true
            return
        end
        missing[name]=nil
        local handler=name=='force' and forced or name=='lock' and relock or (name=='bullet' or name=='bulletAbility') and retarget
            or name=='launch' and launched or name=='skillStart' and skillStarted
            or FLYING[name] and function(context)
                self.counts[name]=self.counts[name]+1;self.window[name]=self.window[name]+1
                return flight(FLYING[name],context)
            end or callback(name)
        local ok,pre,post=pcall(RegisterHook,path,handler,function()end)
        if ok and type(pre)=='number' and type(post)=='number' then
            hooks[name]={pre=pre,post=post};say('挂钩注册ID读回 '..name..' pre='..pre..' post='..post)
        else say('挂钩注册失败 '..name..'：'..tostring(pre))end
    end
    local function install()
        for _,fn in ipairs({'StaticFindObject','RegisterHook','UnregisterHook'})do
            if type(_G[fn])~='function' then self.state='failed';self.message='缺少 '..fn;say(self.message);return end
        end
        for _,name in ipairs(ORDER)do register(name) end
        if next(hooks) then
            self.state='running';self.message='战斗中，参战单位的招式取玩家时拿到的是它的对手'
            selfCheck()
        else self.state='failed';self.message='取玩家函数挂钩失败' end
    end
    local function uninstall(reason)
        if not next(hooks) then return end
        stopEffectLoop();effectScans=0
        stopSpoof('摘钩')
        for key,item in pairs(effects)do releaseEffect(item);effects[key]=nil end
        local kept={}
        for name,hook in pairs(hooks)do
            if not pcall(UnregisterHook,Aim.paths[name],hook.pre,hook.post) then kept[name]=hook end
        end
        local parts={}
        for _,name in ipairs(ORDER)do parts[#parts+1]=LABEL[name]..'='..self.counts[name] end
        parts[#parts+1]=LABEL.flying..'='..self.counts.flying
        say('摘除挂钩（'..reason..'） 改写 '..table.concat(parts,' ')..' 其他调用照旧='..self.passed..' 摘除失败='..tostring(next(kept)~=nil))
        hooks=kept
        if not next(hooks) then self.state='idle';self.message='没有进行中的战斗' end
        missing={}
    end

    function self:tick()
        if not self.alive then return end
        local now=clock()
        local units={}
        if options.fighting() then
            for _,member in ipairs(options.members())do
                if (member.team=='blue' or member.team=='red') and not member.reserve then
                    local key=U.key(member.actor)
                    if key then units[key]=true end
                end
            end
        end
        local changed=false
        for key in pairs(units)do if not fighters[key] then changed=true end end
        for key in pairs(fighters)do if not units[key] then changed=true end end
        fighters=units
        if changed then cache,cacheAt={},now end
        if next(fighters) then
            quietSince=nil
            if not next(hooks) and self.state~='failed' then install()
            elseif next(missing) and (not retryAt or now>=retryAt) then
                retryAt=now+RETRY_SECONDS
                for name in pairs(missing)do register(name) end
            end
        elseif next(hooks) then
            quietSince=quietSince or now
            if now-quietSince>=UNHOOK_SECONDS then uninstall('战斗已结束') end
        end
        summaryAt=summaryAt or now
        if now-summaryAt>=SUMMARY_SECONDS then
            if next(hooks) then
                local parts={}
                for _,name in ipairs(ORDER)do parts[#parts+1]=LABEL[name]..'='..self.window[name];self.window[name]=0 end
                parts[#parts+1]=LABEL.flying..'='..self.window.flying;self.window.flying=0
                say(string.format('近 %.0f 秒：改写 %s 其他调用照旧=%d',now-summaryAt,table.concat(parts,' '),passedWindow))
                passedWindow=0
            end
            summaryAt=now
        end
    end
    function self:status()return {state=self.state,redirected=self.redirected,passed=self.passed,message=self.message}end
    function self:silence(reason)uninstall(reason or 'Mod卸载');self.alive=false end
    return self
end
return Aim
