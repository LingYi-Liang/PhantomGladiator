package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local HUD=require('arena_hud')
local function object(id)
    return {alive=true,IsValid=function(self)return self.alive end,GetAddress=function(self)assert(self.alive);return id end}
end
local blue,red=object(1),object(2);blue.hp=100;red.hp=80
local created,removed,updates=0,0,{}
local renderer={}
function renderer:create(unit)
    created=created+1;return {widget=object(100+created),actor=unit.actor}
end
function renderer:update(record,unit,hp,maximum,title,row)
    if record.actor~=unit.actor then return false,'fixture rebind' end
    updates[#updates+1]={hp=hp,maximum=maximum,title=title,row=row}
    return {visible=true,health=true,names=true,numbers=true}
end
function renderer:remove(record)removed=removed+1;record.widget.alive=false;return true end
function renderer:syncNative(desired,privateKeys)self.desired=desired;self.privateKeys=privateKeys end
local hud=HUD.new({renderer=renderer,isBoss=function()return true end,hp=function(a)return a.hp end,
    maxHP=function()return 100 end,getName=function(unit)return unit.team=='blue' and '甲' or '乙' end})
local members={{actor=blue,team='blue',class_path='blue'},{actor=red,team='red',class_path='red'}}
hud:sync(members)
assert(created==2 and hud:status().visible==2 and hud:status().numbers_verified==2)
assert(updates[1].title=='蓝队 · 甲' and updates[2].title=='红队 · 乙')
hud:sync(members);assert(created==2,'unchanged bars must be retained')
blue.hp=23.5;hud:sync(members);assert(updates[#updates-1].hp==23.5)
hud.records['1'].actor=red
hud:sync(members);assert(hud:status().pending==1 and removed==1,'foreign binding must retire the private record')
hud:sync(members);assert(created==3 and hud:status().visible==2,'a lost binding must rebuild without hijacking the foreign actor')
blue.hp=0;hud:sync(members);assert(hud:status().visible==1 and hud.records['1']==nil,'dead units hide immediately')
hud:clear(true);assert(hud:status().visible==0 and next(hud.records)==nil and next(renderer.desired)==nil)
local calls=0
local failed=HUD.new({isBoss=function()return true end,hp=function()return 10 end,maxHP=function()return 10 end,
    renderer={create=function()calls=calls+1;return nil,'fixture failure' end,remove=function()return true end,syncNative=function()end}})
for _=1,20 do failed:sync(members)end
assert(calls==6,'failed construction must be bounded per actor')
failed:clear();failed:sync(members);assert(calls==8,'manual cleanup resets failed registration attempts')

-- Bosses and their names come from codex.tsv: up to v0.37.4 it ends at source, v0.37.5 adds name and name_lang.
local codexPath='D:/unit-test/Runtime/codex.tsv'
local realOpen,codexText,reads=io.open,nil,0
io.open=function(path,mode)
    assert(path==codexPath and mode=='rb');reads=reads+1
    return {read=function()return codexText end,close=function()end}
end
blue.hp,red.hp=100,80
local titles={}
local bars=HUD.new({codexPath=codexPath,hp=function(a)return a.hp end,maxHP=function()return 100 end,renderer={
    create=function(_,unit)return {widget=object(300),actor=unit.actor} end,
    update=function(_,_,_,_,_,title)titles[#titles+1]=title;return {visible=true,health=true,names=true,numbers=true} end,
    remove=function()return true end,syncNative=function()end}})
local fight={{actor=blue,team='blue',class_path='/Game/Boss.Boss_C'},{actor=red,team='red',class_path='/Game/Mob.Mob_C'}}
codexText='class_path\tzh_name\tis_boss\tenemy_type\tsource\r\n/Game/Boss.Boss_C\t舞狮尊主\t1\t5\tnative\r\n/Game/Mob.Mob_C\t暴徒\t0\t1\tnative\r\n'
bars:sync(fight);assert(#titles==1 and titles[1]=='蓝队 · 舞狮尊主',table.concat(titles,','))
codexText='class_path\tzh_name\tis_boss\tenemy_type\tsource\tname\tname_lang\r\n/Game/Boss.Boss_C\t舞狮尊主\t1\t5\tnative\tLion Dancer\ten\r\n/Game/Mob.Mob_C\t暴徒\t0\t1\tnative\tThug\ten\r\n'
bars:sync(fight);assert(titles[2]=='蓝队 · 舞狮尊主' and reads==1,'the loaded list is kept until the export says the file changed')
bars:reloadCodex();bars:sync(fight)
assert(reads==2 and titles[3]=='Blue · Lion Dancer',tostring(titles[3]))
codexText=codexText:gsub('\ten\r\n','\tko\r\n')
bars:reloadCodex();bars:sync(fight);assert(titles[4]=='Blue · Lion Dancer','languages without team names fall back to English')
codexText='class_path\tzh_name\tis_boss\tenemy_type\tsource\tname\tname_lang\r\n/Game/Boss.Boss_C\t舞狮尊主\t1\t5\tnative\t被面具控制的舞狮尊主：烈焰\tzh-Hans\r\n'
bars:reloadCodex();bars:sync(fight);assert(titles[5]=='蓝队 · 被面具控制的舞狮尊主：烈焰',tostring(titles[5]))
codexText='class_path\tzh_name\tis_boss\tenemy_type\tsource\tname\tname_lang\r\n/Game/Boss.Boss_C\t舞狮尊主\t1\t5\tnative\t\t\r\n'
bars:reloadCodex();bars:sync(fight);assert(titles[6]=='蓝队 · 舞狮尊主','an empty name falls back to the Chinese one')
io.open=realOpen
print('arena_hud: PASS (independent ownership, rebind recovery, real HP/max, dead hide, bounded creation, cleanup, both codex formats, names and team labels in the game language)')
