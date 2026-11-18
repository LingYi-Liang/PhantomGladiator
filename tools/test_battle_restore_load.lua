package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Session=require('battle_session')
local logs,calls={},{}
local session=Session.new(function(line)logs[#logs+1]=line end)
local count,allow=2346,false
for i=1,count do
    session:remember('relation:'..i,function()
        calls[#calls+1]=i
        return allow or i%50~=0,'verified peer'
    end)
end
local ok,done,failed=session:restore()
assert(not ok and failed==46 and done==2300 and #calls==count)
assert(calls[1]==count and calls[count]==1 and session:pendingCount()==failed)
assert(#logs<=12,'bulk restore wrote '..#logs..' synchronous log lines')
allow=true
assert(session:restore() and session:pendingCount()==0 and #calls==count+failed)
assert(calls[count+1]==2300 and calls[#calls]==50,'failed snapshots must retain their reverse restoration order')
print('PASS large restore keeps every readback, retry and reverse ordering')
