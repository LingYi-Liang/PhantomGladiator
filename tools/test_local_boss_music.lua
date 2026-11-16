package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Local=require('local_boss_music')
local function fixture()
    local h={now=0,wall=1000,active=true,id=9,story=0,clears=0,restores=0,scans=0,prepared='-',client=string.rep('a',32),session='session-1'}
    h.ctx={world='w',key='s',name='sub'};h.a={key='a',name='Boss A',hp=100};h.b={key='b',name='Boss B',hp=100}
    h.members={{actor=h.a,id='BOSS_A',team='blue'},{actor=h.b,id='BOSS_B',team='red'}}
    h.o={clock=function()return h.now end,wall=function()return h.wall end,session=function()return h.session end,
        read=function()if h.noLink then return nil end;return 'LocalMusicLinkV1\t'..h.wall..'\t'..(h.linkSession or h.session)..'\t'..h.client..'\t'..h.prepared..'\tBOSS_A,BOSS_B\n'end,
        active=function()return h.active end,context=function()return h.noCtx and nil or h.ctx end,
        snapshot=function()if h.unread then return nil end;return {id=h.id,eventName=h.event or 'ambient',story=h.story,blocked=h.blocked==true}end,
        native=function()h.clears=h.clears+1;if h.callback then h.callback()end;if not h.rejectClear then h.id=0 end;return true end,
        restore=function()h.restores=h.restores+1;if h.rejectRestore then return false end;h.id=9;return true end,
        hooks=function()return not h.noHooks end,members=function()h.scans=h.scans+1;return h.members end,
        unitId=function(m)return m.id end,eligible=function(m)return m.team=='blue'or m.team=='red'end,
        actorState=function(m)if m.actor.gone then return nil end;return {key=m.actor.key,name=m.actor.name,alive=m.actor.hp and m.actor.hp>0,actor=m.actor}end,
        state=function(s,t)h.state,h.message=s,t end,log=function(t)h.log=t end}
    h.c=Local.new(h.o)
    function h:tick()self.c:tick(true)end
    function h:advance()self.now=self.now+0.6;self.wall=self.wall+1 end
    function h:prepare()self:tick();self.prepared=self.c.token;self:advance();self:tick()end
    return h
end
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('disabled path performs no scans or native calls',function()local h=fixture();for _=1,2000 do assert(not h.c:tick(false))end;assert(h.scans==0 and h.clears==0)end)
test('playback requires preparation and native zero readback',function()local h=fixture();h:tick();assert(h.c.token~=''and h.clears==0 and not h.c.ready);h:prepare();assert(h.c.ready and h.clears==1 and h.c:owns()and not h.c:status().local_pending)end)
test('stop restores owned music and drops playback permission',function()local h=fixture();h:prepare();assert(h.c:stop());assert(not h.c.ready and not h.c:owns()and h.restores==1)end)
test('death selects another source with a new preparation token',function()local h=fixture();h:prepare();local old=h.c.token;h.a.hp=0;h:advance();h:tick();assert(h.c.unit=='BOSS_B'and h.c.token~=old and not h.c.ready and h.restores==1)end)
test('unknown source HP never grants playback',function()local h=fixture();h.a.hp=nil;h.b.hp=nil;h:prepare();assert(h.clears==0 and not h.c.ready)end)
test('stale or missing helper link releases ownership',function()local h=fixture();h:prepare();h.noLink=true;h:advance();h:tick();assert(not h.c.ready and h.restores==1)end)
test('wrong game session never acquires native music',function()local h=fixture();h.linkSession='stale';h:prepare();assert(h.clears==0)end)
test('replacement world does not clear new world music',function()local h=fixture();h:prepare();h.ctx={world='new',key='new',name='new'};h.id=42;h:advance();h:tick();assert(h.id==42 and not h.c.ready and h.clears==1)end)
test('story and external music win ownership',function()local h=fixture();h.story=10;h:prepare();assert(h.clears==0);h=fixture();h:prepare();h.id=77;h.event='other';h:tick();assert(h.id==77 and not h.c.ready and h.restores==0)end)
test('failed native clears stop retrying this battle',function()local h=fixture();h.rejectClear=true;h:prepare();for _=1,30 do h:advance();h:tick()end;assert(h.clears==3 and not h.c.ready and h.c.failed)end)
test('failed restoration retains responsibility',function()local h=fixture();h:prepare();h.rejectRestore=true;assert(not h.c:stop()and h.c:owns());h.rejectRestore=false;h:advance();h:advance();assert(h.c:stop()and not h.c:owns())end)
test('stop before late native clear rolls back',function()local h=fixture();h.callback=function()h.active=false;assert(not h.c:stop())end;h:prepare();assert(not h.c.ready and not h.c:owns()and h.id==9)end)
test('death during native clear cannot publish permission',function()local h=fixture();h.callback=function()h.a.hp=0 end;h:prepare();assert(not h.c.ready and h.id==9)end)
test('unread native clear keeps a pending restoration',function()local h=fixture();h.callback=function()h.unread=true end;h:prepare();assert(not h.c.ready and h.c:owns());h.unread=false;h:advance();h.active=false;h:tick();assert(not h.c:owns()and h.id==9)end)
test('unprepared or failed hooks keep original music',function()local h=fixture();h.noHooks=true;h:prepare();assert(h.clears==0 and h.id==9)end)
test('two thousand repeated stable reads never restart a track',function()local h=fixture();h:prepare();for _=1,2000 do h:tick()end;assert(h.c.ready and h.clears==1 and h.restores==0)end)
test('one thousand battle/death/stop cycles leave no owned mute',function()
    for i=1,1000 do
        local h=fixture();if i%3==0 then h.callback=function()h.active=false;h.c:stop()end end
        h:prepare();if i%3==1 then h.a.hp=0;h.b.hp=0 end
        h.active=false;h:advance();h:tick()
        assert(not h.c:owns()and not h.c.ready and h.id==9)
    end
    print('READ 1000 local audio ownership transitions: retained mute=0, late permission=0')
end)
print('local boss music: PASS '..n..' handshake, cancellation and ownership checks; no game accessed')
