package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local O=require('execution_opportunities')
local id=0
local function object(name,t)
    id=id+1;local key=id;t=t or {};t.IsValid=function()return t.alive~=false end
    t.GetAddress=function()return key end;t.GetFName=function()return {ToString=function()return name end}end;return t
end
local a,b,player=object('Boss'),object('Victim'),object('Player')
local ex,ed=object('GA_Counter_C'),object('GA_CounterEd_C')
local componentA=object('Execution',{GetOwner=function()return a end})
local componentB=object('Execution',{GetOwner=function()return b end})
local hooks,queue,cancelled,adopted={},{},{},{}
local internal=false
local guard=O.new({members=function()return {{actor=a,team='blue'},{actor=b,team='red'}}end,getPlayer=function()return player end,
    fighting=function()return true end,available=function()return true end,internal=function()return internal end,
    data=function(name)return name=='GA_Counter_C' end,adopt=function(event)adopted[#adopted+1]=event end,
    staticFind=function(path)return object(path)end,
    registerHook=function(path,pre,post)hooks[path]=post or pre;return 11,12 end,
    unregisterHook=function(path,pre,post)assert(pre==11 and post==12);hooks[path]=nil end,
    defer=function(fn)queue[#queue+1]=fn;return #queue end,cancel=function(h)cancelled[h]=true end})
guard:tick()
local data={ExecutionAbility=ex,ExecutedAbility=ed}
internal=true;hooks[O.executionPath](componentA,data,b,0);assert(#queue==0)
internal=false;hooks[O.executionPath](componentA,data,player,0);assert(#queue==0,'do not adopt real-player executions')
hooks[O.executionPath](componentA,data,b,0);queue[1]()
assert(#adopted==1 and adopted[1].executor==a and adopted[1].target==b)
local extension=object('Extension',{bFinished=false,Deactivate=function(self)self.bFinished=true end})
local task=object('QTE',{ExtensionObj=extension,EndTask=function(self)self.ended=true end})
local ability=object('GrabAbility',{['Execution Info']={Executor=a,Target=b}})
local action=object('MultiClick',{['Async Task']=task,Triggered=false,['Success Event']={TagName='GameplayEvent.QTE.LionDancer.Succeed'},GetAbility=function()return ability end})
local success=0
action.OnSuccess_07EF313E4694428175E13880AB103147=function(self)
    success=success+1;self.Triggered=true
    hooks[O.executionPath](componentB,data,a,0)
end
hooks[O.qtePath](action);queue[2]()
assert(success==1 and task.ended and extension.bFinished,'use the original success branch, then clean only its task')
queue[3]();assert(#adopted==2 and adopted[2].executor==b and adopted[2].target==a,'the victim becomes the executor through the native transition')
hooks[O.qtePath](action);assert(#queue==3,'completed QTE must not repeat')
action.Triggered=false;action['Success Event']={TagName='Unrelated.QTE'}
hooks[O.qtePath](action);assert(#queue==3,'do not auto-complete unrelated QTEs')
hooks[O.executionPath](componentA,data,b,0)
local old=hooks[O.executionPath]
guard:stop('test');queue[4]();old(componentA,data,b,0)
assert(#adopted==2 and cancelled[4] and #queue==4,'stop cancels pending work and silences retained callbacks')
print('execution_opportunities ok: ownership, internal-call exclusion, audited counter, native adoption, cleanup, stop')
