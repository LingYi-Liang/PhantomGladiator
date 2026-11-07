package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Keep=require('stand_keep')
local Ground=require('on_ground')
local address=0
-- An access to a dead object is a native crash in the game, which pcall does not stop: counted here.
local illegal=0
local function object(fields)
    address=address+1;local a=address
    local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function(self)if not self.alive then illegal=illegal+1 end;return a end
    return o
end
-- As the game does it (GA_SpaceState): walking gives the ground tag, falling or flying takes it away.
local function harness()
    local h={logs={},at={},world=object(),now=0,floor=0,members={},camera={X=0,Y=0,Z=500}}
    h.ground=Ground.new({log=function(m)h.logs[#h.logs+1]=m end,location=function(actor)return h.at[actor] end,
        ground=function()return h.floor end,label=function()return 'unit' end,world=function()return h.world end,name=function(text)return text end})
    h.keep=Keep.new({log=function(m)h.logs[#h.logs+1]=m end,clock=function()return h.now end,
        members=function()h.looks=(h.looks or 0)+1;return h.members end,
        location=function(actor)
            if not actor:IsValid() then illegal=illegal+1 end
            return h.at[actor]
        end,ground=h.ground,label=function(actor)return actor.name end,camera=function()return h.camera end})
    function h.all()return table.concat(h.logs,'\n') end
    function h.unit(name,at,mode)
        local tags={['CharacterState.Space.Ground']=(mode==3 or mode==5) and 0 or 1,['Ability.Action']=0,['CharacterType.Stand.Enable']=0}
        local asc=object({GetGameplayTagCount=function(_,tag)return tags[tag.TagName] end})
        local cmc=object({MovementMode=mode or 1})
        cmc.SetMovementMode=function(self,value)
            self.MovementMode=value
            tags['CharacterState.Space.Ground']=(value==1 or value==2) and 1 or 0
        end
        local u=object({name=name,tags=tags,DeadDepth=2000,AbilitySystemComponent=asc,CharacterMovement=cmc,
            CapsuleComponent=object({GetScaledCapsuleHalfHeight=function()return 100 end})})
        u.K2_GetActorRotation=function()return {Pitch=0,Yaw=0,Roll=0} end
        u.K2_TeleportTo=function(self,dest)
            if h.teleportFails then return false end
            h.at[self]=dest;h.teleports=(h.teleports or 0)+1;return true
        end
        h.at[u]=at
        return u
    end
    function h.stand(owner,at,mode)
        local u=h.unit('stand',at,mode)
        h.members[#h.members+1]={actor=u,summoner=owner,stand=true,team='companion'}
        return u
    end
    function h.tick(seconds)
        h.now=h.now+(seconds or 1)
        h.keep:tick()
    end
    return h
end
local function test(name,fn)fn();print('ok - '..name)end

test('frozen in the air by the far rule: on the ground beside the summoner, walking, and her moves can start again',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=20000,Y=0,Z=400},5)
    assert(stand.tags['CharacterState.Space.Ground']==0)
    h.tick()
    assert(stand.CharacterMovement.MovementMode==1 and stand.tags['CharacterState.Space.Ground']==1,h.all())
    local at=h.at[stand]
    assert(at.X==300 and at.Y==0 and at.Z==0+100+3,at.X..' '..at.Z)
    assert(stand.DeadDepth==1e9,'a stand does not die of a fall either')
    assert(h.all():find('stand 飞行：模式=飞行 在地面标签=0 离召唤者=200.0m；放到召唤者身边 传送=true 改走路=true；读回 模式=走路 在地面标签=1 离召唤者=3.0m；累计=1',1,true),h.all())
end)

test('in the air near the summoner with ground under it: it comes straight down, not across the field',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=2000,Y=500,Z=400},5)
    h.tick()
    local at=h.at[stand]
    assert(at.X==2000 and at.Y==500 and at.Z==103,at.X..' '..at.Z)
    assert(h.all():find('放到脚下地面',1,true),h.all())
end)

