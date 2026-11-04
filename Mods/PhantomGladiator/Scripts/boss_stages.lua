-- Bosses whose abilities look up the actors of their own arena by class (GameplayStatics.GetActorOfClass): a spot
-- to warp to for a special move, where a round of summons comes out, a centre their AI walks to. Those actors
-- stand only in the boss's own map; summoned anywhere else nothing was found and the ability took the world
-- origin instead: 冷荼's first round came out there and died at once and her fight stopped, and a warp aimed there sends the boss off toward it. The abilities and maps were read
-- offline from the game files.
-- Before such a boss starts, the mod puts the same actors around it as they stand around its spawner in its own
-- map: x forward and y right of it in cm, z over the ground found by a trace at that spot. They are markers only
-- (arrows, and a sphere or a text hidden in game; 献祭之蛇's centre also registers itself as her targeting spot;
-- 左殇's house is a building, placed with its mesh hidden); their collision goes off so nothing stands in the arena. The set faces the player, the way a boss waits for
-- whoever comes into its arena.
-- 冷荼 (BP_Monster_LengTu) also fights in phases: five rounds of summons, then herself. While she carries the
-- game's own "cannot be hated" marks she is out of reach by design: the arena sends nobody at her (untargetable).
-- Her phase marks are read every second and their changes logged.
local U=require('ue_observe')
local Stages={}
local MOBS='/PBZCombatAsset/ActorData/Mobs/'
local LENGTU='CharacterState.AbilityState.LengTu.'
-- Per boss: each marker's package and where it stands from the boss's spawner (yaw relative to the spawner's).
local STAGES={
    BP_Monster_LengTu={label='冷荼',base=MOBS..'077_LengTu/',
        props={
            {name='BP_LengTu_SummonSlot_01',x=-163,y=-252,z=0,yaw=10},           -- round 1 (清道夫)
            {name='BP_LengTu_SummonSlot_02',x=149,y=411,z=0,yaw=-10},            -- round 2 on
            {name='BP_LengTu_SummonSlot_03',x=289,y=-965,z=0,yaw=25},
            {name='BP_LengTu_FriendlySummonSlot_01',x=1216,y=-63,z=0,yaw=-172.6},
            {name='BP_LengTu_ToBattle_SnapPoint',x=-338,y=-316,z=95,yaw=5},      -- 95 cm over her spawner
            {name='BP_LengTu_SwitchPhase_SnapPoint',x=-2213,y=-871,z=95,yaw=12.7}, -- on a ledge 3.3 m up there; its own floor here
        },
        tags={LENGTU..'Phase.P1',LENGTU..'Phase.P2',LENGTU..'Phase.P3',LENGTU..'Phase.P4',LENGTU..'Phase.P5',
            LENGTU..'Phase.Final',LENGTU..'IsInvulnerable',LENGTU..'OffCombat',LENGTU..'EnableMetaAI',LENGTU..'LeiDang',
            LENGTU..'FinishedQuest',LENGTU..'FirstTimeSummon','AI.Hatred.CanNotBeHatred','AI.Hatred.IgnoreByNPC',
            'CharacterState.Unselectable.Force.Perform'},
        untargetable={'AI.Hatred.CanNotBeHatred','CharacterState.Unselectable.Force.Perform'},
        -- Her checkpoints (Save.P2..P4, written by BP_Monster_LengTu.UnlockTag, read in InitTags at BeginPlay) are kept
        -- in the save under her "Actor ID". The class default LengTu_Combat is the one her own fight in 断魂山 uses (its
        -- spawner sets none): a summoned 冷荼 moved the player's checkpoint (to P4). She gets the
        -- mod's own ID instead, cleared before she reads it so every fight starts at P1.
        saveId='PhantomGladiator_LengTu'},
    -- Warp targets of special moves (MotionWarping, the marker's Arrow): 玉瓒 GA_YuZan_CA_P1/P2 and her black hole,
    -- 独眼弓客 GA_DuYan_Skill_02_Snap, 献祭之蛇 GA_ChiLian_P2_CA_03, 烟千岁 GA_YanQianSui_Skill_01, 左殇 GA_ZuoShang_CA_02,
    -- CA_03 (up to the snap point, down to the landing point) and CA_GEd_01 (domain centre).
    BP_Monster_FemaleVessel_YuZan={label='玉瓒',base=MOBS..'068_YuZan/',
        props={{name='BP_YuZan_CA_Snap_Center',x=37,y=-232,z=1,yaw=14.7}}},
    -- His ground-eye bullets (BP_Bullet_EyeActor_02..04) start at the eye of their number; eye 01 has no position in his map.
    BP_Monster_DuYanBoss={label='独眼弓客',base=MOBS..'059_DuYan/',
        props={{name='BP_DuYan_CA_Snap_Center',x=464,y=-207,z=114,yaw=78.5},
            {name='BP_GroundEye_02',dir='WeaponData/Burst/Ground/',x=-1073,y=-2312,z=115,yaw=78.5},
            {name='BP_GroundEye_03',dir='WeaponData/Burst/Ground/',x=-345,y=9,z=75,yaw=78.5},
            {name='BP_GroundEye_04',dir='WeaponData/Burst/Ground/',x=2290,y=524,z=115,yaw=78.5}}},
    BP_Monster_ChiLian_P2={label='献祭之蛇',base=MOBS..'065_ChiLian_P2/',
        props={{name='BP_ChiLian_P2_Center',x=38,y=-1224,z=9,yaw=-119.6}}},
    BP_Monster_YanQianSui={label='烟千岁',base=MOBS..'073_YanQianSui/',
        props={{name='BP_YanQianSui_SnapPoint',x=732,y=203,z=182,yaw=15}}},
    -- His grab GA_ZuoShang_CA_GEx_01 calls the house's PlayAnim: the house plays its collapse and a roof-cut effect
    -- comes out at its Arrow (24 m ahead of it, 10 m up). In his map it is a whole building; here its mesh is hidden
    -- and it does not collide, so only the effect shows. It leaves with him.
    BP_Monster_ZuoShang={label='左殇',base=MOBS..'054_ZuoShang/',
        props={{name='BP_ZuoShang_CA_02_SnapPoint',x=-1104,y=79,z=743,yaw=-0.5},
            {name='BP_ZuoShang_CA_03_SnapPoint',x=-1683,y=77,z=1392,yaw=0.4},
            {name='BP_ZuoShang_CA_03_DomainCenter',x=463,y=202,z=-2,yaw=-175},
            {name='BP_ZuoShang_House',dir='House/',x=594,y=134,z=0,yaw=-175,hide={'ZhuLinGuWu_Break'}}},
        groups={weapons={label='地面武器',tag='Targeting.Target.ZuoshangSword',reveal='StaticMesh',
            revealOn=MOBS..'054_ZuoShang/Bullet/BP_ZuoShang_GroundWeapon_Base.BP_ZuoShang_GroundWeapon_Base_C:FlyUp'}}},
    BP_Monster_ZuoShang_Ending={label='左殇（银发）',base=MOBS..'054_ZuoShang/',
        props={{name='BP_ZuoShang_House',dir='House/',x=55,y=102,z=0,yaw=-175,hide={'ZhuLinGuWu_Break'}}}},
    BP_Monster_ZuoShang_P2={label='龙体左殇',base=MOBS..'054_ZuoShang/',
        props={{name='BP_ZuoShang_CA_03_LandingPoint',x=275,y=-18,z=0,yaw=0},
            {name='BP_ZuoShang_CA_03_SnapPoint',x=-1459,y=-18,z=1402,yaw=0}}},
    -- 火流星 GA_GuiChai_Red_Passive_Summon: his twin blades come out at the two summon points, warp in to the snap
    -- points (GA_GuiChai_Black_TwinBlade_Summon_Intro_01_New) and his AI's base is the summon base.
    BP_Monster_GuiChai_Red={label='火流星',base=MOBS..'069_GuiChai_Red/Setup/',
        props={{name='BP_Monster_GuiChai_Red_SnapPoint_01',x=579,y=-29,z=0,yaw=85.6},
            {name='BP_Monster_GuiChai_Red_SnapPoint_02',x=974,y=10,z=0,yaw=-90.7},
            {name='BP_Monster_GuiChai_Red_SummonBase',x=721,y=-27,z=0,yaw=-6.3},
            {name='BP_Monster_GuiChai_Red_SummonPoint_01',x=504,y=-281,z=0,yaw=87},
            {name='BP_Monster_GuiChai_Red_SummonPoint_02',x=925,y=248,z=3,yaw=-94.2}}},
    -- The centre their AI is given as its base (blackboard AssignBaseActor) for a special move.
    BP_Monster_CanQu_BiHai={label='碧海大师残躯',base=MOBS..'CanQu_BiHai/Ability/Passive/',
        props={{name='BP_Monster_CanQu_BiHai_ToCenter',x=631,y=202,z=23,yaw=-5.7}}},
    BP_Monster_Danghui={label='荡秽',base=MOBS..'DangHui/Ability/Passive/',
        props={{name='BP_Monster_DangHui_ToCenter',x=-600,y=95,z=116,yaw=-2}}},
    BP_Monster_WuXuan={label='武轩',base=MOBS..'JiangJun/Ability/WuXuan/Passive/',
        props={{name='BP_Monster_WuXuan_CAToCenter',x=1078,y=-59,z=26,yaw=10.9}}},
}
-- 左殇's ground weapons: 42 swords, hammers and clubs stuck in the ground around his spawner in 竹林古屋
-- (/Game/Maps/B01/PBZ_WP_ZhuLinGuWu). Each registers itself on BeginPlay as a Targeting.Target.ZuoshangSword target;
-- his phase move GA_ZuoShang_CA_02 takes every one of those, and each rises, turns to the player and fires a sword
-- bullet as 左殇 (BulletData.CreateBullet with his avatar), then destroys itself. Without them the move only
-- played its show. Placed at x/y from his spawner, on the ground (their height differences there are
-- the slope of his arena), with their full tilt as a quaternion in his spawner's frame, registered but unseen: the
-- arena is not his and they do not collide, so standing there they were walked through. Each one shows as the move
-- picks it up (a hook on FlyUp shows its StaticMesh and the effect under it). Their Owner
-- is 左殇, so their turn to "the player" finds him and gets his opponent (player_aim.lua).
local WEAPON='BP_ZuoShang_GroundWeapon_Base'
for i,w in ipairs({
        {'Club',-563,555,0.8339,-0.057,-0.5222,0.1694},
        {'Club',-460,-795,0.0351,-0.0609,-0.5673,-0.8205},
        {'Club',-436,-420,0.7486,-0.0858,-0.6364,0.1649},
        {'Club',-372,886,-0.0634,0.0149,-0.9714,-0.2285},
        {'Club',-72,787,-0.1351,0.444,-0.1999,0.8629},
        {'Club',7,1290,0.1491,0.1057,-0.8022,0.5685},
        {'Club',189,288,0.094,-0.0339,-0.9361,-0.3374},
        {'Club',191,-1291,0.5008,0.126,-0.856,-0.0243},
        {'Club',457,1487,0.7609,-0.1159,-0.6223,0.1429},
        {'Club',664,-1371,0.7989,0.2516,-0.5298,-0.1336},
        {'Hammer',-617,-775,-0.8311,-0.1216,0.5357,-0.0868},
        {'Hammer',-607,958,0.8404,0.0738,-0.5342,-0.0533},
        {'Hammer',-606,1216,0.7897,0.0142,-0.6116,0.0462},
        {'Hammer',-592,603,0.7823,0.0074,-0.6198,0.0607},
        {'Hammer',-575,-1219,-0.9422,-0.2373,0.199,-0.1279},
        {'Hammer',-491,-422,0.4767,0.5999,-0.5243,-0.3715},
        {'Hammer',-341,793,-0.0238,0.7455,-0.666,-0.005},
        {'Hammer',-297,287,0.2282,0.7102,-0.6256,-0.2286},
        {'Hammer',-213,1413,0.6618,0.0187,-0.7402,0.1171},
        {'Hammer',-181,1051,0.4694,0.5807,-0.5103,-0.4266},
        {'Hammer',-19,628,-0.4426,0.6256,-0.5276,0.3667},
        {'Hammer',1,-1313,-0.2654,0.9285,-0.2577,0.0319},
        {'Hammer',85,-566,0.0597,0.7667,-0.6378,-0.0431},
        {'Hammer',255,1588,-0.3702,0.5847,0.1477,0.7066},
        {'Knife',-596,634,0.7838,0.0209,-0.6091,0.1196},
        {'Knife',-586,1263,-0.016,-0.554,-0.1079,-0.8253},
        {'Knife',-583,941,0.7838,0.0209,-0.6091,0.1196},
        {'Knife',-577,-874,-0.5788,-0.4675,0.3601,-0.5628},
        {'Knife',-576,-843,0.7401,0.0829,-0.6608,0.0934},
        {'Knife',-532,-171,-0.5864,-0.5068,0.3932,-0.4947},
        {'Knife',-494,-596,-0.727,-0.1612,0.6471,-0.1632},
        {'Knife',-381,-28,-0.0911,-0.9958,-0.0122,0.0012},
        {'Knife',-205,392,0.0458,0.5855,-0.1682,0.7917},
        {'Knife',-154,-1353,-0.7097,-0.4848,0.2384,-0.4521},
        {'Knife',-131,-221,-0.1383,0.72,-0.0898,0.6741},
        {'Knife',-57,1471,0.7521,-0.1155,-0.6187,0.1955},
        {'Knife',-15,984,0.6888,0.3287,-0.6292,0.1472},
        {'Knife',139,553,-0.8296,-0.5583,-0.0086,-0.0087},
        {'Knife',259,-815,-0.8296,-0.5583,-0.0086,-0.0087},
        {'Knife',389,890,-0.1361,-0.9906,-0.0122,0.0006},
        {'Knife',466,-1267,-0.3915,-0.7652,-0.0068,-0.5111},
        {'Knife',597,428,0.7038,-0.3455,-0.5949,-0.177},
})do
    local props=STAGES.BP_Monster_ZuoShang.props
    props[#props+1]={name=WEAPON..(w[1]~='' and '_'..w[1] or ''),dir='Bullet/',key='weapon'..i,group='weapons',
        x=w[2],y=w[3],z=0,yaw=0,q={X=w[4],Y=w[5],Z=w[6],W=w[7]}}
end
-- The summon transform stands 50 cm over the player's capsule centre (arena_controller.lua): about 140 cm
-- over the ground, used when the trace finds none.
local GROUND_BELOW=140

local function short(text)return (text:gsub('^'..LENGTU:gsub('%.','%%.'),'')) end

function Stages.isStaged(className)
    return type(className)=='string' and STAGES[(className:gsub('_C$',''))]~=nil
end

function Stages.new(options)
    local log=options.log or function()end
    local now=options.now or os.clock
    local self={records={},placed=0,failures=0}
    local shared={}   -- prop name -> {actor=, users=}: the actors the mod placed, shared by every boss using them
    local revealHook
    local find=options.staticFind or function(path)return StaticFindObject(path)end
    local register=options.registerHook or function(...)return RegisterHook(...)end
    local unregister=options.unregisterHook or function(...)return UnregisterHook(...)end
    local unseen={}     -- actor address -> {actor=, component=, label=}: placed hidden, shown when used
    local revealHooks={}   -- function path -> {pre=, post=}
    local revealed,revealedLogged,revealLines=0,0,0
    local function say(text)log('[BossStage] '..text)end
    local function className(actor)
        local ok,name=pcall(function()return actor:GetClass():GetFName():ToString()end)
        return ok and type(name)=='string' and name or '?'
    end
    local function gone(actor)
        if not U.valid(actor) then return true end
        local ok,destroying=pcall(options.isDestroying,actor)
        return ok and destroying==true
    end
    local function where(actor)
        local at=not gone(actor) and options.location and options.location(actor) or nil
        return at and type(at.X)=='number' and at or nil
    end
    local fname=options.fname or function(text)return FName(text)end
    local function idOf(actor)
        local id=U.field(actor,'Actor ID')
        local ok,text=pcall(function()return id:ToString()end)
        return ok and type(text)=='string' and text or nil
    end
    local function count(actor,tag)
        local ok,n=pcall(options.tagCount,actor,tag)
        return ok and type(n)=='number' and n or nil
    end
    local function quat(degrees)
        local half=math.rad(degrees)/2
        return {X=0,Y=0,Z=math.sin(half),W=math.cos(half)}
    end
    -- A placed-hidden actor the game now uses (FlyUp): show the component and what hangs under it. Runs after the
    -- function, in the game's call.
    local function reveal(context)
        local actor=U.unwrap(context)
        if options.onUsed then pcall(options.onUsed,actor) end
        local key=U.key(actor)
        local entry=key and unseen[key]
        if not entry then return nil end
        unseen[key]=nil
        local part=U.field(actor,entry.component)
        local called,okSeen,visible=false,false,nil
        if U.valid(part) then
            called=pcall(function()part:SetVisibility(true,true)end)
            okSeen,visible=pcall(function()return part:IsVisible()end)
        end
        revealed=revealed+1
        if revealLines<3 or visible~=true then
            revealLines=revealLines+1
            say(string.format('%s被招式取用，显现 %s 调用=%s 读回可见=%s 累计显现=%d',entry.label,className(actor),tostring(called),
                okSeen and tostring(visible) or '?',revealed))
        end
        return nil
    end
    function revealHook(path)
        if revealHooks[path] then return true end
        local okFind,found=pcall(find,path)
        if not okFind or not U.valid(found) then say('找不到用时显现的函数 '..path);return false end
        local ok,pre,post=pcall(register,path,reveal)
        if ok and type(pre)=='number' and type(post)=='number' then
            revealHooks[path]={pre=pre,post=post};say('用时显现挂钩注册ID读回 pre='..pre..' post='..post)
            return true
        end
        say('用时显现挂钩注册失败：'..tostring(pre))
        return false
    end
    local function releaseHooks()
        for path,hook in pairs(revealHooks)do
            local ok,err=pcall(unregister,path,hook.pre,hook.post)
            say('摘除用时显现挂钩 调用='..tostring(ok)..(ok and '' or ' 错误='..tostring(err))..' 本场显现='..revealed)
            if ok then revealHooks[path]=nil end
        end
    end
    local function qmul(a,b)
        return {X=a.W*b.X+a.X*b.W+a.Y*b.Z-a.Z*b.Y,Y=a.W*b.Y-a.X*b.Z+a.Y*b.W+a.Z*b.X,
            Z=a.W*b.Z+a.X*b.Y-a.Y*b.X+a.Z*b.W,W=a.W*b.W-a.X*b.X-a.Y*b.Y-a.Z*b.Z}
    end
    -- Toward the player from where she is summoned; 0 when the player cannot be read.
    local function facing(origin)
        local player=options.player and options.player()
        local at=player and where(player)
        if not at then return 0 end
        local dx,dy=at.X-origin.X,at.Y-origin.Y
        if dx*dx+dy*dy<1 then return 0 end
        return math.deg(math.atan(dy,dx))
    end

    -- One marker: reused when the mod already placed it, left alone when her own map has one.
    local function place(stage,prop,origin,yaw,world,owner)
        local id=prop.key or prop.name
        local mine=shared[id]
        if mine and not gone(mine.actor) then
            mine.users=mine.users+1
            return prop.name..'=沿用已放的（共用 '..mine.users..' 个）','shared'
        end
        shared[id]=nil
        local okAll,list=pcall(options.findAll,prop.name..'_C')
        for _,actor in ipairs(okAll and type(list)=='table' and list or {})do
            local okName,own=pcall(function()return actor:GetFName():ToString()end)
            if not gone(actor) and not (okName and tostring(own):find('^Default__')) then
                return prop.name..'=地图上已有一个，她会用地图上的','map'
            end
        end
        local path=stage.base..(prop.dir or '')..prop.name..'.'..prop.name..'_C'
        local cls=options.findClass and options.findClass(path)
        local loaded=false
        if not U.valid(cls) and options.loadClass then cls=options.loadClass(path);loaded=U.valid(cls) end
        local lib=options.statics and options.statics()
        if not U.valid(cls) or not U.valid(lib) or not U.valid(world) then
            self.failures=self.failures+1
            return string.format('%s=没放（类=%s 函数库=%s World=%s）',prop.name,tostring(U.valid(cls)),tostring(U.valid(lib)),tostring(U.valid(world))),'failed'
        end
        local turn=math.rad(yaw)
        local c,s=math.cos(turn),math.sin(turn)
        local x,y=origin.X+prop.x*c-prop.y*s,origin.Y+prop.x*s+prop.y*c
        local okGround,ground=pcall(options.ground,world,x,y,origin.Z)
        ground=okGround and type(ground)=='number' and ground or nil
        local z=(ground or origin.Z-GROUND_BELOW)+prop.z
        local rotation=prop.q and qmul(quat(yaw),prop.q) or quat(yaw+prop.yaw)
        local t={Translation={X=x,Y=y,Z=z},Rotation=rotation,Scale3D={X=1,Y=1,Z=1}}
        local began,actor=pcall(function()return lib:BeginDeferredActorSpawnFromClass(world,cls,t,1,owner,1)end)
        actor=began and U.unwrap(actor) or nil
        if not U.valid(actor) then
            self.failures=self.failures+1
            return prop.name..'=生成没返回有效对象','failed'
        end
        local finished=pcall(function()lib:FinishSpawningActor(actor,t,1)end)
        shared[id]={actor=actor,users=1}
        local quiet=pcall(function()actor:SetActorEnableCollision(false)end)
        local okCollision,collision=pcall(function()return actor:GetActorEnableCollision()end)
        -- Components that would show (左殇's house): hidden, the actor and its own effects stay.
        local hidden,shown={},false
        local def=prop.group and stage.groups and stage.groups[prop.group]
        local hide=prop.hide or (def and def.reveal and {def.reveal}) or {}
        for _,component in ipairs(hide)do
            local part=U.field(actor,component)
            local called,okSeen,visible=false,false,nil
            if U.valid(part) then
                called=pcall(function()part:SetVisibility(false,true)end)
                okSeen,visible=pcall(function()return part:IsVisible()end)
            end
            shown=shown or not okSeen or visible~=false
            hidden[#hidden+1]=string.format(' 隐藏 %s 调用=%s 读回可见=%s',component,tostring(called),okSeen and tostring(visible) or '?')
        end
        local at=where(actor)
        local off=at and math.sqrt((at.X-x)^2+(at.Y-y)^2+(at.Z-z)^2)
        -- One of many of a class (a group) is not looked up by class; the group's own readback counts them.
        local seen=true
        if not prop.group then
            local okFound,found=pcall(function()return lib:GetActorOfClass(world,cls)end)
            seen=okFound and U.key(U.unwrap(found))==U.key(actor)
        end
        local owned=owner==nil or U.key(U.field(actor,'Owner'))==U.key(owner)
        if finished and seen and owned and not shown then self.placed=self.placed+1 else self.failures=self.failures+1 end
        if def and def.reveal and not shown then
            unseen[U.key(actor)]={actor=actor,component=def.reveal,label=def.label}
        end
        if prop.group then
            return string.format('%s#%s 完成生成=%s 主人读回=%s 地面=%s',prop.name,tostring(prop.key),tostring(finished),tostring(owned),
                ground and string.format('%.0f',ground) or '没找到'),(finished and owned) and 'placed' or 'failed'
        end
        return string.format('%s=%s 完成生成=%s 位置读回差=%s 地面=%s 碰撞关=%s 读回碰撞=%s 她按类能找到=%s%s',prop.name,
            loaded and '加载类后放好' or '放好',tostring(finished),off and string.format('%.0fcm',off) or '?',
            ground and string.format('%.0f',ground) or '没找到（按召唤高度估）',tostring(quiet),okCollision and tostring(collision) or '?',tostring(seen),
            table.concat(hidden)),'placed'
    end

    -- Before FinishSpawn. Not a staged boss: nothing happens and nil comes back.
    function self:prepare(actor,transform,world)
        local name=className(actor):gsub('_C$','')
        local stage=STAGES[name]
        if not stage then return nil end
        local key=U.key(actor)
        local origin=transform and transform.Translation
        if not key or not origin or type(origin.X)~='number' then
            self.failures=self.failures+1
            say(stage.label..'：召唤位置不可读，没放场地物件；她的召唤会出在世界原点')
            return {ok=false}
        end
        local yaw=facing(origin)
        local parts,groups={},{}
        for _,prop in ipairs(stage.props)do
            local text,result=place(stage,prop,origin,yaw,world,actor)
            if prop.group then
                local g=groups[prop.group] or {total=0,placed=0,shared=0,map=0,failed=0,first={}}
                groups[prop.group]=g
                g.total=g.total+1;g[result]=(g[result] or 0)+1
                if result=='failed' and #g.first<3 then g.first[#g.first+1]=text end
            else parts[#parts+1]=text end
        end
        for name,g in pairs(groups)do
            local def=stage.groups and stage.groups[name] or {label=name}
            local hooked=def.revealOn and revealHook(def.revealOn)
            local registered=def.tag and options.targetsByTag and select(2,pcall(options.targetsByTag,def.tag))
            parts[#parts+1]=string.format('%s %d 个：放好=%d 沿用=%d 地图上已有=%d 失败=%d%s%s%s',def.label,g.total,g.placed,g.shared,g.map,g.failed,
                def.tag and string.format('；按 %s 登记的读回=%s',def.tag,tostring(registered)) or '',
                def.revealOn and string.format('；先隐藏，用时显现，挂钩=%s',tostring(hooked)) or '',
                #g.first>0 and '（'..table.concat(g.first,'；')..'）' or '')
        end
        self.records[key]={actor=actor,key=key,name=name,stage=stage,at=now(),tags=nil}
        say(string.format('%s：按原场地放场地物件，整体朝向玩家 %.0f°：%s',stage.label,yaw,table.concat(parts,'；')))
        if stage.saveId then
            local before=idOf(actor)
            local entry=before and options.saveData and select(2,pcall(options.saveData,before))
            local wrote,writeError=pcall(function()actor['Actor ID']=fname(stage.saveId)end)
            local after=idOf(actor)
            local moved=after==stage.saveId
            local reset,resetError=false,'没换成'
            if moved then reset,resetError=pcall(function()actor:ResetTags()end) end
            local ours=moved and options.saveData and select(2,pcall(options.saveData,stage.saveId))
            if not moved or not reset then self.failures=self.failures+1 end
            say(string.format('%s 存档 ID：原来=%s（原地图那场也用它，存档里现在=%s）改成 %s 写入=%s 读回=%s；清空这条的阶段进度 调用=%s 存档里=%s%s',
                stage.label,tostring(before),tostring(entry or '读不到'),stage.saveId,tostring(wrote),tostring(after),tostring(reset),
                tostring(ours or '读不到'),(wrote and '' or ' 写入错误='..tostring(writeError))..(reset and '' or ' 清空错误='..tostring(resetError))))
        end
        return {ok=true}
    end

    function self:release(record,why)
        if not record then return end
        self.records[record.key]=nil
        local parts={}
        local removedGroup={}
        for _,prop in ipairs(record.stage.props)do
            local id=prop.key or prop.name
            local mine=shared[id]
            if mine then
                mine.users=mine.users-1
                if mine.users<=0 then
                    shared[id]=nil
                    local result
                    if gone(mine.actor) then result='已不在'
                    else
                        local ok=pcall(options.destroy,mine.actor)
                        result=gone(mine.actor) and '已移除' or '仍在'
                        if result=='仍在' then self.failures=self.failures+1 end
                        if not prop.group then result='调用='..tostring(ok)..' 读回='..result end
                    end
                    if prop.group then
                        local g=removedGroup[prop.group] or {}
                        removedGroup[prop.group]=g
                        g[result]=(g[result] or 0)+1
                    else parts[#parts+1]=prop.name..(result=='已不在' and '=' or ' ')..result end
                end
            end
        end
        for name,g in pairs(removedGroup)do
            local def=record.stage.groups and record.stage.groups[name] or {label=name}
            parts[#parts+1]=string.format('%s 已移除=%d 已不在（飞出去了或被游戏清掉）=%d 仍在=%d',def.label,g['已移除'] or 0,g['已不在'] or 0,g['仍在'] or 0)
        end
        say(record.stage.label..' '..why..'，场地物件：'..(#parts>0 and table.concat(parts,'；') or '还有别的同名 BOSS 在用，保留'))
        for key,entry in pairs(unseen)do if gone(entry.actor) then unseen[key]=nil end end
        local still=false
        for _,other in pairs(self.records)do
            for _,def in pairs(other.stage.groups or {})do if def.revealOn then still=true end end
        end
        if not still and next(revealHooks) then releaseHooks() end
    end

    -- After the boss is destroyed (the arena's own clean-up).
    function self:releaseActor(actor,why)
        local key=U.key(actor)
        if key then self:release(self.records[key],why or '已清理') end
    end

    -- Out of reach by her own design while she carries one of these marks.
    function self:untargetable(actor)
        local key=U.key(actor)
        local record=key and self.records[key]
        if not record then return false end
        for _,tag in ipairs(record.stage.untargetable or {})do
            local n=count(actor,tag)
            if n and n>0 then return true end
        end
        return false
    end

    function self:tick()
        local t=now()
        if revealed>revealedLogged then
            say('用时显现：本场已显现 '..revealed..' 个（这次 +'..(revealed-revealedLogged)..'）')
            revealedLogged=revealed
        end
        for key,record in pairs(self.records)do
            if gone(record.actor) then self:release(record,'已不在场上')
            elseif record.stage.tags then
                local on,unread={},0
                for _,tag in ipairs(record.stage.tags)do
                    local n=count(record.actor,tag)
                    if n==nil then unread=unread+1 elseif n>0 then on[tag]=true end
                end
                if unread<#record.stage.tags then
                    local added,removed,current={},{},{}
                    for _,tag in ipairs(record.stage.tags)do
                        local was=record.tags and record.tags[tag] or false
                        if on[tag] then current[#current+1]=short(tag) end
                        if on[tag] and not was then added[#added+1]=short(tag) end
                        if was and not on[tag] then removed[#removed+1]=short(tag) end
                    end
                    if not record.tags or #added>0 or #removed>0 then
                        say(string.format('%s 阶段标签 %.1f 秒：%s 现有=%s%s',record.stage.label,t-record.at,
                            record.tags and ('+['..table.concat(added,',')..'] -['..table.concat(removed,',')..']') or '首次读回',
                            #current>0 and table.concat(current,',') or '无',unread>0 and ' 读不到='..unread or ''))
                    end
                    record.tags=on
                end
            end
        end
    end

    function self:count()
        local n=0
        for _ in pairs(self.records)do n=n+1 end
        return n
    end

    function self:status()
        local props=0
        for _,mine in pairs(shared)do if not gone(mine.actor) then props=props+1 end end
        return {stage_bosses=self:count(),stage_props=props,stage_placed=self.placed,stage_failures=self.failures,stage_revealed=revealed}
    end
    return self
end
return Stages
