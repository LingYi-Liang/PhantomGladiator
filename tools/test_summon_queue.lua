-- Isolated timing and cancellation tests for the actual queue, with a controlled clock.
local Queue=dofile('Mods/PhantomGladiator/Scripts/summon_queue.lua')
local time=0
local status={game_session='world-A',game_ready=true}
local failure=false
local calls={}
local queue=Queue.new({now=function()return time end,session=function()return status end,
    spawn=function(path,team,count)
        calls[#calls+1]={path=path,team=team,count=count,start=time}
        time=time+0.125
        if failure then return {ok=false,uncertain=true,message='fixture unknown result'} end
        return {ok=true,message='fixture confirmed'}
    end})
queue:sync(status)
assert(not queue:enqueue('/A','blue',1).ok)
queue.enabled=true
queue:cancel('开始测试')
for i=1,100 do assert(queue:enqueue('/Unit'..i,'blue',i).ok) end
assert(not queue:enqueue('/Overflow','blue',1).ok)
for i=1,100 do
    if i>1 then
        time=queue.nextAt-0.01
        queue:tick()
        assert(#calls==i-1)
        time=queue.nextAt
    end
    queue:tick()
    assert(calls[i].path=='/Unit'..i and calls[i].count==i)
    if i>1 then assert(calls[i].start-calls[i-1].start==0.375) end
end
assert(queue.completed==100 and #queue.jobs==0)
print('summon_queue: 100 retained, FIFO, 125 ms mock spawn plus 250 ms gap')

assert(queue:enqueue('/BeforeMap','red',1).ok)
status={game_session='world-A',game_ready=false}
queue:sync(status)
assert(#queue.jobs==0 and not queue:enqueue('/Loading','red',1).ok)
status={game_session='world-B',game_ready=true}
queue:sync(status)
local epoch=queue:epoch()
assert(queue:enqueue('/Uncertain','red',1).ok and queue:enqueue('/MustNotRun','red',1).ok)
time=queue.nextAt
failure=true
queue:tick()
assert(#calls==101 and #queue.jobs==0 and queue:epoch()~=epoch)
assert(not queue:enqueue('/StaleTransport','red',1,epoch).ok)
time=time+100
queue:tick()
assert(#calls==101 and queue.completed==100)
print('summon_queue: readiness loss cancels waiting; uncertain results cancel remainder and are never retried')
