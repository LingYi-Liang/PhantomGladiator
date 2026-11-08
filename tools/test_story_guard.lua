package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Guard=require('story_guard')
local address=0
local function object(fields)
    address=address+1;local a=address
    local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()return a end
    return o
end
local function fname(text)return {text=text,ToString=function(self)return self.text end} end
local function class(name)return object({GetFName=function()return fname(name) end}) end
local function param(value,readonly)
    return {v=value,type=function()return 'RemoteUnrealParam' end,get=function(self)return self.v end,
        set=function(self,v)if readonly then error('read only') end;self.v=v end}
end
local function harness()
    local h={logs={},now=0,members={},hooks={},nextId=0,removed={},tags={},spawner=nil,has=nil}
    function h.all()return table.concat(h.logs,'\n') end
    h.player=object({GetClass=function()return class('BP_RenewalPlayer_Hun_C') end})
    function h.unit(path)
        local u=object({GetClass=function()return class(path:match('([%w_]+)%.[%w_]+$') or 'X') end})
        h.tags[u]={}
        h.members[#h.members+1]={actor=u,class_path=path}
        return u
    end
    h.pipeline=object({HasTagWithOutSource=function(_,tag)h.asked=tag;h.askedCount=(h.askedCount or 0)+1;return h.has end})
    h.sub=object({GetSpawner=function(_,id)h.spawnerId=id and id.text;return h.spawner end})
    h.guard=Guard.new({log=function(m)h.logs[#h.logs+1]=m end,clock=function()return h.now end,fname=fname,
        members=function()return h.members end,label=function(actor)return 'unit'..actor:GetAddress() end,
        tagCount=function(actor,tag)return (h.tags[actor] or {})[tag] or 0 end,
        find=function(path)return h.missing~=path and object() or nil end,
        registerHook=function(path,pre,post)
            h.nextId=h.nextId+1;h.hooks[path]={pre=pre,post=post,id=h.nextId};return h.nextId,h.nextId+100
        end,
        unregisterHook=function(path,pre,post)h.removed[#h.removed+1]=path;h.hooks[path]=nil;return true end,
        aiSubsystem=function()return h.noSub and nil or h.sub end,pipeline=function()return h.pipeline end})
    function h.send(target,tagName,tags,readonly)
        local hook=h.hooks['/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:SendGameplayEventToActor']
        local actor=param(target,readonly)
        local eventTag=param({TagName=fname(tagName)})
        local list={}
        for _,t in ipairs(tags or {})do list[#list+1]={TagName=fname(t)} end
        local payload=param({InstigatorTags={GameplayTags=list}})
        hook.pre(object(),actor,eventTag,payload)
        return actor,eventTag,payload
    end
    function h.heard(tags)
        local path
        for p in pairs(h.hooks)do if p:find('EventReceived_',1,true) then path=p end end
        local list={}
        for _,t in ipairs(tags or {})do list[#list+1]={TagName=fname(t)} end
        h.hooks[path].pre(h.player,param({InstigatorTags={GameplayTags=list}}))
    end
    function h.makeSpawner(should,would,present,withScript)
        local tag=fname('qsd.击杀.雷当')
        local scripts={}
        if withScript~=false then
            scripts[1]=object({GetClass=function()return class('AIScript_AddTagOnDead_C') end,EventTag={GameplayTags={{TagName=tag}}}})
        end
        local s=object({ShouldSpawn=should,SpawnedAI=present and object() or nil,SpawnInfo={ExtraScripts=scripts},saves=0,despawns=0,
            GetClass=function()return class('BP_AISpawner_C') end})
        s.IsShouldToSpawn=function(self)return self.would end
        s.would=would
        s.Save=function(self)self.saves=self.saves+1;self.would=self.ShouldSpawn end
        s.Despawn=function(self)self.despawns=self.despawns+1;if self.SpawnedAI then self.SpawnedAI.alive=false;self.SpawnedAI=nil end end
        h.spawner=s
        return s,tag
    end
    return h
end

do -- Hooked only while one of the mod's units is a phase-one 雷当; phase two does not count.
    local h=harness()
    h.unit('/PBZCombatAsset/ActorData/Mobs/050_LeiDang_P2/BP_Monster_LeiDang_P2.BP_Monster_LeiDang_P2_C')
    h.guard:tick()
    assert(next(h.hooks)==nil,h.all())
    local one=h.unit('/PBZCombatAsset/ActorData/Mobs/047_LeiDang/BP_Monster_LeiDang_NPC.BP_Monster_LeiDang_NPC_C')
    h.guard:tick()
    local n=0;for _ in pairs(h.hooks)do n=n+1 end
    assert(n==2 and h.all():find('挂钩 发事件 注册ID读回',1,true) and h.all():find('挂钩 玩家收事件 注册ID读回',1,true),h.all())
    h.guard:tick()
    n=0;for _ in pairs(h.hooks)do n=n+1 end
    local _,times=h.all():gsub('挂钩 发事件 注册ID读回','')
    assert(n==2 and times==1,'registered once')
    one.alive=false
    h.guard:tick()
    assert(next(h.hooks)==nil and #h.removed==2 and h.all():find('摘除挂钩 reason=召唤的一阶段雷当都已离场 摘除=2 失败=0',1,true),h.all())
end

do -- Other events and a group clear while no 雷当 of ours is in its phase-end move pass untouched.
    local h=harness()
    local one=h.unit('/PBZCombatAsset/ActorData/Mobs/047_LeiDang/BP_Monster_LeiDang.BP_Monster_LeiDang_C')
    h.guard:tick()
    local actor=h.send(h.player,'GameplayEvent.Hit',{'qsd.击杀.雷当'})
    assert(actor.v==h.player and h.guard:status().passed==0)
    actor=h.send(h.player,'GameplayEvent.MobGroup.Clear',{'qsd.某地.清场'})
    assert(actor.v==h.player and h.guard:status().passed==1 and h.all():find('放行 GameplayEvent.MobGroup.Clear InstigatorTags=[qsd.某地.清场]',1,true),h.all())
    assert(h.guard:status().redirected==0)
    h.tags[one]['CharacterState.AbilityState.LeiDang.Dead']=0
    actor=h.send(h.player,'GameplayEvent.MobGroup.Clear',{'qsd.击杀.雷当'})
    assert(actor.v==h.player and h.guard:status().passed==2)
end

do -- Ours in its phase-end move: the event goes to it, and the player not hearing it is confirmed later.
    local h=harness()
    local one=h.unit('/PBZCombatAsset/ActorData/Mobs/047_LeiDang/BP_Monster_LeiDang.BP_Monster_LeiDang_C')
    h.guard:tick()
    h.tags[one]['CharacterState.AbilityState.LeiDang.Dead']=1
    local actor,eventTag=h.send(h.player,'GameplayEvent.MobGroup.Clear',{'qsd.击杀.雷当'})
    assert(actor.v==one and eventTag.v.TagName.text=='GameplayEvent.MobGroup.Clear',h.all())
    assert(h.all():find('目标改成这只雷当 写入=true 读回=已改 累计=1',1,true) and h.all():find('InstigatorTags=[qsd.击杀.雷当]',1,true),h.all())
    h.now=1;h.guard:tick()
    assert(not h.all():find('确认',1,true),'too early')
    h.now=2.5;h.guard:tick()
    assert(h.all():find('确认：玩家没收到 unit',1,true) and h.guard:status().leaked==0,h.all())
end

do -- If the target cannot be changed, the event's tag is; the player's handler running right after counts as a leak.
    local h=harness()
    local one=h.unit('/PBZCombatAsset/ActorData/Mobs/047_LeiDang/BP_Monster_LeiDang.BP_Monster_LeiDang_C')
    h.guard:tick()
    h.tags[one]['CharacterState.AbilityState.LeiDang.Dead']=1
    local actor,eventTag=h.send(h.player,'GameplayEvent.MobGroup.Clear',{'qsd.击杀.雷当'},true)
    assert(actor.v==h.player and eventTag.v.TagName.text=='None' and h.all():find('事件标签改成 None 写入=false 读回=已改',1,true),h.all())
    h.heard({'qsd.击杀.雷当'})
    assert(h.guard:status().leaked==1 and h.all():find('拦截没生效：玩家仍收到',1,true),h.all())
    h.now=5;h.guard:tick()
    assert(not h.all():find('确认',1,true),'a leak is not confirmed as stopped')
    h.heard({'qsd.别处.清场'})
    assert(h.all():find('（不是召唤的雷当发的）',1,true) and h.guard:status().leaked==1,h.all())
end

do -- The save: phase one's spawner is closed only when the story already counts it killed and the spawner would let it out.
    local h=harness()
    h.noSub=true;h.guard:tick()
    assert(#h.logs==0,'no subsystem, nothing read')
    h.noSub=false;h.now=3;h.guard:tick()
    assert(h.spawnerId=='LeiDang_Seq123-3' and #h.logs==0,'no spawner in this world')
    local s,tag=h.makeSpawner(true,true,false)
    h.has=false;h.now=6;h.guard:tick()
    assert(s.ShouldSpawn==true and s.saves==0 and s.despawns==0,h.all())
    assert(h.asked.TagName==tag and h.all():find('剧情标记[qsd.击杀.雷当]（刷怪点脚本）=false',1,true),h.all())
    h.now=7;h.guard:tick()
    assert(h.askedCount==1,'looked at every 3 s')
    h.has=true;h.now=9;h.guard:tick()
    assert(s.ShouldSpawn==true and s.saves==0 and s.despawns==0 and h.guard:status().repaired==0,'nothing written before the save-repair button')
    assert(h.all():find('助手里点"修复存档"后照 Seq123-4 开始时的做法关掉',1,true),h.all())
    h.now=12;h.guard:tick()
    local _,said=h.all():gsub('助手里点"修复存档"','')
    assert(said==1,'said once while it waits')
    h.guard:arm();h.now=12.5;h.guard:tick()
    assert(s.ShouldSpawn==false and s.saves==1 and s.despawns==1 and h.guard:status().repaired==1,'armed: looked at again right away; '..h.all())
    assert(h.all():find('写 ShouldSpawn=false=true 保存=true 移除=true；读回 ShouldSpawn=false 会刷出=false 在场=false 累计=1',1,true),h.all())
    h.now=16;h.guard:tick()
    assert(s.saves==1 and h.guard:status().repaired==1,'nothing more to do')
end

do -- Phase one standing there is removed; after a reload (ShouldSpawn back on, the save saying dead) nothing is done.
    local h=harness()
    h.guard:arm()
    local s=h.makeSpawner(false,false,true)
    h.has=true;h.guard:tick()
    assert(s.despawns==1 and s.SpawnedAI==nil and h.guard:status().repaired==1,h.all())
    s=h.makeSpawner(true,false,false)
    h.now=3;h.guard:tick()
    assert(s.saves==0 and s.despawns==0 and h.guard:status().repaired==1,h.all())
    s=h.makeSpawner(true,true,false)
    h.has=nil;h.now=6;h.guard:tick()
    assert(s.saves==0,'an unreadable answer changes nothing')
end

do -- Without the spawner's death script the tag is built from its name.
    local h=harness()
    h.makeSpawner(true,true,false,false)
    h.has=false;h.guard:tick()
    assert(h.asked.TagName.text=='qsd.击杀.雷当' and h.all():find('（按名字）=false',1,true),h.all())
end

do -- A hook that cannot be found or registered is reported and not retried every tick.
    local h=harness()
    h.missing='/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:SendGameplayEventToActor'
    h.unit('/PBZCombatAsset/ActorData/Mobs/047_LeiDang/BP_Monster_LeiDang.BP_Monster_LeiDang_C')
    h.guard:tick();h.guard:tick()
    local _,found=h.all():gsub('找不到函数','')
    assert(found==1,h.all())
end
do -- 雷煌 and 雷鸣 run 雷当's AI config and phase-end move: they count as phase one.
    for _,name in ipairs({'BP_Monster_LeiHuang','BP_Monster_LeiMing'})do
        local h=harness()
        h.unit('/Game/RenewalContent/Actors/Mobs/Normal/'..name..'.'..name..'_C')
        h.guard:tick()
        assert(next(h.hooks)~=nil,name..' hooks the event')
    end
    local h=harness()
    h.unit('/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_LeiHuangFake.BP_Monster_LeiHuangFake_C')
    h.guard:tick()
    assert(next(h.hooks)==nil,'only those two classes')
end

do -- The save-repair report: nothing to do, something to do, unread.
    local h=harness()
    local marks={}
    local function has(t)return marks[t] end
    local ok,line=h.guard:diagnose(has)
    assert(ok==nil and line=='雷当','unread')
    marks['qsd.击杀.雷当']=false
    ok,line=h.guard:diagnose(has);assert(ok==true and line=='雷当')
    marks['qsd.击杀.雷当']=true;marks['qsd.Boss战.结束']=true
    ok,line=h.guard:diagnose(has);assert(ok==true,'the fight is over')
    marks['qsd.Boss战.结束']=false
    ok,line=h.guard:diagnose(has)
    assert(ok==false and line=='雷当：已被记成打过，到戏梦山庄时关掉一阶段，只打二阶段',line)
    marks['qsd.Boss战.结束']=nil
    ok,line=h.guard:diagnose(has)
    assert(ok==false and line:find('（读不到这一战打完没有）',1,true),line)
    h.guard:arm();h.makeSpawner(true,true,false);h.has=true;h.guard:tick()
    ok,line=h.guard:diagnose(has)
    assert(ok==false and line=='雷当：已关掉一阶段刷怪点，只打二阶段',line)
end
print('story_guard: PASS')
