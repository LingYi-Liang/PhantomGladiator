package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Fun=require('fun_features')
local address=0
local function object(fields,name)
    address=address+1;local a=address
    fields.IsValid=function()return true end
    fields.GetAddress=function()return a end
    fields.GetFName=function()return {ToString=function()return name or 'obj'end}end
    return fields
end
local function harness(files)
    local h={files=files or {},lines={},attrs={},writes={},now=100,clock=0,loops={},cancelled={},injected={}}
    h.io={open=function(path,mode)
        if mode=='w' and h.failSave then return nil end
        if mode=='r' and h.files[path]==nil then return nil end
        local text=h.files[path] or ''
        return {read=function()return text end,write=function(_,s)text=s;return true end,
            close=function()if mode=='w' then h.files[path]=text end;return true end}
    end}
    h.attrs={Shachi={base=200,current=200},Shachi_Min={base=0,current=0},Shachi_Max={base=800,current=800}}
    h.stats={read=function(_,_,field)local a=h.attrs[field];return a and {base=a.base,current=a.current} end,
        writeBase=function(_,_,field,value)
            h.writes[#h.writes+1]=field..'='..value
            if h.stuck==field then return true end
            h.attrs[field]={base=value,current=value};return true
        end}
    h.frames={}
    h.component=object({PerfectDodgeResultData={HitGameTime=0},ReceiveFrames={ForEach=function(_,fn)
        for handle,frame in pairs(h.frames)do fn(handle,frame)end
    end}},'DeflectComponent')
    h.health={CurrentValue=1000}
    h.shachi={CurrentValue=700}
    h.pawn=object({['Deflect Component']=h.component,AttributeSetBase=object({Health=h.health,Shachi=h.shachi,Shachi_Min={CurrentValue=700}},'AttributeSet')},'BP_RenewalPlayer_C')
    h.stance=object({['Deflect Component']=h.component,['Current Result Data']={HitGameTime=0,DeflectResult={TagName={ToString=function()return 'None'end}}},
        ['Perfect Pre Hit Time']=0.1,['Perfect Window']=0.15,['Great Window']=0.25,['Normal Window']=0.4},'BP_StanceAction_Base_Player_C')
    h.passive=object({['Deflect Component']=h.component,['Perfect Window']=0.2,['Normal Window']=0.4,['Last Deflect Click']=1},'BP_PlayerDeflectPassive_C')
    h.dodgePassive=object({['Deflect Component']=h.component},'BP_PerfectDodgePassive_C')
    h.actions={DEFLECT=object({Triggers={}},'IA_Deflect'),DODGE=object({Triggers={}},'IA_Dodge')}
    h.subsystem=object({},'EnhancedInputLocalPlayerSubsystem')
    h.inject=setmetatable(object({},'InjectInputVectorForAction'),{__call=function(_,sub,action,value)
        assert(sub==h.subsystem and value.X==1)
        h.injected[#h.injected+1]=action==h.actions.DEFLECT and 'DEFLECT' or 'DODGE'
        if action==h.actions.DEFLECT and not h.ignored then h.passive['Last Deflect Click']=h.now end
    end})
    local paths={
        ['/Script/Engine.Default__SubsystemBlueprintLibrary']=object({GetLocalPlayerSubSystemFromPlayerController=function()return h.subsystem end}),
        ['/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem']=object({},'class'),
        ['/Script/EnhancedInput.EnhancedInputSubsystemInterface']=object({},'interface'),
        ['/Script/EnhancedInput.EnhancedInputSubsystemInterface:InjectInputVectorForAction']=h.inject,
        ['/Script/Engine.Default__KismetSystemLibrary']=object({DoesImplementInterface=function()return true end}),
        ['/Script/Engine.Default__GameplayStatics']=object({GetTimeSeconds=function()return h.now end}),
        ['/PBZDeflectSystem/Input/IA_Deflect.IA_Deflect']=h.actions.DEFLECT,
        ['/PBZDeflectSystem/Input/IA_Dodge.IA_Dodge']=h.actions.DODGE,
    }
    StaticFindObject=function(path)return paths[path] end
    FindAllOf=function(name)
        if name=='BP_PlayerDeflectPassive_C' then return {h.passive} end
        if name=='BP_StanceAction_Base_Player_C' then return h.stanceFound and {h.stance} or nil end
        return {h.dodgePassive}
    end
    LoadAsset=function()end
    LoopInGameThreadWithDelay=function(_,fn)h.loops[#h.loops+1]=fn;return #h.loops end
    CancelDelayedAction=function(handle)h.cancelled[#h.cancelled+1]=handle;return true end
    function h.new()
        return Fun.new({path='R',io=h.io,attributes=h.stats,log=function(s)h.lines[#h.lines+1]=s end,clock=function()return h.clock end,
            getPlayer=function()return h.pawn end,getController=function()return object({},'PC')end,
            members=function()return h.members or {} end,
            ready=function()return true end,paused=function()return h.paused end})
    end
    function h.frame()h.loops[#h.loops](); end
    function h.all()return table.concat(h.lines,'\n')end
    return h
end

-- Settings: saved with readback; a failed save keeps the old value; unknown features are refused.
do
    local h=harness()
    local fun=h.new()
    assert(not fun:status().shachi and not fun:status().deflect)
    assert(fun:set('GOD','ON').ok==false and fun:set('SHACHI','MAYBE').ok==false)
    assert(fun:set('SHACHI','ON').ok)
    assert(h.files['R/fun-features.tsv']=='FunFeaturesV1\tSHACHI=1\tDEFLECT=0\tDODGE=0\n',h.files['R/fun-features.tsv'])
    h.failSave=true
    local r=fun:set('DEFLECT','ON')
    assert(r.ok==false and fun:status().deflect==false,r.message)
    h.failSave=false
    local again=Fun.new({path='R',io=h.io,attributes=h.stats,log=function()end})
    assert(again:status().shachi==true and again:status().deflect==false)
end

-- Infinite Shachi: the floor goes up to the max and the bar is filled; turning it off restores the floor.
do
    local h=harness()
    local fun=h.new()
    fun:set('SHACHI','ON');fun:tick()
    assert(h.attrs.Shachi_Min.current==800 and h.attrs.Shachi.current==800,h.all())
    assert(fun:status().shachi_state=='locked')
    assert(h.files['R/fun-shachi-floor.tsv']:match('^ShachiFloorV1\t%S+\t0%.000000\n$'),h.files['R/fun-shachi-floor.tsv'])
    -- A skill spends the bar; the next tick fills it again. A higher max raises the floor with it.
    h.attrs.Shachi={base=300,current=300};h.attrs.Shachi_Max={base=1000,current=1000}
    fun:tick()
    assert(h.attrs.Shachi_Min.current==1000 and h.attrs.Shachi.current==1000)
    assert(fun:status().shachi_state=='locked')
    fun:set('SHACHI','OFF')
    assert(h.attrs.Shachi_Min.current==0 and fun:status().shachi_state=='off',h.all())
    assert(h.files['R/fun-shachi-floor.tsv']=='')
end

-- A floor that does not read back is reported, not called locked.
do
    local h=harness();h.stuck='Shachi_Min'
    local fun=h.new()
    fun:set('SHACHI','ON');fun:tick()
    assert(fun:status().shachi_state=='failed' and fun:status().shachi_failures>0)
end

-- Mod reload while locked: the journaled floor is the original, not the raised one; off restores it.
do
    local h=harness()
    local first=h.new()
    first:set('SHACHI','ON');first:tick();first:silence()
    assert(h.attrs.Shachi_Min.current==800)
    local second=h.new()
    second:tick()
    assert(h.attrs.Shachi_Min.current==800 and second:status().shachi_state=='locked')
    second:set('SHACHI','OFF')
    assert(h.attrs.Shachi_Min.current==0,h.all())
    -- Reloaded with the switch already off: the next instance restores the floor on its first tick.
    local third=h.new();third:set('SHACHI','ON');third:tick();third:silence()
    h.files['R/fun-features.tsv']='FunFeaturesV1\tSHACHI=0\tDEFLECT=0\tDODGE=0\n'
    local fourth=h.new();fourth:tick()
    assert(h.attrs.Shachi_Min.current==0 and h.files['R/fun-shachi-floor.tsv']=='',h.all())
end

-- Auto deflect: one press per announced hit, at half the perfect window before it, read back.
do
    local h=harness()
    local fun=h.new()
    assert(#h.loops==0)
    fun:set('DEFLECT','ON')
    assert(#h.loops==1 and fun:status().guard_state=='waiting')
    fun:tick()
    h.frames[7]={HitGameTime=100.5,IsDodge=false,IsHit=false,DeflectStrength={TagName={ToString=function()return 'Deflect.Strength.Light'end}}}
    h.frame()
    assert(#h.injected==0,'pressed too early')
    h.now=100.43;h.frame()
    assert(#h.injected==0,'a light attack waits for its 0.06 s lead')
    h.now=100.45;h.frame()
    assert(#h.injected==1 and h.injected[1]=='DEFLECT',h.all())
    h.now=100.47;h.frame()
    assert(#h.injected==1,'pressed twice for one hit')
    assert(fun:status().deflect_pressed==1 and fun:status().deflect_received==1 and fun:status().guard_state=='ready',h.all())
    assert(h.all():find('格挡被动收到按键',1,true))
    -- The game consumes the frame before the hit: logged as an early end.
    h.frames[7]=nil;h.frame()
    assert(h.all():find('预告结束 handle=7',1,true))
    -- Dodge frames are left alone while only deflect is on.
    h.frames[8]={HitGameTime=101,IsDodge=true,IsHit=false};h.now=100.95;h.frame()
    assert(#h.injected==1)
    -- Paused (free camera): nothing is pressed.
    h.frames[8]=nil;h.frame()
    h.paused=true;h.frames[9]={HitGameTime=102,IsDodge=false,IsHit=false};h.now=101.95;h.frame()
    assert(#h.injected==1)
    h.paused=false
    fun:set('DEFLECT','OFF')
    assert(#h.cancelled==1 and fun:status().guard_state=='off')
end

-- Auto dodge presses IA_Dodge for red-light frames; a press the passive ignores is not counted as received.
do
    local h=harness();h.ignored=true
    local fun=h.new()
    fun:set('DEFLECT','ON');fun:set('DODGE','ON');fun:tick()
    assert(#h.loops==1,'one loop serves both')
    h.frames[1]={HitGameTime=100.08,IsDodge=true,IsHit=false}
    h.frame()
    assert(h.injected[1]=='DODGE' and fun:status().dodge_pressed==1,h.all())
    h.frames[2]={HitGameTime=100.05,IsDodge=false,IsHit=false}
    h.now=100.01;h.frame()
    assert(h.injected[2]=='DEFLECT' and fun:status().deflect_received==0)
    -- Within the cooldown a second deflect frame waits; after it, it goes in.
    h.frames[3]={HitGameTime=100.06,IsDodge=false,IsHit=false};h.now=100.05;h.frame()
    assert(#h.injected==2)
    h.frames[3].HitGameTime=100.2;h.now=100.15;h.frame()
    assert(#h.injected==3)
end

-- Only deflectability decides: can't-deflect and red-eye attacks are dodged even without IsDodge;
-- blue-eye, power attacks and perfect-dodge counters can be deflected and are.
do
    local function source(kind)
        local action=object({DeflectBulletType=kind},'LGAAction_DurationBulletWithDeflect')
        action.Get=function(self)return self end
        return action
    end
    local h=harness()
    local fun=h.new()
    fun:set('DEFLECT','ON');fun:tick()
    h.frames[1]={HitGameTime=100.05,IsDodge=false,IsHit=false,SourceAction=source(3)};h.frame()
    assert(#h.injected==0,'a red-eye attack cannot be deflected, and dodge is off')
    assert(h.all():find('红光→闪避',1,true) and h.all():find('类型值=3',1,true),h.all())
    h.frames[1]=nil;h.frame()
    fun:set('DODGE','ON')
    h.frames[2]={HitGameTime=100.5,IsDodge=false,IsHit=false,SourceAction=source(3)};h.now=100.45;h.frame()
    h.frames[3]={HitGameTime=101,IsDodge=false,IsHit=false,SourceAction=source(0)};h.now=100.95;h.frame()
    assert(h.injected[1]=='DODGE' and h.injected[2]=='DODGE',h.all())
    for i,frame in ipairs({{kind=2},{kind=4},{kind=1,counter=object({},'GA_Hun_PerfectDodge_ThunderCounter_C')}})do
        local at=101+i*0.5
        h.frames[10+i]={HitGameTime=at,IsDodge=false,IsHit=false,SourceAction=source(frame.kind),CounterAbility=frame.counter}
        h.now=at-0.05;h.frame()
        assert(h.injected[2+i]=='DEFLECT','deflectable attack type '..frame.kind)
    end
    assert(h.all():find('蓝光→格挡',1,true) and h.all():find('重击→格挡',1,true))
end

-- Readbacks: the deflect result once the ability is found, and every HP drop with the frames around it.
do
    local h=harness()
    local fun=h.new()
    fun:set('DEFLECT','ON');fun:tick()
    h.frames[1]={HitGameTime=100.05,IsDodge=false,IsHit=false};h.frame()
    assert(#h.injected==1)
    -- The ability instance appears after the first deflect; the slow tick finds it.
    h.stanceFound=true;h.clock=5;fun:tick()
    assert(h.all():find('格挡技能实例=BP_StanceAction_Base_Player_C',1,true) and h.all():find('完美前置=0.100',1,true),h.all())
    h.frames[1]=nil;h.frame()
    h.frames[2]={HitGameTime=100.5,IsDodge=false,IsHit=false};h.now=100.45;h.frame()
    assert(#h.injected==2)
    h.stance['Current Result Data']={HitGameTime=100.5,DeflectResult={TagName={ToString=function()return 'Deflect.Result.Perfect'end}}}
    h.frame()
    assert(h.all():find('格挡结果=Deflect.Result.Perfect',1,true),h.all())
    -- A hit right after a frame ended is tied to it; a hit with no frame around is called unannounced.
    h.frames[2]=nil;h.frame()
    h.health.CurrentValue=900;h.frame()
    assert(h.all():find('玩家掉血 1000.0→900.0(-100.0) 进行中预告=[] 刚结束=[2:',1,true),h.all())
    h.clock=10;h.health.CurrentValue=850;h.frame()
    assert(h.all():find('-50.0) 进行中预告=[] 刚结束=[] 没有预告的攻击',1,true),h.all())
    -- Healing is not a hit.
    local before=#h.lines
    h.health.CurrentValue=1000;h.frame()
    assert(#h.lines==before and fun:status().deflect_pressed==2)
end

-- Hit readback: each HP drop of an app unit with the player's Shachi before and after, by lock state.
do
    local h=harness()
    local unitHealth={CurrentValue=12000}
    local unit=object({AttributeSetBase=object({Health=unitHealth},'AttributeSet')},'BP_Monster_MoTian_C')
    unit.GetClass=function()return object({},'BP_Monster_MoTian_C')end
    h.members={{actor=unit,team='neutral'}}
    local fun=h.new()
    fun:set('SHACHI','ON');fun:tick()
    assert(#h.loops==1,'infinite Shachi alone runs the loop')
    h.frame()
    unitHealth.CurrentValue=11500;h.shachi.CurrentValue=690;h.frame()
    assert(h.all():find('单位受伤 BP_Monster_MoTian_C -500.0 (HP 12000.0→11500.0) 玩家杀气 700.000→690.000 下限当前=700.000 无限杀气=开',1,true),h.all())
    -- The unit leaves the app's list: no more readings.
    h.members={};fun:tick();unitHealth.CurrentValue=100;local before=#h.lines;h.frame()
    assert(#h.lines==before)
end

-- The release presses every strength at the measured lead. Trial leads for heavier attacks are taken
-- in turn and logged with the result. A frame the game leaves listed long after its hit is ended once
-- and then ignored.
assert(#Fun.HEAVY_LEADS==1 and Fun.HEAVY_LEADS[1]==Fun.LIGHT_LEAD,'every strength uses the measured lead')
do
    local function strength(tag)return {TagName={ToString=function()return tag end}}end
    local measured=Fun.HEAVY_LEADS
    Fun.HEAVY_LEADS={0.09,0.13}
    local h=harness()
    local fun=h.new()
    fun:set('DEFLECT','ON');fun:tick()
    h.frames[1]={HitGameTime=100.3,IsDodge=false,IsHit=false,DeflectStrength=strength('Deflect.Strength.Normal')}
    h.frame();h.now=100.2;h.frame()
    assert(#h.injected==0)
    h.now=100.22;h.frame()
    assert(#h.injected==1 and h.all():find('提前量=0.090',1,true),h.all())
    h.frames[1]=nil;h.frame()
    h.frames[2]={HitGameTime=100.8,IsDodge=false,IsHit=false,DeflectStrength=strength('Deflect.Strength.Knockback')}
    h.now=100.6;h.frame();h.now=100.68;h.frame()
    assert(#h.injected==2 and h.all():find('提前量=0.130',1,true),h.all())
    -- Frame 2 stays listed: after a second past its hit it is ended and not logged again.
    h.now=101.9;h.frame()
    assert(h.all():find('预告 handle=2 命中后',1,true) and h.all():find('预告结束 handle=2',1,true),h.all())
    local before=#h.lines;h.now=102.5;h.frame()
    assert(#h.lines==before,h.all())
    -- Once the game drops it, the same handle can be announced again.
    h.frames[2]=nil;h.frame()
    h.frames[2]={HitGameTime=103,IsDodge=false,IsHit=false};h.now=102.95;h.frame()
    assert(#h.injected==3,h.all())
    Fun.HEAVY_LEADS=measured
end

-- Hit times in another time base are logged and never pressed for.
do
    local h=harness()
    local fun=h.new()
    fun:set('DEFLECT','ON');fun:tick()
    h.frames[4]={HitGameTime=5000,IsDodge=false,IsHit=false};h.frame()
    h.now=100.5;h.frame()
    assert(#h.injected==0 and h.all():find('时间基准对不上',1,true),h.all())
end

-- A subsystem that does not implement the injection interface is never called.
do
    local h=harness()
    StaticFindObject=(function(find)return function(path)
        if path=='/Script/Engine.Default__KismetSystemLibrary' then return object({DoesImplementInterface=function()return false end})end
        return find(path)
    end end)(StaticFindObject)
    local fun=h.new()
    fun:set('DEFLECT','ON');fun:tick()
    h.frames[5]={HitGameTime=100.05,IsDodge=false,IsHit=false};h.frame()
    assert(#h.injected==0 and fun:status().guard_state=='failed',h.all())
end
print('fun_features ok')
