package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local U=require('ue_observe')
local Party=require('huashan_formation')
local seq=0
local function object(class,outer)
    seq=seq+1
    local id=seq
    local o={class=class,outer=outer,live=true}
    function o:IsValid()return self.live end
    function o:GetAddress()return id end
    function o:GetOuter()return self.outer end
    function o:GetFullName()return class..' /Game/Fixture.World:PersistentLevel.'..class..'_'..id end
    function o:GetFName()return {ToString=function()return class..'_'..id end}end
    function o:IsActorBeingDestroyed()return not self.live end
    function o:K2_DestroyActor()self.live=false end
    return o
end
local world=object('World');local assets,props,byPath={},{},{}
local domainPath='/SGameAI/Tools/MobDomain/BP_MobDomain.BP_MobDomain_C'
local spawnerPath='/SGameAI/Tools/Spawner/BP_AISpawner.BP_AISpawner_C'
local root='/PBZCombatAsset/ActorData/Mobs/035_HuaShan/'
local masks='/Game/RenewalContent/Actors/Mobs/Normal/'
local function leaf(path)return path:match('%.([^%.]+)$') end
local function fn(v)return {ToString=function()return v end}end
local function pathOf(o)return o:GetFullName():match('^%S+ (.+)$')end
local function cls(path)
    if assets[path]then return assets[path]end
    local c=object('Class')
    function c:GetFName()return fn(leaf(path))end
    function c:GetFullName()return 'Class '..path end
    function c:IsAnyClass()return true end
    function c:GetSuperStruct()return nil end
    function c:ForEachProperty(cb)for _,prop in ipairs(props[path] or {})do if cb(prop) then break end end end
    assets[path]=c;byPath[path]=c;return c
end
local function instance(path,outer)
    local o=object(leaf(path),outer)
    o.GetClass=function()return cls(path)end;byPath[pathOf(o)]=o;return o
