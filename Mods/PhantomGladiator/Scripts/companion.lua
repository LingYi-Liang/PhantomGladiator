-- Companions: units summoned to the "companion" team follow the player and fight on the player's side.
-- They reuse the game's own helper-NPC kit (docs/REVERSE_ENGINEERING.md v0.35.0):
--   follow  an IdleStateData_Follow instance (/SGameAI/Data; the helper NPCs' follow-the-player idle
--           state, see BT_SGameAI_Idle_NpcHelper_FollowPlayer and STEvaluator_GetFollowDestination)
--           put into the unit's SGameAIComponent.SpawnInfo before its AI starts, the way level spawners
--           set up the story's helpers;
--   side    the player's faction tag on the unit's Faction Component, plus a friendly relation both ways;
--           a companion's own summons get the same once they are adopted into its team, and lose the player
--           from their hatred list; afterwards, every second, anything that changed it is put back and logged,
--           for the mount a rider companion is on as well (a separate pawn with its own faction:
--           BP_RenewalNPC.BP_SGameDriverComponent.DrivingVehicle);
--   assist  BP_SGameAIFunctionLibrary.SyncHatredList(player -> companion), the call summons use to share
--           their summoner's targets, only while the player has enemies on its own hatred list.
-- Every write is read back and logged. Nothing shared is changed: class defaults, assets and the player
-- stay as they are; only the companion's own components are written.
local U=require('ue_observe')
local Companion={}
local FOLLOW='/SGameAI/Data/IdleStateData_Follow.IdleStateData_Follow_C'
local FRIENDLY=0 -- ETeamAttitude
local ASSIST_SECONDS,WATCH_SECONDS,WATCH_EVERY=2,90,5
-- Always friendly: checked every second; a unit that refused the last repair is tried every 10 s.
local GUARD_SECONDS,GUARD_RETRY_SECONDS,REPAIR_LINES=1,10,40
-- Keeping up (metres): the official follow starts at 5 m; walk within 10 m, run beyond,
-- teleport beside the player from 100 m unless a boss fight is on. Without progress for 3 s the engine's
-- SimpleMoveToActor takes over.
local FOLLOW_START_M,RUN_M,TELEPORT_M,STUCK_SECONDS=5,10,100,3
-- Stuck closer than that (companions did not follow down steps, stairs or a jump off a platform;
-- the logs show the fallback move ending at once, path status Idle, 25–35 m away for half a minute): no closer for
-- STUCK_TELEPORT_SECONDS while it hardly moved itself, or a floor or more apart, beyond STUCK_TELEPORT_M, and it is
-- teleported beside the player as at 100 m, under the same boss-fight rule. recall() (the app's 召回到身边 and its
-- function key) brings every live companion beside the player at once, boss fight or not.
local STUCK_TELEPORT_SECONDS,STUCK_TELEPORT_M,STUCK_MOVED_M,LEVEL_M=6,8,3,3
local RECALL_FAN=0.9     -- radians between companions recalled together, so they do not land on each other
local RECALL_NEAR_M=6    -- a recalled companion this close reads back as beside the player
local MECHANIC='/PBZCombatAsset/Config/GlobalConfig_Mechanic.GlobalConfig_Mechanic'
local STATE_LINES,MOVE_LINES,TELEPORT_LINES,GAIT_LINES=40,10,20,20
local MOVING=3 -- EPathFollowingStatus::Moving
-- A fresh companion stood 5–10 s in AI.State.Idle before noticing enemies (its awareness builds up
-- slowly; v0.35.x logs). Out of combat it now engages, once a second, the nearest live hostile its own
-- perception already reports within this distance of the player.
local ENGAGE_M,ENGAGE_LINES=20,20
local STATE_FIELDS={'BehaviorTreeAsset','Bindings','bOverrideSenseConfig','SenseConfigOverride','EnterStateConditions','NextStateData','bLoop'}

