-- Listed offensive player getters and target selectors use their owned caster's enemy.
-- Arena fighters use the opposing team; companions read their private AI blackboard.
-- Ownership follows the current avatar on every call, including shared action templates.
-- Player abilities, follow actions and native story phases keep their original targets.
-- Silver-haired Zuo Shang's particle swords expose per-component user target parameters.
-- Other listed particle attacks use effect_instance_aim's private collections and systems;
-- this module never writes the world's material or Niagara player-position collection.
local U=require('ue_observe')
local Retry=require('lookup_retry')
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
local CASTERS={BP_Monster_ZuoShang_C=true,BP_Monster_ZuoShang_Ending_C=true,BP_Monster_ZuoShang_P2_C=true,
    BP_Monster_ZuoShang_P2_Stand_C=true}
for _,name in ipairs({'FlyingSword','FlyingSpear','FlyingHammer_Big','FlyingGun'})do
    local class='BP_Bullet_ZuoShang_'..name
    local start,finish=name..'Start',name..'End'
    Aim.paths[start]=FLYING_DIR..class..'.'..class..'_C:Received_PostStart'
    Aim.paths[finish]=FLYING_DIR..class..'.'..class..'_C:Received_Deactivate'
    FLYING[start]='start';FLYING[finish]='finish'
    ORDER[#ORDER+1]=start;ORDER[#ORDER+1]=finish
    LABEL[start]=name..'起飞';LABEL[finish]=name..'结束'
end
local UNHOOK_SECONDS,LINES,SUMMARY_SECONDS=10,12,10
Aim.paths.menghuaHit='/Script/SGameCombatSystem.BulletAttackModule:DealDamageToAvatar'
local DEPTH=8
local STEPS={'Pawn','BulletOwnerAvatar','Owner','Instigator','Source Ability'}
local UNLISTED_LINES,BULLET_LINES,FLIGHT_LINES,FLIGHT_PER_KIND=40,60,240,3
-- Particle bullets that aim through their effect: bullet data -> the effect's user switch and position.
local EFFECT_AIMS={BD_ZuoShang_Skill_19={use='UE_UseTestTargetPos',pos='UE_TestTargetPos',system='NS_ZuoShang_SwordShooting_001'}}
Aim.effectAims=EFFECT_AIMS
Aim.paths.launch='/PBZDeflectSystem/Actions/GAA_DelayDeflectProjectileBullet.GAA_DelayDeflectProjectileBullet_C:Go go go'
ORDER[#ORDER+1]='launch';LABEL.launch='特效目标'
local RAIN_END={rainFinished=true,rainDeactivated=true}
for _,entry in ipairs({{'rainFinished','OnParticleSystemFinished'},{'rainDeactivated','OnParticleDeactivated'}})do
    Aim.paths[entry[1]]='/Script/PBZCombatAsset.PBZ_ParticleBullet:'..entry[2]
    ORDER[#ORDER+1]=entry[1];LABEL[entry[1]]=entry[2]
end
local PARTICLE_CLASS,EFFECT_MS,EFFECT_SECONDS,READY,RUNNING='PBZ_ParticleBullet',50,15,1,2
-- Skill 19 launches five particle emitters at 0.62 s and its action ends at 3.97 s.
local RAIN_SCANS={[1]=true,[2]=true,[3]=true,[8]=true,[14]=true,[20]=true,[30]=true,[50]=true,[80]=true}
local RAIN_AGAIN=5        -- seconds within which a second start is the same cast (the skill runs 3.97 s, cools down 80 s)
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
ORDER[#ORDER+1]='skillStart';LABEL.skillStart='私有特效'
Aim.paths.iceSpawn=STATICS..'BeginDeferredActorSpawnFromClass'
ORDER[#ORDER+1]='iceSpawn';LABEL.iceSpawn='冰柱施法归属'
local ICE_CLASS='BP_QiShu_Bing_Icicle_C'
local ICE_SPAWNERS={BP_QiShu_Bing_IcicleSpawner_C=true,BP_Qishu_Bing_SpawnIcicle_C=true}
local ICE_CASTERS={BP_Monster_QiShu_Bing_C=true,BP_Monster_Scavenger_C=true,BP_Monster_Scavenger_P2_C=true}
local WARNING_SKILLS={GA_MBoss_Skill_02_C4_C=true,GA_HookMan_HorseCart_Skill_06_C=true}
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
    'GAA_ForcePlayerWalk_C',                                                              -- the shared "force the player to walk" action (SELF below)
    'BP_YuBi_CA02_Arena_C',                                                              -- boundary actor and ASC cache
    'BP_Bullet_LengTu_StickyWire_C',                                                     -- rope user skeletal-mesh target
    'BP_QiShu_Bing_Icicle_C',                                                            -- in-range frost victim comparison and application
})do AIMS[name]=true end
Aim.aims=AIMS
-- Actions that do something to "the player" as the one a boss performs for, not as a target: GAA_ForcePlayerWalk puts
-- the force-walk attitude and input-mode tags on GetPlayerCharacter when it begins and takes them off when it ends
-- (银发左殇's GA_ZuoShang_CA_01 uses it). Cast by one of this mod's units the real player must not be slowed, and the
-- opponent may change between the two calls and keep the tags; the caster itself stands in for both calls.
local SELF={GAA_ForcePlayerWalk_C=true}
Aim.self=SELF

local function addr(object)
    return U.key(object)
end
local function className(object)
    if not U.valid(object) then return '?' end
    local ok,class=pcall(function()return object:GetClass()end)
    if not ok or not U.valid(class) then return '?' end
    local named,name=pcall(function()return class:GetFName():ToString()end)
    return named and type(name)=='string' and name or '?'
end

function Aim.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local self={alive=true,state='idle',redirected=0,passed=0,message='没有进行中的战斗',counts={},window={}}
    for _,name in ipairs(ORDER)do self.counts[name]=0;self.window[name]=0 end
    self.counts.flying=0;self.window.flying=0
    local hooks={}
    local fighters={}     -- owned arena fighters and companions; stand sources cannot be targets
    local companions={}
    local teams={}
    local roster={}    -- unit address -> full object identity and flying-weapon capability
    local seenLines,lines={},0
    local quietSince,summaryAt,passedWindow=nil,nil,0
    local uninstallAt=0
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
    local retry=Retry.new({clock=clock,log=say})
    local flyingWanted=false
    local iceWanted=false
    local flyingClasses={}
    local iceClasses={}
    local function iceCaster(actor)
        local leaf=className(actor)
        if iceClasses[leaf]~=nil then return iceClasses[leaf]end
        local got,cls=pcall(function()return actor:GetClass()end)
        local found=false
        for _=1,16 do
            if not got or not U.valid(cls)then break end
            local named,name=pcall(function()return cls:GetFName():ToString()end)
            if named and ICE_CASTERS[name]then found=true;break end
            got,cls=pcall(function()return cls:GetSuperStruct()end)
        end
        iceClasses[leaf]=found;return found
    end
    local function flyingCaster(actor)
        local leaf=className(actor)
        if flyingClasses[leaf]~=nil then return flyingClasses[leaf] end
        local ok,cls=pcall(function()return actor:GetClass()end)
        if not ok or not U.valid(cls) then return false end
        local found=false
        for _=1,16 do
            if not U.valid(cls) then break end
            local named,name=pcall(function()return cls:GetFName():ToString()end)
            if named and CASTERS[name] then found=true;break end
            local got,parent=pcall(function()return cls:GetSuperStruct()end)
            cls=got and parent or nil
        end
        flyingClasses[leaf]=found
        return found
    end

    -- One step from an object toward the unit it acts for: an action's or ability's own avatar first (an action may
    -- be a shared template whose outer is its class), then the fields, then the outer.
    local function step(object)
        local cls=className(object)
        local getter=(cls:find('^GA_') or cls:find('^SubGA_')) and 'GetAvatarActorFromActorInfo'
            or (cls:find('^GAA_') or cls:find('^GAAction_') or cls:find('^LGAAction')) and 'GetAvatarActor'
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
        if not U.valid(object) then return nil end
        local okPlayer,player=pcall(function()return options.player and options.player()end)
        local playerKey=okPlayer and U.key(player)
        local current,visited=object,{}
        for _=1,DEPTH do
            local key=addr(current)
            if not key or key==playerKey or visited[key] then break end
            visited[key]=true
            if fighters[key] then return key end
            current=step(current)
            if not current then break end
        end
        return nil
    end
    local function opponentOf(key,castTarget,castName)
        if companions[key] then return options.companionTargetOf(companions[key],castTarget,castName)end
        return options.opponentOf(key)
    end
    -- A companion's enemy of a moment ago (companion_target.lua lastEnemy), for a skill lock taken while its AI
    -- target key is empty; nil for blue and red, whose opponent is the arena's.
    local function lastEnemyOf(key)
        if companions[key] and type(options.companionLastEnemyOf)=='function' then return options.companionLastEnemyOf(companions[key]) end
        return nil
    end
    local function isPlayerActor(actor)
        local ok,player=pcall(function()return options.player and options.player()end)
        return ok and U.valid(player) and addr(player)==addr(actor)
    end
    local function sameTeam(source,target)
        return source==target or teams[source]~=nil and teams[source]==teams[target]
    end
    function self:ownerOf(object)return unitOf(object)end
    function self:hasSources()return self.alive and next(fighters)~=nil end
    function self:targetOf(key)
        if not fighters[key] then return nil end
        local ok,target=pcall(opponentOf,key)
        return ok and U.valid(target) and target or nil
    end
    -- A native story pair owns its own targets until its scoped phase finishes.
    local phaseErrors=0
    local function phaseResult(ok,value)
        if not ok and phaseErrors<8 then
            phaseErrors=phaseErrors+1;say('阶段归属读回未确认，保留原生目标 '..tostring(value))
        end
        return not ok or value==true
    end
    local function phaseBusy(unit)
        if not unit then return false end
        if options.phaseBusyKey then
            local ok,value=pcall(options.phaseBusyKey,unit)
            return phaseResult(ok,value)
        end
        if not options.phaseBusy then return false end
        local ok,actor=pcall(function()return options.actorOf and options.actorOf(unit)end)
        if not ok or not U.valid(actor) then return true end
        local called,value=pcall(options.phaseBusy,actor)
        return phaseResult(called,value)
    end

    function self:canRedirect(key)return self.alive and fighters[key]~=nil and not phaseBusy(key)end
    local iceLines=0
    local function iceSpawn(_,context,actorClass,_,_,ownerParam)
        if not self.alive or not next(fighters) then return nil end
        local spawner=U.unwrap(context)
        if not ICE_SPAWNERS[className(spawner)] then return nil end
        local cls=U.unwrap(actorClass)
        if not U.valid(cls) then return nil end
        local named,name=pcall(function()return cls:GetFName():ToString()end)
        if not named or name~=ICE_CLASS or U.valid(U.unwrap(ownerParam)) then return nil end
        local kind=U.kind(ownerParam)
        if kind~='RemoteUnrealParam' and kind~='LocalUnrealParam' then return nil end
        local source=unitOf(U.field(spawner,'Source Ability'))
        if not source or phaseBusy(source) or options.paused and options.paused() then return nil end
        local got,actor=pcall(function()return options.actorOf and options.actorOf(source)end)
        local targeted,target=pcall(opponentOf,source)
        if not got or U.key(actor)~=source or not targeted or not U.valid(target) then return nil end
        if options.world then
            local known,world=pcall(options.world)
            if not known or not U.inWorld(spawner,world) or not U.inWorld(actor,world) then return nil end
        end
        local wrote=pcall(function()ownerParam:set(actor)end)
        local good=U.key(U.unwrap(ownerParam))==source
        if good then
            self.redirected=self.redirected+1
            self.counts.iceSpawn=self.counts.iceSpawn+1;self.window.iceSpawn=self.window.iceSpawn+1
        end
        if iceLines<8 then
            iceLines=iceLines+1
            say('冰柱延迟生成保留施法归属：源='..className(actor)..'；Owner参数写入='..tostring(wrote)..'；读回='..tostring(good))
        end
        return nil
    end
    -- A caller outside the list that acts for a fighting unit keeps the player; it is named once in the log, so a skill
    -- that still goes for the player can be found. A few tries per class, since the first object may act for nobody.
    local unlistedTries,unlistedLines={},0
    -- Set further down: a get-player call made by a sword-rain skill starts the search for its emitters as well.
    local rainByCall
    local function noteUnlisted(object,cls,name)
        local tries=unlistedTries[cls] or 0
        if tries>=3 or unlistedLines>=UNLISTED_LINES then return end
        unlistedTries[cls]=tries+1
        if unitOf(object) then
            unlistedTries[cls]=3;unlistedLines=unlistedLines+1
            say('没改写的取玩家调用 调用方='..cls..' 函数='..LABEL[name])
        end
    end
    local dragonReads=0
    local function callback(name)
        return function(_,context,index)
            if not self.alive then return nil end
            if name=='character' and options.boundaryCharacter then
                local answer=options.boundaryCharacter(context,index)
                if answer~=nil then return answer end
            end
            if not next(fighters) then return nil end
            local object=U.unwrap(context)
            if not U.valid(object) then return nil end
            local cls=className(object)
            if options.formationPlayerLookup and ((name=='character' and cls=='GA_HuaShan_Troop_Healing_C')
                or (name=='pawn' and cls=='GA_HuaShan_RedTroop_BigBro_Skill_08_01_C')) and U.unwrap(index)==0 then
                local answer=options.formationPlayerLookup(object)
                if answer~=nil then return answer end
            end
            local unit
            local warning=name=='pawn' and cls=='GAAction_ParticleOnPlayer_C'
            if warning then
                -- This shared action is redirected only for inspected offensive telegraphs.
                local got,ability=pcall(function()return object:GetAbility()end)
                ability=got and U.unwrap(ability) or nil
                if not U.valid(ability) or not WARNING_SKILLS[className(ability)] then return nil end
                local found,avatar=pcall(function()return object:GetAvatarActor()end)
                local key=found and U.key(U.unwrap(avatar))
                if key and fighters[key]==true then unit=key end
            else
                if cls~=probe and not aims(object,cls) then
                    if name=='pawn' and rainByCall then rainByCall(object,cls) end
                    noteUnlisted(object,cls,name);return nil
                end
                unit=unitOf(object)
            end
            if not unit or phaseBusy(unit) or (options.paused and options.paused()) then self.passed=self.passed+1;passedWindow=passedWindow+1;return nil end
            if SELF[cls] then
                local got,caster=pcall(function()return options.actorOf and options.actorOf(unit)end)
                if not got or not U.valid(caster) or U.key(caster)~=unit then self.passed=self.passed+1;passedWindow=passedWindow+1;return nil end
                self.redirected=self.redirected+1
                self.counts[name]=self.counts[name]+1;self.window[name]=self.window[name]+1
                if lines<LINES and not seenLines[name..cls] then
                    seenLines[name..cls]=true;lines=lines+1
                    say(string.format('改写 %s 调用方=%s → 施法者自己 %s（不作用于玩家） 累计=%d',LABEL[name],cls,className(caster),self.counts[name]))
                end
                return caster
            end
            local ok,target=pcall(opponentOf,unit)
            if not ok or not U.valid(target) then self.passed=self.passed+1;passedWindow=passedWindow+1;return nil end
            if warning and not U.npcPath(target) then return nil end
            if cls=='BP_ZuoShang_P2_DragonPillarBullet_C' and name=='pawn' and dragonReads<20 and className(target)=='BP_Monster_MoTian_C' then
                dragonReads=dragonReads+1
                local mesh=U.field(target,'Mesh')
                local animOk,anim=false,nil
                if U.valid(mesh) then animOk,anim=pcall(function()return mesh:GetAnimInstance()end) end
                local playing,montage=false,nil
                if animOk and U.valid(anim) then playing,montage=pcall(function()return anim:GetCurrentActiveMontage()end) end
                local asc=U.field(target,'AbilitySystemComponent')
                local function count(tag)
                    if not U.valid(asc) then return '?' end
                    local ok,n=pcall(function()return asc:GetGameplayTagCount({TagName=FName(tag)})end)
                    return ok and tonumber(U.unwrap(n)) or '?'
                end
                local identified,motion=false,nil
                if playing and U.valid(montage) then identified,motion=pcall(function()return montage:GetFullName()end) end
                say('龙柱起飞 魔渊实例='..tostring(U.key(target))..' 当前动作='..tostring(identified and motion or '无读回')
                    ..' 动作中='..count('Ability.Action')..' 破防='..count('CharacterState.Stand.Break'))
            end
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
        if not unit or phaseBusy(unit) or (options.paused and options.paused()) then self.passed=self.passed+1;passedWindow=passedWindow+1;return nil end
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
    local lockWrites=0
    function self:lockAbilityOf(actor)
        if not self.alive or not U.valid(actor) then return false end
        local ability=U.field(actor,'Source Ability')
        if not U.valid(ability) then return false end
        local unit=unitOf(ability)
        if not unit or phaseBusy(unit) then return false end
        local beforeLock=U.field(ability,'Lock Target')
        local before=beforeLock and U.struct(beforeLock,'Component')
        local okTarget,target=pcall(opponentOf,unit)
        local remembered=false
        if not okTarget or not U.valid(target) then
            -- A companion whose AI target key is empty at this moment: the enemy it was fighting just now, revalidated.
            okTarget,target=pcall(lastEnemyOf,unit)
            remembered=okTarget and U.valid(target)
        end
        if not okTarget or not U.valid(target) then
            local okOwner,owner=pcall(function()return before:GetOwner()end)
            say('招式锁定没改：'..className(ability)..' 没有对手；游戏自己选的锁定='
                ..(U.valid(before) and (okOwner and U.valid(owner) and (isPlayerActor(owner) and '玩家' or className(owner)) or '?') or '空'))
            return false
        end
        local root=U.field(target,'RootComponent')
        if not U.valid(root) then say('招式锁定没改：'..className(target)..' 没有根组件');return false end
        if addr(before)==addr(root) and U.field(ability,'Lock Target Selected')==true then return true end
        local beforeOwner=U.valid(before) and (function()local ok,o=pcall(function()return before:GetOwner()end);return ok and U.valid(o) and className(o) or '?' end)() or '空'
        local okSet,err=pcall(function()
            ability['Lock Target']={Component=root,SocketName=FName('None')}
            ability['Lock Target Selected']=true
        end)
        local lock=U.field(ability,'Lock Target')
        local back=lock and U.struct(lock,'Component')
        local good=addr(back)==addr(root) and U.field(ability,'Lock Target Selected')==true
        if lockWrites<LINES then
            lockWrites=lockWrites+1
            say(string.format('招式锁定 %s：原目标=%s -> %s%s 写入=%s%s 读回=%s',className(ability),beforeOwner,className(target),remembered and '（AI 目标暂时为空，用刚才的敌人）' or '',tostring(okSet),okSet and '' or '('..tostring(err)..')',good and '生效' or '没生效'))
        end
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
        if not okOwner or not U.valid(owner) then return nil end
        local onStand=fighters[U.key(owner)]=='stand'
        local unit=unitOf(ability)
        if not unit or phaseBusy(unit) or (options.paused and options.paused()) then return nil end
        local onAlly=sameTeam(unit,U.key(owner))
        if not onStand and not onAlly and not isPlayer(owner) then return nil end
        local okTarget,target=pcall(opponentOf,unit)
        if not okTarget or not U.valid(target) then okTarget,target=pcall(lastEnemyOf,unit) end
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
            say(string.format('招式的锁定落在%s，改成对手 招式=%s -> %s 写入=%s 返回值=%s 读回=%s 累计=%d',onStand and '替身' or onAlly and '友方' or '玩家',where,className(target),tostring(okSet),tostring(okOut),
                addr(back and U.struct(back,'Component'))==addr(root) and '生效' or '没生效',self.counts.lock))
        end
        return nil
    end

    -- Where a bullet gets its target: its data's selector, called natively (UBulletTargetSelectorBase.SelectTarget), which
    -- fills the Target out parameter. 左殇's flying swords hover (BulletMovementData_Rotation), home for 0.2 s toward that
    -- target, then fly straight, so it decides where they all go. A bullet of a fighting unit aimed at anything but another
    -- fighting unit goes to the unit's opponent, and each skill is named once with what it had, on the player or not.
    local bulletLines,bulletSeen=0,{}
    local function retarget(route,_,avatar,_,ability,_,_,out)
        if not self.alive or not next(fighters) then return nil end
        local owner=U.unwrap(avatar)
        if not U.valid(owner) then return nil end
        local key=U.key(owner)
        if not key or not fighters[key] or phaseBusy(key) or (options.paused and options.paused()) then return nil end
        local okTarget,target=pcall(opponentOf,key)
        if not okTarget or not U.valid(target) then
            okTarget,target=pcall(lastEnemyOf,key)
            if not okTarget then target=nil end
        end
        local current=out and U.unwrap(out)
        local comp=current and U.struct(current,'Component')
        local had='空'
        if U.valid(comp) then
            local okOwner,hit=pcall(function()return comp:GetOwner()end)
            if okOwner and U.valid(hit) then
                had=className(hit)
                local intended=companions[key] and U.key(target)
                if intended and U.key(hit)==intended then return nil end
                if companions[key] and not U.valid(target) and isPlayer(hit) then return false end
                if fighters[U.key(hit)]==true and not sameTeam(key,U.key(hit)) then
                    local where=U.valid(U.unwrap(ability)) and className(U.unwrap(ability)) or '?'
                    if not bulletSeen['ok'..where] and bulletLines<BULLET_LINES then
                        bulletSeen['ok'..where]=true;bulletLines=bulletLines+1
                        say('子弹目标 招式='..where..' 目标='..had..'（参战单位，不改）')
                    end
                    return nil
                end
            end
        end
        if not U.valid(target) then return nil end
        local root=U.field(target,'RootComponent')
        local wanted=U.key(root)
        if not wanted then return false end
        local function matches()
            return U.key(U.struct(U.unwrap(out),'Component'))==wanted
        end
        local okSet=pcall(function()out:set({Component=root,SocketName=FName('None')})end)
        local verified=matches()
        if not verified then
            local socket=U.unwrap(out)
            if U.kind(socket)=='UScriptStruct' and U.valid(root) then
                okSet=pcall(function()socket.Component=root;socket.SocketName=FName('None')end)
                verified=matches()
            end
        end
        if verified then
            self.redirected=self.redirected+1
            self.counts[route]=self.counts[route]+1;self.window[route]=self.window[route]+1
        end
        local where=U.valid(U.unwrap(ability)) and className(U.unwrap(ability)) or '?'
        local report=route..where..tostring(verified)
        if not bulletSeen[report] and bulletLines<BULLET_LINES then
            bulletSeen[report]=true;bulletLines=bulletLines+1
            say(string.format('子弹目标改成对手 招式=%s 原目标=%s -> %s 写入=%s 读回=%s 累计=%d',where,had,className(target),tostring(okSet),
                verified and '生效' or '失败，本次选敌作废',self.counts[route]))
        end
        return verified
    end

    -- Once a flying weapon starts: a target that is not a fighting unit becomes the opponent, on the bullet itself. When it
    -- ends: where it is against the player, its target and its caster, which says what it really flew at.
    local function place(actor)
        if not U.valid(actor) then return nil end
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
        if not key or not fighters[key] or phaseBusy(key) then return nil end
        local okTarget,target=pcall(opponentOf,key)
        target=okTarget and U.valid(target) and target or nil
        local _,hit=holderOf(bullet)
        local note=''
        if kind=='start' and target and not (hit and fighters[U.key(hit)]==true and not sameTeam(key,U.key(hit))) and not (options.paused and options.paused()) then
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
        local okWant,wanted=pcall(opponentOf,unit)
        probe=className(actor)
        local ok,got=pcall(function()return lib:GetPlayerCharacter(actor,0)end)
        probe=nil
        got=ok and U.unwrap(got) or nil
        local same=okWant and U.valid(wanted) and addr(got)==addr(wanted)
        say(string.format('自检（临时放行该单位的类）：以 %s 为上下文取玩家角色 → %s；应为对手 %s；改写生效=%s%s',className(actor),
            U.valid(got) and className(got) or '空',okWant and U.valid(wanted) and className(wanted) or '无',tostring(same),
            ok and '' or ' 错误='..tostring(got)))
    end

    local effects,rainSearch,effectLoop={},{},nil
    local effectGeneration,effectCancelAt=0,0
    local function nameOf(object)
        if not U.valid(object) then return '?'end
        local ok,name=pcall(function()return object:GetFName():ToString()end)
        return ok and type(name)=='string' and name or '?'
    end
    local function stopEffectLoop(force)
        if not effectLoop then return end
        if not force then
            if clock()<effectCancelAt then return end
            effectCancelAt=clock()+1
        end
        local ok,result=pcall(CancelDelayedAction,effectLoop)
        if ok and result~=false then effectLoop=nil;effectGeneration=effectGeneration+1;effectCancelAt=0 end
    end
    local function objectName(object)
        if not U.valid(object)then return nil end
        local ok,name=pcall(function()return object:GetFullName()end)
        return ok and type(name)=='string'and name or nil
    end
    local function effectCall(obj,method,...)
        if not U.valid(obj)then return nil end
        local args=table.pack(...);local ok,v=pcall(function()return obj[method](obj,table.unpack(args,1,args.n))end)
        if ok then return U.unwrap(v)end
    end
    local function effectAsset(comp,spec)
        local asset=U.field(comp,'Asset')
        if nameOf(asset)==spec.system then return asset end
        asset=effectCall(comp,'GetAsset')
        if nameOf(asset)==spec.system then return asset end
    end
    local function attached(comp,bullet)
        local key=U.key(bullet)
        if not key or not U.valid(comp) then return false end
        if U.key(effectCall(comp,'GetOwner'))==key then return true end
        local parent=effectCall(comp,'GetAttachParent')
        return U.valid(parent) and (U.key(parent)==U.key(U.field(bullet,'SceneRoot')) or U.key(effectCall(parent,'GetOwner'))==key)
    end
    local niagaraClass,niagaraRetryAt=nil,0
    local function componentClass()
        if U.valid(niagaraClass) then return niagaraClass end
        if clock()<niagaraRetryAt then return end
        niagaraRetryAt=clock()+3
        local ok,cls=pcall(StaticFindObject,'/Script/Niagara.NiagaraComponent')
        if ok and objectName(cls)=='Class /Script/Niagara.NiagaraComponent' then niagaraClass=cls;return cls end
    end
    local function particleComponent(bullet,spec,previous,unique,frame)
        local direct=U.field(bullet,'ParticleComponent')
        local asset=effectAsset(direct,spec)
        if asset then
            if attached(direct,bullet) then return direct,asset,'attached' end
            -- A world-pooled Niagara component need not have the projectile as its UObject owner.
            -- Require the projectile's live native slot, declared system and exclusive binding.
            local owner=U.field(bullet,'BulletOwnerAvatar')
            local source=U.field(bullet,'BulletSourceAbility');local data=U.field(bullet,'BulletData')
            local fxOwner=effectCall(direct,'GetOwner')
            local key,sourceKey=U.key(owner),U.key(source)
            if not frame.worldChecked then
                frame.worldChecked=true
                frame.world=options.world and options.world()
                frame.worldKey=U.key(frame.world)
            end
            local world=frame.world
            local binding=previous and previous.route=='pooled' and U.key(previous.comp)==U.key(direct)
                and previous.owner==key and (not sourceKey or previous.sourceKey==sourceKey) and previous.asset==U.key(asset)
                and previous.dataKey==U.key(data) and previous.worldKey==frame.worldKey and previous.compName==objectName(direct)
            if key and fighters[key] and U.key(U.field(data,'Particle'))==U.key(asset)
                and frame.worldKey and (binding or (U.inWorld(bullet,world) and U.inWorld(direct,world)))
                and effectCall(direct,'IsActive')==true
                and (not sourceKey or unitOf(source)==key)
                and (U.key(fxOwner)==key or (not U.valid(U.field(fxOwner,'AbilitySystemComponent')) and U.field(fxOwner,'BulletStatus')==nil))
                and hooks.rainFinished and hooks.rainDeactivated and (binding or unique and unique(direct,bullet)) then
                return direct,asset,'pooled'
            end
        end
        -- Read only the projectile's own component list, never search the world for an effect.
        if previous and previous.route=='actorList' then
            local component=previous.comp
            local system=effectAsset(component,spec)
            if system and U.key(system)==previous.asset and attached(component,bullet) and effectCall(component,'IsActive')==true then
                return component,system,'actorList'
            end
        end
        if not unique and not (previous and previous.route=='secondary') then
            return nil,nil,asset and 'ownership' or U.valid(direct) and 'system' or 'component'
        end
        local found,system,ambiguous
        local function consider(candidate)
            if not U.valid(candidate) or not attached(candidate,bullet) then return end
            local sys=effectAsset(candidate,spec)
            if sys then
                if found and U.key(found)~=U.key(candidate)then ambiguous=true end
                found,system=candidate,sys
            end
        end
        local instances=U.struct(U.field(bullet,'EffectInstanceData'),'InstanceData')
        if instances then pcall(function()instances:ForEach(function(_,row)
            for _,v in ipairs(U.array(U.struct(U.unwrap(row),'NiagaraComponents')) or {})do consider(v)end
        end)end) end
        local root=U.field(bullet,'SceneRoot')
        if U.valid(root) then for _,v in ipairs(U.array(U.field(root,'AttachChildren')) or {})do consider(v)end end
        if found and not ambiguous then return found,system,'secondary' end
        if not found and unique then
            local cls=componentClass()
            if cls then
                for _,candidate in ipairs(U.array(effectCall(bullet,'K2_GetComponentsByClass',cls)) or {})do
                    if effectCall(candidate,'IsActive')==true then consider(candidate)end
                end
                if found and not ambiguous then return found,system,'actorList' end
            end
        end
        return nil,nil,ambiguous and 'ambiguous' or asset and 'ownership' or U.valid(direct) and 'system' or 'component'
    end
    local function setVariable(comp,method,name,value)
        if not U.valid(comp)then return false end
        return pcall(function()comp[method](comp,FName(name),value)end)
    end
    local function statusOf(bullet)
        return U.valid(bullet) and U.unwrap(U.field(bullet,'BulletStatus')) or nil
    end
    -- What each search saw, kept on its request, so a volley that was never found says where it stopped.
    local function seen(request,field)request.seen=request.seen or {};request.seen[field]=(request.seen[field] or 0)+1 end
    local function poolSlots(frame,list)
        if frame.slots~=nil then return frame.slots end
        if not list then
            local ok,value=pcall(FindAllOf,PARTICLE_CLASS)
            if not ok or type(value)~='table' then frame.slots=false;return false end
            list=value
        end
        local slots={}
        for _,bullet in ipairs(list)do
            local status=statusOf(bullet)
            if status==RUNNING or status==READY then
                local id=U.key(U.field(bullet,'ParticleComponent'))
                if id then slots[id]=slots[id]==nil and U.key(bullet) or false end
            end
        end
        frame.slots=slots
        return slots
    end
    local function scanEffects(frame)
        local ok,list=pcall(FindAllOf,PARTICLE_CLASS)
        for _,request in pairs(rainSearch)do seen(request,'scans');if not ok or type(list)~='table' then seen(request,'empty') end end
        if not ok or type(list)~='table' then return end
        local function unique(comp,bullet)
            return poolSlots(frame,list)[U.key(comp)]==U.key(bullet)
        end
        -- Native pooling can move a still-live slot between two casts before a finish callback.
        for key,item in pairs(effects)do
            if item.route=='pooled' and not unique(item.comp,item.bullet) then
                effects[key]=nil
            end
        end
        for _,bullet in ipairs(list)do
            local key=addr(bullet)
            if key and not effects[key] then
                local status=statusOf(bullet)
                local mine=rainSearch[U.key(U.field(bullet,'BulletOwnerAvatar')) or '']
                if mine then seen(mine,'owned');if status==RUNNING or status==READY then seen(mine,'live')end end
                if status==RUNNING or status==READY then
                    local owner=U.field(bullet,'BulletOwnerAvatar')
                    local ownerKey=U.valid(owner) and U.key(owner)
                    local request=rainSearch[ownerKey]
                    if request then
                        local dataName=nameOf(U.field(bullet,'BulletData'))
                        local spec=EFFECT_AIMS[dataName]
                        if spec then seen(request,'data')else request.otherData=dataName end
                        if spec then
                            local comp,asset,route=particleComponent(bullet,spec,nil,unique,frame)
                            seen(request,comp and 'adopted' or route)
                            if not comp and not request.rejected then
                                local direct=U.field(bullet,'ParticleComponent')
                                local owner=effectCall(direct,'GetOwner')
                                request.rejected=' 首次拒绝='..route..' 组件='..nameOf(direct)..' 属主='..nameOf(owner)
                                    ..' 系统='..nameOf(U.field(direct,'Asset'))
                            end
                            if comp then
                                effects[key]={bullet=bullet,bulletKey=key,route=route,worldKey=frame.worldKey,sourceKey=U.key(U.field(bullet,'BulletSourceAbility')),dataKey=U.key(U.field(bullet,'BulletData')),comp=comp,compName=objectName(comp),asset=U.key(asset),owner=ownerKey,data=dataName,spec=spec,since=clock(),writes=0,cast=request}
                                request.left=request.left-1
                            end
                        end
                    end
                end
            end
        end
        for owner,request in pairs(rainSearch)do if request.left<=0 then rainSearch[owner]=nil end end
    end
    local effectLines=0
    local function sayEffect(text)
        if effectLines<BULLET_LINES then effectLines=effectLines+1;say(text) end
    end
    local releaseEffect
    local function castSpot(owner,cast,spots)
        if spots[cast]~=nil then return spots[cast] end
        local ok,target=pcall(opponentOf,owner,cast.target,cast.targetName)
        -- A companion whose AI target key is empty during the rain: the enemy it was fighting a moment ago.
        if not ok or not U.valid(target) then ok,target=pcall(lastEnemyOf,owner) end
        if not ok or not U.valid(target) then spots[cast]=false;return false end
        local at=place(target)
        local got,x,y,z=pcall(function()return at.X,at.Y,at.Z end)
        local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
        local result=false
        if got and finite(x)and finite(y)and finite(z)then
            if companions[owner] then cast.target,cast.targetName=target,objectName(target) end
            result={target=target,spot={X=x,Y=y,Z=z}}
        end
        spots[cast]=result
        return result
    end
    local function aimEffect(item,spots,frame)
        local owner=U.field(item.bullet,'BulletOwnerAvatar')
        local key=U.key(owner)
        local data=U.field(item.bullet,'BulletData')
        local dataName=U.valid(data) and nameOf(data) or nil
        if not key or not fighters[key] or not EFFECT_AIMS[dataName] then return false end
        if phaseBusy(key) then return false end
        local comp,asset,route=particleComponent(item.bullet,EFFECT_AIMS[dataName],item,nil,frame)
        if not comp then return false end
        -- Pooled bullets can change owner or component while their previous wrappers still look valid.
        local sourceKey=U.key(U.field(item.bullet,'BulletSourceAbility'))
        if item.owner~=key or item.dataKey~=U.key(data) or item.sourceKey~=sourceKey or item.asset~=U.key(asset) or addr(item.comp)~=addr(comp) then
            if item.switched then releaseEffect(item,frame) end
            if item.owner~=key or item.dataKey~=U.key(data) or item.sourceKey~=sourceKey then item.cast=rainSearch[key] or {} end
            item.owner,item.data,item.spec,item.comp=key,dataName,EFFECT_AIMS[dataName],comp
            item.route,item.sourceKey,item.dataKey,item.worldKey=route,sourceKey,U.key(data),frame.worldKey
            item.asset,item.compName=U.key(asset),objectName(comp)
            item.switched=nil;item.since=clock();item.writes=0
            sayEffect('刷新特效归属 读回施法者='..key..' 组件='..tostring(addr(comp))..' 数据='..dataName)
        end
        local aim=castSpot(item.owner,item.cast,spots)
        if not aim then
            if not item.noTarget then item.noTarget=true;sayEffect('特效目标没改 子弹='..tostring(item.data)..'：此刻读不到施法者的对手，保持游戏自己的目标') end
            return
        end
        local target,spot=aim.target,aim.spot
        -- Which of the two the effect declared cannot be read offline; setting the other only adds an unused value.
        local okPosition=setVariable(item.comp,'SetVariablePosition',item.spec.pos,spot)
        local okVector=setVariable(item.comp,'SetVariableVec3',item.spec.pos,spot)
        if not okPosition and not okVector then return end
        item.writes=item.writes+1
        if not item.switched then
            local okUse=setVariable(item.comp,'SetVariableBool',item.spec.use,true)
            item.switched=okUse
            if not okUse then return end
            self.redirected=self.redirected+1
            self.counts.launch=self.counts.launch+1;self.window.launch=self.window.launch+1
            local okPlayer,player=pcall(function()return options.player and options.player()end)
            local from=place(item.bullet)
            sayEffect(string.format('特效目标改成对手 子弹=%s 招式=%s 对手=%s 开关=%s 写入=%s 坐标写入=%s/%s 发射点距对手=%s 距玩家=%s',item.data,
                U.valid(U.field(item.bullet,'BulletSourceAbility')) and className(U.field(item.bullet,'BulletSourceAbility')) or '?',
                className(target),item.spec.use,tostring(okUse),tostring(okPosition),tostring(okVector),metres(from,spot),
                okPlayer and U.valid(player) and metres(from,place(player)) or '?'))
        end
    end
    releaseEffect=function(item,frame)
        if not item.switched then return end
        local ok=false
        if U.valid(item.comp)and objectName(item.comp)==item.compName then
            local asset=effectAsset(item.comp,item.spec)
            local pooled=item.route=='pooled' and options.world and U.key(options.world())==item.worldKey
                and U.key(U.field(item.bullet,'ParticleComponent'))==U.key(item.comp)
                and U.key(U.field(item.bullet,'BulletOwnerAvatar'))==item.owner
                and (not U.valid(U.field(item.bullet,'BulletSourceAbility')) or U.key(U.field(item.bullet,'BulletSourceAbility'))==item.sourceKey)
                and U.key(U.field(item.bullet,'BulletData'))==item.dataKey
            if pooled then
                local slots=poolSlots(frame or {})
                local id=U.key(item.comp)
                pooled=slots and (slots[id]==nil or slots[id]==U.key(item.bullet))
            end
            if ((item.route~='pooled' and attached(item.comp,item.bullet)) or pooled) and U.key(asset)==item.asset then
                ok=setVariable(item.comp,'SetVariableBool',item.spec.use,false)
            end
        end
        sayEffect(string.format('特效目标还原 子弹=%s 跟随对手写入=%d次 关开关=%s',item.data,item.writes,tostring(ok==true)))
    end
    local function retireParticle(context,parameter)
        if not self.alive or not next(effects) then return end
        local thread=options.inGameThread or IsInGameThread
        if type(thread)=='function' and not thread() then return end
        local bullet,comp=U.unwrap(context),U.unwrap(parameter);local key=U.key(bullet)
        local item=key and effects[key]
        if item and U.key(comp)==U.key(item.comp) then effects[key]=nil;releaseEffect(item) end
    end
    local function effectTick()
        if not self.alive then stopEffectLoop();return end
        local search=false
        for owner,request in pairs(rainSearch)do
            request.tick=request.tick+1
            if not fighters[owner] or phaseBusy(owner) or request.tick>80 then
                -- A cast whose emitters were not all found: what the searches saw (the rain then keeps the game's own target).
                if request.cast and request.left>0 then
                    local s=request.seen or {}
                    sayEffect(string.format('剑雨发射器没找全：还差%d个；搜索%d轮（读不到列表%d轮） 属于施法者的特效子弹=%d 其中在运行=%d 数据对得上=%d 组件对得上=%d 缺组件=%d 系统不符=%d 归属不符=%d 多组件=%d%s%s%s',
                        request.left,s.scans or 0,s.empty or 0,s.owned or 0,s.live or 0,s.data or 0,s.adopted or 0,s.component or 0,s.system or 0,s.ownership or 0,s.ambiguous or 0,request.rejected or '',
                        request.otherData and(' 见到别的数据='..tostring(request.otherData))or'',
                        not fighters[owner] and' 施法者已不在名单'or phaseBusy(owner)and' 施法者在转阶段'or''))
                end
                rainSearch[owner]=nil
            elseif RAIN_SCANS[request.tick] then search=true end
        end
        local frame={}
        if search then scanEffects(frame) end
        local now,spots=clock(),{}
        local paused=options.paused and options.paused()
        for key,item in pairs(effects)do
            local status=statusOf(item.bullet)
            if (status==RUNNING or status==READY) and now-item.since<EFFECT_SECONDS then
                local owner=U.key(U.field(item.bullet,'BulletOwnerAvatar'))
                if not fighters[owner] or phaseBusy(owner) or paused and owner~=item.owner or not paused and aimEffect(item,spots,frame)==false then
                    releaseEffect(item,frame);effects[key]=nil
                end
            else
                releaseEffect(item,frame);effects[key]=nil
            end
        end
        if not next(rainSearch) and not next(effects) then stopEffectLoop() end
    end
    local register
    local function watchRain(unit,cast)
        local request=rainSearch[unit]
        if cast then rainSearch[unit]={tick=0,left=5,cast=true}
        elseif request then
            request.tick=0
            if not request.cast then request.left=request.left+1 end
        else rainSearch[unit]={tick=0,left=1} end
        local volley=rainSearch[unit]
        if companions[unit] and not volley.target then
            local target=self:targetOf(unit)
            volley.target,volley.targetName=target,objectName(target)
        end
        register('rainFinished');register('rainDeactivated')
        if not effectLoop then
            effectGeneration=effectGeneration+1;local generation=effectGeneration
            local ok,handle=pcall(LoopInGameThreadWithDelay,EFFECT_MS,function()
                if generation==effectGeneration and self.alive then effectTick()end
            end)
            if ok and handle~=nil and handle~=false then effectLoop=handle
            else effectGeneration=effectGeneration+1;rainSearch={};say('特效目标循环启动失败：'..tostring(handle)) end
        end
    end
    local function launched(context)
        if not self.alive or not next(fighters) then return end
        local action=U.unwrap(context)
        if not EFFECT_AIMS[nameOf(U.field(action,'Bullet Data'))] then return end
        local unit=unitOf(action)
        if unit and not phaseBusy(unit) then watchRain(unit,false) end
    end

    local effectSkillClass={} -- class name -> whether it or a parent is in EFFECT_SKILLS
    local function skillKind(ability,name)
        if effectSkillClass[name]==nil then
            -- A skill's subclasses play the same effect (GA_ZuoShang_P2_Skill_17_NoCD, ..._Sword_2Hit_A_FastCancel).
            local found=false
            local okClass,class=pcall(function()return ability:GetClass()end)
            for _=1,8 do
                if not okClass or not U.valid(class) then break end
                local okName,parent=pcall(function()return class:GetFName():ToString()end)
                if okName and parent=='GA_ZuoShang_Skill_19_C' then found='rain';break end
                if okName and EFFECT_SKILLS[parent] then found=true;break end
                okClass,class=pcall(function()return class:GetSuperStruct()end)
            end
            effectSkillClass[name]=found
        end
        return effectSkillClass[name]
    end
    -- One cast of the rain, whichever of its two starts is seen first: the skill's own activation (a blueprint hook on
    -- the base class's K2_ActivateAbility) or the first GetPlayerPawn the skill makes (a native hook, seen in a
    -- tester's log for this very skill while no emitter was ever found). RAIN_AGAIN keeps one cast from starting twice.
    local rainStarted={}
    local function startRain(unit,name,how)
        local now=clock()
        if rainSearch[unit] and rainSearch[unit].cast and rainStarted[unit] and now-rainStarted[unit]<RAIN_AGAIN then return end
        rainStarted[unit]=now
        watchRain(unit,true)
        local volley=rainSearch[unit]
        sayEffect('剑雨起手（'..how..'） 招式='..name..' 施法者是随从='..tostring(companions[unit]~=nil)..' 记下的敌人='..(volley and U.valid(volley.target) and className(volley.target) or '无'))
    end
    rainByCall=function(object,cls)
        if not cls:find('^GA_') or skillKind(object,cls)~='rain' then return end
        local unit=unitOf(object)
        if unit and not phaseBusy(unit) and not(rainStarted[unit] and clock()-rainStarted[unit]<RAIN_AGAIN) then startRain(unit,cls,'取玩家调用') end
    end
    local function skillStarted(context)
        if not self.alive or not next(fighters) then return nil end
        local ability=U.unwrap(context)
        if not U.valid(ability) then return nil end
        local name=className(ability)
        if options.formationCast and (name=='GA_HuaShan_Story_Intro_C' or name=='GA_HuaShan_Troop_Healing_C'
            or name=='GA_HuaShan_Troop_Resurrection_C') then options.formationCast(ability,name) end
        local kind=skillKind(ability,name)
        if not kind then return nil end
        local unit=unitOf(ability)
        if not unit or phaseBusy(unit) then return nil end
        if kind=='rain' then startRain(unit,name,'招式起手')
        elseif self.effects then
            self.effects:arm()
            self.counts.skillStart=self.counts.skillStart+1;self.window.skillStart=self.window.skillStart+1
        end
        return nil
    end

    -- Native damage dispatch is synchronous. Keep only the outer pair when identical calls nest.
    local menghuaHits,pendingHits,removeHitAt=false,{},0
    local function sampleHit(post,module,...)
        if not self.alive or not menghuaHits then return end
        local thread=options.inGameThread or IsInGameThread
        if type(thread)~='function' then return end
        local checked,onThread=pcall(thread)
        if not checked or onThread~=true then return end
        local n=select('#',...)
        if n~=5 and not (post and n==6) then return end
        module=U.unwrap(module)
        local owner=U.field(module,'LastOwnerAvatar')
        local caster=U.key(owner)
        local entry=caster and roster[caster]
        if not entry or not entry.hitKinds or not companions[caster] then return end
        local target=U.unwrap(select(n==6 and 2 or 1,...))
        local moduleKey,targetKey=U.key(module),U.key(target)
        if not moduleKey or not targetKey then return end
        local key=moduleKey..'/'..caster..'/'..targetKey
        local sample=pendingHits[key]
        if post then
            if not sample then return end
            sample.depth=sample.depth-1
            if sample.depth>0 then return end
            pendingHits[key]=nil
            if sample.nested or sample.entry~=entry then return end
            local after=options.hp(target)
            say('梦华随从弹体伤害调用 弹体='..sample.data..' 施法者='..caster..' 受击者='..sample.target
                ..'('..targetKey..') HP='..tostring(sample.hp)..' -> '..tostring(after))
            return
        end
        if sample then sample.depth=sample.depth+1;sample.nested=true;return end
        if entry.hitCount>=48 then return end
        local data=nameOf(U.field(module,'BulletData'))
        local receiver=className(target)
        local kind=data..'/'..receiver
        local count=entry.hitKinds[kind] or 0
        if count>=2 then return end
        entry.hitCount=entry.hitCount+1;entry.hitKinds[kind]=count+1
        pendingHits[key]={entry=entry,data=data,target=receiver,hp=options.hp(target),depth=1}
    end
    local function syncHitProbe(now)
        local name='menghuaHit'
        local path=Aim.paths[name]
        pendingHits={}
        if menghuaHits and not hooks[name] and retry:ready(path) then
            local ok,pre,post=pcall(RegisterHook,path,function(...)sampleHit(false,...)end,function(...)sampleHit(true,...)end)
            local installed=ok and type(pre)=='number' and type(post)=='number'
            retry:result(path,installed)
            if installed then hooks[name]={pre=pre,post=post} end
        elseif not menghuaHits and hooks[name] and now>=removeHitAt then
            removeHitAt=now+1
            local h=hooks[name];local ok,result=pcall(UnregisterHook,path,h.pre,h.post)
            if ok and result~=false then hooks[name]=nil end
        end
    end

    -- A blueprint that is not loaded yet (a selector comes in with the first bullet data) is tried again while the fight runs.
    local function needed(name)
        return next(fighters)~=nil and not hooks[name] and (not FLYING[name] or flyingWanted)
            and (name~='iceSpawn' or iceWanted) and (not RAIN_END[name] or next(rainSearch) or next(effects))
    end
    register=function(name)
        if not needed(name) then return end
        local path=Aim.paths[name]
        if not retry:ready(path) then return end
        local okFind,found=pcall(StaticFindObject,path)
        retry:result(path,okFind and U.valid(found))
        if not okFind or not U.valid(found) then
            return
        end
        local handler=name=='force' and forced or name=='lock' and relock
            or (name=='bullet' or name=='bulletAbility') and function(...)return retarget(name,...)end
            or name=='launch' and launched or name=='skillStart' and skillStarted
            or RAIN_END[name] and retireParticle or name=='iceSpawn' and iceSpawn
            or FLYING[name] and function(context)
                self.counts[name]=self.counts[name]+1;self.window[name]=self.window[name]+1
                return flight(FLYING[name],context)
            end or callback(name)
        local ok,pre,post=pcall(RegisterHook,path,handler,function()end)
        if ok and type(pre)=='number' and type(post)=='number' then
            hooks[name]={pre=pre,post=post};say('挂钩注册ID读回 '..name..' pre='..pre..' post='..post)
        else retry:result(path..':register',false,tostring(pre))end
    end
    local function install()
        for _,fn in ipairs({'StaticFindObject','RegisterHook','UnregisterHook'})do
            if type(_G[fn])~='function' then self.state='failed';self.message='缺少 '..fn;say(self.message);return end
        end
        for _,name in ipairs(ORDER)do register(name) end
        if next(hooks) then
            self.state='running';self.message='参战单位与随从的攻击取当前敌人'
            selfCheck()
        else self.state='failed';self.message='取玩家函数挂钩失败' end
    end
    local function uninstall(reason,force,restore)
        if not next(hooks) and not effectLoop and not next(effects) then return end
        if not force then
            if clock()<uninstallAt then return end
            uninstallAt=clock()+1
        end
        stopEffectLoop(force);rainSearch={}
        local frame={}
        for key,item in pairs(effects)do
            if restore~=false then releaseEffect(item,frame) end
            effects[key]=nil
        end
        local kept={}
        for name,hook in pairs(hooks)do
            local ok,result=pcall(UnregisterHook,Aim.paths[name],hook.pre,hook.post)
            if not ok or result==false then kept[name]=hook end
        end
        local parts={}
        for _,name in ipairs(ORDER)do parts[#parts+1]=LABEL[name]..'='..self.counts[name] end
        parts[#parts+1]=LABEL.flying..'='..self.counts.flying
        say('摘除挂钩（'..reason..'） 改写 '..table.concat(parts,' ')..' 其他调用照旧='..self.passed..' 摘除失败='..tostring(next(kept)~=nil))
        hooks=kept
        if not next(hooks) then self.state='idle';self.message='没有需要适配的攻击单位';uninstallAt=0 end
    end

    function self:tick()
        if not self.alive then return end
        local now=clock()
        local units,current,added={},{},false
        flyingWanted=false
        iceWanted=false
        menghuaHits=false
        local members=options.members()
        if options.prepareMembers then options.prepareMembers(members)end
        companions={}
        teams={}
        local fighting=options.fighting()
            for _,member in ipairs(members)do
                local companion=member.team=='companion' and type(options.companionTargetOf)=='function'
                if (companion or fighting and (member.team=='blue' or member.team=='red')) and (not member.reserve or member.stand) then
                    local key=U.key(member.actor)
                    -- A stand can cast a skill, but cannot be the opponent a skill aims at.
                    if key then
                        units[key]=member.stand and 'stand' or true
                        teams[key]=member.team
                        if companion and not member.stand then companions[key]=member.actor end
                        local named,identity=pcall(function()return member.actor:GetFullName()end)
                        identity=named and type(identity)=='string'and identity or nil
                        local entry=roster[key]
                        if not identity or not entry or entry.name~=identity then
                            if not entry or identity and entry.name~=identity then added=true end
                            entry={name=identity,flying=flyingCaster(member.actor),ice=iceCaster(member.actor)}
                        end
                        local caster=entry.flying
                        if companion and options.hp and type(member.class_path)=='string'
                            and member.class_path:match('%.BP_Monster_MengHua_C$') then
                            entry.hitKinds=entry.hitKinds or {};entry.hitCount=entry.hitCount or 0
                            if entry.hitCount<48 then menghuaHits=true end
                        end
                        current[key]=entry
                        if caster then flyingWanted=true end
                        if entry.ice then iceWanted=true end
                    end
                end
            end
        roster=current
        fighters=units
        if added then retry:reset() end
        if next(fighters) then
            quietSince=nil
            if not next(hooks) and self.state~='failed' then install()
            else
                for _,name in ipairs(ORDER)do register(name) end
            end
        elseif options.boundaryPending and options.boundaryPending() then
            quietSince=nil -- A companion's native field can finish after the roster changes.
        elseif next(hooks) then
            quietSince=quietSince or now
            if now-quietSince>=UNHOOK_SECONDS then uninstall('战斗已结束') end
        end
        if menghuaHits or hooks.menghuaHit then syncHitProbe(now) end
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
    function self:silence(reason,onGameThread)self.alive=false;uninstall(reason or 'Mod卸载',true,onGameThread==true)end
    return self
end
return Aim
