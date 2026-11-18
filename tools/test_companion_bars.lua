package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Bars=arg[1] and assert(loadfile(arg[1]))() or require('companion_bars')
local serial,calls=0,{}
local function note(name)calls[#calls+1]=name end
local function class(name)return {IsValid=function()return true end,GetFName=function()return {ToString=function()return name end}end}end
local function object(name,fields)
    serial=serial+1;local id=serial;local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function(self)assert(self.alive);return id end
    o.GetClass=function()return class(name)end
    return o
end
local function makeWidget()
    local w=object('WB_EnemyHPBar_C',{visibility=1,WantToShow=false,hpbar=object('PBZAnimProgressBar_C',{CurPercent=1})})
    function w:GetVisibility()return self.visibility end
    function w:SetVisibility(v)note('widget:SetVisibility '..v);self.visibility=v end
    function w:ForSeq_ShowEnemyHPBar()note('ForSeq_ShowEnemyHPBar');self.WantToShow=true;self.visibility=4 end
    function w:ForSeq_UpdateHealth(r)note('ForSeq_UpdateHealth '..r);self.hpbar.CurPercent=r end
    function w:CanDisplayHpBar(out)out.CanDisplay=false end
    function w:Init(actor)note('Init');self.SelfActor=actor end
    return w
end
local function makeActor(name,withComponent)
    local actor=object(name,{hp=100,max=100})
    if withComponent then
        local component=object('PBZLazyWidgetComponent',{bHiddenInGame=true,visible=false})
        function component:IsVisible()return self.visible end
        function component:SetVisibility(v)note('component:SetVisibility');self.visible=v end
        function component:SetHiddenInGame(h)note('component:SetHiddenInGame');self.bHiddenInGame=h end
        function component:GetUserWidgetObject()return self.widget end
        function component:EnsureWidgetCreated()note('EnsureWidgetCreated');self.widget=self.widget or makeWidget()end
        actor.hpbar=component
        function actor:EnsureInitHpBar()note('EnsureInitHpBar');component.widget=makeWidget();component.widget.SelfActor=self end
    end
    return actor
end
local logs={}
local function logged(text)return table.concat(logs,'\n'):find(text,1,true)~=nil end
local bars=Bars.new({log=function(m)logs[#logs+1]=m end,hp=function(a)return a.hp end,maxHP=function(a)return a.max end})

-- A companion's own bar is created by the NPC's own initialisation, bound to it, shown and set to its health.
local companion=makeActor('BP_Monster_A_C',true);companion.hp=80
local blue,summon=makeActor('BP_Monster_B_C',true),makeActor('BP_Monster_C_C',true)
local members={{actor=companion,team='companion',class_path='/Game/X/BP_Monster_A.BP_Monster_A_C'},
    {actor=blue,team='blue',class_path='/Game/X/BP_Monster_B.BP_Monster_B_C'},
    {actor=summon,team='companion',summoner=companion,class_path='/Game/X/BP_Monster_C.BP_Monster_C_C'}}
bars:sync(members)
local widget=companion.hpbar.widget
assert(widget and widget.SelfActor==companion,'the NPC creates and binds its own bar')
assert(companion.hpbar.visible==true and companion.hpbar.bHiddenInGame==false,'the component is shown')
assert(widget.visibility==4 and widget.WantToShow==true,'shown the way the game shows it')
assert(widget.hpbar.CurPercent==0.8,'the bar shows the companion\'s health')
assert(bars:status().companions==1 and bars:status().shown==1)
assert(blue.hpbar.widget==nil and summon.hpbar.widget==nil,'blue units and a companion\'s summons are left alone')
assert(logged('开始显示 unit=BP_Monster_A 之前：组件可见=false 组件隐藏=true 控件=未创建'),table.concat(logs,'\n'))
assert(logged('创建血条 unit=BP_Monster_A EnsureInitHpBar调用=true 读回控件=WB_EnemyHPBar_C'))
assert(logged('显示后 unit=BP_Monster_A：组件可见=true 组件隐藏=false 控件=WB_EnemyHPBar_C 可见性=4 WantToShow=true 绑定本单位=true 游戏判断可显示=false 血条比例=0.8'),table.concat(logs,'\n'))

-- Unchanged: nothing is written again.
calls={};bars:sync(members)
assert(#calls==0,'a shown bar at the same health is left alone: '..table.concat(calls,','))

-- The game hides it: shown again, counted and logged with the state it was in.
widget.visibility=1;bars:sync(members)
assert(widget.visibility==4 and bars:status().reshown==1)
assert(logged('血条被游戏收起，重新显示 第1次 unit=BP_Monster_A 当时：组件可见=true 组件隐藏=false 控件=WB_EnemyHPBar_C 可见性=1'))
-- If the game's own show does not make it visible, it is set visible directly.
widget.ForSeq_ShowEnemyHPBar=function()note('ForSeq_ShowEnemyHPBar')end
widget.visibility=1;bars:sync(members)
assert(widget.visibility==3 and bars:status().reshown==2)

-- Health follows; a fallen companion's bar is put away.
calls={};companion.hp=50;bars:sync(members)
assert(widget.hpbar.CurPercent==0.5 and calls[1]=='ForSeq_UpdateHealth 0.5',table.concat(calls,','))
companion.hp=0;bars:sync(members)
assert(widget.visibility==1 and bars:status().shown==0 and logged('随从倒下，收起血条 unit=BP_Monster_A'))

-- No init function: the component creates the widget, which is then bound to the unit.
local plain=makeActor('BP_Monster_D_C',true);plain.EnsureInitHpBar=nil
calls={};bars:sync({{actor=plain,team='companion',class_path='/Game/X/BP_Monster_D.BP_Monster_D_C'}})
assert(plain.hpbar.widget and plain.hpbar.widget.SelfActor==plain and calls[1]=='EnsureWidgetCreated' and calls[2]=='Init',table.concat(calls,','))
assert(logged('创建血条 unit=BP_Monster_D EnsureInitHpBar调用=false 读回控件=WB_EnemyHPBar_C') and logged('控件没绑定本单位，调用Init=true 读回绑定=true unit=BP_Monster_D'))
local count=0;for _ in pairs(bars.records)do count=count+1 end
assert(count==1,'companions no longer in the arena are forgotten')

-- A unit without the bar component is noted once; a gone unit is skipped.
local bare=makeActor('BP_Other_C',false)
local before=#logs
for _=1,3 do bars:sync({{actor=bare,team='companion',class_path='/Game/X/BP_Other.BP_Other_C'}})end
assert(#logs==before+1 and logged('没有头顶血条组件 unit=BP_Other 类=BP_Other_C'))
bare.alive=false;bars:sync({{actor=bare,team='companion'}})
assert(bars:status().companions==0)
do
    local a=makeActor('BP_Rebuilt_C',true);a.hp=50
    local probe=Bars.new({hp=function(v)return v.hp end,maxHP=function(v)return v.max end})
    local list={{actor=a,team='companion'}}
    probe:sync(list);assert(a.hpbar.widget.hpbar.CurPercent==0.5)
    local rebuilt=makeWidget();rebuilt.SelfActor=a;rebuilt.visibility=4;a.hpbar.widget=rebuilt
    probe:sync(list)
    print('replacement companion bar ratio='..rebuilt.hpbar.CurPercent)
    assert(rebuilt.hpbar.CurPercent==0.5,'a replacement widget cannot inherit the prior widget health write')
    rebuilt.hpbar.CurPercent=1;probe:sync(list)
    assert(rebuilt.hpbar.CurPercent==0.5,'native resets must be read back even while companion HP is unchanged')
    local original=rebuilt.ForSeq_UpdateHealth
    rebuilt.hpbar.CurPercent=1;rebuilt.ForSeq_UpdateHealth=function()end;probe:sync(list)
    assert(probe.records[tostring(a:GetAddress())].ratio==nil,'unconfirmed health writes are not cached as complete')
    assert(probe:status().failures==1,'one failed readback must not throw an internal diagnostic error')
    rebuilt.ForSeq_UpdateHealth=original;probe:sync(list);assert(rebuilt.hpbar.CurPercent==0.5)
    rebuilt.SelfActor=blue;rebuilt.Init=function()end
    calls={};probe:sync(list)
    assert(probe:status().shown==0 and #calls==0,'failed binding must not update a foreign actor widget')
    a.hp=0;probe:sync(list);assert(#calls==0,'death cleanup cannot hide a widget rebound to somebody else')
end
print('companion_bars: PASS (own bar created and bound, health readback, re-shown, rebuilt/native reset recovery, fallen hidden, fallback init, foreign binding gate)')
do
    local red=makeActor('ArenaHun',true)
    local roster={{actor=red,team='red',class_path='/Game/ArenaHun.ArenaHun_C'}}
    local arenaBars=Bars.new({hp=function()return 40 end,maxHP=function()return 80 end,arenaBar=function(unit)return unit.actor==red end})
    arenaBars:sync(roster)
    assert(red.hpbar.widget.SelfActor==red and red.hpbar.widget.hpbar.CurPercent==.5)
    assert(arenaBars:status().companions==0 and arenaBars:status().shown==0,'an arena bar must not inflate companion counts')
    print('PASS an opted-in arena body gets its native overhead HP without joining the companion roster')
end
