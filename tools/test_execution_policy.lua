package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Policy=require('execution_policy')
local function actor(key,rank)
    local a={key=key,label='Actor '..key,rank=rank}
    function a:IsValid()return not self.dead end
    function a:GetAddress()return self.key end
    function a:GetFullName()return self.label end
    a['Actor Config']={IsValid=function()return true end,['Difficulty Tag']={TagName='CharacterType.Difficulty.'..rank}}
    return a
end
local function fixture(setting)
    local h={setting=setting or'on_50',rolls=0,members={},configured=true}
    h.boss=actor('boss','Boss');h.members[1]={actor=h.boss,team='red',class_path='/Game/BP_Boss.BP_Boss_C'}
    for i=1,50 do h.members[#h.members+1]={actor=actor('mob'..i,'Mob'),team='blue',class_path='/Game/BP_Mob.BP_Mob_C'}end
    h.p=Policy.new({configured=function()return h.configured end,rule=function()return h.setting end,
        random=function()h.rolls=h.rolls+1;return(h.rolls*37%100)/100 end})
    h.p:sync(h.members,true);return h
end
local passed=0;local function test(n,fn)fn();passed=passed+1;print('PASS '..n)end
test('default 100 and disabled feature need no random draws',function()local h=fixture('on_100');for _=1,1000 do assert(h.p:allow(h.boss,h.members[2].actor,true))end;assert(h.rolls==0);h.configured=false;h.p:sync({},true);assert(h.p:allow(nil,nil,true)and h.rolls==0)end)
test('half chance is fixed for each target and not repeated each tick',function()local h=fixture();local allowed=0;for i=2,51 do if h.p:allow(h.boss,h.members[i].actor,true)then allowed=allowed+1 end end
    for _=1,100 do for i=2,51 do h.p:allow(h.boss,h.members[i].actor,true)end end
    assert(h.rolls==50 and allowed>=20 and allowed<=30);print('READ 50 targets, allowed='..allowed..', draws after 5050 requests='..h.rolls)end)
test('off and zero skip automatic finishers without rolling',function()for _,setting in ipairs({'off_50','on_0'})do local h=fixture(setting);assert(not h.p:allow(h.boss,h.members[2].actor,true)and h.rolls==0)end end)
test('boss targets and normal NPC executors keep their existing path',function()local h=fixture('off_0');assert(h.p:allow(h.boss,h.members[2].actor,false));h.boss['Actor Config']['Difficulty Tag'].TagName='CharacterType.Difficulty.Mob';assert(h.p:allow(h.boss,h.members[2].actor,true))end)
test('same address replacement never inherits a prior draw',function()local h=fixture();local a=h.members[2].actor;h.p:allow(h.boss,a,true);a.label='New actor';h.p:sync(h.members,true);h.p:allow(h.boss,a,true);assert(h.rolls==2)end)
test('stop and roster departure discard prior decisions',function()local h=fixture();h.p:allow(h.boss,h.members[2].actor,true);h.p:sync({},false);h.p:sync(h.members,true);h.p:allow(h.boss,h.members[2].actor,true);assert(h.rolls==2)end)
test('configuration change is atomic and invalid randomness skips',function()local h=fixture();h.p:allow(h.boss,h.members[2].actor,true);h.setting='off_50';assert(not h.p:allow(h.boss,h.members[2].actor,true));h.setting='on_25';h.p:allow(h.boss,h.members[2].actor,true);assert(h.rolls==2)
    h=fixture();h.p=Policy.new({configured=function()return true end,rule=function()return'on_50'end,random=function()return 0/0 end});h.p:sync(h.members,true);assert(not h.p:allow(h.boss,h.members[2].actor,true))end)
test('friendly, missing and reserves never gain a custom finisher',function()local h=fixture();h.members[2].team='red';h.p:sync(h.members,true);assert(not h.p:allow(h.boss,h.members[2].actor,true));h.members[2].team='blue';h.members[2].reserve=true;h.p:sync(h.members,true);assert(not h.p:allow(h.boss,h.members[2].actor,true))end)
print('execution policy: PASS '..passed..' fixed-probability/scope/lifecycle checks; no game accessed')
