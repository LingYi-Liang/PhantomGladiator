local input=assert(io.open(arg[1]or'Mods/PhantomGladiator/Scripts/main.lua','rb'));local source=input:read('*a');input:close()
local now,calls=10,0
local env={os={clock=function()return now end},LiveSeconds=function()return 0 end,log=function()end,
    Config={RuntimePath='fixture'},runtimeSession={status=function()return {game_ready=true,game_session='session'}end},
    arenaSupport={worldSubsystem=function()return nil end},step=function(_,fn)fn()end}
env.require=function(key)assert(key=='battle_music');return {new=function(options)return options end}end
local construct=assert(source:match("arenaSupport%.battleMusic=require%('battle_music'%)%.new%(%b{}%)"))
assert(load(construct,'music factory wiring','t',env))()
local clock=env.arenaSupport.battleMusic.clock
assert(clock()==10,'music heartbeat clock must advance while movement timers are frozen')
local step=assert(source:match("step%('battleMusic',function%(%).-\n    end%)"))
local tick=assert(load('return function(self)'..step..' end','music support wiring','t',env))()
local support={battleMusic={tick=function()calls=calls+1 end}}
for i=0,10 do now=10+i*.1;tick(support)end
assert(calls>=3 and calls<=5,'music support must poll in real time during movement freeze')
print('music real-time wiring: PASS movement freeze keeps heartbeat/cleanup polling; calls='..calls)
