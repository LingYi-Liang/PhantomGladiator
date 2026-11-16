local f=assert(io.open(arg[1]or'Mods/PhantomGladiator/Scripts/main.lua','rb'));local source=f:read('*a');f:close()
local code=assert(source:match('local function supportSteps%(self%).-\nend\nfunction arenaSupport:tick')):gsub('\nfunction arenaSupport:tick$','')
local noop=function()end
local proxy=setmetatable({},{__index=function()return noop end,__call=noop})
local formats,logs=0,{}
local now,increment=0,0.000001
local strings=setmetatable({format=function(...)formats=formats+1;return string.format(...)end},{__index=string})
local env=setmetatable({os={clock=function()now=now+increment;return now end},string=strings,table=table,pairs=pairs,ipairs=ipairs,
    tickMembers={},tickStatus={state='idle'},SLOW_TICK_MS=10,slowTicks=0,
    log=function(s)logs[#logs+1]=s end,supportMeter={add=function(_,total,started,costs)assert(type(costs.reinforce)=='number')end}},
    {__index=function(_,key)return proxy end})
local tick=assert(load(code..'\nreturn supportSteps','support profiling path','t',env))()
local support=setmetatable({musicNext=1e20},{__index=function()return proxy end})
for _=1,200 do tick(support)end
print('MEASURE 200 fast support loops formatted timing strings='..formats)
assert(formats==0 and #logs==0,'fast ticks should keep numeric measurements without formatting unused log text')
increment=.01;tick(support)
assert(#logs==1 and logs[1]:find('reinforce=',1,true)and logs[1]:find('支持循环耗时',1,true),'slow diagnostics must still contain per-step timings')
env.slowTicks=60;formats=0;tick(support);assert(formats==0,'exhausted diagnostics budget should not format discarded logs')
print('support measurement: PASS fast-path zero formatting, numeric meter retained and slow detail preserved')