local function fname(object)
    local ok,name=pcall(function()return object:GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end
local function className(object)
    if not U.valid(object) then return 'invalid' end
    local ok,class=pcall(function()return object:GetClass()end)
    return ok and U.valid(class) and fname(class) or '?'
end
local function show(v)
    v=U.unwrap(v)
    if type(v)=='number' then return string.format('%.6g',v) end
    if v==nil or type(v)=='boolean' or type(v)=='string' then return tostring(v) end
    if U.valid(v) then return fname(v) end
    local items=U.array(v)
    if items then
        local names={}
        for i=1,math.min(#items,6) do names[#names+1]=show(items[i]) end
        return '['..#items..']{'..table.concat(names,',')..'}'
    end
    local tag=U.struct(v,'TagName')
    if tag~=nil then return show(tag) end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string' and s or U.kind(v)
end
local function tagName(tag)
    local name=U.struct(tag,'TagName')
    return name~=nil and show(name) or show(tag)
end
local function relation(component,other)
    local ok,value=pcall(function()return component:GetFactionRelation(other)end)
    return ok and tonumber(U.unwrap(value)) or nil
end
local function faction(component)
    local ok,tag=pcall(function()return component:GetCurrnetFaction()end)
    return ok and U.unwrap(tag) or nil
end

function Companion.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.time
    local self={alive=true,count=0,prepared=0,follow=0,side=0,friendly=0,assists=0,failures=0,message='还没有随从',
        moves=0,teleports=0,gaits=0,stateLines=0,repairs=0,repairLines=0}
    local units,serial,followClass,inspected={},0,nil,false
    local function say(m)log('[Companion] '..m)end

    -- Read-only: what the official follow state carries, logged once per Lua lifetime.
    local function inspect(cls)
        local props,funcs={},{}
        local okCdo,cdo=pcall(function()return cls:GetCDO()end)
        if not okCdo or not U.valid(cdo) then cdo=nil end
        pcall(function()cls:ForEachProperty(function(p)
            local name=fname(p)
            props[#props+1]=name..(cdo and ('='..show((U.field(cdo,name)))) or '')
        end)end)
        pcall(function()cls:ForEachFunction(function(f)
            local params={}
            pcall(function()f:ForEachProperty(function(p)params[#params+1]=fname(p)end)end)
            funcs[#funcs+1]=fname(f)..'('..table.concat(params,',')..')'
        end)end)
        local inherited={}
        for _,name in ipairs(STATE_FIELDS)do
            if cdo then inherited[#inherited+1]=name..'='..show((U.field(cdo,name))) end
        end
        say('官方跟随状态类 '..fname(cls)..' 自身字段='..(#props>0 and table.concat(props,' ') or '无')
            ..' 继承字段='..table.concat(inherited,' ')..' 函数='..(#funcs>0 and table.concat(funcs,' ') or '无'))
    end
    local function loadFollow()
        if U.valid(followClass) then return followClass end
        local cls=StaticFindObject(FOLLOW)
        if not U.valid(cls) then
            pcall(LoadAsset,FOLLOW)
            cls=StaticFindObject(FOLLOW)
        end
        if not U.valid(cls) then
            pcall(LoadAsset,(FOLLOW:gsub('_C$','')))
            cls=StaticFindObject(FOLLOW)
        end
        if not U.valid(cls) then return nil end
        followClass=cls
        if not inspected then inspected=true;inspect(cls)end
        return cls
    end

    local function aiOf(actor)
        local controller=U.field(actor,'Controller')
        local ai=U.field(controller,'SGameAIComponent')
        return U.valid(ai) and ai or nil
    end
    local function idleData(ai)return U.struct(U.field(ai,'SpawnInfo'),'IdleStateData')end

    -- The player's side: faction tag, then a friendly relation both ways. Returns both readbacks and the log text.
    local function joinSide(actor,player)
        local parts={}
        local mine,theirs=U.field(actor,'Faction Component'),U.field(player,'Faction Component')
        local sideOk,friendOk=false,false
        if not U.valid(mine) or not U.valid(theirs) then parts[#parts+1]='阵营=阵营组件不可用'
        else
            local wanted,before=faction(theirs),faction(mine)
            if wanted~=nil then
                local wrote=pcall(function()mine:SetFaction(wanted)end)
                sideOk=tagName(faction(mine))==tagName(wanted)
                parts[#parts+1]='阵营 '..tagName(before)..' -> '..tagName(wanted)..' 写入='..tostring(wrote)..' 读回='..tostring(sideOk)
            else parts[#parts+1]='阵营=玩家阵营不可读' end
            local wrote=pcall(function()mine:SetFactionRelationOverride(player,FRIENDLY,true)end)
            local there,back=relation(mine,player),relation(theirs,actor)
            friendOk=there==FRIENDLY and back==FRIENDLY
            parts[#parts+1]='友好关系写入='..tostring(wrote)..' 随从→玩家='..tostring(there)..' 玩家→随从='..tostring(back)
        end
        return sideOk,friendOk,table.concat(parts,'；')
    end
    local function onHatredList(actor,target)
        local key=U.key(target)
        for _,entry in ipairs(U.array(U.field(U.field(actor,'BP_PBZHatredManagerComponent'),'HatredList')) or {})do
            if U.key(entry)==key then return true end
        end
        return false
    end
    -- A summon adopted into a companion's team was spawned by the game on its summoner's side, which is the
    -- enemy's: it may already be after the player.
    local function adoptSide(record,actor,player)
        record.sideTries=(record.sideTries or 0)+1
        local sideOk,friendOk,text=joinSide(actor,player)
        local hm=U.field(actor,'BP_PBZHatredManagerComponent')
        local before=onHatredList(actor,player)
        local removed=''
        if before and U.valid(hm) then
            local ok=pcall(function()hm:RemoveActorFromHatredList(player)end)
            removed=' 移出玩家仇恨 调用='..tostring(ok)..' 读回仍在='..tostring(onHatredList(actor,player))
        end
        record.sideOk=sideOk and friendOk
        if sideOk then self.side=self.side+1 end
        if friendOk then self.friendly=self.friendly+1 end
        -- Given up after three tries: counted once; the always-friendly check keeps trying every 10 s.
        if not record.sideOk and record.sideTries>=3 then self.failures=self.failures+1;record.guardFailed=true end
        say('召唤物加入玩家一方 unit='..tostring(record.path)..' 第'..record.sideTries..'次 '..text..' 原本在仇恨玩家='..tostring(before)..removed)
    end

    -- Always friendly to the player: a companion (or adopted summon) whose relation either way, faction tag or
    -- hatred has drifted is put back, with what it had become in the log. Up to v0.37.3 the no-aggro switch did
    -- this to companions summoned while it was on; whatever else does it shows up here.
    local function keepFriendly(record,actor,player)
        local mine,theirs=U.field(actor,'Faction Component'),U.field(player,'Faction Component')
        if not U.valid(mine) or not U.valid(theirs) then return end
        local there,back=relation(mine,player),relation(theirs,actor)
        local wanted,tag=faction(theirs),tagName(faction(mine))
        local tagOk=wanted==nil or tag==tagName(wanted)
        local hating=onHatredList(actor,player)
        if there==FRIENDLY and back==FRIENDLY and tagOk and not hating then record.guardFailed=nil;return end
        self.repairs=self.repairs+1
        local sideOk,friendOk,text=joinSide(actor,player)
        local removed=''
        if hating then
            local hm=U.field(actor,'BP_PBZHatredManagerComponent')
            local ok=U.valid(hm) and pcall(function()hm:RemoveActorFromHatredList(player)end)
            removed='；移出玩家仇恨 调用='..tostring(ok)
        end
        local fixed=sideOk and friendOk and not onHatredList(actor,player)
        if not fixed and not record.guardFailed then self.failures=self.failures+1 end
        record.guardFailed=not fixed or nil
        if self.repairLines<REPAIR_LINES then
            self.repairLines=self.repairLines+1
            say('随从对玩家不再是友好，改回 unit='..tostring(record.path)..' 改回前 随从→玩家='..tostring(there)..' 玩家→随从='..tostring(back)
                ..' 阵营='..tag..' 仇恨里有玩家='..tostring(hating)..'；'..text..removed..' 结果='..tostring(fixed))
        end
    end

    -- Before ActivateAI: follow state, faction and relation. A step that does not read back is logged;
    -- the unit is still summoned and stays the player's companion on the steps that did.
    function self:prepare(actor,unitPath)
        local key=U.key(actor)
        if not key then return {ok=false,message='随从对象无效'} end
        self.prepared=self.prepared+1
        local player=options.getPlayer and options.getPlayer()
        local record={actor=actor,path=unitPath,at=clock()}
        units[key]=record
        local parts={}
        -- 1. official follow idle state
        local ai=aiOf(actor)
        local followOk=false
        if not ai then parts[#parts+1]='跟随=没有SGameAIComponent'
        else
            local before=idleData(ai)
            record.restart=U.field(ai,'bAIStarted')==true
            local cls=loadFollow()
            if not cls then parts[#parts+1]='跟随=官方跟随状态类加载失败'
            else
                serial=serial+1
                local made,state=pcall(StaticConstructObject,cls,ai,FName('PG_CompanionFollow_'..serial))
                if made and U.valid(state) then
                    local wrote=pcall(function()ai.SpawnInfo.IdleStateData=state end)
                    followOk=U.key(idleData(ai))==U.key(state)
                    record.followState=state
                    -- ActorToFollow is a soft pointer. Writing it from Lua crashed the game natively in v0.35.1
                    -- (docs/REVERSE_ENGINEERING.md); the target goes into the blackboard instead.
                    parts[#parts+1]='跟随写入='..tostring(wrote)..' 读回='..tostring(followOk)..' 原闲置数据='..show(before)
                        ..' AI已启动='..tostring(record.restart)
                else parts[#parts+1]='跟随=创建状态对象失败 '..tostring(state) end
            end
        end
        -- 2. the player's side: faction tag, then a friendly relation both ways
        local sideOk,friendOk,sideText=joinSide(actor,player)
        parts[#parts+1]=sideText
        if followOk then self.follow=self.follow+1 end
        if sideOk then self.side=self.side+1 end
        if friendOk then self.friendly=self.friendly+1 end
        if not (followOk and sideOk and friendOk) then self.failures=self.failures+1 end
        self.message=followOk and '随从已设为跟随玩家' or '官方跟随没有读回，随从可能留在原地'
        say('准备 unit='..tostring(unitPath)..' '..table.concat(parts,'；'))
        return {ok=followOk and friendOk,message=self.message}
    end

    -- After ActivateAI. A unit whose AI had already started before the follow state was written gets
    -- one restart so that its idle state is built from the new data.
    function self:afterActivate(actor,unitPath)
        local record=units[U.key(actor) or '']
        local ai=aiOf(actor)
        if not record or not ai then return end
        local restarted=''
        if record.restart then
            local stopped=pcall(function()ai:StopAI()end)
            local started=pcall(function()ai:StartAI()end)
            restarted=' 重启AI stop='..tostring(stopped)..' start='..tostring(started)
        end
        local kept=record.followState and U.key(idleData(ai))==U.key(record.followState)
        say('激活后读回 unit='..tostring(unitPath)..' AI已启动='..tostring(U.field(ai,'bAIStarted'))
            ..' 状态='..tagName(U.field(ai,'CurrentStateTag'))..' 闲置数据='..show(idleData(ai))..' 跟随数据保留='..tostring(kept)..restarted)
    end

    -- The follow state writes its parameters to the blackboard by gameplay tag (AssignParameters,
    -- SetValueAs*ByTag). Once the blackboard exists: list its keys, let the state assign its parameters,
    -- and point every object key named like a follow target at the player.
    local function blackboardKeys(bb)
        local keys,data,seen={},U.field(bb,'BlackboardAsset'),{}
        for _=1,4 do
            if not U.valid(data) then break end
            for _,entry in ipairs(U.array(U.field(data,'Keys')) or {})do
                local name=show(U.struct(entry,'EntryName'))
                if name~='nil' and not seen[name] then
                    seen[name]=true
                    keys[#keys+1]={name=name,type=className(U.struct(entry,'KeyType'))}
                end
            end
            data=U.field(data,'Parent')
        end
        return keys
    end
    local function followKeys(record,ai,player)
        local bb=U.field(ai,'BlackboardComponent')
        if not U.valid(bb) or not U.valid(U.field(bb,'BlackboardAsset')) then return false end
        record.keysChecked=true
        local keys=blackboardKeys(bb)
        local assigned=record.followState and pcall(function()record.followState:AssignParameters(bb)end)
        local names,found={},{}
        for _,key in ipairs(keys)do
            local value=key.type:find('Object',1,true) and U.unwrap(select(2,pcall(function()return bb:GetValueAsObject(FName(key.name))end))) or nil
            names[#names+1]=key.name..':'..key.type:gsub('BlackboardKeyType_','')..(value~=nil and ('='..show(value)) or '')
            if key.type:find('Object',1,true) and key.name:lower():find('follow',1,true) then found[#found+1]=key.name end
        end
        record.followKeys=found
        say('黑板键 '..#keys..'个：'..table.concat(names,' ')..'；官方参数写入='..tostring(assigned)..' 跟随对象键='..(#found>0 and table.concat(found,',') or '无'))
        return true
    end
    -- Points the follow keys at the player; returns how many now read back the player.
    local function pointFollowKeys(record,ai,player)
        local bb=U.field(ai,'BlackboardComponent')
        local ok=0
        for _,name in ipairs(record.followKeys or {})do
            local key=FName(name)
            local current=U.unwrap(select(2,pcall(function()return bb:GetValueAsObject(key)end)))
            if U.key(current)~=U.key(player) then pcall(function()bb:SetValueAsObject(key,player)end)end
            current=U.unwrap(select(2,pcall(function()return bb:GetValueAsObject(key)end)))
            if U.key(current)==U.key(player) then ok=ok+1 end
        end
        return ok
    end

    local function hatredCount(actor)
        local hm=U.field(actor,'BP_PBZHatredManagerComponent')
        local list=U.array(U.field(hm,'HatredList'))
        return list and #list or nil
    end
    local function distance(a,b)
        if not options.getLocation then return nil end
        local okA,pa=pcall(options.getLocation,a)
        local okB,pb=pcall(options.getLocation,b)
        if not okA or not okB or not pa or not pb then return nil end
        local ok,d=pcall(function()return math.sqrt((pa.X-pb.X)^2+(pa.Y-pb.Y)^2+(pa.Z-pb.Z)^2)/100 end)
        return ok and d or nil
    end
    local function fmt(d)return d and string.format('%.1fm',d) or '?' end
    local function at(actor)
        if not options.getLocation then return nil end
        local ok,p=pcall(options.getLocation,actor)
        return ok and type(p)=='table' and type(p.X)=='number' and p or nil
    end
    local function metres(a,b)
        if not a or not b then return nil end
        return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)/100
    end

    -- A boss fight is on when the companion or the player has a boss on its hatred list
    -- (PDA_ActorConfig Difficulty Tag CharacterType.Difficulty.*Boss).
    local function isBoss(actor)
        return tagName(U.field(U.field(actor,'Actor Config'),'Difficulty Tag')):match('Boss$')~=nil
    end
    local function bossFight(...)
        for _,actor in ipairs({...})do
            local hm=U.field(actor,'BP_PBZHatredManagerComponent')
            for _,enemy in ipairs(U.array(U.field(hm,'HatredList')) or {})do
                if U.valid(enemy) and isBoss(enemy) then return true end
            end
        end
        return false
    end

    -- Walk and run use the character's own movement mode (BP_RenewalNPC SetMovementMode) with the
    -- game's tags from GlobalConfig_Mechanic. With the speed held by the locomotion driver, Sprinting
    -- still played the walk animation (v0.35.7); NPCs chase in Jogging, so running uses Jogging and
    -- Sprinting only where a build has no jog tag.
    local gaitTags
    local function gaits()
        if gaitTags then return gaitTags end
        local mechanic=StaticFindObject(MECHANIC)
        if not U.valid(mechanic) then return nil end
        local jog=U.field(mechanic,'Jogging Tag')
        local name=tagName(jog)
        gaitTags={walk=U.field(mechanic,'Walking Tag'),
            run=(name~='' and name~='None' and name~='nil') and jog or U.field(mechanic,'Sprinting Tag')}
        say('移动模式标签 走路='..tagName(gaitTags.walk)..' 跑步='..tagName(gaitTags.run))
        return gaitTags
    end
    -- Set when the wanted gait changes; if the AI's own movement-mode service changed it back, set again
    -- at most every 5 s rather than fighting it every tick. The speed it ends up with is logged.
    local function setGait(record,actor,wanted,now)
        local tags=gaits()
        if not tags or tags[wanted]==nil then return end
        if record.gait==wanted and (tagName(U.field(actor,'AIMovementMode'))==tagName(tags[wanted])
            or (record.gaitAt and now-record.gaitAt<5)) then return end
        record.gaitAt=now
        local called=pcall(function()actor:SetMovementMode(tags[wanted])end)
        local actual=tagName(U.field(actor,'AIMovementMode'))
        record.gait=wanted
        self.gaits=self.gaits+1
        if self.gaits<=GAIT_LINES then
            say('移动模式 '..className(actor)..' -> '..wanted..' 调用='..tostring(called)..' 读回='..actual
                ..' 最大速度='..show((U.field(U.field(actor,'CharacterMovement'),'MaxWalkSpeed'))))
        end
    end

    -- Running needs a speed. The Sprinting tag reads back but the speed stays at the AI's walking value
    -- (80 for 魔渊, 100 for 阿花), and writing CharacterMovement.MaxWalkSpeed is undone the next frame
    -- by the character's Locomotion Driver (v0.35.6). The driver's own UseCustomMaxSpeed is used instead:
    -- the character's sprint speed (PDA_ActorConfig Sprint Parameters ExplicitWalkSpeed) or 1.1× the
    -- player's, at least 500; StopUseCustomMovementParameters hands the speed back within 10 m or in combat.
    local function speedOf(actor)
        return tonumber((U.field(U.field(actor,'CharacterMovement'),'MaxWalkSpeed')))
    end
    local function runSpeed(record,actor,player)
        if record.runSpeed then return record.runSpeed end
        local config=U.field(actor,'Actor Config')
        local sprint=tonumber((U.struct(U.field(config,'Sprint Parameters'),'ExplicitWalkSpeed')))
        local playerSpeed=speedOf(player)
        record.runSpeed=math.max(sprint or 0,(playerSpeed or 0)*1.1,500)
        say('跑步速度 '..className(actor)..' 冲刺配置='..tostring(sprint)..' 玩家='..tostring(playerSpeed)..' 采用='..record.runSpeed)
        return record.runSpeed
    end
    -- Read-only, once per companion while it runs: what its animation instance and gameplay tags say
    -- about gait, to see what picks the walk or run animation.
    local ANIM_WORDS={'gait','speed','walk','run','jog','sprint','attitude','locomotion','move','velocity'}
    local function describeAnimation(actor)
        local mesh=U.field(actor,'Mesh')
        local okAnim,anim=pcall(function()return mesh:GetAnimInstance()end)
        local parts={}
        if okAnim and U.valid(anim) then
            local okClass,class=pcall(function()return anim:GetClass()end)
            for _=1,4 do
                if not okClass or not U.valid(class) or #parts>=40 then break end
                pcall(function()class:ForEachProperty(function(property)
                    local name=fname(property)
                    local lower=name:lower()
                    for _,word in ipairs(ANIM_WORDS)do
                        if lower:find(word,1,true) and #parts<40 then parts[#parts+1]=name..'='..show((U.field(anim,name)));break end
                    end
                end)end)
                okClass,class=pcall(function()return class:GetSuperStruct()end)
            end
        end
        local tags={}
        local asc=U.field(actor,'AbilitySystemComponent')
        local okTags,owned=pcall(function()return asc:GetOwnedGameplayTags()end)
        for _,tag in ipairs(okTags and U.array(U.struct(owned,'GameplayTags')) or {})do
            local name=tagName(tag)
            if name:find('Attitude',1,true) or name:find('Locomotion',1,true) or name:find('Movement',1,true) then tags[#tags+1]=name end
        end
        say('跑步动画只读 '..className(actor)..' 动画='..(okAnim and className(anim) or '不可读')..' 字段：'..(#parts>0 and table.concat(parts,' ') or '无')
            ..' 移动标签：'..(#tags>0 and table.concat(tags,',') or (okTags and '无' or '不可读')))
    end
    -- Read-only samples of what the animation reads, while we make it run and while its own AI moves it
    -- fast in combat, to compare the two (v0.35.9: the run animation is chosen by something other than
    -- speed; candidates moveState, GameplayTag_IsSprint, SpeedWalkRun).
    local SAMPLE_LIMIT=8
    local function vec(v)
        local x,y,z=U.struct(v,'X'),U.struct(v,'Y'),U.struct(v,'Z')
        if type(x)~='number' then return show(v) end
        return string.format('(%.0f,%.0f,%.0f)',x,y or 0,z or 0)
    end
    local function sampleAnimation(record,actor,ai,why,now)
        if (record.samples or 0)>=SAMPLE_LIMIT or (record.sampleAt and now-record.sampleAt<1) then return end
        local mesh=U.field(actor,'Mesh')
        local okAnim,anim=pcall(function()return mesh:GetAnimInstance()end)
        if not okAnim or not U.valid(anim) then return end
        record.samples=(record.samples or 0)+1;record.sampleAt=now
        local okVelocity,velocity=pcall(function()return actor:GetVelocity()end)
        local speed=nil
        if okVelocity then
            local x,y=U.struct(velocity,'X'),U.struct(velocity,'Y')
            if type(x)=='number' and type(y)=='number' then speed=math.sqrt(x*x+y*y) end
        end
        local tags={}
        local asc=U.field(ai,'AbilitySystemComponent')
        local okTags,owned=pcall(function()return asc:GetOwnedGameplayTags()end)
        for _,tag in ipairs(okTags and U.array(U.struct(owned,'GameplayTags')) or {})do
            local name=tagName(tag)
            if name:find('Attitude',1,true) or name:find('Sprint',1,true) or name:find('Move',1,true) then tags[#tags+1]=name end
        end
        say('动画采样'..record.samples..' '..why..' '..className(actor)..' 实际速度='..(speed and string.format('%.0f',speed) or '?')
            ..' moveState='..show((U.field(anim,'moveState')))..' IsSprint='..show((U.field(anim,'GameplayTag_IsSprint')))
            ..' SpeedWalkRun='..vec((U.field(anim,'SpeedWalkRun')))..' DisplacementSpeed='..show((U.field(anim,'DisplacementSpeed')))
            ..' 移动模式='..tagName(U.field(actor,'AIMovementMode'))..' 状态='..tagName(U.field(ai,'CurrentStateTag'))
            ..' 标签='..(okTags and (#tags>0 and table.concat(tags,',') or '无') or '不可读'))
    end
    local function setSpeed(record,actor,player,wanted,now)
        local driver=U.field(actor,'Locomotion Driver')
        if not U.valid(driver) then return end
        if wanted=='run' then
            if record.speedMode~='run' then
                local before,target=speedOf(actor),runSpeed(record,actor,player)
                local called=pcall(function()driver:UseCustomMaxSpeed(target,false,{})end)
                record.speedMode,record.speedAt,record.speedChecked='run',now,false
                self.speeds=(self.speeds or 0)+1
                if self.speeds<=GAIT_LINES then
                    say('跑步速度生效 '..className(actor)..' UseCustomMaxSpeed('..target..') 调用='..tostring(called)..' 速度 '..tostring(before)..' -> '..tostring(speedOf(actor)))
                end
            elseif not record.speedChecked and now-record.speedAt>=1 then
                record.speedChecked=true
                say('跑步1秒后读回 '..className(actor)..' 最大速度='..tostring(speedOf(actor)))
                if not record.animDescribed then record.animDescribed=true;describeAnimation(actor)end
            end
        elseif record.speedMode=='run' then
            local called=pcall(function()driver:StopUseCustomMovementParameters()end)
            record.speedMode=nil
            say('恢复走路速度 '..className(actor)..' 调用='..tostring(called)..' 最大速度='..tostring(speedOf(actor)))
        end
    end

    -- Beside the player, 2.5 m toward where the companion stood; slot n (recall) turns that by RECALL_FAN each.
    local function teleport(record,actor,player,d,now,why,slot)
        record.teleportAt=now
        local pa,pc=at(player),at(actor)
        if not pa or not pc then return end
        local dx,dy=pc.X-pa.X,pc.Y-pa.Y
        local len=math.sqrt(dx*dx+dy*dy)
        if len<1 then dx,dy,len=1,0,1 end
        dx,dy=dx/len,dy/len
        if slot and slot>1 then
            local turn=(slot-1)*RECALL_FAN
            dx,dy=dx*math.cos(turn)-dy*math.sin(turn),dx*math.sin(turn)+dy*math.cos(turn)
        end
        local dest={X=pa.X+dx*250,Y=pa.Y+dy*250,Z=pa.Z+30}
        local okRot,rot=pcall(function()return actor:K2_GetActorRotation()end)
        local called,moved=pcall(function()return actor:K2_TeleportTo(dest,okRot and rot or {Pitch=0,Yaw=0,Roll=0})end)
        self.teleports=self.teleports+1
        record.farSince,record.stuckSince=nil,nil
        if self.teleports<=TELEPORT_LINES then
            say((why or '传送到玩家身边')..' '..className(actor)..' 原距离='..fmt(d)..' 调用='..tostring(called)..' 返回='..show(moved)..' 读回距离='..fmt(distance(actor,player)))
        end
        return called and U.unwrap(moved)==true
    end

    local function engage(record,actor,ai,player,ours)
        local perception=U.field(ai,'AIPerception')
        if not U.valid(perception) then return end
        local out={}
        local ok=pcall(function()perception:GetPerceivedHostileActors(out)end)
        local seen=ok and U.array(out.OutActors) or nil
        if not seen or #seen==0 then return end
        local best,bestDistance
        local playerKey=U.key(player)
        for _,enemy in ipairs(seen)do
            local key=U.key(enemy)
            if key and key~=playerKey and not ours[key] then
                local okHP,hp=true,1
                if options.hp then okHP,hp=pcall(options.hp,enemy) end
                local fromPlayer=distance(enemy,player)
                if okHP and type(hp)=='number' and hp>0 and fromPlayer and fromPlayer<=ENGAGE_M then
                    local fromCompanion=distance(enemy,actor)
                    if fromCompanion and (not bestDistance or fromCompanion<bestDistance) then best,bestDistance=enemy,fromCompanion end
                end
            end
        end
        if not best then return end
        local called=pcall(function()ai:ForceIntoCombat(best)end)
        self.engages=(self.engages or 0)+1
        if self.engages<=ENGAGE_LINES then
            say('主动迎敌 '..className(actor)..' -> '..className(best)..' 距离='..fmt(bestDistance)..' 感知到敌对='..#seen..' 调用='..tostring(called)
                ..' 状态读回='..tagName(U.field(ai,'CurrentStateTag')))
        end
    end

    local function keepUp(record,actor,player,state,d,now)
        if not d then return end
        local combat=state:find('Combat',1,true)~=nil
        if d>=TELEPORT_M then
            if record.teleportAt and now-record.teleportAt<3 then return end
            if bossFight(actor,player) then
                if not record.bossLogged then record.bossLogged=true;say('正在和BOSS打斗，距离'..fmt(d)..'也不传送')end
                return
            end
            record.bossLogged=nil
            return teleport(record,actor,player,d,now)
        end
        if combat then
            if record.speedMode=='run' then setSpeed(record,actor,player,'walk',now) end
            record.farSince,record.stuckSince=nil,nil;record.gait=nil;return
        end
        local gait=d>RUN_M and 'run' or 'walk'
        setGait(record,actor,gait,now)
        setSpeed(record,actor,player,gait,now)
        if d<=FOLLOW_START_M then record.farSince,record.stuckSince=nil,nil;return end
        -- Stuck: no 2 m closer for STUCK_TELEPORT_SECONDS, hardly moved itself or a floor apart (see the constants).
        local here,there=at(actor),at(player)
        if not record.stuckSince or d<record.stuckBest-2 then
            record.stuckSince,record.stuckBest,record.stuckFrom=now,d,here
        elseif now-record.stuckSince>=STUCK_TELEPORT_SECONDS and d>=STUCK_TELEPORT_M then
            local moved=metres(here,record.stuckFrom)
            local rise=here and there and math.abs(here.Z-there.Z)/100 or nil
            if (moved and moved<STUCK_MOVED_M) or (rise and rise>=LEVEL_M) then
                if record.teleportAt and now-record.teleportAt<3 then return end
                if bossFight(actor,player) then
                    if not record.bossLogged then record.bossLogged=true;say('卡住跟不上，但正在和BOSS打斗，不传送 距离='..fmt(d))end
                    return
                end
                record.bossLogged=nil
                self.stuck=(self.stuck or 0)+1
                return teleport(record,actor,player,d,now,string.format('卡住%.0f秒跟不上（自己移动%s，高差%s），传送到玩家身边',
                    now-record.stuckSince,fmt(moved),fmt(rise)))
            end
        end
        if not record.farSince or d<record.farDistance-0.5 then
            if record.farSince and not record.closingLogged and not record.moveAt then
                record.closingLogged=true;say('官方跟随在靠近玩家 '..fmt(record.farDistance)..' -> '..fmt(d))
            end
            record.farSince,record.farDistance=now,d
            return
        end
        if now-record.farSince<STUCK_SECONDS or (record.moveAt and now-record.moveAt<3) then return end
        -- A move toward an actor keeps tracking that actor; only start a new one once the last has stopped
        -- (re-issuing every 2 s in v0.35.3 restarted the walk each time and looked choppy).
        local controller=U.field(actor,'Controller')
        local okStatus,status=pcall(function()return controller:GetMoveStatus()end)
        status=okStatus and tonumber(U.unwrap(status)) or nil
        if status==MOVING then return end
        do
            record.moveAt=now
            local helper=StaticFindObject('/Script/AIModule.Default__AIBlueprintHelperLibrary')
            local called=U.valid(controller) and U.valid(helper) and pcall(function()helper:SimpleMoveToActor(controller,player)end)
            self.moves=self.moves+1
            if self.moves<=MOVE_LINES then say('备用跟随 SimpleMoveToActor '..className(actor)..' 距离='..fmt(d)..' 上次移动状态='..tostring(status)..' 调用='..tostring(called))end
        end
    end

    function self:tick()
        if not self.alive then return end
        local now=clock()
        local player=options.getPlayer and options.getPlayer()
        local live={}
        for _,member in ipairs(options.members and options.members() or {})do
            local key=member.team=='companion' and U.key(member.actor)
            if key then live[key]=member end
        end
        for key in pairs(units)do if not live[key] then units[key]=nil end end
        -- Every unit this mod summoned, any team: a companion does not pick a fight with them by itself.
        local ours={}
        for _,member in ipairs(options.members and options.members() or {})do
            local key=U.key(member.actor)
            if key then ours[key]=true end
        end
        local count=0
        for key,member in pairs(live)do
            if not member.stand then count=count+1 end
            local record=units[key]
            if not record then
                -- e.g. a companion's own summons, adopted into its team without a follow state
                record={actor=member.actor,path=member.class_path,at=now,adopted=true}
                units[key]=record
                say('登记随从（未经召唤准备，例如随从自己的召唤物） unit='..tostring(member.class_path))
            end
            if record.adopted and not record.sideOk and (record.sideTries or 0)<3 and U.valid(player) then
                adoptSide(record,member.actor,player)
            elseif U.valid(player) and (not record.guardAt or now-record.guardAt>=(record.guardFailed and GUARD_RETRY_SECONDS or GUARD_SECONDS)) then
                record.guardAt=now
                keepFriendly(record,member.actor,player)
                -- A rider's mount is a pawn of its own, still on the enemy's side unless it is put on the player's too.
                local mount=U.field(U.field(member.actor,'BP_SGameDriverComponent'),'DrivingVehicle')
                local mountKey=U.valid(mount) and U.key(mount)
                if mountKey and mountKey~=key and mountKey~=U.key(player) then
                    if record.mountKey~=mountKey then
                        record.mountKey,record.mount=mountKey,{actor=mount,path='坐骑 '..className(mount)..'（随从 '..tostring(record.path)..'）'}
                    end
                    keepFriendly(record.mount,mount,player)
                end
            end
            -- A stand waits parked with its AI off until a move of its summoner shows it, and that move places it
            -- (GAA_TeleportCharacterRelativeToTargetActor). Follow, teleport and target orders would move it in the middle of one.
            -- While it executes a boss (arena_executions.lua) the same goes for a companion.
            if not member.stand and not (options.busy and options.busy(member.actor)) then
                if U.valid(player) and (not record.assistAt or now-record.assistAt>=ASSIST_SECONDS) then
                    record.assistAt=now
                    local enemies=hatredCount(player)
                    local lib=options.aiLib and options.aiLib()
                    local world=options.getWorld and options.getWorld()
                    if enemies and enemies>0 and U.valid(lib) and U.valid(world) then
                        local before=hatredCount(member.actor)
                        local ok=pcall(function()lib:SyncHatredList(player,member.actor,world)end)
                        if ok then self.assists=self.assists+1 end
                        if not record.assistLogged then
                            record.assistLogged=true
                            say('协助 同步玩家仇恨到随从 调用='..tostring(ok)..' 玩家仇恨='..enemies..' 随从仇恨 '..tostring(before)..' -> '..tostring(hatredCount(member.actor)))
                        end
                    end
                end
                local ai=aiOf(member.actor)
                local state=ai and tagName(U.field(ai,'CurrentStateTag')) or '?'
                local d=U.valid(player) and distance(member.actor,player) or nil
                if ai and U.valid(player) then
                    if not record.keysChecked then followKeys(record,ai,player) end
                    -- Outside combat the idle state may assign its parameters again; keep the target on the player.
                    if record.followKeys and #record.followKeys>0 and not state:find('Combat',1,true)
                        and (not record.keysAt or now-record.keysAt>=2) then
                        record.keysAt=now
                        local ok=pointFollowKeys(record,ai,player)
                        if not record.keysLogged then record.keysLogged=true;say('跟随对象键指向玩家 读回='..ok..'/'..#record.followKeys)end
                    end
                    keepUp(record,member.actor,player,state,d,now)
                    -- Running on our orders, or moving fast on its own in combat: sample the animation inputs.
                    if record.speedMode=='run' then sampleAnimation(record,member.actor,ai,'我们让它跑',now)
                    elseif state:find('Combat',1,true) and (record.combatSamples or 0)<4 then
                        local okVelocity,velocity=pcall(function()return member.actor:GetVelocity()end)
                        local x,y=okVelocity and U.struct(velocity,'X'),okVelocity and U.struct(velocity,'Y')
                        if type(x)=='number' and type(y)=='number' and math.sqrt(x*x+y*y)>300 and (not record.sampleAt or now-record.sampleAt>=1) then
                            record.combatSamples=(record.combatSamples or 0)+1
                            record.samples=math.max(0,(record.samples or 0)-1) -- combat samples do not use up the running ones
                            sampleAnimation(record,member.actor,ai,'战斗中自己快速移动',now)
                        end
                    end
                    if not state:find('Combat',1,true) and (not record.engageAt or now-record.engageAt>=1) then
                        record.engageAt=now
                        engage(record,member.actor,ai,player,ours)
                    end
                end
                if state~=record.state then
                    if record.state and self.stateLines<STATE_LINES then
                        self.stateLines=self.stateLines+1
                        say('状态变化 '..className(member.actor)..' '..record.state..' -> '..state..' 距玩家='..fmt(d))
                    end
                    record.state=state
                end
                if now-record.at<=WATCH_SECONDS and (not record.watchAt or now-record.watchAt>=WATCH_EVERY) then
                    record.watchAt=now
                    say('跟随观察 '..className(member.actor)..' 距玩家='..fmt(d)..' 状态='..state..' 闲置数据='..(ai and show(idleData(ai)) or '?'))
                end
            end
        end
        self.count=count
        if count==0 and self.prepared>0 then self.message='随从已全部离场' end
    end

    -- 召回到身边 (the app's button and the recall function key): every live companion beside the player now, fanned
    -- out, read back by distance. Also in a boss fight.
    function self:recall()
        local player=options.getPlayer and options.getPlayer()
        if not U.valid(player) then return {ok=false,message='玩家无效，没有召回随从',spawned_count=0} end
        local now=clock()
        local count,near,missed=0,0,{}
        for _,member in ipairs(options.members and options.members() or {})do
            local actor=member.actor
            if member.team=='companion' and not member.stand and U.valid(actor) and not (options.busy and options.busy(actor)) then
                local okHP,hp=true,1
                if options.hp then okHP,hp=pcall(options.hp,actor) end
                if okHP and type(hp)=='number' and hp>0 then
                    count=count+1
                    local key=U.key(actor)
                    local record=key and units[key] or {actor=actor}
                    local moved=teleport(record,actor,player,distance(actor,player),now,'召回到玩家身边',count)
                    local after=distance(actor,player)
                    if moved and after and after<=RECALL_NEAR_M then
                        near=near+1
                    else
                        missed[#missed+1]=className(actor)..'('..fmt(after)..')'
                    end
                end
            end
        end
        self.recalls=(self.recalls or 0)+1
        if count==0 then say('召回：没有活着的随从');return {ok=true,message='没有可召回的随从',spawned_count=0} end
        local message='已召回 '..near..'/'..count..' 个随从到身边'..(#missed>0 and ('；没到位：'..table.concat(missed,'、')) or '')
        say(message)
        return {ok=near==count,message=message,spawned_count=0}
    end

    function self:silence()self.alive=false end
    function self:status()
        return {count=self.count,prepared=self.prepared,follow=self.follow,side=self.side,friendly=self.friendly,
            assists=self.assists,failures=self.failures,moves=self.moves,teleports=self.teleports,gaits=self.gaits,repairs=self.repairs,
            stuck=self.stuck or 0,recalls=self.recalls or 0,message=self.message}
    end
    return self
end
return Companion
