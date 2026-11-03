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
local U=require('ue_observe')
local Aim={}
local STATICS='/Script/Engine.GameplayStatics:'
Aim.paths={character=STATICS..'GetPlayerCharacter',pawn=STATICS..'GetPlayerPawn'}
local ORDER={'character','pawn'}
local LABEL={character='取玩家角色',pawn='取玩家Pawn'}
local UNHOOK_SECONDS,LINES,SUMMARY_SECONDS=10,12,10
local CACHE_SECONDS,DEPTH=20,8
local STEPS={'Pawn','BulletOwnerAvatar','Owner','Instigator'}
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

    local function callback(name)
        return function(_,context)
            if not self.alive or not next(fighters) then return nil end
            local object=U.unwrap(context)
            if not U.valid(object) then return nil end
            local cls=className(object)
            if cls~=probe and not aims(object,cls) then return nil end
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

    local function install()
        for _,fn in ipairs({'StaticFindObject','RegisterHook','UnregisterHook'})do
            if type(_G[fn])~='function' then self.state='failed';self.message='缺少 '..fn;say(self.message);return end
        end
        for _,name in ipairs(ORDER)do
            local path=Aim.paths[name]
            local okFind,found=pcall(StaticFindObject,path)
            if not okFind or not U.valid(found) then say('找不到函数 '..path)
            else
                local ok,pre,post=pcall(RegisterHook,path,callback(name),function()end)
                if ok and type(pre)=='number' and type(post)=='number' then
                    hooks[name]={pre=pre,post=post};say('挂钩注册ID读回 '..name..' pre='..pre..' post='..post)
                else say('挂钩注册失败 '..name..'：'..tostring(pre))end
            end
        end
        if next(hooks) then
            self.state='running';self.message='战斗中，参战单位的招式取玩家时拿到的是它的对手'
            selfCheck()
        else self.state='failed';self.message='取玩家函数挂钩失败' end
    end
    local function uninstall(reason)
        if not next(hooks) then return end
        local kept={}
        for name,hook in pairs(hooks)do
            if not pcall(UnregisterHook,Aim.paths[name],hook.pre,hook.post) then kept[name]=hook end
        end
        local parts={}
        for _,name in ipairs(ORDER)do parts[#parts+1]=LABEL[name]..'='..self.counts[name] end
        say('摘除挂钩（'..reason..'） 改写 '..table.concat(parts,' ')..' 其他调用照旧='..self.passed..' 摘除失败='..tostring(next(kept)~=nil))
        hooks=kept
        if not next(hooks) then self.state='idle';self.message='没有进行中的战斗' end
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
            if not next(hooks) and self.state~='failed' then install() end
        elseif next(hooks) then
            quietSince=quietSince or now
            if now-quietSince>=UNHOOK_SECONDS then uninstall('战斗已结束') end
        end
        summaryAt=summaryAt or now
        if now-summaryAt>=SUMMARY_SECONDS then
            if next(hooks) then
                local parts={}
                for _,name in ipairs(ORDER)do parts[#parts+1]=LABEL[name]..'='..self.window[name];self.window[name]=0 end
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
