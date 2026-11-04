package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Combos=require('boss_combos')
local address=0
local function object(name,fields)
    address=address+1;local a=address
    local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()return a end
    o.GetFName=function()return {ToString=function()return name end} end
    o.GetClass=function()return {GetFName=function()return {ToString=function()return name end} end} end
    return o
end
FName=function(text)return text end
local function harness()
    local h={lines={},hooks={},members={},fighting=true,events={},board={},tasks={},waits={},now=0}
    h.aiLib=object('SGameAIFunctionLibrary',{
        SetValueAsVectorByTag=function(_,board,tag,value)h.board[tag.TagName]=value end,
        SetValueAsRotatorByTag=function(_,board,tag,value)h.board[tag.TagName]=value end,
        SetValueAsObjectByTag=function(_,board,tag,value)board.keys[tag.TagName]=value;h.board[tag.TagName]=value end,
        GetValueAsObjectByTag=function(_,board,tag)return board.keys[tag.TagName] end,
        GetRunningBehaviorTree=function(_,controller)return controller.tree end})
    h.bbLib=object('AIBlueprintHelperLibrary',{GetBlackboard=function(_,actor)
        if not actor.board then actor.board=object('Blackboard',{keys={}}) end
        return actor.board
    end})
    h.abilityLib=object('AbilitySystemBlueprintLibrary',{SendGameplayEventToActor=function(_,actor,tag,data)h.events[#h.events+1]={actor=actor,tag=tag.TagName,tree=data.OptionalObject} end})
    StaticFindObject=function(path)
        if path:find('SGameAIFunctionLibrary') then return h.aiLib end
        if path:find('AIBlueprintHelperLibrary') then return h.bbLib end
        if path:find('AbilitySystemBlueprintLibrary') then return h.abilityLib end
        if path:find(':') then return object(path) end
        local name=path:match('%.([%w_]+)$')
        if name then return object(name) end
    end
    FindAllOf=function(class)
        if class=='BTTask_AssignBehaviorTreesToGroupMember_C' then return h.tasks end
        assert(class=='BTTask_WaitGameplayTagRemoveFromActor_C')
        return h.waits
    end
    RegisterHook=function(path,pre,post)h.hooks[path]=pre;return 1,2 end
    UnregisterHook=function(path)h.hooks[path]=nil end
    function h.unit(class,team,reserve)
        local actor=object(class,{K2_GetActorLocation=function()return {X=1000,Y=0,Z=50} end,K2_GetActorRotation=function()return {Yaw=0} end})
        actor.IsAlive=function(self)return not self.dead end
        h.members[#h.members+1]={actor=actor,team=team,reserve=reserve}
        return actor
    end
    function h.new(enabled)
        local c=Combos.new({clock=function()return h.now end,log=function(s)h.lines[#h.lines+1]=s end,members=function()return h.members end,fighting=function()return h.fighting end})
        c.enabled=enabled
        return c
    end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end
local function test(name,fn)fn();print('ok - '..name)end
local function info(actor)return {AvatarActor={Get=function()return actor end}} end

test('a hook whose blueprint is not loaded yet comes in on a later tick, and is named once meanwhile',function()
    local h=harness();local c=h.new(true)
    local realFind=StaticFindObject
    StaticFindObject=function(path)if path==Combos.paths.gateYuu then return nil end;return realFind(path) end
    h.unit('BP_Monster_TieGui_C','blue');h.unit('BP_Monster_Yuu_C','blue')
    c:tick();c:tick()
    assert(h.hooks[Combos.paths.gateYuu]==nil and h.hooks[Combos.paths.gateTieGui]~=nil)
    local _,said=h.all():gsub('读回=未找到，退避重试','')
    assert(said==1,h.all())
    StaticFindObject=realFind
    h.now=1;c:tick()
    assert(h.hooks[Combos.paths.gateYuu]~=nil,h.all())
end)

test('of two of one class the living one pairs',function()
    local h=harness();local c=h.new(true)
    local firstTie=h.unit('BP_Monster_TieGui_C','blue')
    local secondTie,yuu=h.unit('BP_Monster_TieGui_C','blue'),h.unit('BP_Monster_Yuu_C','blue')
    firstTie.dead=true
    c:tick()
    assert(yuu.board.keys['AI.BlackboardKey.Object.Vehicle']==secondTie,h.all())
end)

test('a switch that could not be saved says so',function()
    local h=harness()
    local realOpen=io.open
    io.open=function(path,mode)if mode=='w' then return nil end;return realOpen(path,mode) end
    local c=Combos.new({path='R',log=function(s)h.lines[#h.lines+1]=s end,members=function()return h.members end,fighting=function()return false end})
    local answer=c:set(true)
    io.open=realOpen
    assert(answer.ok==false and answer.message:find('没保存下来',1,true) and c.enabled==true)
end)

test('off: two partners stay two single bosses',function()
    local h=harness();local c=h.new(false)
    h.unit('BP_Monster_TieGui_C','blue');h.unit('BP_Monster_Yuu_C','blue')
    c:tick()
    assert(next(h.hooks)==nil and not h.all():find('连携',1,true))
end)

test('on: same team partners link without any group or spawner; opposite teams do not; only their own tasks are changed',function()
    local h=harness();local c=h.new(true)
    -- A node in the tree asset, a copy that names its tree, and the same two kinds from another pair's trees.
    h.tasks={object('BTTask',{GetOuter=function()return object('BT_Yuu_AllOutAttack_01') end}),object('BTTask',{TreeAsset=object('BT_TieGui_AllOutAttack_02')}),
        object('BTTask',{GetOuter=function()return object('BT_Jade_AllOutAttack_01') end}),object('BTTask',{TreeAsset=object('BT_HuaShan_JianOu_Healing')})}
    h.waits={object('BTWait',{Timeout=-1,GetOuter=function()return object('BT_TieGui_Troop_02') end}),object('BTWait',{Timeout=-1,TreeAsset=object('BT_Yuu_AllOutAttack_03')}),
        object('BTWait',{Timeout=-1,TreeAsset=object('BT_GuiChai_Red_AllOutAttack_02_01')})}
    local tie,yuu=h.unit('BP_Monster_TieGui_C','blue'),h.unit('BP_Monster_Yuu_C','blue')
    h.unit('BP_Monster_Yuu_C','red');h.unit('BP_Monster_FengXueDaoKe_C','blue')
    c:tick();c:tick()
    assert(tie.MobGroup==nil and tie.Spawner==nil and yuu.MobGroup==nil,'a real group makes the AI ask for its mob domain and the game die')
    assert(h.tasks[1].AlwaysSuccess==true and h.tasks[2].AlwaysSuccess==true)
    assert(h.tasks[3].AlwaysSuccess==nil and h.tasks[4].AlwaysSuccess==nil,'another pair keeps what the game set')
    assert(h.waits[1].Timeout==8 and h.waits[2].Timeout==8,'a partner dying with the tag does not hold the survivor')
    assert(h.waits[3].Timeout==-1)
    assert(h.all():find('连携 铁鬼+玉妖 队伍=blue：BP_Monster_TieGui_C + BP_Monster_Yuu_C；分派任务 AlwaysSuccess 读回=2/2（别的树 2 个没动）；等搭档超时 读回=2/2（别的树 1 个没动）',1,true),h.all())
    assert(c:status().links==1,'once')
    local h2=harness();local c2=h2.new(true)
    h2.unit('BP_Monster_TieGui_C','blue');h2.unit('BP_Monster_Yuu_C','red')
    c2:tick();assert(next(h2.hooks)==nil)
end)

test('each partner sits in the other one\'s Vehicle key, or the trees wait forever; a dead one is taken out',function()
    local h=harness();local c=h.new(true)
    local tie,yuu=h.unit('BP_Monster_TieGui_C','blue'),h.unit('BP_Monster_Yuu_C','blue')
    c:tick()
    assert(tie.board.keys['AI.BlackboardKey.Object.Vehicle']==yuu and yuu.board.keys['AI.BlackboardKey.Object.Vehicle']==tie)
    assert(h.all():find('搭档键 单位=BP_Monster_TieGui_C 搭档=BP_Monster_Yuu_C 写入=true 读回=true',1,true),h.all())
    tie.dead=true;c:tick()
    assert(yuu.board.keys['AI.BlackboardKey.Object.Vehicle']==nil,'the survivor stops copying a dead unit\'s target')
    assert(h.all():find('搭档不在了，清空搭档键 单位=BP_Monster_Yuu_C',1,true),h.all())
    tie.dead=false;c:tick()
    assert(yuu.board.keys['AI.BlackboardKey.Object.Vehicle']==tie,'back again')
    h.fighting=false;c:tick()
    assert(tie.board.keys['AI.BlackboardKey.Object.Vehicle']==nil and yuu.board.keys['AI.BlackboardKey.Object.Vehicle']==nil,'nothing left after the fight')
    -- A blackboard that is not there yet is tried again on the next tick.
    local h2=harness();local c2=h2.new(true)
    local t2,y2=h2.unit('BP_Monster_TieGui_C','blue'),h2.unit('BP_Monster_Yuu_C','blue')
    h2.bbLib.GetBlackboard=function()return nil end
    c2:tick();assert(h2.all():find('还没有黑板',1,true),h2.all())
    h2.bbLib.GetBlackboard=function(_,actor)if not actor.board then actor.board=object('Blackboard',{keys={}}) end;return actor.board end
    c2:tick();assert(t2.board.keys['AI.BlackboardKey.Object.Vehicle']==y2)
end)

test('a tree a linked unit starts is named in the log',function()
    local h=harness();local c=h.new(true)
    local tie,yuu=h.unit('BP_Monster_TieGui_C','blue'),h.unit('BP_Monster_Yuu_C','blue')
    local controller=object('AIController',{tree=object('BT_Combat')})
    yuu.GetController=function()return controller end
    c:tick();c:tick()
    assert(not h.all():find('行为树 单位',1,true),'ordinary trees are not worth a line')
    controller.tree=object('BT_Yuu_AllOutAttack_01');c:tick();c:tick()
    local _,lines=h.all():gsub('行为树 单位=BP_Monster_Yuu_C %-> BT_Yuu_AllOutAttack_01','')
    assert(lines==1,h.all())
end)

test('the gate opens for a linked unit with a living partner only',function()
    local h=harness();local c=h.new(true)
    local tie,yuu=h.unit('BP_Monster_TieGui_C','blue'),h.unit('BP_Monster_Yuu_C','blue')
    c:tick()
    local gate=h.hooks[Combos.paths.gateYuu]
    local ability=object('GA_Yuu_AllOutAttack_C')
    assert(gate(ability,info(yuu))==true)
    assert(gate(ability,info(object('BP_Monster_Yuu_C')))==nil,'a unit outside the pair keeps the game answer')
    assert(h.all():find('组合技放行 招式=GA_Yuu_AllOutAttack_C 单位=BP_Monster_Yuu_C 搭档=BP_Monster_TieGui_C',1,true),h.all())
    -- Trees that loaded with the ability, after the pair linked, are done on its first answer.
    local late=object('BTTask',{TreeAsset=object('BT_Yuu_AllOutAttack_02')})
    h.tasks={late}
    gate(object('GA_TieGui_AllOutAttack_C'),info(tie))
    assert(late.AlwaysSuccess==true,h.all())
    late.AlwaysSuccess=nil
    gate(object('GA_TieGui_AllOutAttack_C'),info(tie))
    assert(late.AlwaysSuccess==nil,'once for each ability')
    tie.dead=true
    assert(gate(ability,info(yuu))==nil,'partner dead')
    assert(gate(ability,{})==nil,'no caster readable')
    -- No partner key yet: the game's own answer stays, or the tree would hang on the empty key.
    local h2=harness();local c2=h2.new(true)
    local t2,y2=h2.unit('BP_Monster_TieGui_C','blue'),h2.unit('BP_Monster_Yuu_C','blue')
    h2.bbLib.GetBlackboard=function()return nil end
    c2:tick()
    assert(h2.hooks[Combos.paths.gateYuu](ability,info(y2))==nil,'no key, no combo')
    h2.bbLib.GetBlackboard=function(_,actor)if not actor.board then actor.board=object('Blackboard',{keys={}}) end;return actor.board end
    c2:tick()
    assert(h2.hooks[Combos.paths.gateYuu](ability,info(y2))==true,'key read back, combo allowed')
end)

test('the assign task finding nobody: the partner gets its tree and the assign keys',function()
    local h=harness();local c=h.new(true)
    local tie,yuu=h.unit('BP_Monster_TieGui_C','blue'),h.unit('BP_Monster_Yuu_C','blue')
    c:tick()
    local assign=h.hooks[Combos.paths.assign]
    assign(object('BTTask',{ControlledPawn=yuu,TreeAsset=object('BT_Yuu_AllOutAttack_02')}))
    assert(#h.events==1 and h.events[1].actor==tie and h.events[1].tag=='GameplayEvent.AI.EventTransition.CustomState')
    assert(h.events[1].tree.GetFName():ToString()=='BT_Yuu_AllOutAttack_02_TieGui')
    local spot=h.board['AI.BlackboardKey.Vector.AssignLocation']
    assert(math.abs(spot.X-1150)<0.01 and math.abs(spot.Y+150)<0.01 and h.board['AI.BlackboardKey.Object.AssignBaseActor']==yuu)
    assert(h.all():find('组合技分派 单位=BP_Monster_Yuu_C 树=BT_Yuu_AllOutAttack_02 -> 搭档=BP_Monster_TieGui_C 树=BT_Yuu_AllOutAttack_02_TieGui 黑板写入=true 发事件=true',1,true),h.all())
    -- The next tick says what the partner really runs, whatever that is.
    local brain=object('AIController',{tree=object('BT_Combat')})
    tie.GetController=function()return brain end
    c:tick()
    assert(h.all():find('分派后 搭档=BP_Monster_TieGui_C 要跑=BT_Yuu_AllOutAttack_02_TieGui 实际在跑=BT_Combat',1,true),h.all())
    local _,once=h.all():gsub('分派后','');c:tick();local _,still=h.all():gsub('分派后','')
    assert(once==1 and still==1,'one line for one dispatch')
    assign(object('BTTask',{ControlledPawn=object('BP_Other_C'),TreeAsset=object('BT_Yuu_AllOutAttack_02')}))
    assert(#h.events==1,'not a linked unit')
    assign(object('BTTask',{ControlledPawn=tie,TreeAsset=object('BT_Other')}))
    assert(#h.events==1 and c:status().failures==1 and h.all():find('没找到搭档的树',1,true))
    tie.AbilitySystemComponent=object('ASC',{GetGameplayTagCount=function()return 1 end})
    assign(object('BTTask',{ControlledPawn=yuu,TreeAsset=object('BT_Yuu_AllOutAttack_01')}))
    assert(#h.events==1,'partner marked as not to be assigned')
end)

test('switch off or fight over: hooks go; on again links anew',function()
    local h=harness();local c=h.new(true)
    h.unit('BP_Monster_TieGui_C','blue');h.unit('BP_Monster_Yuu_C','blue')
    c:tick();assert(next(h.hooks)~=nil)
    assert(c:set(false).ok)
    assert(next(h.hooks)==nil and h.all():find('解除连携 铁鬼+玉妖（开关已关）',1,true),h.all())
    c:set(true);assert(c:status().links==2)
    h.now=1;c:tick();assert(next(h.hooks)~=nil,'re-enabled hooks return on the next due retry')
    h.fighting=false;c:tick()
    assert(next(h.hooks)==nil and h.all():find('解除连携 铁鬼+玉妖（战斗结束或单位离场）',1,true))
end)
print('boss_combos: all tests passed')
