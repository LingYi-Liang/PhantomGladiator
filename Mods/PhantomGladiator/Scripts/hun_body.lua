-- Experimental, owned NPC body only. Never possesses a player or edits a shared config.
-- The body is born through the normal summon chain with its template untouched. The two tags its
-- template starts with (cannot be hated, forced hide) are then cleared on that one instance and read back.
-- After that, hun_look.lua swaps the body mesh and main anim class on that instance and adds its look parts. Read-only
-- probes of the body (and of the real player, read only) run before and after those writes, once per summon request.
-- At the second support cycle hun_weapons.lua slots a player weapon config and runs the body's fight loop.
-- Parts and weapon actors these modules registered are destroyed when the body leaves the arena, or, for a body that
-- died, when its death readback ends.
local U=require('ue_observe')
local Look=require('hun_look')
local Weapons=require('hun_weapons')
local Vitals=require('hun_vitals')
local Body={path='/PBZCombatAsset/ActorData/Mobs/000_Hun/BP_Monster_Hun.BP_Monster_Hun_C'}
local CONFIG='/PBZCombatAsset/ActorData/Mobs/000_Hun/ActorConfig/ActorC_Monster_Hun.ActorC_Monster_Hun'
local ABILITY_UTILS='/Script/SGameUtils.Default__AbilityUtils'
local CLEAR={'AI.Hatred.CanNotBeHatred','CharacterState.Unselectable.Force.Hide'}
local MESH_CLASSES={'SkeletalMeshComponent','StaticMeshComponent','GroomComponent','ChildActorComponent','ChaosClothComponent'}
local ASSET_FIELDS={'SkeletalMeshAsset','SkinnedAsset','StaticMesh','GroomAsset','ChildActorClass','ClothAsset','Asset'}
-- Support cycles after birth during which the tags are read again, in case the game adds them late.
local WATCH=20
local MAX_COMPONENT_LINES=48
local MAX_PLAYER_LINES=96
-- Support cycles after birth at which the body's movement is read again, when it is likely walking or fighting.
local MOTION_CHECKS={[6]=true,[14]=true}
-- Probes (all read-only).
local PROBE_TAGS={'AI','CharacterType.AI.Boss','CharacterState.Stand.SimpleExe','CharacterState.Space.Ground',
    'CharacterState.CanWeakExecute.Weak','CharacterState.CanWeakExecute.LowHealth','CharacterState.ReadyToDeflect'}
local PROBE_ATTRIBUTES={'Health','Health_Max','Shachi','Shachi_Max','ShachiRegen','ShachiRegenCooldown','SpiritShadow','SpiritShadow_Max',
    'UltimateCharge','UltimateCharge_Max','UltimateChargeCount','UltimateChargeCount_Max','Frost_Accumulation','Infliction_Max'}
local MAX_ABILITY_NAMES=40
local MAIN_SLOT='Weapon.Slot.Main'
local SAMPLE_MS=100        -- the deflect-frame sampler's period
local SAMPLE_SECONDS=90    -- how long it runs after the first support cycle
local SAMPLE_LINES=30      -- lines it may write in a load
local SLOT_LINES=2         -- montage-slot lines per summon request
local COOLDOWN_LINES=4     -- player weapon-switch cooldown lines in a load
local DEATH_SECONDS=15     -- death readback: one line a second for this long after HP reaches 0
local DEATH_HIDE_AFTER=1   -- seconds after HP reaches 0 at which Look.STEPS.deathHide hides the added parts
local WEAPON_CHECK=2       -- support cycle after birth at which hun_weapons equips the body
-- A summoned unit that is a Hun body with no attribute values in its profile keeps the game's numbers.
Body.KEEP_STATS={
    onSpawn=function()return {ok=true,message='魂保持游戏原值'}end,
    onSummon=function()return {ok=true,message='魂保持游戏原值'}end,
}
-- The numbers a summoned unit takes. A Hun body never takes the arena's set or the companions': its profile's values
-- (the fields the game knows) when there are any, the game's own numbers otherwise.
-- Returns the stats object, how many profile fields were dropped, and where the numbers come from.
function Body.statsFor(owned,values,known,default,hunStats,keep)
    if not owned then return default,0,nil end
    local chosen,dropped={},0
    for field,value in pairs(values or{})do if known[field]then chosen[field]=value else dropped=dropped+1 end end
    if next(chosen)~=nil then
        hunStats.mode,hunStats.custom='custom',chosen
        return hunStats,dropped,'方案'
    end
    return keep or Body.KEEP_STATS,dropped,'游戏原值'
end
local function call(o,m,...)
    if not U.valid(o)then return false end
    local a,n={...},select('#',...);local ok,value=pcall(function()return o[m](o,table.unpack(a,1,n))end)
    return ok,U.unwrap(value)
end
local function name(o)local ok,n=call(o,'GetFullName');return ok and type(n)=='string'and n or nil end
local function short(o)local n=name(o);return n and(n:match('[%.:]([^%.:]+)$')or n)or'?'end
local function tag(t)
    local v=U.struct(t,'TagName');if type(v)=='string'then return v end
    local ok,s=pcall(function()return v:ToString()end);return ok and s or nil
end
local function text(v)
    v=U.unwrap(v)
    if type(v)=='string'then return v end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and type(s)=='string'and s or nil
