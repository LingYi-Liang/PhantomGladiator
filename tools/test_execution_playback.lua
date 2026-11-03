package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local P=require('execution_playback')
local id=0
local function object(name,t)
    id=id+1;local key=id;t=t or {};t.IsValid=function()return t.alive~=false end
    t.GetAddress=function()return key end;t.GetFName=function()return {ToString=function()return name end}end;return t
end
local t,current,pos=0,nil,0
local native=object('Anim',{GetCurrentActiveMontage=function()return current end,Montage_GetPosition=function(_,m)assert(m==current);return pos end})
local actor=object('NPC',{Mesh=object('Mesh',{GetAnimInstance=function()return native end})})
local ability=object('Ability',{GetCurrentMontage=function()return current end})
local left,right=object('Left_Montage'),object('Right_Montage')
local variants={Left_Montage={clip_from=0,clip_to=3,rate=1},Right_Montage={clip_from=5.36,clip_to=9.43,rate=1}}
local frames,selected,ended,cancelled={},{},{},{}
local wanted
local options={actor=actor,variants=variants,now=function()return t end,ability=function()return ability end,
    loop=function(ms,fn)assert(ms==16);frames[#frames+1]=fn;return #frames end,
    cancel=function(handle)cancelled[handle]=true end,
    onVariant=function(def,name,p)selected[#selected+1]=name;return true end,
    onPosition=function(p)wanted=p;return true end,
    onEnd=function(reason,failed)ended[#ended+1]={reason,failed}end}
local run=P.start(options)
assert(run.alive and not run.ready and #selected==0,'wait for actual native selection; never pick the first variant')
current=right;pos=0.25;t=0.1;frames[1]()
assert(run.ready and selected[1]=='Right_Montage' and math.abs(wanted-5.61)<0.001)
current=left;pos=1;t=0.2;frames[1]()
assert(selected[2]=='Left_Montage' and wanted==1,'native branch changes change the rendered clip')
current=nil;t=0.3;frames[1]();assert(run.alive)
t=0.7;frames[1]();assert(not run.alive and cancelled[1] and ended[1][2]==false)
local n=#ended;frames[1]();assert(#ended==n,'a cancelled callback stays silent')
t=1;local missing=P.start(options);t=3.1;frames[2]()
assert(not missing.alive and ended[#ended][2]==true,'missing native montage has a bounded failure')
assert(P.clipPosition(variants.Right_Montage,99)==9.43)
print('execution_playback ok: native choice, continuation, clip offset, natural end, timeout, cancellation')
