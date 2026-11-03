package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local HUD=require('arena_boss_hud')
local function obj(id,extra)
    local v=extra or {};v.alive=true
    function v:IsValid()return self.alive end
    function v:GetAddress()assert(self.alive);return id end
    function v:GetFullName()assert(self.alive);return 'Actor '..id end
    return v
end
local actor=obj(1,{hp=100});local other=obj(2,{hp=50});local widgets={};local registered,removed,initialized=0,0,0
local hud=obj(3)
function hud:GetBossHPBarInstances()return widgets end
local function widget(a,id)
    local w=obj(id,{Character=a,hpbar=obj(id+100,{CurPercent=0}),BossName=obj(id+200,{value=''})})
    function w:IsVisible()return true end
    function w:Init(value)assert(self.Character==value);initialized=initialized+1 end
    function w:ForSeq_UpdateHealth(value)self.hpbar.CurPercent=value end
    function w:ForSeq_SetNameText(value)self.BossName.value=value end
    function w.BossName:GetText()return self.value end
    return w
end
function hud:RegisterBossHPBar(a)
    assert(a.alive);registered=registered+1
    local w=widget(nil,10+registered);widgets[#widgets+1]=w
    return {type=function()return 'UScriptStruct' end,widget=w}
end
function hud:GetBossHPBarInstanceByHandle(handle)return handle.widget end
function hud:UnRegisterBossHPBar(a)
    assert(a.alive);removed=removed+1
    local keep={};for _,w in ipairs(widgets) do if w.Character~=a then keep[#keep+1]=w end end;widgets=keep
end
local ui=HUD.new({getHUD=function()return hud end,isBoss=function()return true end,hp=function(a)return a.hp end,
    maxHP=function()return 100 end,makeText=function(s)return s end,getName=function()return '测试BOSS' end})
local members={{actor=actor,team='blue',class_path='test'}}
ui:sync(members);assert(registered==1 and ui:status().registered==0,'request is not a verified widget')
ui:sync(members);assert(ui:status().registered==1 and ui:status().visible==1)
assert(initialized==1 and ui:status().health_verified==1 and ui:status().names_verified==1,'empty native widget must bind actor, real HP and name')
actor.hp=50;ui:sync(members);assert(widgets[1].hpbar.CurPercent==0.5,'the bar must reflect a real health change')
widgets[1].BossName.value='被原生界面覆盖的名字'
ui:sync(members)
assert(widgets[1].BossName.value=='蓝队 · 测试BOSS' and ui:status().names_verified==1,
    'cached success cannot hide a later native title overwrite')
members[1].team='red';ui:sync(members)
assert(widgets[1].BossName.value=='红队 · 测试BOSS','team/name changes must reset successful write retries')
for i=1,5 do widgets[1].BossName.value='原生重写'..i;ui:sync(members) end
assert(widgets[1].BossName.value=='红队 · 测试BOSS','successful corrections must not exhaust the failure retry budget')
ui:sync(members);assert(registered==1,'verified bars must not be re-created every tick')
widgets[#widgets+1]=widget(other,30)
ui:sync({members[1],{actor=other,team='red'}});ui:clear()
assert(removed==1 and #widgets==1 and widgets[1].Character==other,'native preexisting bars must be left alone')
local missing=obj(50);function missing:GetBossHPBarInstances()return {} end
local attempts=0;function missing:RegisterBossHPBar()attempts=attempts+1 end
local ui2=HUD.new({getHUD=function()return missing end,isBoss=function()return true end,hp=function(a)return a.hp end})
for _=1,20 do ui2:sync(members) end
assert(attempts==1 and ui2:status().pending==1,'an unresolved registration must not create duplicate empty widgets')
local list,registrations={},0
local fallbackHUD=obj(70,{BossPoint=obj(71)})
function fallbackHUD:GetBossHPBarInstances()return {} end
function fallbackHUD.BossPoint:GetAllEntries()return list end
function fallbackHUD:RegisterBossHPBar()
    registrations=registrations+1;list[#list+1]=widget(nil,80+registrations);return {}
end
function fallbackHUD:UnRegisterBossHPBar(a)
    local keep={};for _,w in ipairs(list)do if w.Character~=a then keep[#keep+1]=w end end;list=keep
end
function fallbackHUD.BossPoint:UnregsiterHandleByWidget(target)
    local keep={};for _,w in ipairs(list)do if w~=target then keep[#keep+1]=w end end;list=keep
end
local ui3=HUD.new({getHUD=function()return fallbackHUD end,isBoss=function()return true end,hp=function(a)return a.hp end,
    maxHP=function()return 100 end,makeText=function(s)return s end,getName=function()return '测试BOSS' end})
local pair={members[1],{actor=other,team='red'}}
for _=1,5 do ui3:sync(pair) end
assert(registrations==2 and ui3:status().registered==2,'opaque native handles must use a unique new BossPoint entry without duplicates or guessed ordering')
ui3:clear();assert(#list==0)
list[1]=widget(nil,99);ui3:clear(true);assert(#list==0,'manual cleanup removes unbound old empty bars through the native extension point')
print('arena_boss_hud: PASS (native handle binding, Init, real HP and name readback, deduplication, preserve preexisting bars)')
