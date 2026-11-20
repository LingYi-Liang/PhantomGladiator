package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Music=require('battle_music')
local Catalog=require('battle_music_catalog')
local function object(key,name,outer,class)
    local value={live=true,key=key,name=name,outer=outer}
    function value:IsValid()return self.live end
    function value:GetAddress()assert(self.live);return self.key end
    function value:GetFullName()assert(self.live);return self.name end
    function value:GetOuter()assert(self.live);return self.outer end
    if class then
        local cls=object(key+10000,'Class '..class)
        function cls:GetFName()return {ToString=function()return class end}end
        function value:GetClass()assert(self.live);return cls end
    end
    return value
end
local function fixture()
    local h={files={},now=0,active=true,ready=true,thread=true,calls={},hooks={},logs={},lookups=0,seq=0}
    h.world=object(1,'World Test')
    h.sub=object(2,'MusicSubsystem Test.MusicSubsystem_0',h.world)
    h.ambient=object(3,'AkAudioEvent ambient',nil,'AkAudioEvent')
    h.sub.CurPlayingID_Gameplay=10;h.sub.CurPlayingEvent_Gameplay=h.ambient
    h.sub.CurPlayingID_Story=0;h.sub.bDontInitMusic=false;h.sub.bDisableBossMusicOnUI=false
    h.actor=object(4,'BP_Monster_MoTian_C Test.MoTian_1',h.world);h.actor.hp=100
    h.members={{actor=h.actor,team='blue',class_path='/Game/BP_Monster_MoTian.BP_Monster_MoTian_C'}}
    h.assets={}
    for _,track in pairs(Catalog.tracks)do
        for _,field in ipairs({'event','state'})do
            local path=track[field];local class=field=='event' and 'AkAudioEvent' or 'AkStateValue'
            h.seq=h.seq+1;h.assets[path]=h.assets[path] or object(100+h.seq,class..' '..path,nil,class)
        end
    end
    local function recorded(name,...)
        assert(h.thread,'native music call outside game thread')
        h.calls[#h.calls+1]={name=name,args={...}}
    end
    function h.sub:PlayMusicAndSetState(event,state,kind,force)
        recorded('play',event,state,kind,force);assert(kind==1 and force==true)
        if h.noPost then return end
        self.CurPlayingID_Gameplay=self.CurPlayingID_Gameplay+100;self.CurPlayingEvent_Gameplay=event
        if h.hooks[Music.paths[1]]then h.hooks[Music.paths[1]]({type=function()return 'RemoteUnrealParam'end,get=function()return h.sub end})end
    end
    function h.sub:ClearMusic(fade,gameplay,story)
        recorded('clear',fade,gameplay,story);assert(gameplay==true and story==false)
        if not h.delayStop then self.CurPlayingID_Gameplay=0;self.CurPlayingEvent_Gameplay=nil end
    end
    function h.sub:UpdateGameplayMusic(ended)
        recorded('restore',ended);assert(ended==false)
        if h.failRestore then error('simulated restore failure')end
        self.CurPlayingID_Gameplay=10;self.CurPlayingEvent_Gameplay=h.ambient
    end
    local fs={open=function(path,mode)
        if mode=='rb' then if h.files[path]==nil then return nil end;return {read=function()return h.files[path]end,close=function()return true end}end
        if h.failWrite then return nil end
        local text='';return {write=function(_,value)text=value;return true end,flush=function()return true end,close=function()h.files[path]=text;return true end}
    end}
    local ops={remove=function(path)h.files[path]=nil;return true end,rename=function(from,to)
        if h.failRename or not h.files[from] or h.files[to]then return nil end
        h.files[to]=h.files[from];h.files[from]=nil;return true
    end}
    h.options={path='memory',io=fs,os=ops,clock=function()return h.now end,world=function()return h.world end,
        subsystem=function()h.lookups=h.lookups+1;return h.sub end,ready=function()return h.ready end,inGameThread=function()return h.thread end,
        members=function()return h.members end,status=function()return {battle_active=h.active}end,hp=function(actor)assert(actor.live);return actor.hp end,
        find=function(path)if h.assets[path]then return h.assets[path]end;if h.missingHooks then return nil end;return object(1000,'Function '..path)end,
        load=function(path)return h.assets[path]end,
        register=function(path,fn)h.hooks[path]=fn;return 1,2 end,unregister=function(path)if h.rejectUnhook then return false end;h.hooks[path]=nil;return true end,
        log=function(line)h.logs[#h.logs+1]=line end}
    h.music=Music.new(h.options)
    function h:count(name)local n=0;for _,v in ipairs(self.calls)do if v.name==name then n=n+1 end end;return n end
    return h
end
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
test('native default does no actor scans, asset loads or native music calls',function()
    local h=fixture();for _=1,100 do h.music:tick()end
    assert(h.music:stop().ok)
    assert(h.lookups==0 and #h.calls==0 and next(h.hooks)==nil)
end)
test('auto starts one confirmed track and does not restart it every tick',function()
    local h=fixture();assert(h.music:set('AUTO','MOYUAN_P1').ok)
    assert(h:count('play')==1 and h.music:status().state=='playing' and not h.music:status().pending)
    for _=1,20 do h.music:tick()end
    assert(h:count('play')==1 and h.music.lease.track=='MOYUAN_P1')
    assert(table.concat(h.logs,'\n'):find('读回ID=',1,true))
end)
test('configured but idle music does not scan native world objects',function()
    local h=fixture();h.active=false;h.music:set('AUTO','MOYUAN_P1')
    for _=1,100 do h.music:tick()end
    assert(h.lookups==0 and #h.calls==0)
end)
test('explicit arena music does not require native boss-UI music to be enabled',function()
    local h=fixture();h.sub.bDisableBossMusicOnUI=true
    h.music:set('AUTO','MOYUAN_P1');assert(h:count('play')==1)
end)
test('confirmed death stops only gameplay music and asks the native system to resume',function()
    local h=fixture();h.music:set('AUTO','MOYUAN_P1');h.actor.hp=0;h.music:tick()
    assert(h:count('clear')==1 and h:count('restore')==1 and not h.music.lease)
    assert(h.sub.CurPlayingEvent_Gameplay==h.ambient)
end)
test('native negative-one sentinels mean no playback rather than unreadable or active story music',function()
    local h=fixture();h.sub.CurPlayingID_Gameplay=-1;h.sub.CurPlayingEvent_Gameplay=nil;h.sub.CurPlayingID_Story=-1
    h.music:set('AUTO','MOYUAN_P1');assert(h:count('play')==1 and h.music.lease)
    function h.sub:ClearMusic(_,gameplay,story)
        assert(gameplay and not story);self.CurPlayingID_Gameplay=-1;self.CurPlayingEvent_Gameplay=nil
    end
    h.actor.hp=0;h.music:tick();assert(not h.music.lease and h:count('restore')==1)
end)
test('unknown HP holds the current track without treating the actor as dead',function()
    local h=fixture();h.music:set('AUTO','MOYUAN_P1');h.actor.hp=nil;h.music:tick()
    assert(h:count('clear')==0 and h.music:status().state=='waiting')
    h.actor.hp=0;h.music:tick();assert(h:count('clear')==1)
end)
test('manual selection changes track without restoring ambient music between two mod tracks',function()
    local h=fixture();h.music:set('TRACK','MOYUAN_P1');h.music:set('TRACK','LEIDANG_P1')
    assert(h:count('play')==2 and h:count('clear')==1 and h:count('restore')==0 and h.music.lease.track=='LEIDANG_P1')
end)
test('native takeover is never cleared when its playing ID has changed',function()
    local h=fixture();h.music:set('AUTO','MOYUAN_P1')
    h.sub.CurPlayingID_Gameplay=999;h.sub.CurPlayingEvent_Gameplay=h.ambient;h.music:tick()
    assert(h:count('clear')==0 and h.music.suspended and not h.music.lease)
    for _=1,5 do h.music:tick()end;assert(h:count('play')==1)
end)
test('native callbacks yield and story playback never gets cleared',function()
    local h=fixture();h.music:set('AUTO','MOYUAN_P1')
    h.sub.CurPlayingID_Story=500;h.hooks[Music.paths[2]]({type=function()return 'RemoteUnrealParam'end,get=function()return h.sub end})
    h.music:tick();assert(h:count('clear')==1 and h:count('restore')==0 and h.sub.CurPlayingID_Story==500)
end)
test('asynchronous fade retains ownership until zero is read back and then restores',function()
    local h=fixture();h.music:set('AUTO','MOYUAN_P1');h.delayStop=true;h.active=false;h.music:tick()
    assert(h.music.lease and h.music:status().pending and h:count('restore')==0)
    h.now=1;h.sub.CurPlayingID_Gameplay=0;h.sub.CurPlayingEvent_Gameplay=nil;h.music:tick()
    assert(not h.music.lease and h:count('restore')==1)
end)
test('failed native recovery is retained and retried instead of being reported complete',function()
    local h=fixture();h.music:set('AUTO','MOYUAN_P1');h.failRestore=true;h.active=false;h.music:tick()
    assert(h.music.restorePending and h.music:status().pending and h.music:status().state=='failed')
    h.failRestore=false;h.music:tick();assert(not h.music.restorePending and h:count('restore')==2)
end)
test('old-world actors cannot start music in a replacement world',function()
    local h=fixture();h.music:set('AUTO','MOYUAN_P1')
    h.world=object(50,'World Next');h.sub.outer=h.world;h.sub.key=51;h.sub.name='MusicSubsystem Next.MusicSubsystem_0'
    h.sub.CurPlayingID_Gameplay=900;h.sub.CurPlayingEvent_Gameplay=h.ambient;h.music:tick()
    assert(h:count('play')==1 and h:count('clear')==0 and not h.music.lease)
end)
test('reserves, companion and no-team units do not start an arena theme',function()
    for _,change in ipairs({{team='companion'},{team='neutral'},{reserve=true},{aid=true}})do
        local h=fixture();for k,v in pairs(change)do h.members[1][k]=v end
        h.music:set('TRACK','MOYUAN_P1');assert(h:count('play')==0)
    end
end)
test('settings survive reload and save failures keep the old choice',function()
    local h=fixture();h.active=false;h.music:set('TRACK','LEIDANG_P1')
    local other=Music.new(h.options);assert(other.mode=='TRACK' and other.track=='LEIDANG_P1')
    local before=h.files['memory/battle-music.tsv'];h.failRename=true
    assert(not h.music:set('AUTO','MOYUAN_P1').ok and h.files['memory/battle-music.tsv']==before and h.music.mode=='TRACK')
    assert(not h.music:set('TRACK','../BAD').ok)
end)
test('an accepted native call without a valid playing readback never claims playback',function()
    local h=fixture();h.noPost=true;h.music:set('AUTO','MOYUAN_P1')
    assert(h:count('play')==1 and not h.music.lease and h.music:status().state=='failed' and h.sub.CurPlayingEvent_Gameplay==h.ambient)
    for i=1,20 do h.now=i*5;h.music:tick()end
    assert(h:count('play')==3,'a bad track must not force native audio forever')
end)
test('partial hook readiness, wrong threads and unload cannot issue uncontrolled music calls',function()
    local h=fixture();h.missingHooks=true;h.music:set('AUTO','MOYUAN_P1');assert(#h.calls==0)
    h.missingHooks=false;h.now=4;h.thread=false;h.music:tick();assert(#h.calls==0)
    h.thread=true;h.music:tick();assert(h:count('play')==1)
    h.music:silence();h.actor.hp=0;h.music:tick();assert(h:count('clear')==0)
end)
print('battle_music: PASS ('..passed..' ownership, death, recovery and session checks; no game accessed)')

test('native mode plays Mo Yuan only during an arena fight and restores on exit',function()
    local h=fixture()
    h.music:tick(h.members,{battle_active=false});assert(h:count('play')==0)
    h.music:tick(h.members,{battle_active=true});assert(h:count('play')==1)
    h.music:tick(h.members,{battle_active=true});assert(h:count('play')==1)
    h.options.moYuanPhaseTwo=function()return true end
    h.music:tick(h.members,{battle_active=true});assert(h.music.lease.track=='MOYUAN_P2' and h:count('play')==2)
    h.music:tick({}, {battle_active=false});assert(not h.music.lease and h:count('restore')==1)
end)
