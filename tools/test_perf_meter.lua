package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Meter=require('perf_meter')
local lines={}
local meter=Meter.new({label='自由视角每帧',log=function(s)lines[#lines+1]=s end,slow=8,hitch=50})
-- 60 frames a second for a minute: each costs 1 ms, one costs 12 ms, and the game takes 80 ms over one frame.
local t,frames=0,0
local function frame(cost,parts)meter:add(cost,t,parts);frames=frames+1 end
while t<60 do
    local cost=frames==100 and 12 or 1
    frame(cost,{guard=cost*0.25,track=cost*0.5})
    t=t+(frames==200 and 0.080 or 1/60)
end
assert(#lines==0,'nothing before the minute is up: '..table.concat(lines,'\n'))
frame(1,{guard=0.25,track=0.5})
assert(#lines==1,'one summary a minute')
local line=lines[1]
assert(line:find('[Perf] 自由视角每帧 近60秒：',1,true),line)
assert(line:find('最长12.0ms ≥8ms有1次',1,true),line)
assert(line:find('间隔≥50ms有1次 最长间隔80ms',1,true),line)
assert(line:find('平均间隔16.',1,true),line)
assert(line:find('；track 平均',1,true) and line:find('guard 平均',1,true)
    and line:find('track',1,true)<line:find('guard',1,true),'the costliest part first: '..line)
-- The camera put away for ten seconds: that is not a slow frame.
meter:pause()
t=t+10
for _=1,3700 do frame(1);t=t+1/60 end
assert(#lines==2 and lines[2]:find('间隔≥50ms有0次',1,true),lines[2])
-- At most six parts are listed, the costliest first.
local many=Meter.new({label='支持循环',log=function(s)lines[#lines+1]=s end,slow=10,hitch=1000,every=1})
local parts={}
for i=1,9 do parts['step'..i]=i end
many:add(45,0,parts);many:add(45,1,parts)
local last=lines[#lines]
assert(last:find('；step9 平均9.00/最长9.0 step8',1,true) and not last:find('step3',1,true),last)
-- Not numbers: ignored.
many:add(nil,2);many:add('x',2)
print('perf_meter: PASS (a summary each minute, slow passes, gaps, pause, costliest parts)')
