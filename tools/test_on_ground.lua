package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Ground=require('on_ground')
local address=0
local function object(fields)
    address=address+1;local a=address
    local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()return a end
    return o
end
local function harness()
    local h={logs={},at={},heights={},world=object(),asked={}}
    h.ground=function(world,x,y,z,up)
        h.asked[#h.asked+1]={x=x,y=y,z=z,up=up}
        local height=h.heights[x..','..y]
        if height==nil then height=h.floor end
        if height==false then return nil end
        return height
    end
    h.g=Ground.new({log=function(m)h.logs[#h.logs+1]=m end,location=function(actor)return h.at[actor] end,ground=h.ground,
        label=function()return 'unit' end,world=function()return h.world end,name=function(text)return text end,player=function()return h.player end})
    function h.all()return table.concat(h.logs,'\n') end
    function h.unit(half,at,mode,block)
        local u
        local asc=object({tags={['AI.DisableCombatAI']=block or 0}})
        asc.GetGameplayTagCount=function(self,tag)return self.tags[tag.TagName] or 0 end
        local cmc=object({MovementMode=mode or 1})
        cmc.SetMovementMode=function(self,value)self.MovementMode=value;asc.tags['AI.DisableCombatAI']=0;h.walked=value end
        u=object({CapsuleComponent=object({half=half,GetScaledCapsuleHalfHeight=function(self)return self.half end}),AbilitySystemComponent=asc,CharacterMovement=cmc,DeadDepth=2000})
        u.K2_GetActorRotation=function()return {Pitch=0,Yaw=30,Roll=0} end
        u.K2_TeleportTo=function(self,dest,rot)h.at[self]=dest;h.rot=rot;h.teleports=(h.teleports or 0)+1;return true end
        h.at[u]=at or {X=0,Y=0,Z=0}
        return u
    end
    return h
end

do -- a summon starts on the ground under its spot, whichever way its spot was off; a fall can no longer kill it
    local h=harness();h.floor=-300
    local u=h.unit(96)
    local t={Translation={X=10,Y=20,Z=50}}
    local placed=h.g:place(u,t,h.world)
    assert(t.Translation.Z==-300+96+3 and placed.ground==-300 and placed.before==50,tostring(t.Translation.Z))
    assert(h.asked[1].up==0,'first from its own height: a roof over a low room is not its floor')
    assert(u.DeadDepth==1e9 and h.all():find('坠落致死深度 2000 -> 1000000000.0 写入=true',1,true),h.all())
    h.at[u]={X=10,Y=20,Z=t.Translation.Z}
    h.g:settle(u,placed)
    assert(not h.teleports and h.all():find('地面Z=-300.0 半高 出生前=96.0 现在=96 原高度=50.0 目标=-201.0 抬高=否 读回Z=-201.0',1,true),h.all())
end

do -- inside a slope nothing is under it: traced again from over the spot
    local h=harness()
    local answers={false,100}
    h.g=Ground.new({location=function(actor)return h.at[actor] end,label=function()return 'unit' end,world=function()return h.world end,name=function(t)return t end,
        ground=function(world,x,y,z,up)h.asked[#h.asked+1]={up=up};return table.remove(answers,1) or nil end})
    local t={Translation={X=0,Y=0,Z=50}}
    assert(h.g:place(h.unit(96),t,h.world) and t.Translation.Z==100+96+3)
    assert(h.asked[1].up==0 and h.asked[2].up==nil)
end

do -- started inside something and the look from 3 m up lands high: the top of that thing, the spot keeps its height
    local h=harness()
    local calls=0
    h.g=Ground.new({location=function(actor)return h.at[actor] end,label=function()return 'unit' end,world=function()return h.world end,name=function(t)return t end,
        ground=function()calls=calls+1;if calls==1 then return nil,'inside' end;return 166 end})
    local t={Translation={X=0,Y=0,Z=50}}
    assert(h.g:place(h.unit(96),t,h.world)==nil and t.Translation.Z==50)
end

do -- nothing under the spot and the same answer: a hill, a spot at the player's height goes up onto it
    local h=harness()
    local calls=0
    h.g=Ground.new({location=function(actor)return h.at[actor] end,label=function()return 'unit' end,world=function()return h.world end,name=function(t)return t end,
        ground=function()calls=calls+1;if calls==1 then return nil end;return 340 end})
    local t={Translation={X=0,Y=0,Z=50}}
    assert(h.g:place(h.unit(96),t,h.world) and t.Translation.Z==340+96+3,tostring(t.Translation.Z))
end

do -- started inside something shallow, as a spot sunk a little into the ground: it comes up
    local h=harness()
    local calls=0
    h.g=Ground.new({location=function(actor)return h.at[actor] end,label=function()return 'unit' end,world=function()return h.world end,name=function(t)return t end,
        ground=function()calls=calls+1;if calls==1 then return nil,'inside' end;return 100 end})
    local t={Translation={X=0,Y=0,Z=50}}
    assert(h.g:place(h.unit(96),t,h.world) and t.Translation.Z==100+96+3,tostring(t.Translation.Z))
end

do -- its real capsule is taller than the class default: lifted out of the ground; a shorter one is left to land
    local h=harness();h.floor=0
    local u=h.unit(96)
    local t={Translation={X=0,Y=0,Z=50}}
    local placed=h.g:place(u,t,h.world)
    u.CapsuleComponent.half=200;h.at[u]={X=0,Y=0,Z=99}
    h.g:settle(u,placed)
    assert(h.at[u].Z==203 and h.teleports==1 and h.rot.Yaw==30,h.all())
    local short=h.unit(96);placed=h.g:place(short,{Translation={X=0,Y=0,Z=50}},h.world)
    short.CapsuleComponent.half=50;h.at[short]={X=0,Y=0,Z=99}
    h.g:settle(short,placed)
    assert(h.teleports==1 and h.at[short].Z==99)
end

do -- a spot over a drop: closer to the player, the first place with ground in reach
    local h=harness();h.floor=-5000
    h.player=object();h.at[h.player]={X=0,Y=0,Z=0}
    h.heights['500.0,0.0']=-30
    local t={Translation={X=1000,Y=0,Z=50}}
    local u=h.unit(96)
    local placed=h.g:place(u,t,h.world)
    assert(t.Translation.X==500 and t.Translation.Z==-30+96+3 and placed.closer==0.5,tostring(t.Translation.X))
    h.at[u]={X=500,Y=0,Z=t.Translation.Z};h.g:settle(u,placed)
    assert(h.all():find('出生点下面是落差，移近玩家到50%',1,true),h.all())
end

do -- no ground found, or no capsule: the spot stays as it was
    local h=harness();h.floor=false
    local t={Translation={X=0,Y=0,Z=50}}
    assert(h.g:place(h.unit(96),t,h.world)==nil and t.Translation.Z==50)
    assert(h.all():find('出生点下方没找到地面，高度不变 Z=50',1,true))
    h.floor=0
    local bare=object()
    assert(h.g:place(bare,t,h.world)==nil and t.Translation.Z==50)
    h.g:settle(bare,nil)
end

do -- a unit held in the air goes on the ground under it and walks; the trace starts at its feet, under its own body
    local h=harness();h.floor=-500
    local u=h.unit(96,{X=1,Y=2,Z=100},5,1)
    assert(h.g:free(u,nil)==true)
    assert(h.at[u].X==1 and h.at[u].Y==2 and h.at[u].Z==-500+96+3,tostring(h.at[u].Z))
    assert(h.asked[1].z==4 and h.asked[1].up==10,'from the feet')
    assert(h.walked==1 and h.all():find('解除空中冻结 unit：放到脚下地面',1,true) and h.all():find('读回 模式=1 封锁标签=0',1,true),h.all())
    assert(h.g.freed==1 and u.DeadDepth==1e9)
    assert(h.g:free(u,nil)==false,'done: walking, not blocked')
end

do -- too far down, or nothing there: beside its opponent, on the ground there
    local h=harness();h.floor=-5000
    local enemy=h.unit(96,{X=1000,Y=0,Z=0})
    h.heights['1300.0,0.0']=-40
    local u=h.unit(96,{X=2000,Y=0,Z=100},5,1)
    assert(h.g:free(u,enemy)==true)
    assert(h.at[u].X==1300 and h.at[u].Y==0 and h.at[u].Z==-40+96+3,h.all())
    assert(h.all():find('放到对手身边',1,true),h.all())
end

do -- falling: an ordinary fall lands by itself; off a cliff it comes back beside its opponent
    local h=harness();h.floor=-200
    local enemy=h.unit(96,{X=0,Y=0,Z=0})
    local u=h.unit(96,{X=100,Y=0,Z=100},3,0)
    assert(h.g:free(u,enemy)==false and not h.teleports,'ground in reach')
    h.floor=-9000
    h.heights['300.0,0.0']=-10
    assert(h.g:free(u,enemy)==true and h.at[u].X==300 and h.at[u].Z==-10+96+3 and h.walked==1,h.all())
    assert(h.all():find('坠崖拉回 unit：放到对手身边',1,true),h.all())
end

do -- left alone: flying without the block (a move or a far unit), blocked on the ground, or nowhere to put it
    local h=harness();h.floor=0
    local flying=h.unit(96,{X=0,Y=0,Z=100},5,0)
    assert(h.g:free(flying,nil)==false)
    local grounded=h.unit(96,{X=0,Y=0,Z=100},1,1)
    assert(h.g:free(grounded,nil)==false)
    h.floor=false
    local nowhere=h.unit(96,{X=0,Y=0,Z=100},5,1)
    assert(h.g:free(nowhere,nil)==false,'no ground and no opponent')
    assert(not h.teleports and h.g.freed==0)
    assert(h.g:free(object(),nil)==false,'no movement component')
end

do -- a crowd does not use up what the log says later
    local h=harness();h.floor=0
    for _=1,40 do
        local u=h.unit(96)
        local p=h.g:place(u,{Translation={X=0,Y=0,Z=50}},h.world)
        h.at[u]={X=0,Y=0,Z=99};h.g:settle(u,p)
    end
    local u=h.unit(96,{X=0,Y=0,Z=100},5,1)
    assert(h.g:free(u,nil)==true and h.all():find('解除空中冻结',1,true),h.all())
end

do -- over a drop, a spot moves toward the middle of the batch when there is one, not toward the hidden body
    local h=harness()
    local anchored=Ground.new({log=function()end,location=function()return {X=9000,Y=9000,Z=100} end,player=function()return h.world end,
        anchor=function()return {X=0,Y=0,Z=100} end,label=function()return 'unit' end,name=function(s)return s end,
        ground=function(_,x)return x==300 and 90 or nil end})
    local u=h.unit(96)
    local t={Translation={X=400,Y=0,Z=150}}
    local placed=anchored:place(u,t,h.world)
    assert(placed and placed.closer==0.75 and t.Translation.X==300 and t.Translation.Y==0,'moved along the line to the anchor')
end

do -- a stand between moves: straight down when it may stay and ground is in reach, otherwise beside its summoner
    local h=harness();h.floor=0
    local owner,stand=h.unit(100,{X=0,Y=0,Z=100}),h.unit(90,{X=500,Y=0,Z=400},5)
    local done=h.g:park(stand,owner,true)
    assert(done.moved and done.walked and done.how=='脚下地面',done.how)
    assert(h.at[stand].X==500 and h.at[stand].Z==93 and h.walked==1,h.at[stand].Z)
    assert(stand.DeadDepth==1e9,'no death from the fall it was in')
    h.at[stand]={X=20000,Y=0,Z=400}
    done=h.g:park(stand,owner,false)
    assert(done.how=='召唤者身边' and h.at[stand].X==300 and h.at[stand].Y==0 and h.at[stand].Z==93,h.at[stand].X)
    -- Right on top of the summoner: any direction will do.
    h.at[stand]={X=0,Y=0,Z=100}
    done=h.g:park(stand,owner,false)
    assert(done.how=='召唤者身边' and h.at[stand].X==300,h.at[stand].X)
end

do -- a ledge or a hole beside the summoner: its own spot; no ground read at all: its feet
    local h=harness();h.floor=0
    local owner,stand=h.unit(100,{X=0,Y=0,Z=100}),h.unit(90,{X=20000,Y=0,Z=400},5)
    h.heights['300.0,0.0']=-2000
    local done=h.g:park(stand,owner,false)
    assert(done.how=='召唤者脚下' and h.at[stand].X==0 and h.at[stand].Z==93,done.how)
    h.heights['300.0,0.0']=nil
    h.floor=false
    h.at[stand]={X=20000,Y=0,Z=400}
    done=h.g:park(stand,owner,false)
    assert(done.how=='召唤者脚下' and h.at[stand].X==0 and h.at[stand].Z==0+90+3,h.at[stand].Z)
end

do -- nothing to work with: says why, moves nothing; a dead object is not asked anything
    local h=harness();h.floor=0
    local owner,stand=h.unit(100,{X=0,Y=0,Z=100}),h.unit(90,{X=0,Y=0,Z=400},5)
    h.at[owner]=nil
    local done=h.g:park(stand,owner,false)
    assert(done.why=='读不到位置或胶囊' and not h.teleports)
    owner.alive=false
    done=h.g:park(stand,owner,false)
    assert(done.why=='对象失效' and not h.teleports)
end

print('on_ground: PASS')