end
local function num(v)return type(v)=='number'and v==v and string.format('%.3g',v)or tostring(v)end
local function tags(config)
    local container=U.field(config,'InitialTags');local array=U.struct(container,'GameplayTags');local values=U.array(array)
    if not values then return nil end
    local result={};for _,v in ipairs(values)do local s=tag(v);if not s then return nil end;result[#result+1]=s end
    return result
end
local function weak(value)
    value=U.unwrap(value)
    if U.valid(value)then return value end
    local ok,object=pcall(function()return value:Get()end)
    return ok and U.valid(object)and object or nil
end
function Body.new(o)
    local self={alive=true,prepared=0,failed=0,message='等待召唤魂'}
    local context,records,batch,epoch,dumped,probed=nil,{},0,0,{},{}
    local dying,samplers,sampleLines,slotLines,cooldownLines,lastCooldown={},{},0,{},0,nil
    local announced={}  -- "即将" lines of read-only native getters with no precedent, once a load
    local find=o.find or StaticFindObject
    local findAll=o.findAll or FindAllOf
    local fname=o.fname or FName
    local loadClass=o.loadClass or LoadAsset
    local steps=o.steps or Look.STEPS
    local probing=o.probe
    if probing==nil then probing=steps.probe==true end
    local clock=o.clock or os.clock
    local stats=o.stats
    local function say(s)(o.log or function()end)('[HunBody] '..s)end
    -- hun_look reads what the real player wears (read only) when its follow switch is on.
    local look=o.look or Look.new({log=o.log,find=find,load=loadClass,findAll=findAll,fname=fname,steps=steps,player=o.player})
    local function current(actor,record)
        if not self.alive then return false end
        local world=o.world();local player=o.player()
        return U.valid(world)and U.inWorld(actor,world)and U.key(actor)~=U.key(player)
            and U.npcPath(actor)==Body.path and(not record or record.epoch==epoch and record.world==U.key(world)and record.name==name(actor))
    end
    -- The arena's last member list and battle flag, as tick() received them; every actor is checked again before use.
    local lastMembers,battle={},false
    local function getStats()
        if stats==nil then
            local ok,module=pcall(require,'character_stats')
            stats=ok and module.new()or false
        end
        return stats or nil
    end
    -- The opponents of one body: members of the other fighting team, never the player.
    local function opponents(r)
        local key,mine=U.key(r.actor),r.team
        if not mine then
            for _,m in ipairs(lastMembers)do if U.key(m.actor)==key then mine=m.team;break end end
        end
        if mine=='neutral' or mine=='companion' then
            local target=o.target and o.target(r.actor,mine)
            if U.valid(target) and U.inWorld(target,o.world()) and U.key(target)~=key and
                (mine=='neutral' or U.key(target)~=U.key(o.player())) then return {target} end
            return {}
        end
        if mine~='blue'and mine~='red'then return {}end
        local player=U.key(o.player())
        if o.target then
            local target=o.target(r.actor,mine)
            local targetKey=U.key(target)
            if targetKey and targetKey~=key and targetKey~=player and U.inWorld(target,o.world()) then return {target} end
            return {}
        end
        local list={}
        for _,m in ipairs(lastMembers)do
            local k=U.key(m.actor)
            if k and k~=key and k~=player and not m.stand and not m.reserve and not m.aid
                and (m.team=='blue' or m.team=='red') and m.team~=mine then list[#list+1]=m.actor end
        end
        return list
    end
    local qteFamilies
    local function qteFamily(actor)
        if U.key(actor) and U.key(actor)==U.key(o.player()) then return true end
        if qteFamilies==nil then
            local ok,module=pcall(require,'arena_grabs')
            qteFamilies=ok and type(module.QTE_FAMILIES)=='table'and module.QTE_FAMILIES or false
        end
        local p=U.npcPath(actor)
        local root=type(p)=='string'and p:match('^(/PBZCombatAsset/ActorData/Mobs/[^/]+/)')
        return qteFamilies and root and qteFamilies[root]~=nil or false
    end
    local function owned(r)return self.alive and records[U.key(r.actor)or'']==r and current(r.actor,r)end
    local role=require('hun_arena_role').new({current=owned,load=loadClass,find=find,player=o.player,aiOf=o.aiOf,
        stat=function(actor,field)
            local adapter=getStats()
            local sample=adapter and adapter:read(actor,field)
            return sample and sample.current
        end,
        fname=fname,log=o.log or function()end})
    local function fighting(r)
        if r and r.dead then return false end
        if r and (r.team=='neutral' or r.team=='companion') then return U.valid(o.target and o.target(r.actor,r.team)) end
        return battle
    end
    local actionGuard=o.actionGuard or require('hun_action_guard').new({log=o.log,find=find,fname=fname,current=owned,
        register=o.register,unregister=o.unregister,world=o.world,now=o.now or clock})
    local weapons=o.weapons or Weapons.new({log=o.log,find=find,load=loadClass,fname=fname,clock=o.now or clock,loop=o.loop,cancel=o.cancel,
        guard=actionGuard,
        stats=getStats,hp=o.hp,battle=fighting,opponents=opponents,nativeTarget=o.nativeTarget,pairProtected=o.pairProtected,
        qteFamily=qteFamily,steps=o.weaponSteps,current=owned})
    local function optional(module,method,...)
        local fn=module and module[method]
        if type(fn)~='function'then return end
        local ok,why=pcall(fn,module,...)
        if not ok then say(method..' 中断：'..tostring(why))end
    end
    local function mayRevealAfterSpawn(asc)
        for _,tag in ipairs({'Ability.Executed','Ability.Action.Execution','CharacterState.HitReact.State.Executing',
            'Ability.Action.Hun.HeiMoShang.Reborn','CharacterState.Immortal.HeiMoShang','CharacterState.Vanish',
            'CharacterState.Unselectable.Force.Perform','CharacterState.Dead'}) do
            local got,count=call(asc,'GetGameplayTagCount',{TagName=fname(tag)})
            if not got or count~=0 then return false end
        end
        return true
    end
    -- Reads both tags on this instance, sets a non-zero spawn tag to zero and reads it again.
    -- Returns whether both read zero afterwards, plus one text with every value read.
    local function clear(r)
        local asc=U.field(r.actor,'AbilitySystemComponent')
        if not U.valid(asc)then return false,'ASC未就绪'end
        local parts,zero,lib={},true,nil
        for _,tagName in ipairs(CLEAR)do
            local value={TagName=fname(tagName)}
            local got,before=call(asc,'GetGameplayTagCount',value)
            before=got and type(before)=='number'and before or nil
            local wrote,after='未写',before
            if before and before>0 then
                if r.phase=='observed' and not mayRevealAfterSpawn(asc) then return false,'等待原生动作可见状态' end
                if lib==nil then local found,object=pcall(find,ABILITY_UTILS);lib=found and U.valid(object)and object or false end
                if not lib then wrote='找不到AbilityUtils'
                elseif not current(r.actor,r)then wrote='实例已变化'
                else wrote=tostring(call(lib,'SetLooseGameplayTagCount',r.actor,value,0)==true)end
                local again,count=call(asc,'GetGameplayTagCount',value)
                after=again and type(count)=='number'and count or nil
            end
            if after~=0 then zero=false end
            parts[#parts+1]=tagName..' '..tostring(before)..'→'..tostring(after)..'（写入='..wrote..'）'
        end
        return zero,table.concat(parts,'；')
    end
    local function hidden(actor)local value=U.field(actor,'bHidden');if type(value)=='boolean'then return value end;return nil end
    -- Read-only. Every mesh, hair, cloth and child-actor component an actor carries: what it shows, what it hangs on,
    -- and for skinned meshes which animation class drives it. Listed for the body and for the real player,
    -- once per summon request, to compare the two looks.
    local function nameOf(value)
        if not U.valid(value)then return'无'end
        return short(value)
    end
    local function socketOf(component)
        local got,socket=call(component,'GetAttachSocketName')
        if not got or socket==nil then return'?'end
        return text(socket)or'?'
    end
    local function components(actor,label,limit)
        local key,lines,total=U.key(actor),{},0
        if not key then say('外观部件：'..label..' 不可读');return end
        for _,className in ipairs(MESH_CLASSES)do
            local ok,list=pcall(findAll,className)
            for _,component in ipairs(ok and type(list)=='table'and list or{})do
                if U.valid(component)then
                    local gotOwner,owner=call(component,'GetOwner')
                    local level=gotOwner and U.key(owner)==key and 1 or nil
                    if not level and gotOwner and U.valid(owner)then
                        local gotParent,parent=call(owner,'GetOwner')
                        if gotParent and U.key(parent)==key then level=2 end
                    end
                    if level then
                        total=total+1
                        if #lines<limit then
                            local asset
                            for _,property in ipairs(ASSET_FIELDS)do
                                local value=U.field(component,property)
                                if U.valid(value)then asset=value;break end
                            end
                            local gotVisible,visible=call(component,'IsVisible')
                            local gotParent,parent=call(component,'GetAttachParent')
                            local line=(U.className(component)or'?')..' '..short(component)..(level==2 and'（挂件:'..nameOf(owner)..'）'or'')
                                ..' 资源='..(asset and short(asset)or'无')..' 挂在='..(gotParent and nameOf(parent)or'?')..'@'..socketOf(component)
                                ..' 可见='..tostring(gotVisible and visible)..' 游戏内隐藏='..tostring(U.field(component,'bHiddenInGame'))
                                ..' 强制LOD='..tostring(U.field(component,'ForcedLodModel'))
                            local gotAnim,instance=call(component,'GetAnimInstance')
                            if gotAnim and U.valid(instance)then line=line..' 动画实例='..tostring(U.className(instance))end
                            local animClass=U.field(component,'AnimClass')
                            if U.valid(animClass)then line=line..' 动画类='..short(animClass)end
                            lines[#lines+1]=line
                        end
                    end
                end
            end
        end
        say('外观部件：'..label..'；共'..total..'个'..(total>#lines and'，只列前'..#lines..'个'or''))
        for _,line in ipairs(lines)do say('  '..line)end
    end
    -- Read-only. The animation layers an actor's config links by default, how its movement is set up, and what its
    -- anim instance knows of that movement.
    local function motion(actor,label)
        local config=U.field(actor,'Actor Config')
        local layers=U.array(U.field(config,'Default Linked Animation Layers'))
        local names={};for _,layer in ipairs(layers or{})do names[#names+1]=nameOf(layer)end
        local movement=U.field(actor,'CharacterMovement')
        local velocity=U.field(movement,'Velocity')
        local x,y=U.struct(velocity,'X'),U.struct(velocity,'Y')
        local speed=type(x)=='number'and type(y)=='number'and string.format('%.0f',math.sqrt(x*x+y*y))or'?'
        local _,instance=call(U.field(actor,'Mesh'),'GetAnimInstance')
        local hasVelocity=U.field(instance,'HasVelocity');if hasVelocity==nil then hasVelocity=U.field(instance,'bHasVelocity')end
        say('动画与移动：'..label..'；配置='..nameOf(config)..'；默认动画层='..(layers and(#names>0 and table.concat(names,'|')or'空')or'未读回')
            ..'；移动模式='..tostring(U.field(movement,'MovementMode'))..'；水平速度='..speed..'；最大行走速度='..tostring(U.field(movement,'MaxWalkSpeed'))
            ..'；朝移动方向转身='..tostring(U.field(movement,'bOrientRotationToMovement'))..'；用控制器朝向='..tostring(U.field(actor,'bUseControllerRotationYaw'))
            ..'；动画实例='..tostring(U.className(instance))..'；HasVelocity='..tostring(hasVelocity)..'；DisplacementSpeed='..num(U.field(instance,'DisplacementSpeed')))
    end
    local function look_(r)
        components(r.actor,'魂 '..r.name,MAX_COMPONENT_LINES)
        motion(r.actor,'魂')
        local player=o.player()
        if U.valid(player)then
            components(player,'主角 '..tostring(name(player)),MAX_PLAYER_LINES)
            motion(player,'主角')
        else say('外观部件：主角不可读')end
    end

    ---- Read-only probes (plan 0-2 … 0-10). Each kind runs in its own pcall; a failure writes "探查中断".
    local function stat(actor,field)
        if not stats then
            local ok,module=pcall(require,'character_stats')
            stats=ok and module.new()or false
        end
        if not stats then return nil end
        local ok,value=pcall(stats.read,stats,actor,field)
        return ok and type(value)=='table'and value.current or nil
    end
    local function tagCount(actor,tagName)
        local got,count=call(U.field(actor,'AbilitySystemComponent'),'GetGameplayTagCount',{TagName=fname(tagName)})
        return got and type(count)=='number'and count or nil
    end
    local gameNow=o.now or clock
    local function executionImmunity(r,remove)
        local policy=r.loadout and r.loadout.survival
        if not policy or policy.execution~='immune' or not owned(r) then return end
        if remove and not r.executionTag then return end
        local key='CharacterState.CanNotBeExecuted'
        local before=tagCount(r.actor,key)
        if before==nil or (not remove and before>0) then return end
        local lib=find(ABILITY_UTILS)
        if not U.valid(lib) then return end
        local method=remove and 'RemoveLooseGameplayTag' or 'AddLooseGameplayTag'
        say('即将 '..method..' '..key..' 实例='..r.name)
        local ok=call(lib,method,r.actor,{TagName=fname(key)},false)
        local after=tagCount(r.actor,key)
        if ok and after and after==before+(remove and -1 or 1) then r.executionTag=not remove end
        say('处决免疫 '..r.name..' 标签 '..tostring(before)..'→'..tostring(after))
    end
    local kitOptions={log=o.log,find=find,load=loadClass,findAll=findAll,fname=fname,current=owned,stats=getStats,stat=stat,
        hp=o.hp,aiOf=o.aiOf,nativeTarget=o.nativeTarget,pairProtected=o.pairProtected,fighting=fighting,now=gameNow,clock=gameNow,
        paused=o.paused,loop=o.loop,cancel=o.cancel,guard=actionGuard}
    local defense=o.defense or require('hun_defense').new(kitOptions)
    local grabGuard=o.grabGuard or require('hun_grab_guard').new(kitOptions)
    local supply=o.supply or require('hun_supply').new(kitOptions)
    local shadows=o.shadows or require('hun_shachi').new(kitOptions)
    local brain=require('hun_brain').new({now=gameNow,tag=tagCount,hp=o.hp,stat=stat,pairProtected=o.pairProtected,
        log=o.log or function()end,supply=supply,shadows=shadows,distance=o.distance or function()end,
        target=function(r)
            if (r.team=='blue' or r.team=='red') and not battle then return nil end
            local target=o.target and o.target(r.actor,r.team)
            if U.valid(target) and U.key(target)~=U.key(r.actor) and U.inWorld(target,o.world())
                and (r.team=='neutral' or U.key(target)~=U.key(o.player())) then return target end
        end})
    -- One timer for all brains and no idle timer after the last NPC leaves.
    local brainTimer=require('hun_combat_timer').new(100,o.loop,o.cancel or CancelDelayedAction,gameNow,say)
    local function stopBrains()brainTimer:stop() end
    local function decide(record)
        if owned(record) then brain:tick(record) end
    end
    local function tickBrains()
        if not self.alive then return end
        local count,now=0,nil
        for _,record in pairs(records)do
            if record.intent and not record.kitStopping and not record.dead then
                count=count+1
                local waiting=(record.team=='blue' or record.team=='red') and not battle and record.wasIdle
                if not waiting or record.shadowBusy or record.supplyBusy then
                    if record.brainErrorAt then now=now or gameNow() end
                    if not record.brainErrorAt or (now and (now<record.brainErrorAt or now-record.brainErrorAt>=record.brainRetryDelay)) then
                        local ok,err=pcall(decide,record)
                        if ok then
                            if record.brainErrorAt then say('战斗决策恢复 '..record.name) end
                            record.brainErrorAt,record.brainRetryDelay=nil,nil
                        else
                            if not record.brainErrorAt then say('战斗决策稍后重试 '..record.name..' '..tostring(err)) end
                            record.brainErrorAt=now or gameNow() or 0
                            record.brainRetryDelay=math.min(4,(record.brainRetryDelay or .25)*2)
                            record.intent.busy=true
                        end
                    end
                end
            end
        end
        if count==0 then stopBrains() end
    end
    local function startBrain(r)
        if not r.usedPhases then brain:start(r) end
        r.brainTimerPending=not brainTimer:ensure(tickBrains)
    end
    local function skeletonOf(actor)
        local _,asset=call(U.field(actor,'Mesh'),'GetSkeletalMeshAsset')
        return U.field(asset,'Skeleton')
    end
    -- 0-2 anim instance, linked instances and the movement references the anim graph reads.
    local function probeAnim(actor,label)
        local mesh=U.field(actor,'Mesh')
        local _,instance=call(mesh,'GetAnimInstance')
        local linked={}
        for _,item in ipairs(U.array(U.field(mesh,'LinkedInstances'))or{})do linked[#linked+1]=tostring(U.className(item))end
        local _,graph=call(mesh,'GetLinkedAnimGraphInstanceByTag',fname('MMGraph'))
        local _,post=call(mesh,'GetPostProcessInstance')
        local hasVelocity=U.field(instance,'HasVelocity');if hasVelocity==nil then hasVelocity=U.field(instance,'bHasVelocity')end
        say('动画实例：'..label..'；实例类='..tostring(U.className(instance))..'；AnimClass='..nameOf(U.field(mesh,'AnimClass'))
            ..'；链接实例=['..table.concat(linked,'|')..']；MMGraph='..(U.valid(graph)and tostring(U.className(graph))or'无')
            ..'；MMGraph.CharacterMovement有效='..tostring(U.valid(U.field(graph,'CharacterMovement')))
            ..'；后处理='..(U.valid(post)and tostring(U.className(post))or'无')
            ..'；RenewalHun有效='..tostring(U.valid(U.field(instance,'RenewalHun')))..'；CharacterMovement有效='..tostring(U.valid(U.field(instance,'CharacterMovement')))
            ..'；bUseNewLocomotion='..tostring(U.field(instance,'bUseNewLocomotion'))..'；bUseMM='..tostring(U.field(instance,'bUseMM'))
            ..'；HasVelocity='..tostring(hasVelocity)..'；DisplacementSpeed='..num(U.field(instance,'DisplacementSpeed'))
            ..'；WeaponType='..tostring(U.field(instance,'WeaponType')))
    end
    -- 0-3 which slots the montage playing now uses, and whether the anim graph has them active.
    local function probeSlots(r,where)
        if (slotLines[r.batch]or 0)>=SLOT_LINES then return end
        local _,instance=call(U.field(r.actor,'Mesh'),'GetAnimInstance')
        local _,montage=call(instance,'GetCurrentActiveMontage')
        if not U.valid(montage)then return end
        slotLines[r.batch]=(slotLines[r.batch]or 0)+1
        local slots={}
        for _,track in ipairs(U.array(U.field(montage,'SlotAnimTracks'))or{})do slots[#slots+1]=tostring(text(U.struct(track,'SlotName')))end
        local _,default=call(instance,'IsSlotActive',fname('DefaultSlot'))
        local _,upper=call(instance,'IsSlotActive',fname('UpperBody'))
        say('蒙太奇槽：魂 '..r.name..'（'..where..'）；当前蒙太奇='..short(montage)..'；槽=['..table.concat(slots,'|')..']；DefaultSlot活动='..tostring(default)
            ..'；UpperBody活动='..tostring(upper)..'；动画实例='..tostring(U.className(instance)))
    end
    -- 0-4 hat socket, material slots and the hat bone's scale.
    local function probeHat(actor,label)
        local mesh=U.field(actor,'Mesh')
        local _,socket=call(mesh,'DoesSocketExist',fname('hatSocket'))
        local _,count=call(mesh,'GetNumMaterials')
        local slots={}
        for _,slot in ipairs(U.array(select(2,call(mesh,'GetMaterialSlotNames')))or{})do slots[#slots+1]=tostring(text(slot))end
        local materials={}
        if type(count)=='number'then for i=0,math.min(count,16)-1 do local _,m=call(mesh,'GetMaterial',i);materials[#materials+1]=nameOf(m)end end
        local _,transform=call(mesh,'GetSocketTransform',fname('hat'),3)
        local scale=U.struct(transform,'Scale3D')
        local _,asset=call(mesh,'GetSkeletalMeshAsset')
        say('帽子与材质：'..label..'；网格='..nameOf(asset)..'；hatSocket存在='..tostring(socket)..'；材质数='..tostring(count)
            ..'；材质槽=['..table.concat(slots,'|')..']；材质=['..table.concat(materials,'|')..']；hat骨缩放=('
            ..num(U.struct(scale,'X'))..','..num(U.struct(scale,'Y'))..','..num(U.struct(scale,'Z'))..')')
    end
    -- 0-5 the body's skeleton next to the player's (read only).
    local function probeSkeleton(r,label)
        local mine,theirs=skeletonOf(r.actor),skeletonOf(o.player())
        say('骨架：'..label..'；魂='..nameOf(mine)..'；主角（只读）='..nameOf(theirs)..'；相同='..tostring(U.key(mine)~=nil and U.key(mine)==U.key(theirs)))
    end
    -- 0-6 granted abilities and the tags that decide executions, deflects and AI.
    local function probeAbilities(actor,label)
        local asc=U.field(actor,'AbilitySystemComponent')
        local specs=U.array(U.struct(U.field(asc,'ActivatableAbilities'),'Items'))
        local names,double={},0
        for i,spec in ipairs(specs or{})do
            if i>512 then break end
            local ability=U.struct(spec,'Ability')
            -- A spec holds the class default object: Default__GA_X_C reads as GA_X_C.
            local n=(nameOf(ability):gsub('^Default__',''))
            if n:find('^GA_Hun_Double_')then double=double+1 end
            if #names<MAX_ABILITY_NAMES then
                names[#names+1]=n..'(h='..tostring(U.struct(U.struct(spec,'Handle'),'Handle'))..',active='..tostring(U.struct(spec,'ActiveCount'))..')'
            end
        end
        local counts={}
        for _,t in ipairs(PROBE_TAGS)do counts[#counts+1]=t..'='..tostring(tagCount(actor,t))end
        say('技能与标签：'..label..'；技能数='..(specs and #specs or'未读回')..'；GA_Hun_Double_*='..double..'；清单=['..table.concat(names,' ')
            ..((specs and #specs>#names)and' …'or'')..']；'..table.concat(counts,' '))
    end
    -- 0-7 the components that execution, input and weapons go through.
    local function probeComponents(actor,label)
        local main={TagName=fname(MAIN_SLOT)}
        local exec=U.field(actor,'Execution Component')
        local info=U.field(exec,'CurrentExecutionInfo')
        say('组件：'..label..'；ExecutionComponent 有效='..tostring(U.valid(exec))..' ActorConfig='..nameOf(U.field(exec,'ActorConfig'))
            ..' AbilitySystem有效='..tostring(U.valid(U.field(exec,'AbilitySystem')))..' 当前处决 执行方有效='..tostring(weak(U.struct(info,'Executor'))~=nil)
            ..' 目标有效='..tostring(weak(U.struct(info,'Target'))~=nil))
        local input=U.field(actor,'Ability Input Component')
        local bindings=U.array(U.field(input,'InputBindings'))
        say('组件：'..label..'；AbilityInputComponent 有效='..tostring(U.valid(input))..' AbilitySystem有效='..tostring(U.valid(U.field(input,'AbilitySystem')))
            ..' Controller有效='..tostring(U.valid(U.field(input,'Controller')))..' SGameInput有效='..tostring(weak(U.field(input,'SGameInput'))~=nil)
            ..' ActionPhase='..tostring(U.field(input,'ActionPhase'))..' InputBindings数='..(bindings and #bindings or'未读回'))
        local wc=U.field(actor,'Character Weapons Component')
        if not announced.weapons then
            announced.weapons=true
            say('即将 只读武器组件 GetSlotWeapons/GetCurrentWeaponIndex/GetCurrentChangeWeaponCooldown（本次加载第一次） '..label)
        end
        local slotCount=Weapons.mainSlotCount(wc,main)
        local _,index=call(wc,'GetCurrentWeaponIndex',main,false)
        local _,cooldown=call(wc,'GetCurrentChangeWeaponCooldown',main)
        local runtime,keys=U.field(wc,'RuntimeWeaponData'),0
        pcall(function()runtime:ForEach(function()keys=keys+1 end)end)
        local unarm=U.array(U.field(wc,'UnarmLayers'))
        say('组件：'..label..'；CharacterWeaponsComponent 有效='..tostring(U.valid(wc))..' AbilitySystem有效='..tostring(U.valid(U.field(wc,'AbilitySystem')))
            ..' AbilityInput有效='..tostring(weak(U.field(wc,'AbilityInput'))~=nil)..' 主槽武器数='..tostring(slotCount or'未读回')
            ..' 当前主武器序号='..tostring(index)..' 换武器冷却='..num(cooldown)..' RuntimeWeaponData键数='..keys..' UnarmLayers数='..(unarm and #unarm or'未读回'))
        say('组件：'..label..'；DeflectComponent 存在='..tostring(U.valid(U.field(actor,'Deflect Component'))))
    end
    -- 0-8 resource attributes.
    local function probeAttributes(actor,label)
        local parts={}
        for _,field in ipairs(PROBE_ATTRIBUTES)do local v=stat(actor,field);parts[#parts+1]=field..'='..(v and num(v)or'不可读')end
        say('资源属性：'..label..'；'..table.concat(parts,' '))
    end
    local function guarded(kind,fn,...)
        local ok,why=pcall(fn,...)
        if not ok then say('探查中断：'..kind..' 原因='..tostring(why))end
    end
    -- One full probe of the body at a stage ('改前' before hun_look writes anything, '改后' at the first support
    -- cycle). Only the first body of a summon request is probed, so each kind writes at most a few lines a request.
    local function probe(r,stage)
        if not probing or probed[r.batch]~=r.name then return end
        local label='魂 '..r.name..' '..stage
        guarded('动画实例',probeAnim,r.actor,label)
        guarded('帽子与材质',probeHat,r.actor,label)
        guarded('骨架',probeSkeleton,r,label)
        guarded('技能与标签',probeAbilities,r.actor,label)
        guarded('组件',probeComponents,r.actor,label)
        guarded('资源属性',probeAttributes,r.actor,label)
        guarded('蒙太奇槽',probeSlots,r,stage)
        if stage=='改前'then
            local player=o.player()
            if U.valid(player)then guarded('动画实例',probeAnim,player,'主角（只读）')else say('探查中断：主角不可读')end
        end
    end
    -- 0-9 the deflect frames the body receives (ReceiveFrames), every SAMPLE_MS while the sampler runs, and 0-10 the
    -- player's weapon-switch cooldown (read only). At most one line a second, SAMPLE_LINES in a load.
    local function sampleFrames(r,s)
        local deflect=U.field(r.actor,'Deflect Component')
        local map=U.field(deflect,'ReceiveFrames')
        local now=o.now and o.now()
        local entries,count={},0
        if map~=nil then
            pcall(function()map:ForEach(function(_,v)
                count=count+1
                if #entries<4 then
                    local frame=U.unwrap(v)
                    local hit=U.struct(frame,'HitGameTime')
                    local source=weak(U.struct(frame,'SourceAction'))
                    local kind=U.field(source,'DeflectBulletType');if kind==nil then kind=U.field(source,'DeflectType')end
                    entries[#entries+1]=string.format('距命中=%s 闪避=%s 类型=%s 反击=%s',type(hit)=='number'and type(now)=='number'and num(hit-now)or'?',
                        tostring(U.struct(frame,'IsDodge')),tostring(kind),nameOf(U.struct(frame,'CounterAbility')))
                end
            end)end)
        end
        s.samples=s.samples+1
        if count>0 then s.seen=s.seen+1 end
        local t=clock()
        if sampleLines<SAMPLE_LINES and(count>0 and t-(s.lastLine or-1)>=1 or t-(s.lastBeat or s.started)>=10)then
            sampleLines=sampleLines+1;s.lastLine=t
            if count==0 then s.lastBeat=t end
            say('预告：魂 '..r.name..'；条数='..count..(map==nil and'（读不到 ReceiveFrames）'or'')..'；已采样'..s.samples..'次 有预告'..s.seen..'次'
                ..(#entries>0 and'；'..table.concat(entries,'；')or''))
        end
        probeSlots(r,'战斗采样')
        if cooldownLines<COOLDOWN_LINES and t-(s.lastCooldown or-1)>=1 then
            s.lastCooldown=t
            local player=o.player()
            local wc=U.field(player,'Character Weapons Component')
            if not announced.playerCooldown then
                announced.playerCooldown=true
                say('即将 只读玩家 武器组件 GetCurrentChangeWeaponCooldown（本次加载第一次，不写）')
            end
            local got,cooldown=call(wc,'GetCurrentChangeWeaponCooldown',{TagName=fname(MAIN_SLOT)})
            if got and type(cooldown)=='number'and cooldown~=lastCooldown and(lastCooldown~=nil or cooldown>0)then
                cooldownLines=cooldownLines+1
                say('只读玩家 换武器冷却='..num(cooldown)..'（上次读到='..tostring(lastCooldown and num(lastCooldown))..'）')
            end
            if got and type(cooldown)=='number'then lastCooldown=cooldown end
        end
    end
    local function stopSampler(key,why)
        local s=samplers[key];if not s then return end
        samplers[key]=nil
        if s.handle then pcall(o.cancel or CancelDelayedAction,s.handle)end
        say('预告采样结束：'..why..'；共采样'..s.samples..'次 有预告'..s.seen..'次')
    end
    local function startSampler(key,r)
        if not probing or probed[r.batch]~=r.name or samplers[key]or sampleLines>=SAMPLE_LINES then return end
        local loop=o.loop or LoopInGameThreadWithDelay
        if type(loop)~='function'then return end
        local s={samples=0,seen=0,started=clock()}
        samplers[key]=s
        local ok,handle=pcall(loop,SAMPLE_MS,function()
            if samplers[key]~=s then return end
            if records[key]~=r or not current(r.actor,r)then stopSampler(key,'实例离场或已变化');return end
            if clock()-s.started>=SAMPLE_SECONDS or sampleLines>=SAMPLE_LINES then stopSampler(key,'到时或到行数上限');return end
            local read,why=pcall(sampleFrames,r,s)
            if not read then stopSampler(key,'探查中断：'..tostring(why))end
        end)
        if not ok or handle==nil or handle==false then samplers[key]=nil;say('探查中断：预告采样没登记 '..tostring(handle));return end
        s.handle=handle
    end
    -- 1-7 read only: once HP reaches 0, one line a second for DEATH_SECONDS: health, the Dead tag, whether the actor
    -- is being destroyed, whether it is still valid. Nothing is written.
    local function deathLine(d)
        local t=clock()
        if t-(d.last or-1)<1 then return end
        d.last=t;d.lines=d.lines+1
        if not current(d.actor,d.record)then
            say('死亡读回：实例='..d.name..' 第'..string.format('%.0f',t-d.at)..'秒 已无效=true，停止读回');d.lines=math.huge;return
        end
        local read,hp=pcall(o.hp,d.actor)
        local _,destroying=call(d.actor,'IsActorBeingDestroyed')
        local parts=d.record and type(look.partsText)=='function'and look:partsText(d.record)or''
        say('死亡读回：实例='..d.name..' 第'..string.format('%.0f',t-d.at)..'秒 HP='..tostring(read and hp)..' Dead='..tostring(tagCount(d.actor,'CharacterState.Dead'))
            ..' 销毁中='..tostring(destroying)..' 有效=true'..(parts~=''and('；新部件可见=['..parts..']')or''))
        local hide=steps.deathHide==true and t-d.at>=DEATH_HIDE_AFTER
        if steps.deathHide=='follow' and not d.hidden then
            local mesh=U.field(d.actor,'Mesh')
            local readVisible,visible=call(mesh,'IsVisible')
            hide=hidden(d.actor)==true or U.field(mesh,'bHiddenInGame')==true
                or (not (d.record and d.record.rigBaseline) and readVisible and visible==false)
        end
        if hide and not d.hidden and d.record then
            d.hidden=true;optional(look,'hideParts',d.record)
        end
    end
    -- Parts and weapon actors of a body that left the arena: destroyed now, or after its death readback.
    local function cleanup(r,why)
        optional(look,'cleanup',r,why)
        optional(weapons,'cleanup',r,why)
    end
    local function hpOf(actor)
        local read,hp=pcall(o.hp,actor)
        return read and type(hp)=='number'and hp or nil
    end
    local function watchDeath(key,r)
        if not steps.deathWatch or dying[key]or r.deathWatched then return end
        r.deathWatched=true
        dying[key]={actor=r.actor,name=r.name,at=clock(),lines=0,record=r}
        say('死亡读回开始：实例='..r.name..'；HP到0，之后每秒一行，最多'..DEATH_SECONDS..'秒，只读')
    end
    local function endDeath(key,d,why)
        dying[key]=nil
        if d.left then cleanup(d.record,'死亡读回结束（'..why..'）')end
    end
    local function tickDeaths()
        for key,d in pairs(dying)do
            if d.lines>=DEATH_SECONDS or clock()-d.at>DEATH_SECONDS+0.5 then endDeath(key,d,'到时或已无效')
            else
                local ok,why=pcall(deathLine,d)
                if not ok then say('死亡读回中断：'..tostring(why));endDeath(key,d,'中断')end
            end
        end
    end

    local accessoryClasses={}
    local function releaseEffects(r)
        if not r.accessoryHandles or not current(r.actor,r) then return end
        local asc=U.field(r.actor,'AbilitySystemComponent')
        if not U.valid(asc) then return end
        local confirmed,failed=0,{}
        for _,entry in ipairs(r.accessoryHandles)do
            if U.key(entry.asc)~=U.key(asc) then
                failed[#failed+1]=entry.label..'（能力组件已更换）'
            else
                if probing then say('即将撤下饰品效果 '..entry.label) end
                local ok,result=call(asc,'RemoveActiveGameplayEffect',entry.handle,1)
                local got,count=call(asc,'GetGameplayEffectCount',entry.cls,nil,true)
                if ok and result~=false and got and type(count)=='number' then confirmed=confirmed+1
                else failed[#failed+1]=entry.label..'（撤下调用或层数未确认）' end
                if probing then say('撤下饰品 '..entry.label..' 调用='..tostring(ok and result~=false)..' 剩余层数='..tostring(got and count)) end
            end
        end
        if #r.accessoryHandles>0 then
            say('撤下效果：实例='..r.name..'；调用并读回层数 '..confirmed..'/'..#r.accessoryHandles
                ..(#failed>0 and '；未确认：'..table.concat(failed,'、') or ''))
        end
        r.accessoryHandles=nil
    end
    local function applyEffects(r,effects,category)
        if #effects==0 then return end
        local asc=U.field(r.actor,'AbilitySystemComponent')
        if not U.valid(asc)then say(category..'：实例='..r.name..'；ASC未就绪，没有施加');return end
        if r.loadout.kit then
            local got,owner=call(asc,'GetOwner')
            if not got or U.key(owner)~=U.key(r.actor) then say(category..'：ASC 归属未确认');return end
        end
        r.accessoryHandles=r.accessoryHandles or {}
        local applied,unconfirmed=0,{}
        for _,effect in ipairs(effects)do
            if not current(r.actor,r)then unconfirmed[#unconfirmed+1]='实例已变化，停止';break end
            local cls=accessoryClasses[effect.path]
            local loaded=U.valid(cls)
            if not loaded then loaded,cls=pcall(loadClass,effect.path) end
            if not loaded or not U.valid(cls)then unconfirmed[#unconfirmed+1]=effect.label..'（效果类没载入）'
            else
                accessoryClasses[effect.path]=cls
                local got,before=call(asc,'GetGameplayEffectCount',cls,nil,true)
                if not got or type(before)~='number' then
                    unconfirmed[#unconfirmed+1]=effect.label..'（原层数未读回）'
                else
                    if probing then say('即将施加'..category..' '..effect.label..' 实例='..r.name) end
                    local sent,handle=call(asc,'BP_ApplyGameplayEffectToSelf',cls,effect.level,{})
                    local again,after=call(asc,'GetGameplayEffectCount',cls,nil,true)
                    if sent and again and type(after)=='number' and after>before then
                        applied=applied+1
                        if handle~=nil then
                            local id=U.struct(handle,'Handle')
                            local saved=type(id)=='number' and {Handle=id,bPassedFiltersAndWasExecuted=true} or handle
                            r.accessoryHandles[#r.accessoryHandles+1]={handle=saved,cls=cls,label=effect.label,asc=asc,effect=effect}
                        end
                    else
                        unconfirmed[#unconfirmed+1]=effect.label..'（调用='..tostring(sent==true)..' 层数'..tostring(before)..'→'..tostring(again and after)..'）'
                        if sent and handle and current(r.actor,r) then
                            say('即将撤回未确认饰品 '..effect.label)
                            call(asc,'RemoveActiveGameplayEffect',handle,1)
                            local checked,count=call(asc,'GetGameplayEffectCount',cls,nil,true)
                            say('撤回后层数='..tostring(checked and count)..' 原层数='..before)
                        end
                    end
                end
            end
        end
        say(category..'：实例='..r.name..'；方案启用'..#effects..'条；效果层数增加'..applied..'条'
            ..(#unconfirmed>0 and'；未确认：'..table.concat(unconfirmed,'、',1,math.min(#unconfirmed,12))..(#unconfirmed>12 and' 等'..#unconfirmed..'条'or'')or''))
        return applied
    end
    local regenPrefix='/PBZCombatAsset/Prototypes/GameplayEffects/Accessories/New/GE_Accessory_Regen_Lv'
    local function suspendRegen(r)
        if not r.accessoryHandles or not current(r.actor,r) then return end
        local asc=U.field(r.actor,'AbilitySystemComponent')
        local own=U.key(asc);if not own then return end
        for i=#r.accessoryHandles,1,-1 do
            local entry=r.accessoryHandles[i];local fx=entry.effect
            if fx and (fx.path==regenPrefix..'1.GE_Accessory_Regen_Lv1_C' or fx.path==regenPrefix..'2.GE_Accessory_Regen_Lv2_C')
                and U.key(entry.asc)==own then
                local got,before=call(asc,'GetGameplayEffectCount',entry.cls,nil,true)
                if got and type(before)=='number' and before>0 then
                    local sent,result=call(asc,'RemoveActiveGameplayEffect',entry.handle,1)
                    local read,after=call(asc,'GetGameplayEffectCount',entry.cls,nil,true)
                    say('死亡停用周期回血 '..r.name..' 层数='..tostring(before)..'→'..tostring(after))
                    if sent and result~=false and read and after==before-1 then
                        table.remove(r.accessoryHandles,i);r.suspendedRegen=fx
                    end
                end
            end
        end
    end
    local function equip(r)
        local profile=r.loadout
        r.effectsPending=false
        if not profile or (not profile.kit and not profile.accessories) then return end
        local asc=U.field(r.actor,'AbilitySystemComponent')
        local ready=U.valid(asc)
        if ready and profile.kit then
            local got,owner=call(asc,'GetOwner')
            ready=got and U.key(owner)==U.key(r.actor)
        end
        if not ready then
            r.effectsPending=r.checks<WATCH
            if r.checks==1 or not r.effectsPending then say('出生效果：能力组件或归属尚未就绪；实例='..r.name..'；继续复查='..tostring(r.effectsPending)) end
            return
        end
        local hp=hpOf(r.actor)
        if r.dead or (hp and hp<=0) or (tagCount(r.actor,'CharacterState.Dead') or 0)>0 then return end
        if profile.kit then
            r.kitReady=true
            executionImmunity(r,false)
            optional(grabGuard,'start',r)
            optional(shadows,'equip',r)
        end
        local before
        if r.loadout and r.loadout.kit then before=Vitals.read(r.actor,stat) end
        if r.loadout and r.loadout.kit and tagCount(r.actor,'CharacterState.Talent.EnableNotConsumeBullet')==0 then
            -- The native armament cost task reads this talent tag and performs its own chance roll.
            local effect='GE_Talent_EnableNotConsumeBullet'
            applyEffects(r,{{label='影武暗源节省',level=1,path='/PBZCombatAsset/Prototypes/GameplayEffects/Talent/'..effect..'.'..effect..'_C'}},'天赋效果')
        end
        r.equipped=applyEffects(r,r.loadout and r.loadout.accessories and r.loadout.effects or {},'饰品效果')
        if before then
            Vitals.fillSpawn(r,before,Vitals.read(r.actor,stat),{current=owned,stats=getStats,read=stat,
                alive=function(a)return (hpOf(a) or 0)>0 and tagCount(a,'CharacterState.Dead')==0 end,
                log=o.log or function()end})
        end
    end
    local function describe(r)
        local ai=o.aiOf and o.aiOf(r.actor);local controller=U.field(r.actor,'Controller')
        local read,hp=pcall(o.hp,r.actor)
        return 'HP='..tostring(read and hp)..'；隐藏='..tostring(hidden(r.actor))..'；Controller有效='..tostring(U.valid(controller))..'；AI有效='..tostring(U.valid(ai))
    end
    function self:spawn(arena,team,count,revision,frozenProfile)
        if context or not self.alive then return {ok=false,message='魂本体验证正在处理',spawned_count=0}end
        if team~='blue'and team~='red'and team~='neutral'and team~='companion'then return {ok=false,message='阵营无效',spawned_count=0}end
        if type(count)~='number'or count%1~=0 or count<1 or count>100 then return {ok=false,message='数量须为1～100',spawned_count=0}end
        local world=o.world();if not U.valid(world)then return {ok=false,message='当前世界未就绪',spawned_count=0}end
        batch=batch+1
        local read,loadout=true,frozenProfile
        if frozenProfile==nil then
            read,loadout=pcall(o.loadout or function()end)
        elseif type(frozenProfile)~='table' or not frozenProfile.kit or tostring(frozenProfile.revision)~=tostring(revision) then
            return {ok=false,message='排队魂方案与请求不一致',spawned_count=0}
        end
        if o.requireProfile and (not read or type(loadout)~='table') then
            return {ok=false,message='魂方案未读回，请打开助手并重新召唤',spawned_count=0}
        end
        if o.requireProfile and not loadout.kit then
            return {ok=false,message='请打开本版助手以转换旧方案，然后重新召唤',spawned_count=0}
        end
        if read and type(loadout)=='table' and loadout.kit and tostring(loadout.revision)~=tostring(revision) then
            return {ok=false,message='方案已变更，请重新召唤',spawned_count=0}
        end
        context={team=team,world=U.key(world),revision=revision,epoch=epoch,batch=batch,loadout=read and type(loadout)=='table'and loadout or nil}
        local ok,result=pcall(arena.spawn,arena,Body.path,team,count,true)
        context=nil
        if not ok then return {ok=false,uncertain=true,message='魂本体生成未确认，停止继续尝试并先清理',spawned_count='unknown'}end
        if type(result)=='table' and (result.ok or (type(result.spawned_count)=='number' and result.spawned_count>0)) then
            result.message=(result.message or'')..'；魂按召唤时的方案出战'
        end
        return result
    end
    local function stopKit(r,why)
        r.kitStopping=true
        role:restore(r)
        executionImmunity(r,true)
        optional(grabGuard,'stop',r);optional(actionGuard,'stop',r)
        optional(defense,'stop',r);optional(supply,'stop',r);optional(shadows,'cleanup',r)
        optional(weapons,'stop',r,why or '停止');releaseEffects(r)
    end
    function self:capture(actor,path)
        if not context or path~=Body.path then return end
        local key,n=U.key(actor),name(actor)
        if not key then return end
        local previous=records[key]
        if previous and previous.batch==context.batch and previous.name==n and previous.world==context.world then return end
        if dying[key] then endDeath(key,dying[key],'出生地址已重新使用') end
        if previous then
            records[key]=nil
            stopSampler(key,'出生地址已重新使用')
            stopKit(previous,'出生地址已重新使用')
            cleanup(previous,'出生地址已重新使用')
        end
        records[key]={actor=actor,name=n,team=context.team,world=context.world,revision=context.revision,epoch=context.epoch,batch=context.batch,loadout=context.loadout,phase='captured',
            refused=context.epoch~=epoch or not n or not current(actor)or context.world~=U.key(o.world())}
    end
    -- Before the game initialises the body: identity only. Nothing is written and the template is only read.
    function self:prepare(actor)
        local r=records[U.key(actor)or''];if not r then return true end
        if r.refused or not current(actor,r)then return false,'魂本体身份或世界已变化'end
        local source=U.field(actor,'Actor Config');local sourceName=name(source)
        local initial=tags(source)
        say('出生前读回：实例='..r.name..'；配置='..tostring(sourceName and sourceName:match(' (/.+)$'))..'；是预期模板='..tostring(sourceName~=nil and sourceName:match(' (/.+)$')==CONFIG)
            ..'；模板初始标签='..(initial and table.concat(initial,'|')or'未读回')..'；不复制、不改模板'
            ..'；方案版本='..tostring(r.loadout and r.loadout.revision)..'（请求='..tostring(r.revision)..'）')
        r.phase='prepared';return true
    end
    -- After FinishSpawn: the two tags are cleared, the body is probed ('改前'), then hun_look swaps its mesh and anim
    -- class. Whatever those steps read back, the birth stands (false only when the identity changed).
    function self:finished(actor)
        local r=records[U.key(actor)or''];if not r then return true end
        if not current(actor,r)then return false,'魂本体身份或世界已变化'end
        role:prepare(r)
        local zero,text_=clear(r)
        r.phase,r.checks,r.tags,r.zero='finished',0,text_,zero
        say('出生后标签：实例='..r.name..'；'..text_..'；两项都为0='..tostring(zero)..'；'..describe(r))
        self.prepared=self.prepared+1
        self.message=zero and'魂已正常出生，隐藏与不可仇恨标签读回为0，等待画面和行为验证'or'魂已正常出生，但隐藏或不可仇恨标签还没读回为0，可能看不见或不被索敌'
        if probing and not probed[r.batch]then probed[r.batch]=r.name end
        probe(r,'改前')
        local applied,why=pcall(look.apply,look,r,function()return current(actor,r)end)
        if not applied then say('外观与动画中断：实例='..r.name..' 原因='..tostring(why))end
        return true
    end
    function self:prepareRole(actor)
        local r=records[U.key(actor) or '']
        if r and current(actor,r) then
            role:prepare(r)
            role:excludePlayer(r)
        end
    end
    function self:teamBarName(unit)
        if unit.class_path==Body.path and (unit.team=='blue' or unit.team=='red') and self:owns(unit.actor) then return '魂' end
    end
    function self:isArenaBody(actor)
        local r=records[U.key(actor) or '']
        return r~=nil and (r.team=='blue' or r.team=='red') and current(actor,r)
    end
    function self:confirmedDead(actor)
        local r=records[U.key(actor) or '']
        if not r or not r.dead or not current(actor,r) then return false end
        -- Arena and HUD readers can run before the next support update.
        return tagCount(actor,'CharacterState.Dead')~=0 or (hpOf(actor) or 0)<=0
    end
    function self:hudVitals(unit)
        if unit.class_path~=Body.path or not self:owns(unit.actor) then return end
        local r=records[U.key(unit.actor)]
        local v=Vitals.read(unit.actor,stat)
        if r.awaitHitSample then
            local who=type(r.awaitHitSample)=='string' and r.awaitHitSample or '玩家';r.awaitHitSample=nil
            say(who..'命中后下一拍 '..r.team..' '..r.name..' HP='..tostring(v.hp)..' 杀气='..tostring(v.shachi)..'/'..tostring(v.shachiMax))
        end
        r.lastHudSample=v
        if self:confirmedDead(unit.actor) then v.hp=0 end
        return v
    end
    function self:tick(members,battleActive)
        if not self.alive then return end
        battle=battleActive==true
        optional(actionGuard,'tick')
        if next(records)then lastMembers=members or{};self:follow(members)else lastMembers={}end
        if next(dying)then tickDeaths()end
    end
    function self:follow(members)
        local motionTime,outfitSweep
        local owned={};for _,m in ipairs(members or{})do local key=U.key(m.actor);if key then owned[key]=true end end
        for key,r in pairs(records)do
            if not owned[key]or not current(r.actor,r)then
                stopSampler(key,'实例离场')
                stopKit(r,'实例离场')
                records[key]=nil
                if r.dead or(r.phase=='observed'and U.valid(r.actor)and(hpOf(r.actor)or 1)<=0)then watchDeath(key,r)end
                if dying[key]and dying[key].record==r then dying[key].left=true else cleanup(r,'实例离场')end
            elseif r.phase=='observed' then
                local hp=hpOf(r.actor)
                local dead
                if r.dead or (r.loadout and r.loadout.kit) or (hp and hp<=0) then
                    dead=tagCount(r.actor,'CharacterState.Dead')
                end
                if not r.dead and ((hp and hp<=0) or (dead and dead>0)) and not self:holdsDeath(r.actor)
                    and (tagCount(r.actor,'Ability.Action.Hun.HeiMoShang.Reborn') or 0)==0
                    and (tagCount(r.actor,'CharacterState.Immortal.HeiMoShang') or 0)==0 then
                    r.dead=true
                    optional(supply,'interrupt',r);optional(shadows,'interrupt',r)
                    r.supplyBusy,r.shadowBusy=false,false
                    if r.intent then r.intent.busy=false;r.intent.busyUntil=nil;r.intent.incomingUntil=nil end
                    watchDeath(key,r)
                elseif r.dead and dead==0 and hp and hp>0 then
                    r.dead,r.deathWatched=false,false
                    r.brainErrorAt,r.brainRetryDelay=nil,nil
                    if dying[key] then endDeath(key,dying[key],'死亡标签已解除且生命为正') end
                    optional(look,'restoreDeathVisibility',r)
                    if r.suspendedRegen then
                        local fx=r.suspendedRegen;r.suspendedRegen=nil;applyEffects(r,{fx},'重生恢复周期回血')
                    end
                    r.regenDeathChecked=nil
                    if r.intent then startBrain(r) end
                end
                if r.dead and dead and dead>0 and not r.regenDeathChecked and not self:holdsDeath(r.actor)
                    and tagCount(r.actor,'Ability.Action.Hun.HeiMoShang.Reborn')==0
                    and tagCount(r.actor,'CharacterState.Immortal.HeiMoShang')==0 then
                    r.regenDeathChecked=true;suspendRegen(r)
                end
            end
            if records[key]==r and not r.dead and (r.phase=='finished'or r.phase=='observed')and r.checks<WATCH then
                r.checks=r.checks+1
                local zero,text_=clear(r)
                if text_~=r.tags then say('标签变化（第'..r.checks..'次复查）：实例='..r.name..'；'..text_..'；两项都为0='..tostring(zero))end
                r.tags,r.zero=text_,zero
                r.streak=zero and(r.streak or 0)+1 or 0
                if r.phase=='finished'then
                    say('本体初始化读回：实例='..r.name..'；'..describe(r))
                end
                if r.phase=='finished' or r.effectsPending then
                    local equipped,why=pcall(equip,r)
                    if not equipped then say('饰品效果施加中断：'..tostring(why))end
                end
                if r.phase=='finished'then
                    if probing and not dumped[r.batch]then
                        dumped[r.batch]=true
                        local listed,why2=pcall(look_,r)
                        if not listed then say('外观探查中断：'..tostring(why2))end
                        r.lookLogged=true
                    end
                    local rechecked,why3=pcall(look.recheck,look,r)
                    if not rechecked then say('外观复读中断：'..tostring(why3))end
                    probe(r,'改后')
                    startSampler(key,r)
                    r.phase='observed'
                elseif r.streak>=2 and not r.shown and hidden(r.actor)==true and mayRevealAfterSpawn(U.field(r.actor,'AbilitySystemComponent')) then
                    -- The tags have read zero for two cycles in a row and the game still keeps the actor hidden.
                    r.shown=true
                    local wrote=call(r.actor,'SetActorHiddenInGame',false)
                    say('解除隐藏：实例='..r.name..'；SetActorHiddenInGame(false)调用='..tostring(wrote==true)..'；隐藏读回='..tostring(hidden(r.actor)))
                end
                if r.checks==1 then self:prepareRole(r.actor)end
                if not r.weaponSetupCheck and r.checks>=WEAPON_CHECK and records[key]==r and not r.dead
                    and (not (r.loadout and r.loadout.kit) or r.kitReady) then
                    r.weaponSetupCheck=r.checks
                    optional(weapons,'equip',r)
                    if r.loadout and r.loadout.kit then
                        startBrain(r);optional(defense,'start',r)
                    end
                elseif r.weaponInitPending and r.weaponSetupCheck and not r.dead and records[key]==r
                    and (r.checks==r.weaponSetupCheck+2 or r.checks==r.weaponSetupCheck+6) then
                    r.wep=nil
                    optional(weapons,'equip',r)
                end
                if r.lookLogged and MOTION_CHECKS[r.checks]then
                    local read,why=pcall(motion,r.actor,'魂（第'..r.checks..'次复查）')
                    if not read then say('动画与移动读取中断：'..tostring(why))end
                end
                if r.checks==WATCH then
                    say('复查结束：实例='..r.name..'；'..text_..'；两项都为0='..tostring(zero)..'；'..describe(r))
                    self.message=zero and'魂标签持续为0；外观和战斗表现以画面为准'or'魂的隐藏或不可仇恨标签没能保持为0，见日志'
                end
            end
            if records[key]==r and r.phase=='observed' and not r.dead and not r.kitStopping then
                if r.brainTimerPending then startBrain(r) end
                if r.defenseTimerPending then optional(defense,'retryTimer',r) end
                if r.weaponTimerPending then optional(weapons,'retryTimer',r) end
                if r.weaponSetupCheck and r.loadout and r.loadout.kit then optional(actionGuard,'follow',r) end
            elseif records[key]==r and r.dead then optional(actionGuard,'stop',r)
            end
            if records[key]==r and r.phase=='observed' and not r.dead and r.appearance then
                motionTime=motionTime or gameNow()
                if motionTime and motionTime>=r.appearance.nextCheck then
                    outfitSweep=outfitSweep or {materialJobs={}}
                    optional(look,'maintainAppearance',r,motionTime,outfitSweep)
                end
            end
            if records[key]==r and r.phase=='observed' and not r.dead and r.motion then
                motionTime=motionTime or gameNow()
                if motionTime and motionTime>=r.motion.nextCheck then optional(look,'maintainMotion',r,motionTime) end
            end
            if records[key]==r and (r.team=='blue' or r.team=='red') and r.phase=='observed' and not r.dead then
                local t=gameNow()
                if t and t>=(r.roleCheckAt or 0) then
                    r.roleCheckAt=t+2
                    role:excludePlayer(r)
                end
            end
            if records[key]==r and r.team=='neutral' and r.phase=='observed' and not r.dead and o.challenge then
                local t=gameNow()
                if t and t>=(r.challengeAt or 0) then
                    r.challengeAt=t+3
                    local target=o.target and o.target(r.actor,r.team)
                    if not U.valid(target) and current(r.actor,r) then o.challenge(r.actor) end
                end
            end
        end
        if outfitSweep and #outfitSweep.materialJobs>0 then optional(look,'flushMaterials',outfitSweep.materialJobs,motionTime) end
    end
    -- Whether this actor is a Hun body this module summoned and still follows.
    function self:owns(actor)
        local key=U.key(actor)
        return key~=nil and records[key]~=nil and current(actor,records[key])
    end
    function self:profile(actor)
        local r=records[U.key(actor)or'']
        if r and current(actor,r) then return r.loadout end
    end
    function self:weaponConfig(actor)
        local r=records[U.key(actor)or'']
        if r and r.wep and r.wep.active and current(actor,r) then return r.wep.active.config end
    end
    function self:holdsDeath(actor)
        local r=records[U.key(actor)or'']
        if r and r.intent and current(actor,r) then return supply:holdsDeath(r)==true end
        return false
    end
    -- The attribute values this body was summoned with; nil when its profile sets none.
    function self:attributes(actor)
        local r=records[U.key(actor)or'']
        local values=r and r.loadout and r.loadout.attributes
        if r and r.loadout and r.loadout.kit then return require('hun_growth').values(values) end
        if values and next(values)~=nil then return values end
    end
    function self:status()return {probe_supported=true,full_ready=false,prepared=self.prepared,message=self.message}end
    function self:cancel()
        local nextEpoch=epoch+1
        local kept=false
        for _,r in pairs(records)do
            if r.team=='companion' and (r.phase=='finished' or r.phase=='observed') and current(r.actor,r)
                and (not context or context.batch~=r.batch) then
                r.epoch=nextEpoch;kept=true
            else
                stopKit(r)
                if current(r.actor,r) then optional(look,'cleanup',r,'停止') end
            end
        end
        if not kept then stopBrains() end
        epoch=nextEpoch
    end
    function self:silence(onGameThread)
        local restore=onGameThread==true and self.alive
        if not restore then self.alive=false end
        stopBrains()
        if restore then
            for _,r in pairs(records)do
                stopKit(r)
                if current(r.actor,r) then cleanup(r,'Mod 卸载') end
            end
        elseif next(records) then
            say('卸载时仍有魂，已停止回调；存活实例的原生状态须在游戏线程停止时还原')
        end
        self.alive=false;epoch=epoch+1;context=nil
        for key in pairs(samplers)do stopSampler(key,'Mod 卸载')end
        role:silence()
        optional(grabGuard,'silence')
        optional(actionGuard,'silence',onGameThread)
        optional(defense,'silence',restore)
        optional(weapons,'silence',restore)
        optional(supply,'silence')
        optional(shadows,'silence')
        records,dying,lastMembers={},{},{}
    end
    return self
end
return Body
