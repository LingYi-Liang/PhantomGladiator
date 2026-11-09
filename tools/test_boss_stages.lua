package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Stages=dofile('Mods/PhantomGladiator/Scripts/boss_stages.lua')
local address=0
local function object(fields,name)
    address=address+1;local a=address
    fields.alive=true
    fields.IsValid=function(self)return self.alive end
    fields.GetAddress=function()return a end
    fields.GetFName=function()return {ToString=function()return fields.objectName or name..'_'..a end}end
    local class={IsValid=function()return true end,GetFName=function()return {ToString=function()return name end}end}
    fields.GetClass=function()return class end
    return fields
end
local lines,now={},0
local locations,classes,spawned,finished,destroyed={},{},{},{},{}
local world=object({},'World')
local player=object({},'BP_Player_C')
locations[player]={X=1000,Y=0,Z=150}
local tags={}
local hooks,unhooked={},{}
local FLYUP='/PBZCombatAsset/ActorData/Mobs/054_ZuoShang/Bullet/BP_ZuoShang_GroundWeapon_Base.BP_ZuoShang_GroundWeapon_Base_C:FlyUp'
local saves={LengTu_Combat='{"UnLockTags":[" CharacterState.AbilityState.LengTu.Save.P4 "]}'}
local mapActors={}
local loadable={}
local function classFor(name)
    classes[name]=classes[name] or object({},name..'_C')
    return classes[name]
