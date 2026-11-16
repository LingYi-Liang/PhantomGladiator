package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Policy=arg[1]and assert(loadfile(arg[1]))()or require('execution_policy')
local reads=0;local members={}
for i=1,1000 do
    local a={label='Actor '..i}
    function a:IsValid()return true end
    function a:GetAddress()return i end
    function a:GetFullName()reads=reads+1;return self.label end
    a['Actor Config']={IsValid=function()return true end,['Difficulty Tag']={TagName='CharacterType.Difficulty.Boss'}}
    members[i]={actor=a,team=i==1 and'red'or'blue',class_path='/Game/BP_Test.BP_Test_C'}
end
local p=Policy.new({configured=function()return true end,rule=function()return'on_50'end,random=function()return 0.25 end})
for _=1,200 do p:sync(members,true)end
print('MEASURE 1000 members x 200 syncs idle identity reads='..reads)
assert(reads==0,'custom probability without an execution opportunity must not read every actor name')
assert(p:allow(members[1].actor,members[2].actor,true)and p.draws==1)
members[2].actor.label='Replacement actor'
p:sync(members,true);assert(p:allow(members[1].actor,members[2].actor,true)and p.draws==2)
assert(reads<=6,'identity is verified at the opportunity and replacements cannot inherit a draw')
print('execution policy cost: PASS zero idle name reads; live identity checks still gate actual decisions')
