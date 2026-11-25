-- 虚空 summoned directly gets the pipa her native entrance would have given her.
package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Pipa=require('xukong_pipa')
local serial=0
local function object(name,fields)
    serial=serial+1;local id=serial
    local a=fields or {};a.valid=true
    function a:IsValid()return self.valid end
    function a:GetAddress()return id end
    function a:GetFullName()return name end
    return a
end
local FAN='PBZ_MainWeaponConfig_C /PBZCombatAsset/ActorData/Mobs/079_XuKong/WeaponData/Weapon_XuKong.Weapon_XuKong'
local PIPA='PBZ_MainWeaponConfig_C '..Pipa.weapon
local function fixture()
    local h={logs={},now=100,calls={},members={}}
    h.mod=Pipa.new({log=function(s)h.logs[#h.logs+1]=s end,clock=function()return h.now end,fname=function(s)return s end,
        members=function()return h.members end,mapOpponent=function()return h.enemy end,actionBusy=function()return h.actionBusy==true end})
    function h:xu(options)
        options=options or {}
        local actor=object(options.name or 'BP_Monster_XuKong_C /Game/Map.XuKong_'..(#h.members+1))
        local wc=object('Weapons',{index=options.index or 0,armed=options.armed==true,slots={[0]=object(FAN),[1]=object(options.second or PIPA)}})
        local function slot(tag)assert(tag.TagName=='Weapon.Slot.Main')end
        function wc:GetCurrentWeaponIndex(tag,pending)slot(tag);assert(pending==false);return self.index end
        function wc:GetSlotWeapon(tag,i,out)slot(tag);if h.noSlot then return end;out.WeaponConfig=self.slots[i] end
        function wc:SetCurrentWeapon(tag,i)
            slot(tag);h.calls[#h.calls+1]='current '..i
            if h.refuse then return false end
            if not h.ignored then self.index=i end
            return true
        end
        function wc:SetArmed(tag,v)
            slot(tag);h.calls[#h.calls+1]='armed '..tostring(v)
            if not h.refuseArmed then self.armed=v end
        end
        function wc:IsArmed(tag)slot(tag);return self.armed end
        actor['Character Weapons Component']=wc
        local asc=object('ASC',{tags={}})
        function asc:GetGameplayTagCount(tag)return self.tags[tag.TagName] or 0 end
        actor.AbilitySystemComponent=asc
        local m={actor=actor,class_path=options.class or Pipa.path,team=options.team or 'blue',summoner=options.summoner,
            aid=options.aid,stand=options.stand}
        h.members[#h.members+1]=m
        return actor,wc,asc,m
    end
    function h:run(seconds)local t=self.now+seconds;repeat self.mod:tick();self.now=self.now+.55 until self.now>t end
    function h:logged(text)local n=0;for _,l in ipairs(self.logs)do if l:find(text,1,true) then n=n+1 end end;return n end
    return h
end
local n=0;local function test(label,fn)fn();n=n+1;print('PASS '..label)end

test('a direct summon of any team gets the pipa once, armed, and it is read back',function()
    for _,team in ipairs({'blue','red','companion','neutral'})do
        local h=fixture();local _,wc=h:xu({team=team});h:run(20)
        assert(wc.index==1 and wc.armed==true and table.concat(h.calls,',')=='current 1,armed true',team)
        assert(h:logged('即将 换上琵琶')==1 and h:logged('序号 0→1 持握=true 已换上=true')==1 and h.mod.given==1)
    end
end)
test('native skill observation confirms the held weapon against a map enemy only for a companion',function()
    local h=fixture();local a=h:xu({team='companion'});h:run(1)
    h.mod:started(a,'GA_XuKong_Skill_01_C')
    assert(h:logged('随从打地图敌人')==0)
    h.enemy=object('BP_Monster_Native_C /Game/Map.Hostile')
    h.mod:started(a,'GA_XuKong_Skill_01_C')
    assert(h:logged('出招=GA_XuKong_Skill_01_C 武器序号=1 持琵琶读回=true')==1)
end)
test('the 虚空 of 梦华, helpers and other units are left to the game',function()
    for _,options in ipairs({{summoner=object('MengHua')},{aid=true},{stand=true},{class='/Game/Other.Other_C'}})do
        local h=fixture();local _,wc=h:xu(options);h:run(6);assert(#h.calls==0 and wc.index==0 and #h.logs==0)
    end
end)
test('a unit that has the pipa already, or no pipa, is not touched',function()
    local h=fixture();local _,wc=h:xu({index=1,armed=true});h:run(20);assert(#h.calls==0 and #h.logs==0 and wc.index==1)
    h=fixture();h:xu({second='PBZ_MainWeaponConfig_C /Game/Weapon_Other.Weapon_Other'});h:run(20)
    assert(#h.calls==0 and h:logged('一号武器不是琵琶')==1,'said once, then left')
end)
test('weapons that are not ready are tried again, with an end',function()
    local h=fixture();local actor,wc=h:xu();actor['Character Weapons Component']=nil;h:run(3);assert(#h.calls==0)
    actor['Character Weapons Component']=wc;h:run(2);assert(wc.index==1)
    h=fixture();local a=h:xu();a['Character Weapons Component']=nil;h:run(60)
    assert(h:logged('没有换上琵琶')==1 and h:logged('武器组件未就绪')==1)
    h=fixture();h.noSlot=true;h:xu();h:run(60);assert(#h.calls==0 and h:logged('备用武器未读回')==1)
    h=fixture();h.refuse=true;local _,w=h:xu();h:run(60)
    assert(w.index==0 and h.calls[1]=='current 1' and #h.calls==12 and h:logged('切换未接受')==1,'a refused switch is never armed')
    h=fixture();h.ignored=true;h:xu();h:run(60);assert(h:logged('切换未读回')==1)
end)
test('a switched slot is not counted until holding the pipa reads back',function()
    local h=fixture();local _,wc=h:xu()
    h.refuseArmed=true;h:run(2)
    assert(wc.index==1 and not wc.armed and h.mod.given==0)
    h.refuseArmed=false;h:run(3)
    assert(wc.armed and h.mod.given==1)
    local n=0;for _,action in ipairs(h.calls)do if action=='current 1' then n=n+1 end end
    assert(n==1,'only the missing hold should be retried')
end)
test('during a paired performance nothing is switched',function()
    for _,tag in ipairs({'Ability.Action.Execution','Ability.Executed','CharacterState.HitReact.State.Executing','CharacterState.Dead'})do
        local h=fixture();local _,wc,asc=h:xu();asc.tags[tag]=1;h:run(15);assert(#h.calls==0,tag)
        asc.tags[tag]=nil;h:run(3);assert(wc.index==1,tag)
    end
end)
test('defers the pipa while a regular action is starting or its montage remains',function()
    local h=fixture();local _,wc,asc=h:xu()
    asc.tags['Ability.Action']=1;h:run(15)
    assert(#h.calls==0 and wc.index==0,'do not switch during an ordinary ability')
    asc.tags['Ability.Action']=nil;h.actionBusy=true;h:run(15)
    assert(#h.calls==0,'do not switch out of a finishing montage')
    h.actionBusy=false;h:run(3)
    assert(wc.index==1 and wc.armed and h.mod.given==1)
end)
test('a move that takes the weapon away gets it back, a bounded number of times',function()
    local h=fixture();local _,wc,asc=h:xu();h:run(2);assert(wc.index==1)
    wc.index=2;asc.tags['Ability.Action.Execution']=1;h:run(5);assert(wc.index==2,'not while she performs')
    asc.tags['Ability.Action.Execution']=nil;h:run(4);assert(wc.index==1 and h.mod.given==2)
    for _=1,20 do wc.index=2;h:run(5)end
    assert(h.mod.given==6 and wc.index==2 and h:logged('不再检查')==1)
end)
test('a unit that left is forgotten, another one at its address is new, and unloading stops',function()
    local h=fixture();local actor,wc,_,m=h:xu();h:run(2);assert(h.mod.given==1)
    h.members={};h.mod:tick();h.members={m};wc.index=0;h.mod:tick();assert(wc.index==1 and h.mod.given==2,'a new visit is looked at at once')
    local name=actor.GetFullName;actor.GetFullName=function()return 'BP_Monster_XuKong_C /Game/Map.Another' end
    wc.index=0;h:run(1);assert(wc.index==1 and h.mod.given==3,'checked at once, not at the old unit\'s next look')
    actor.GetFullName=name;h.mod:silence();wc.index=0;h:run(6);assert(wc.index==0)
end)
test('two units are handled on their own clocks and an idle roster reads nothing',function()
    local h=fixture();local reads=0
    h.mod=Pipa.new({log=function()end,clock=function()reads=reads+1;return h.now end,fname=function(s)return s end,members=function()return h.members end})
    h:run(10);assert(reads==0)
    local _,a=h:xu();h:run(1);local _,b=h:xu();h:run(2);assert(a.index==1 and b.index==1)
end)
print(n..' tests passed')