test('in a move: never touched, in the air or far away',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=20000,Y=0,Z=400},5)
    stand.tags['Ability.Action']=1
    h.tick()
    assert(stand.CharacterMovement.MovementMode==5 and not h.teleports)
    stand.tags['Ability.Action']=0;stand.tags['CharacterType.Stand.Enable']=1
    h.tick()
    assert(stand.CharacterMovement.MovementMode==5 and not h.teleports)
    -- A tag that does not read is not a stand known to be idle.
    stand.tags['CharacterType.Stand.Enable']=nil
    h.tick()
    assert(stand.CharacterMovement.MovementMode==5 and not h.teleports)
    -- The move over: it is its turn.
    stand.tags['CharacterType.Stand.Enable']=0
    h.tick()
    assert(stand.CharacterMovement.MovementMode==1 and h.teleports==1)
end)

test('an ordinary fall lands by itself; one that lasts goes down at once',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=500,Y=0,Z=400},3)
    h.tick(0.6)
    assert(stand.CharacterMovement.MovementMode==3 and not h.teleports,'just started falling')
    h.tick(1.1)
    assert(stand.CharacterMovement.MovementMode==1 and h.teleports==1,h.all())
    assert(h.all():find('stand 下落：',1,true))
end)

test('on the ground and near: left where it is, however long, but a fall can no longer kill it',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=5900,Y=0,Z=100},1)
    for _=1,20 do h.tick() end
    assert(stand.DeadDepth==1e9,'from the first look')
    assert(not h.teleports and #h.logs<=1,h.all())
    assert(h.at[stand].X==5900)
end)

test('left far behind on the ground: comes along before the ground under it unloads',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=6100,Y=0,Z=100},1)
    h.tick()
    assert(h.at[stand].X==300 and h.teleports==1,h.all())
    assert(h.all():find('stand 离召唤者太远：',1,true))
end)

test('camera out of reach of the summoner: the script would freeze it again, so it waits, and says so once',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=500,Y=0,Z=100},5)
    h.camera={X=0,Y=13000,Z=100}
    h.tick();h.tick();h.tick()
    assert(stand.CharacterMovement.MovementMode==5 and not h.teleports)
    local _,said=h.all():gsub('等镜头回来',' ')
    assert(said==1,h.all())
    h.camera={X=0,Y=500,Z=100}
    h.tick()
    assert(stand.CharacterMovement.MovementMode==1 and h.teleports==1,h.all())
    -- No camera to read: nothing to wait for.
    local h2=harness()
    h2.camera=nil
    local owner2=h2.unit('owner',{X=0,Y=0,Z=100})
    local stand2=h2.stand(owner2,{X=500,Y=0,Z=100},5)
    h2.tick()
    assert(stand2.CharacterMovement.MovementMode==1)
end)

test('a teleport the game refuses is said and tried again later, not every look',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=20000,Y=0,Z=400},5)
    h.teleportFails=true
    h.tick(1)
    assert(h.all():find('传送=false',1,true),h.all())
    assert(h.keep.parked==0)
    local lines=#h.logs
    h.tick(0.6);h.tick(0.6)
    assert(#h.logs==lines,'waits '..h.all())
    h.teleportFails=false
    h.tick(1)
    assert(h.teleports==1 and h.keep.parked==1,h.all())
    assert(stand.CharacterMovement.MovementMode==1)
end)

test('objects that are gone are not asked anything',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=20000,Y=0,Z=400},5)
    owner.alive=false
    h.tick()
    assert(stand.CharacterMovement.MovementMode==5 and not h.teleports,'no summoner, nowhere to go')
    stand.alive=false
    h.tick()
    assert(illegal==0,illegal)
    h.members={}
    h.tick()
    assert(illegal==0,illegal)
end)

test('looks twice a second at most, and a crowd does not use up the log',function()
    local h=harness()
    local owner=h.unit('owner',{X=0,Y=0,Z=100})
    local stand=h.stand(owner,{X=20000,Y=0,Z=400},5)
    h.tick(1)
    assert(h.teleports==1 and h.looks==1)
    h.at[stand]={X=20000,Y=0,Z=400};stand.CharacterMovement:SetMovementMode(5)
    h.tick(0.1);h.tick(0.1)
    assert(h.teleports==1 and h.looks==1,'not yet')
    for _=1,200 do
        h.at[stand]={X=20000,Y=0,Z=400};stand.CharacterMovement:SetMovementMode(5)
        h.tick(3)
    end
    local _,lines=h.all():gsub('%[StandKeep%]',' ')
    assert(lines<=60,lines)
    assert(h.keep.parked>100)
end)
print('test_stand_keep: all passed')