end
local statics=object({
    BeginDeferredActorSpawnFromClass=function(_,w,cls,t,collision,owner,scale)
        assert(w==world and collision==1 and owner~=nil and owner.alive and scale==1,'placed with the boss as owner')
        local name=cls.GetFName and nil
        for n,c in pairs(classes)do if c==cls then name=n end end
        local actor=object({collision=true,cls=cls,Owner=owner},name..'_C')
        actor.SetActorEnableCollision=function(self,on)self.collision=on end
        actor.GetActorEnableCollision=function(self)return self.collision end
        if name:find('^BP_ZuoShang_GroundWeapon') then
            actor.StaticMesh=object({visible=true,SetVisibility=function(self,on,children)assert(children==true);self.visible=on end,
                IsVisible=function(self)return self.visible end},'StaticMeshComponent')
        end
        if name=='BP_ZuoShang_House' then
            actor.ZhuLinGuWu_Break=object({visible=true,SetVisibility=function(self,on,children)assert(children==true);self.visible=on end,
                IsVisible=function(self)return self.visible end},'SkeletalMeshComponent')
        end
        locations[actor]=t.Translation
        spawned[#spawned+1]={actor=actor,name=name,t=t}
        return actor
    end,
    FinishSpawningActor=function(_,actor,t,scale)finished[#finished+1]=actor end,
    GetActorOfClass=function(_,w,cls)
        for _,s in ipairs(spawned)do if s.actor.cls==cls and s.actor.alive then return s.actor end end
    end},'Default__GameplayStatics')
local stage=Stages.new({log=function(s)lines[#lines+1]=s end,now=function()return now end,
    location=function(a)return locations[a] end,
    isDestroying=function(a)return a.destroying==true end,
    player=function()return player end,
    findClass=function(path)
        local name=path:match('/([%w_]+)%.[%w_]+_C$')
        local folder=name:find('^BP_LengTu_') and '077_LengTu/' or name:find('^BP_Monster_GuiChai_Red_') and '069_GuiChai_Red/Setup/'
            or name=='BP_ZuoShang_House' and '054_ZuoShang/House/' or name:find('^BP_ZuoShang_GroundWeapon') and '054_ZuoShang/Bullet/'
            or name:find('^BP_ZuoShang_') and '054_ZuoShang/'
        assert(folder and path=='/PBZCombatAsset/ActorData/Mobs/'..folder..name..'.'..name..'_C',path)
        if name=='BP_LengTu_FriendlySummonSlot_01' then return nil end   -- not loaded yet
        return classFor(name)
    end,
    loadClass=function(path)loadable[#loadable+1]=path;return classFor(path:match('/([%w_]+)%.[%w_]+_C$'))end,
    statics=function()return statics end,
    findAll=function(name)return mapActors[name] or {}end,
    ground=function(w,x,y,z)assert(w==world);return 0 end,
    tagCount=function(actor,tag)return tags[tag] or 0 end,
    fname=function(text)return {ToString=function()return text end}end,
    staticFind=function(path)return object({},'Function')end,
    registerHook=function(path,callback)hooks[path]=callback;return 7,8 end,
    unregisterHook=function(path,pre,post)assert(pre==7 and post==8);unhooked[#unhooked+1]=path;hooks[path]=nil end,
    saveData=function(id)return saves[id]~=nil end,
    targetsByTag=function(tag)assert(tag=='Targeting.Target.ZuoshangSword');local n=0;for _,s in ipairs(spawned)do if s.name:find('^BP_ZuoShang_GroundWeapon') and s.actor.alive and not s.actor.destroying then n=n+1 end end;return n end,
    destroy=function(a)a.destroying=true;destroyed[#destroyed+1]=a end})
local function all()return table.concat(lines,'\n')end
local function test(name,fn)fn();print('ok - '..name)end
local transform={Translation={X=0,Y=0,Z=190},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
local function boss(name)
    local b=object({['Actor ID']={ToString=function()return 'LengTu_Combat' end}},name)
    b.ResetTags=function(self)saves[self['Actor ID']:ToString()]='{"UnLockTags":[" "]}';self.reset=true end
    return b
end
local function placed(name)
    for _,s in ipairs(spawned)do if s.name==name then return s end end
end

test('the last dance leaves opponent selection during the protected pole phase',function()
    local force='CharacterState.Unselectable.Force.Perform'
    local pole='CharacterState.AbilityState.LionDancer.OnPole'
    local lion=boss('BP_Monster_LionDancer_P2_C')
    local native=boss('BP_Monster_LionDancer_P2_C')
    local helper=boss('BP_Monster_LionDancer_P2_NPC_C')
    local phase={}
    local phaseLogs={}
    local stages=Stages.new({tagCount=function(_,tag)return phase[tag] or 0 end,
        log=function(line)phaseLogs[#phaseLogs+1]=line end})
    local prepared=stages:prepare(lion,transform,world)
    assert(prepared and prepared.ok,'register the spawned unit without placing props')
    assert(not stages:untargetable(lion),'normal combat before the pole phase')
    phase[pole],phase[force]=1,1
    assert(stages:untargetable(lion),'do not aim opponents at the protected boss')
    stages:tick()
    assert(table.concat(phaseLogs):find(force,1,true),'the runtime readback includes the protection tag')
    assert(not stages:untargetable(native) and not stages:untargetable(helper),'scope to the mod-spawned boss')
    phase[force]=0
    assert(not stages:untargetable(lion),'target resumes when the game clears the protection after the last summon')
    stages:releaseActor(lion)
    phase[force]=1
    assert(not stages:untargetable(lion) and stages:count()==0,'registration is released with the spawn')
end)

test('only the listed bosses are staged',function()
    assert(Stages.isStaged('BP_Monster_LengTu_C') and Stages.isStaged('BP_Monster_LengTu') and Stages.isStaged('BP_Monster_GuiChai_Red_C'))
    assert(not Stages.isStaged('BP_Monster_LengTu_Preview_C') and not Stages.isStaged('BP_Monster_MengHua_C') and not Stages.isStaged(nil))
    assert(stage:prepare(boss('BP_Monster_MengHua_C'),transform,world)==nil and #spawned==0 and #lines==0)
end)

local lengtu=boss('BP_Monster_LengTu_C')
test('her six markers stand around her as around her spawner, facing the player',function()
    local r=stage:prepare(lengtu,transform,world)
    assert(r and r.ok)
    assert(#spawned==6 and #finished==6,'all six spawned and finished')
    -- The player stands on +X, so her forward is +X and her right +Y.
    local slot=placed('BP_LengTu_SummonSlot_01').t
    assert(slot.Translation.X==-163 and slot.Translation.Y==-252 and slot.Translation.Z==0,'x forward, y right, on the ground')
    local perch=placed('BP_LengTu_SwitchPhase_SnapPoint').t
    assert(perch.Translation.X==-2213 and perch.Translation.Y==-871 and perch.Translation.Z==95,'the perch 24 m behind, 95 cm over its floor')
    local yaw=math.deg(2*math.atan(perch.Rotation.Z,perch.Rotation.W))
    assert(math.abs(yaw-12.7)<0.01)
    for _,s in ipairs(spawned)do assert(s.actor.collision==false,'markers lose their collision') end
    assert(loadable[1]=='/PBZCombatAsset/ActorData/Mobs/077_LengTu/BP_LengTu_FriendlySummonSlot_01.BP_LengTu_FriendlySummonSlot_01_C',
        'a class not loaded yet is loaded')
    assert(all():find('冷荼：按原场地放场地物件，整体朝向玩家 0°',1,true))
    assert(all():find('BP_LengTu_SummonSlot_01=放好 完成生成=true 位置读回差=0cm 地面=0 碰撞关=true 读回碰撞=false 她按类能找到=true',1,true))
    assert(all():find('冷荼 存档 ID：原来=LengTu_Combat（原地图那场也用它，存档里有记录=true）改成 PhantomGladiator_LengTu 写入=true 读回=PhantomGladiator_LengTu；清空这条的阶段进度 调用=true 存档里有记录=true',1,true),all())
    assert(saves.PhantomGladiator_LengTu=='{"UnLockTags":[" "]}','cleared under the mod ID')
    assert(lengtu.reset and saves.LengTu_Combat:find('Save.P4',1,true),'the entry her own fight uses is only read, never written')
    assert(stage:status().stage_placed==6 and stage:status().stage_props==6 and stage:status().stage_failures==0)
end)

test('the set turns with where the player stands',function()
    local other=Stages.new({log=function()end,location=function(a)return locations[a] end,isDestroying=function()return false end,
        player=function()return player end,findClass=function(path)return classFor(path:match('/([%w_]+)%.[%w_]+_C$'))end,
        statics=function()return statics end,findAll=function()return {} end,ground=function()return nil end,
        tagCount=function()return 0 end,destroy=function()end})
    local before=#spawned
    locations[player]={X=0,Y=1000,Z=150}
    -- Her markers already stand from the first set: findAll here sees none, GetActorOfClass finds the first.
    assert(other:prepare(boss('BP_Monster_LengTu_C'),transform,world).ok)
    local slot=spawned[before+1].t.Translation
    assert(math.abs(slot.X-252)<0.001 and math.abs(slot.Y+163)<0.001,'forward is now +Y: x=-y, y=x')
    assert(slot.Z==190-140,'no ground found: 140 cm under the summon height')
    for i=before+1,#spawned do spawned[i].actor.alive=false end
    locations[player]={X=1000,Y=0,Z=150}
end)

test('her phase marks are logged when they change, and she is out of reach while marked',function()
    tags['AI.Hatred.CanNotBeHatred']=1;tags['CharacterState.AbilityState.LengTu.Phase.P1']=1
    now=1;stage:tick()
    assert(all():find('冷荼 阶段标签 1.0 秒：首次读回 现有=Phase.P1,AI.Hatred.CanNotBeHatred',1,true))
    assert(stage:untargetable(lengtu)==true)
    local n=#lines
    now=2;stage:tick()
    assert(#lines==n,'no change: nothing logged')
    tags['CharacterState.AbilityState.LengTu.Phase.P1']=0;tags['CharacterState.AbilityState.LengTu.Phase.P2']=1
    now=3;stage:tick()
    assert(all():find('冷荼 阶段标签 3.0 秒：+[Phase.P2] -[Phase.P1] 现有=Phase.P2,AI.Hatred.CanNotBeHatred',1,true))
    tags['AI.Hatred.CanNotBeHatred']=0
    assert(stage:untargetable(lengtu)==false,'reachable once the game removes the mark')
    -- P4 until P5: only IsInvulnerable and the mark the game's NPCs leave her alone by.
    tags['CharacterState.AbilityState.LengTu.IsInvulnerable']=1;tags['AI.Hatred.IgnoreByNPC']=1
    assert(stage:untargetable(lengtu)==true,'still out of reach while the NPCs are told to leave her alone')
    tags['CharacterState.AbilityState.LengTu.IsInvulnerable']=0;tags['AI.Hatred.IgnoreByNPC']=0
    assert(stage:untargetable(lengtu)==false,'reachable in P5, when the game takes that mark off too')
    tags['AI.Hatred.IgnoreByNPC']=1
    assert(stage:untargetable(boss('BP_Monster_MengHua_C'))==false,'any other unit is never held back')
    tags['AI.Hatred.IgnoreByNPC']=0
end)

test('a second one shares the markers, which leave with the last of them',function()
    local second=boss('BP_Monster_LengTu_C')
    local before=#spawned
    assert(stage:prepare(second,transform,world).ok and #spawned==before,'nothing new placed')
    assert(all():find('BP_LengTu_SummonSlot_01=沿用已放的（共用 2 个）',1,true))
    stage:releaseActor(lengtu,'随 BOSS 清理')
    assert(#destroyed==0 and all():find('冷荼 随 BOSS 清理，场地物件：还有别的同名 BOSS 在用，保留',1,true))
    second.alive=false
    stage:tick()
    assert(#destroyed==6,'all six removed with the last one')
    assert(all():find('冷荼 已不在场上，场地物件：BP_LengTu_SummonSlot_01 调用=true 读回=已移除',1,true))
    assert(stage:count()==0 and stage:status().stage_props==0)
end)

test('in her own map the markers there are left to her',function()
    local before=#spawned
    mapActors['BP_LengTu_SummonSlot_01_C']={object({objectName='Default__BP_LengTu_SummonSlot_01_C'},'BP_LengTu_SummonSlot_01_C'),
        object({},'BP_LengTu_SummonSlot_01_C')}
    assert(stage:prepare(boss('BP_Monster_LengTu_C'),transform,world).ok)
    assert(#spawned==before+5,'the five others placed')
    assert(all():find('BP_LengTu_SummonSlot_01=地图上已有一个，她会用地图上的',1,true))
    mapActors={}
end)

test('a missing summon position places nothing',function()
    local before=#spawned
    local r=stage:prepare(boss('BP_Monster_LengTu_C'),{},world)
    assert(r and not r.ok and #spawned==before and all():find('召唤位置不可读',1,true))
end)
test('火流星 gets his five markers from their own folder, with no phase marks or save ID',function()
    local before,lines0=#spawned,#lines
    local guichai=boss('BP_Monster_GuiChai_Red_C')
    assert(stage:prepare(guichai,transform,world).ok)
    assert(#spawned==before+5)
    local slot=placed('BP_Monster_GuiChai_Red_SummonPoint_02')
    assert(slot and slot.t.Translation.X==925 and slot.t.Translation.Y==248 and slot.t.Translation.Z==3)
    assert(all():find('火流星：按原场地放场地物件',1,true) and not all():find('火流星 存档',1,true))
    assert(guichai['Actor ID']:ToString()=='LengTu_Combat' and not guichai.reset,'only 冷荼 gets the save ID change')
    now=50;stage:tick()
    assert(not all():find('火流星 阶段标签',1,true) and stage:untargetable(guichai)==false)
    stage:releaseActor(guichai)
    assert(all():find('火流星 已清理，场地物件：BP_Monster_GuiChai_Red_SnapPoint_01 调用=true 读回=已移除',1,true))
end)
test('左殇 (silver hair) gets his house with its mesh hidden and no collision, gone when he leaves',function()
    local before=#spawned
    local zuoshang=boss('BP_Monster_ZuoShang_Ending_C')
    assert(stage:prepare(zuoshang,transform,world).ok and #spawned==before+3)
    local house=placed('BP_ZuoShang_House')
    assert(house and house.actor.collision==false and house.actor.ZhuLinGuWu_Break.visible==false)
    assert(house.t.Translation.X==55 and house.t.Translation.Y==102)
    -- His CA_03 goes up to the snap point and down on the landing point, as they stand from his spawner in 断魂山.
    local mine={}
    for i=before+1,#spawned do mine[spawned[i].name]=spawned[i] end
    local land,snap=mine.BP_ZuoShang_CA_03_LandingPoint,mine.BP_ZuoShang_CA_03_SnapPoint
    assert(land and land.t.Translation.X==-494 and land.t.Translation.Y==-18 and land.t.Translation.Z==0,'landing point 4.9 m behind him')
    assert(snap and snap.t.Translation.X==-2227 and snap.t.Translation.Y==-18 and snap.t.Translation.Z==1402,'snap point 22 m behind, 14 m up')
    assert(land.actor.collision==false and snap.actor.collision==false and land.actor.Owner==zuoshang)
    assert(all():find('BP_ZuoShang_CA_03_LandingPoint=放好 完成生成=true 位置读回差=0cm 地面=0 碰撞关=true 读回碰撞=false 她按类能找到=true',1,true),all())
    assert(all():find('BP_ZuoShang_CA_03_SnapPoint=放好 完成生成=true 位置读回差=0cm 地面=0 碰撞关=true 读回碰撞=false 她按类能找到=true',1,true),all())
    assert(all():find('BP_ZuoShang_House=放好 完成生成=true 位置读回差=0cm 地面=0 碰撞关=true 读回碰撞=false 她按类能找到=true 隐藏 ZhuLinGuWu_Break 调用=true 读回可见=false',1,true),all())
    zuoshang.alive=false;stage:tick()
    assert(house.actor.destroying and all():find('左殇（银发） 已不在场上，场地物件：BP_ZuoShang_House 调用=true 读回=已移除',1,true))
    assert(land.actor.destroying and snap.actor.destroying and all():find('BP_ZuoShang_CA_03_SnapPoint 调用=true 读回=已移除',1,true),all())
end)
test('组织冥主：左殇 gets his 42 ground weapons, unseen until his move uses them, owned by him, tilted, gone with him',function()
    local before=#spawned
    local zuoshang=boss('BP_Monster_ZuoShang_C')
    assert(stage:prepare(zuoshang,transform,world).ok)
    local weapons={}
    for i=before+1,#spawned do if spawned[i].name:find('^BP_ZuoShang_GroundWeapon') then weapons[#weapons+1]=spawned[i] end end
    assert(#weapons==42,'all 42 placed: '..#weapons)
    for _,w in ipairs(weapons)do
        assert(w.actor.Owner==zuoshang,'owned by 左殇, so their turn to the player finds him')
        local r=w.t.Rotation
        assert(math.abs(r.X*r.X+r.Y*r.Y+r.Z*r.Z+r.W*r.W-1)<1e-3,'a unit quaternion')
        assert(w.t.Translation.Z==0,'on the ground')
    end
    assert(weapons[1].actor.Owner==zuoshang and (weapons[1].t.Rotation.X~=0 or weapons[1].t.Rotation.Y~=0),'tilted, not only turned')
    assert(all():find('地面武器 42 个：放好=42 沿用=0 地图上已有=0 失败=0；按 Targeting.Target.ZuoshangSword 登记的读回=42；先隐藏，用时显现，挂钩=true',1,true),all())
    for _,w in ipairs(weapons)do assert(w.actor.StaticMesh.visible==false,'unseen until the move uses it') end
    assert(hooks[FLYUP],'FlyUp hooked')
    hooks[FLYUP](weapons[2].actor);hooks[FLYUP](weapons[3].actor);hooks[FLYUP](weapons[3].actor)
    assert(weapons[2].actor.StaticMesh.visible and weapons[3].actor.StaticMesh.visible and not weapons[4].actor.StaticMesh.visible)
    hooks[FLYUP](object({},'BP_ZuoShang_GroundWeapon_Base_Knife_C'))   -- one of the map's own: not ours, left alone
    assert(all():find('地面武器被招式取用，显现 BP_ZuoShang_GroundWeapon_Base_',1,true) and all():find('读回可见=true 累计显现=2',1,true),all())
    now=60;stage:tick()
    assert(all():find('用时显现：本场已显现 2 个（这次 +2）',1,true) and stage:status().stage_revealed==2)
    assert(not all():find('BP_ZuoShang_GroundWeapon_Base_Knife#',1,true),'one line for the group, not one per weapon')
    weapons[1].actor.alive=false   -- one flew off
    zuoshang.alive=false;stage:tick()
    assert(all():find('地面武器 已移除=41 已不在（飞出去了或被游戏清掉）=1 仍在=0',1,true),all())
    assert(#unhooked==1 and unhooked[1]==FLYUP and all():find('摘除用时显现挂钩 调用=true 本场显现=2',1,true),'the hook leaves with the last of them')
end)
-- The save-repair button: 冷荼's old ID's checkpoint is cleared with her own ResetTags, she is born under it (what InitTags
-- reads is the read-back), then moves to the mod's ID.
local function checkpointStages(wants)
    local asked,done={},{}
    local s=Stages.new({log=function(m)lines[#lines+1]=m end,now=function()return now end,location=function(a)return locations[a] end,
        isDestroying=function(a)return a.destroying==true end,player=function()return player end,
        findClass=function(path)return classFor(path:match('/([%w_]+)%.[%w_]+_C$'))end,statics=function()return statics end,
        findAll=function()return {} end,ground=function()return 0 end,tagCount=function()return 0 end,destroy=function()end,
        fname=function(text)return {ToString=function()return text end}end,saveData=function(id)return saves[id]~=nil end,
        checkpoint={wants=function(id)asked[#asked+1]=id;return wants end,done=function(id,ok,read)done[#done+1]={id=id,ok=ok,read=read} end}})
    return s,asked,done
end
local function bornWith(actor,list)
    local tags={}
    for _,t in ipairs(list)do tags[#tags+1]={TagName={ToString=function()return t end}} end
    actor.UnLockTags={GameplayTags=tags}
end
test('armed: the old ID is cleared first, she keeps it through BeginPlay, then moves; the read-back decides',function()
    saves.LengTu_Combat='{"UnLockTags":[" CharacterState.AbilityState.LengTu.Save.P4 "]}'
    saves.PhantomGladiator_LengTu=nil
    local s,asked,done=checkpointStages(true)
    local preview=boss('BP_Monster_LengTu_Preview_C')
    local r=s:prepare(preview,transform,world)
    assert(r and r.ok and asked[1]=='LengTu_Combat','the preview class gets the save ID too, and asks')
    assert(saves.LengTu_Combat=='{"UnLockTags":[" "]}' and preview['Actor ID']:ToString()=='LengTu_Combat','cleared, not moved yet')
    assert(all():find('冷荼（预览）：按"修复存档"清掉存档里 LengTu_Combat 的阶段进度（模组以前写的）：ResetTags 调用=true',1,true),all())
    bornWith(preview,{})
    local f=s:finished(preview)
    assert(f and f.ok==true and done[1].id=='LengTu_Combat' and done[1].ok==true and #done[1].read==0)
    assert(preview['Actor ID']:ToString()=='PhantomGladiator_LengTu' and saves.PhantomGladiator_LengTu=='{"UnLockTags":[" "]}','moved and cleared there')
    assert(all():find('LengTu_Combat 清掉后出生时读到的阶段进度=[] 已清空',1,true),all())
    assert(s:finished(preview)==nil,'once')
end)
test('armed but she still read a checkpoint there: reported as not cleared, and she moves anyway',function()
    saves.LengTu_Combat='{"UnLockTags":[" CharacterState.AbilityState.LengTu.Save.P4 "]}'
    local s,_,done=checkpointStages(true)
    local preview=boss('BP_Monster_LengTu_Preview_C')
    s:prepare(preview,transform,world)
    bornWith(preview,{'CharacterState.AbilityState.LengTu.Save.P4'})
    local f=s:finished(preview)
    assert(f.ok==false and done[1].ok==false and done[1].read[1]=='CharacterState.AbilityState.LengTu.Save.P4')
    assert(preview['Actor ID']:ToString()=='PhantomGladiator_LengTu' and all():find('=[CharacterState.AbilityState.LengTu.Save.P4] 没清空',1,true),all())
end)
test('armed and finished() never came: the next tick moves her, so no checkpoint goes under the old ID',function()
    local s,_,done=checkpointStages(true)
    local preview=boss('BP_Monster_LengTu_Preview_C')
    s:prepare(preview,transform,world)
    bornWith(preview,{})
    s:tick()
    assert(preview['Actor ID']:ToString()=='PhantomGladiator_LengTu' and #done==1)
    local gone=boss('BP_Monster_LengTu_Preview_C')
    s:prepare(gone,transform,world)
    gone.alive=false
    s:tick()
    assert(#done==1,'one that left is dropped')
end)
test('not armed: moved before she starts, the old ID only read',function()
    saves.LengTu_Combat='{"UnLockTags":[" CharacterState.AbilityState.LengTu.Save.P4 "]}'
    local s,asked,done=checkpointStages(false)
    local preview=boss('BP_Monster_LengTu_Preview_C')
    s:prepare(preview,transform,world)
    assert(asked[1]=='LengTu_Combat' and preview['Actor ID']:ToString()=='PhantomGladiator_LengTu' and saves.LengTu_Combat:find('Save.P4',1,true))
    assert(s:finished(preview)==nil and #done==0)
end)
-- A marker of her own map far from where she is summoned (断魂山: her arena 380 m off) is borrowed and put back.
local function mapMarker(name,at,yaw)
    local m=object({},name..'_C')
    locations[m]=at
    m.rot={Pitch=0,Yaw=yaw,Roll=0}
    m.RootComponent=object({Mobility=0,SetMobility=function(self,v)self.Mobility=v end},'SceneComponent')
    m.K2_GetActorRotation=function(self)return self.rot end
    m.K2_SetActorLocationAndRotation=function(self,loc,rot,sweep,hit,teleport)
        assert(self.RootComponent.Mobility==2 and sweep==false and teleport==true,'made movable first, teleported')
        locations[self]={X=loc.X,Y=loc.Y,Z=loc.Z};self.rot=rot
    end
    return m
end
local function borrowingStages(markers,listed)
    local lib=object({BeginDeferredActorSpawnFromClass=statics.BeginDeferredActorSpawnFromClass,FinishSpawningActor=statics.FinishSpawningActor,
        GetActorOfClass=function(self,w,cls)
            for name,m in pairs(markers)do if cls==classFor(name) then return m end end
            return statics.GetActorOfClass(self,w,cls)
        end},'Default__GameplayStatics')
    return Stages.new({log=function(m)lines[#lines+1]=m end,now=function()return now end,location=function(a)return locations[a] end,
        isDestroying=function(a)return a.destroying==true end,player=function()return player end,
        findClass=function(path)return classFor(path:match('/([%w_]+)%.[%w_]+_C$'))end,statics=function()return lib end,
        findAll=function(name)local short=name:gsub('_C$','');if listed and listed[short] then return listed[short] end
            local m=markers[short];return m and {m} or {} end,ground=function()return 0 end,
        tagCount=function()return 0 end,destroy=function(a)a.destroying=true end,fname=function(text)return {ToString=function()return text end}end})
end
test('a marker of her own map far off is borrowed: moved beside her, found by class, put back as it was when she leaves',function()
    local slot=mapMarker('BP_LengTu_SummonSlot_01',{X=40000,Y=0,Z=500},33)
    local s=borrowingStages({BP_LengTu_SummonSlot_01=slot})
    local b=boss('BP_Monster_LengTu_C')
    assert(s:prepare(b,transform,world).ok)
    local at=locations[slot]
    assert(at.X==-163 and at.Y==-252 and at.Z==0 and slot.rot.Yaw==10,'where the mod would place its own')
    assert(all():find('BP_LengTu_SummonSlot_01=地图上那个在 402 米外，借过来放到这里 可移动=true 调用=true 位置读回差=0cm 地面=0 她按类能找到=true（她离场时放回原处）',1,true),all())
    assert(s:status().stage_borrowed==1)
    b.alive=false
    s:tick()
    at=locations[slot]
    assert(at.X==40000 and at.Y==0 and at.Z==500 and slot.rot.Yaw==33 and slot.RootComponent.Mobility==0,'back as it was')
    assert(all():find('BP_LengTu_SummonSlot_01 放回地图原处 调用=true 位置读回差=0cm',1,true),all())
end)
test('a marker of her own map near where hers would stand is used where it is',function()
    local slot=mapMarker('BP_LengTu_SummonSlot_01',{X=837,Y=-252,Z=0},33)
    local s=borrowingStages({BP_LengTu_SummonSlot_01=slot})
    assert(s:prepare(boss('BP_Monster_LengTu_C'),transform,world).ok)
    assert(locations[slot].X==837 and slot.rot.Yaw==33,'not moved')
    assert(all():find('BP_LengTu_SummonSlot_01=地图上已有一个（离这里 10 米），她会用地图上的',1,true),all())
end)
test('of two in her map, the one her abilities find by class is the one borrowed',function()
    local decoy=mapMarker('BP_LengTu_SummonSlot_01',{X=-30000,Y=0,Z=0},5)
    local slot=mapMarker('BP_LengTu_SummonSlot_01',{X=40000,Y=0,Z=500},33)
    local s=borrowingStages({BP_LengTu_SummonSlot_01=slot},{BP_LengTu_SummonSlot_01={decoy,slot}})
    assert(s:prepare(boss('BP_Monster_LengTu_C'),transform,world).ok)
    assert(locations[slot].X==-163 and locations[decoy].X==-30000,'the first found by class moves, the other stays')
end)
print('test_boss_stages: all passed')