end
PropertyTypes={ArrayProperty='array',SoftClassProperty='softclass',SoftObjectProperty='soft',InterfaceProperty='iface'}
local badMembers,sharedDefault=false,false
local function property(owner,name,kind)
    local list=props[owner] or {};props[owner]=list
    local x={GetFName=function()return fn(name)end,GetFullName=function()return kind..' '..owner..':'..name end,
        IsA=function(_,t)return t==PropertyTypes[kind]end,
        GetInner=function()return {GetFullName=function()return 'SoftObjectProperty '..owner..':Members.Members' end,
            IsA=function(_,t)return t==PropertyTypes.SoftObjectProperty end}end}
    function x:ContainerPtrToValuePtr(o,index)assert(index==0 and o:IsValid() and o:GetClass()==cls(owner));return o end
    function x:ImportText(text,o,flags,sameOwner)
        assert(o==sameOwner and flags==0)
        if kind=='ArrayProperty' then
            assert(#o.Members==0);o.Members={}
            for p in text:gmatch('"([^"]+)"')do local a=assert(byPath[p]);o.Members[#o.Members+1]=a end
            if badMembers then table.remove(o.Members)end
        else
            local a=assert(byPath[text:match('"([^"]+)"') or text])
            if kind=='InterfaceProperty' then o[name]=a
            else o[name]={type=function()return 'TSoftObjectPtrUserdata'end,actor=a} end
        end
    end
    list[#list+1]=x
end
local gp='/Script/SGameAI.MobGroup'
property(gp,'Members','ArrayProperty');property(gp,'MobDomain','InterfaceProperty');property(gp,'MobDomainActor','SoftObjectProperty')
property(spawnerPath,'Class','SoftClassProperty')
local created,opens,events,logs={}, {},{},{}
local sys=object('Kismet');function sys:GetPathName(a)return pathOf(a)end
function sys:Conv_SoftClassReferenceToClass(soft)return soft.actor end
sys.Conv_SoftObjectReferenceToObject=sys.Conv_SoftClassReferenceToClass
local statics=object('GameplayStatics')
local function groupFor(d)
    local g=instance(gp,d);g.Scripts={};g.Members={};g.RuntimeMembers={}
    g.MobDomain=d;g.MobDomainActor={type=function()return 'TSoftObjectPtrUserdata'end,actor=d}
    function g:GetMemberInterfaces()return self.Members end
    function g:GetAliveMemberPawns()
        local result={};for _,sp in ipairs(self.Members)do if sp.SpawnedAI and sp.SpawnedAI.hp>0 then result[#result+1]=sp.SpawnedAI end end
        return result
    end
    return g
end
local template=groupFor(world)
function statics:BeginDeferredActorSpawnFromClass(w,c,t)
    assert(w==world)
    local path=pathOf(c);local a=instance(path,world);created[#created+1]=a
    a.at=t.Translation
    function a:SetActorEnableCollision(v)self.collision=v end
    function a:GetActorEnableCollision()return self.collision end
    function a:SetActorHiddenInGame(v)self.bHidden=v end
    if path==domainPath then
        local map={DefaultGroup=sharedDefault and template or groupFor(a)}
        function map:Add(key,g)self[key:ToString()]=g end
        a.MobDomainConfig={MobGroups=map};a.ActorsInMobDomain={}
        function a:SetEnabled(v)self.bEnabled=v end;function a:IsEnabled()return self.bEnabled end
        function a:IsActorInMobDomain(x)for _,v in ipairs(self.ActorsInMobDomain)do if v==x then return true end end;return false end
        function a:GetActorsInMobDomain()return self.ActorsInMobDomain end
    else
        assert(path==spawnerPath);a.SpawnInfo={DefaultGameplayTags={GameplayTags={}}}
        function a:GetPawn()return self.SpawnedAI end
        function a:GetMobGroup()return self.MobGroup end
        function a:GetOtherAliveMembersInGroup()
            local out={};for _,sp in ipairs(self.MobGroup.Members)do if sp~=self and sp:GetPawn().hp>0 then out[#out+1]=sp end end;return out
        end
    end
    return a
end
function statics:FinishSpawningActor(a)
    if a:GetClass()==cls(spawnerPath)then assert(a.InitialSpawn==false and a.AutoRespawnOnDead==false and a.SpawnedAI==nil)end
    a.finished=true;return a
end
local t=0;local foes,companionFoes={},{};local worldNow=world;local list={}
local ai=object('AILibrary')
function ai:SetValueAsVectorByTag(bb,tag,v)bb[tag.TagName:ToString()]=v end
function ai:GetValueAsVectorByTag(bb,tag)return bb[tag.TagName:ToString()]end
function ai:GetRunningBehaviorTree(c)return c.tree end
local gas=object('GAS')
function gas:SendGameplayEventToActor(a,tag,payload)
    assert(tag.TagName:ToString()=='GameplayEvent.AI.EventTransition.CustomState')
    a.Controller.tree=payload.OptionalObject;events[#events+1]=a
end
local utils=object('Tags')
function utils:AddLooseGameplayTag(a,tag)a.tags[tag.TagName:ToString()]=1 end
function utils:RemoveLooseGameplayTag(a,tag)a.tags[tag.TagName:ToString()]=0 end
local libs={['/Script/Engine.Default__KismetSystemLibrary']=sys,['/Script/SGameAI.Default__SGameAIFunctionLibrary']=ai,
    ['/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary']=gas,['/Script/SGameUtils.Default__AbilityUtils']=utils}
local function lookup(p)return libs[p] or cls(p)end
local opts={world=function()return worldNow end,statics=function()return statics end,find=lookup,load=lookup,fname=fn,
    now=function()return t end,hp=function(a)return a.hp end,aiOf=function(a)return a.ai end,
    opponent=function(a)return foes[a]end,busy=function(a)return a.busy==true end,
    companionOpponent=function(a)return companionFoes[a]end,companionFighting=function(a)return a.combat==true end,
    location=function(a)return a.at end,log=function(l)logs[#logs+1]=l end,
    invalid=function()return {IsValid=function()return false end}end,
    construct=function(c,d)
        assert(c==cls(gp));local g=groupFor(d);g.MobDomain=nil;g.MobDomainActor=nil;return g
    end}
local manage=Party.new(opts)
local function fighter(path,position)
    local actor=instance(path,world)
    actor.hp=100;actor.tags={};actor.at=position
    actor.Controller=object('Controller',world);actor.Controller.Pawn=actor
    actor.ai=object('AI',actor.Controller);actor.ai.Pawn=actor;actor.ai.BlackboardComponent=object('BB',actor.Controller)
    actor.ai.SpawnedAIScripts={}
    function actor:GetAISpawner()return self.Spawner end;function actor:GetMobGroup()return self.MobGroup end
    function actor:GetController()return self.Controller end
    actor.AbilitySystemComponent=object('ASC',actor)
    function actor.AbilitySystemComponent:GetGameplayTagCount(tag)return actor.tags[tag.TagName:ToString()] or 0 end
    function actor.AbilitySystemComponent:K2_GiveAbilityAndActivateOnce(c)opens[#opens+1]=actor;return {Handle=123}end
    actor.AbilitySystemComponent.ActivatableAbilities={Items={}}
    return actor
end
local function party(red,team,offset)
    local jade=red=='jade'
    local pair=red=='puppet' or red=='swordswoman'
    local leader=red and 'BP_Monster_HuaShan_RedTroop_BigBro' or 'BP_Monster_HuaShan_Blue'
    local child=red and 'BP_Monster_HuaShan_RedTroop_Soldier' or 'BP_Monster_HuaShan_White'
    local maskOrder={'BP_Monster_JadeMaskMan','BP_Monster_GoldMaskMan','BP_Monster_IronMaskMan'}
    local puppet=root..'BP_Monster_HuaShan_JianOu.BP_Monster_HuaShan_JianOu_C'
    local swordswoman='/PBZCombatAsset/ActorData/Mobs/034_EMei/BP_Monster_EMei_Sword_JianZhen.BP_Monster_EMei_Sword_JianZhen_C'
    local pairOrder=red=='puppet' and {puppet,swordswoman} or {swordswoman,puppet}
    local token={nativeFormation=true};local rows={}
    for i=1,pair and 2 or jade and 3 or 7 do
        local id=jade and maskOrder[i] or (i==1 and leader or child)
        local path=pair and pairOrder[i] or (jade and masks or root)..id..'.'..id..'_C'
        local actor=fighter(path,{X=offset+30*i,Y=10,Z=64})
        rows[i]={actor=actor,path=path,transform={Translation=actor.at},parent=i>1 and rows[1].actor or nil}
        list[#list+1]={actor=actor,class_path=path,team=team,formationGroup=token,formation=i==1}
    end
    manage:roster(list)
    return token,rows
end
if arg[1]=='fixture' then
    return {world=world,options=opts,assets=assets,manage=manage,actor=fighter,party=party,foes=foes,events=events,
        intro=opens,created=created,logs=logs,setTime=function(v)t=v end,setWorld=function(w)worldNow=w end,tree=cls}
end
local a,blue=party(false,'blue',1000);local b,red=party(true,'red',3000)
-- Shipped UE4SS exposes the soft FFields but does not list either kind in PropertyTypes.
PropertyTypes.SoftObjectProperty=nil;PropertyTypes.SoftClassProperty=nil
assert(manage:placeholderOf(blue[1].actor)==nil,'unprepared actors have no owned placeholder')
assert(manage:prepare(a,blue,world,'blue'));assert(manage:ready(a,blue))
assert(manage:prepare(b,red,world,'red'));assert(manage:ready(b,red))
for _,rows in ipairs({blue,red})do
    for _,row in ipairs(rows)do
        assert(manage:placeholderOf(row.actor)==row.actor.Spawner,'expose only that member’s placeholder')
    end
end
assert(manage:activated(a));assert(manage:activated(b))
local main,aj=blue[1].actor,red[1].actor
assert(main.MobGroup~=aj.MobGroup and main.MobGroup.MobDomain~=aj.MobGroup.MobDomain)
assert(main.MobGroup.MobDomain:IsActorInMobDomain(aj))
-- Read the exact public native boundaries used by the cooked assignment, heal and revival blueprints.
for _,rows in ipairs({blue,red})do
    local lead=rows[1].actor;local sp=lead:GetAISpawner()
    local seen={};for _,other in ipairs(sp:GetOtherAliveMembersInGroup())do seen[other:GetPawn()]=true end
    for i=2,7 do assert(seen[rows[i].actor] and rows[i].actor:GetAISpawner().MobGroup==lead:GetMobGroup())end
    assert(#sp:GetOtherAliveMembersInGroup()==6)
    local donor=rows[2].actor
    local receivers={};for _,o in ipairs(donor:GetAISpawner().MobGroup.Members)do
        local pawn=o:GetPawn();if pawn:GetClass()==lead:GetClass() then receivers[#receivers+1]=pawn end
    end
    assert(#receivers==1 and receivers[1]==lead)
end
for _,row in ipairs(blue)do assert(row.actor.tags['CharacterState.AbilityState.Troop.TroopMob']==1)end
assert(main.ai.BlackboardComponent['AI.BlackboardKey.Vector.DomainCenter'].X==main.at.X)
local fallen=blue[4].actor;fallen.hp=0;fallen.tags['CharacterState.AbilityState.Troop.ReadyForResurrection']=1
assert(#main.Spawner:GetOtherAliveMembersInGroup()==5 and #main.MobGroup:GetMemberInterfaces()==7)
local recovered
for _,sp in ipairs(main.Spawner.MobGroup.Members)do local x=sp:GetPawn();if x.tags['CharacterState.AbilityState.Troop.ReadyForResurrection']==1 then recovered=x end end
assert(recovered==fallen);fallen.hp=60
assert(#main.Spawner:GetOtherAliveMembersInGroup()==6)
foes[main]=aj;foes[aj]=main
manage:assigned(main,aj);manage:assigned(aj,main);t=1;manage:tick();t=2;manage:tick()
assert(#opens==1 and opens[1]==aj and #events==1 and events[1]==main)
manage:assigned(aj,main);t=3;manage:tick();assert(#opens==1)
local healing=instance(root..'Abilities/Troop/GA_HuaShan_Troop_Healing.GA_HuaShan_Troop_Healing_C',blue[2].actor)
function healing:GetAvatarActorFromActorInfo()return blue[2].actor end
healing.bIsActive=true;manage:started(healing,'GA_HuaShan_Troop_Healing_C')
assert(manage:supportingActor(blue[2].actor) and not manage:supportingActor(red[2].actor))
assert(manage:localPlayerLookup(healing) and not U.valid(manage:localPlayerLookup(healing)))
healing.bIsActive=false;assert(not manage:supportingActor(blue[2].actor))
local alerts=0
local death=instance(root..'Fixture.AIScript_HuaShan_Troop_Blue_Dead_C',main.ai);death.Pawn=main
function death:OnGroupMemberDead(sp)assert(sp==fallen.Spawner);alerts=alerts+1 end
main.ai.SpawnedAIScripts={death}
fallen.hp=0;fallen.tags['CharacterState.Dead']=1;manage:lifeChanged(a,fallen,false)
t=4;manage:tick();t=5;manage:tick();assert(alerts==1)
fallen.hp=60;fallen.tags['CharacterState.Dead']=0;manage:lifeChanged(a,fallen,true)
fallen.hp=0;fallen.tags['CharacterState.Dead']=1;manage:lifeChanged(a,fallen,false)
t=6;manage:tick();assert(alerts==2)
local twinToken,twins=party(false,'blue',6100)
assert(manage:prepare(twinToken,twins,world,'blue') and manage:ready(twinToken,twins))
assert(twins[1].actor.MobGroup~=main.MobGroup and #twins[1].actor.MobGroup.Members==7)
for _,sp in ipairs(twins[1].actor.MobGroup.Members) do assert(sp:GetPawn().at.X>6000)end
local total=#events
local nativeTask=object('Instance',twins[1].actor)
nativeTask.TreeAsset=cls(root..'BehaviorTree/Troop/Init/BT_HuaShan_Troop_Init_07.BT_HuaShan_Troop_Init_07')
nativeTask.ActorsToAssign={};for i=2,7 do nativeTask.ActorsToAssign[i-1]=twins[i].actor end
assert(manage:beforeAttack(twins[1].actor,aj));manage:observe(nativeTask,twins[1].actor)
foes[twins[1].actor]=aj;manage:assigned(twins[1].actor,aj);t=7;manage:tick();assert(#events==total,'native opener must not be sent again')
local oldGroup=main.MobGroup;main.hp=0
list[1]=table.remove(list);manage:roster(list);t=8;manage:tick()
assert(blue[2].actor.MobGroup==oldGroup and oldGroup.MobDomain:IsValid())
-- No mutation of the other party or a map NPC during a partial failure.
local oldCount=#created;local c,third=party(true,'blue',5100)
badMembers=true;assert(not manage:prepare(c,third,world,'blue'));badMembers=false
for i=oldCount+1,#created do assert(not created[i].live,'owned partial helper left behind')end
for _,row in ipairs(third)do assert(not row.actor.Spawner and not row.actor.MobGroup)end
assert(#aj.MobGroup.Members==7)
sharedDefault=true
local spare,rows=party(true,'red',7100)
assert(manage:prepare(spare,rows,world,'red') and manage:ready(spare,rows))
local private=rows[1].actor.MobGroup
assert(private~=template and private.MobDomain:GetClass()==cls(domainPath) and private:GetOuter()==private.MobDomain)
assert(#template.Members==0 and template.MobDomain==world)
sharedDefault=false
local pet,allied=party(false,'companion',9000)
assert(manage:prepare(pet,allied,world,'companion'),'white formation can join the map as a companion')
assert(manage:ready(pet) and manage:activated(pet))
local leader=allied[1].actor
local mapEnemy=fighter('/Game/Fixture.MapEnemy_C',{X=12000,Y=10,Z=64})
local petDomain=leader.MobGroup.MobDomain
assert(not petDomain:IsActorInMobDomain(aj) and not petDomain:IsActorInMobDomain(mapEnemy))
assert(#leader.Spawner:GetOtherAliveMembersInGroup()==6)
companionFoes[leader]=mapEnemy
leader.at={X=11400,Y=8,Z=61}
total=#events
leader.combat=false;t=9;manage:tick();assert(#events==total)
leader.combat=true;t=10;manage:tick();t=10.6;manage:tick()
assert(#events==total+1 and events[#events]==leader)
assert(leader.ai.BlackboardComponent['AI.BlackboardKey.Vector.DomainCenter'].X==11400)
assert(petDomain:IsActorInMobDomain(mapEnemy) and not petDomain:IsActorInMobDomain(aj) and not mapEnemy.MobGroup)
t=11;manage:tick();assert(#events==total+1)
companionFoes[leader]=nil;leader.combat=false;t=12;manage:tick();t=14;manage:tick()
assert(not petDomain:IsActorInMobDomain(mapEnemy))
leader.Controller.tree=nil
companionFoes[leader]=mapEnemy;leader.combat=true;t=15;manage:tick();t=15.6;manage:tick()
assert(#events==total+2 and events[#events]==leader)
local redPet,redAllied=party(true,'companion',13000)
assert(Party.supportsCompanion(redAllied[1].path),'red native leader must offer its formation to companions')
assert(manage:prepare(redPet,redAllied,world,'companion') and manage:ready(redPet) and manage:activated(redPet))
local ajFollower=redAllied[1].actor
assert(#ajFollower.Spawner:GetOtherAliveMembersInGroup()==6)
local before=#opens
companionFoes[ajFollower]=mapEnemy
t=16;manage:tick();assert(#opens==before)
ajFollower.combat=true;t=17;manage:tick();t=18;manage:tick()
assert(#opens==before+1 and opens[#opens]==ajFollower)
assert(ajFollower.MobGroup.MobDomain:IsActorInMobDomain(mapEnemy) and not mapEnemy.MobGroup)
local jade,maskRows=party('jade','companion',15000)
assert(Party.supportsCompanion(maskRows[1].path))
assert(manage:prepare(jade,maskRows,world,'companion') and manage:ready(jade) and manage:activated(jade))
local jadeLeader=maskRows[1].actor
local openCount,eventCount=#opens,#events
companionFoes[jadeLeader]=mapEnemy;jadeLeader.combat=true
companionFoes[ajFollower]=nil;ajFollower.combat=false
t=19;manage:tick();t=21;manage:tick()
companionFoes[ajFollower]=mapEnemy;ajFollower.combat=true
t=22;manage:tick()
assert(#opens==openCount and #events==eventCount,'Jade has no HuaShan opener and the red transformation is once per life')
local peers=jadeLeader.Spawner:GetOtherAliveMembersInGroup()
assert(#peers==2 and peers[1]:GetPawn()==maskRows[2].actor and peers[2]:GetPawn()==maskRows[3].actor)
assert(not mapEnemy.MobGroup and jadeLeader.MobGroup.MobDomain:IsActorInMobDomain(mapEnemy))
maskRows[2].actor.hp=0
assert(#jadeLeader.Spawner:GetOtherAliveMembersInGroup()==1)
local puppetToken,puppetRows=party('puppet','companion',17000)
local swordToken,swordRows=party('swordswoman','companion',19000)
assert(Party.supportsCompanion(puppetRows[1].path) and Party.supportsCompanion(swordRows[1].path),
    'both original Sword of Despair formation cards should support a private companion party')
local generalSword=puppetRows[2].path:gsub('JianZhen','Top')
local originalPlacement=puppetRows[2].path
puppetRows[2].path=generalSword
assert(not manage:prepare(puppetToken,puppetRows,world,'companion'),
    'the original healing tree filters the formation sword class, not the other red swordswoman')
puppetRows[2].path=originalPlacement
for _,arrangement in ipairs({{puppetToken,puppetRows},{swordToken,swordRows}})do
    local token,roster=arrangement[1],arrangement[2]
    assert(manage:prepare(token,roster,world,'companion') and manage:ready(token) and manage:activated(token))
    local first,second=roster[1].actor,roster[2].actor
    local members=first:GetAISpawner():GetOtherAliveMembersInGroup()
    assert(#members==1 and members[1]:GetPawn()==second and first:GetMobGroup()==second:GetMobGroup())
    assert(#second:GetMobGroup():GetAliveMemberPawns()==2)
    companionFoes[first]=mapEnemy;first.combat=true
end
assert(puppetRows[1].actor:GetMobGroup()~=swordRows[1].actor:GetMobGroup())
t=23;manage:tick()
assert(#opens==openCount and #events==eventCount,'this original pair does not use the unrelated HuaShan opening')
assert(puppetRows[1].actor.MobGroup.MobDomain:IsActorInMobDomain(mapEnemy) and not mapEnemy.MobGroup)
manage:roster({});t=24;manage:tick();manage:silence(true)
for _,a in ipairs(created)do assert(not a.live)end
for _,rows in ipairs({blue,red,twins,allied,redAllied,maskRows,puppetRows,swordRows})do for _,r in ipairs(rows)do assert(r.actor.live and not r.actor.Spawner and not r.actor.MobGroup)end end
print('PASS private HuaShan, Jade and Sword of Despair groups, companion encounters, native membership, same-group revival, and cleanup')
