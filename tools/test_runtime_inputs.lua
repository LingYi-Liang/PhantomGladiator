package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Camera=require('free_camera')
local passed,failed,constructed=0,0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1;print('ok - '..name)
    else failed=failed+1;print('FAIL - '..name..': '..tostring(err))end
end
local function filesystem(files)
    return {open=function(path,mode)
        if not mode:find('r',1,true) then
            return {write=function(self)return self end,flush=function()return true end,close=function()return true end}
        end
        local value=files[path]
        if value==nil then return nil end
        return {read=function()if value~=false then return value end end,close=function()return true end}
    end}
end
local function camera(text)
    local logs={}
    local c=Camera.new({path='memory',io=filesystem({['memory/free-camera-settings.tsv']=text}),
        log=function(s)logs[#logs+1]=s end})
    return c,logs
end
test('camera ignores future fields and keeps all valid known values',function()
    local c=camera('FreeCameraSettingsV1\nspeed\t1500\nfuture\t12\nturn\t150\nsmooth\t25\n')
    local s=c:settings();assert(s.speed==1500 and s.turn==150 and s.smooth==25)
end)
test('camera repairs one invalid field without dropping the other valid fields',function()
    for _,value in ipairs({'bad','nan','1e309','-1','900.5','99999',''})do
        local c,logs=camera('FreeCameraSettingsV1\nspeed\t'..value..'\nturn\t150\nsmooth\t25\n')
        local s=c:settings();assert(s.speed==900 and s.turn==150 and s.smooth==25,'lost valid fields for '..value)
        assert(#logs>=1 and #logs<=4,'invalid known values need bounded diagnostics')
    end
end)
test('partial camera settings preserve complete fields and default missing fields',function()
    local c=camera('FreeCameraSettingsV1\nspeed\t1500\nturn\t')
    local s=c:settings();assert(s.speed==1500 and s.turn==100 and s.smooth==40)
end)
local modules={
    {'free_camera','FreeCameraSettingsV1\nspeed\t900\nturn\t100\nsmooth\t40\n','free-camera-settings.tsv'},
    {'free_camera','FreeCameraV1\ncontroller\t/Test.PC\n','free-camera.tsv'},
    {'spectator_mode','SpectatorV1\nF\t/Test.P\t42\t/Test.H\t43\t1\n','spectator-state.tsv'},
    {'arena_grabs','NPCGrabPolicyV1\n/PBZCombatAsset/ActorData/Mobs/A/E.E\t42\n','npc-grab-policy.tsv'},
    {'spawn_level','SpawnLevelV1\t25\tunit\tworld\n','spawn-level.tsv'},
    {'stat_match','StatMatchV2\tcustom\nAttack\t100\n','stat-match-settings.tsv'},
    {'home_levels','SpawnLevelSettingsV1\tCUSTOM\t25\nunit\tBP_Test\t30\n','spawn-level-settings.tsv'},
    {'boss_combos','BossCombosV1\tON\n','boss-combos.tsv'},
    {'immortal_teams','ImmortalTeamsV1\tblue=1\n','immortal-teams.tsv'},
    {'battle_clock_hud','ClockHudV1\tshow=1\n','clock-hud.tsv'},
    {'execution_camera','ExecutionCameraV1\ton=1\n','execution-camera.tsv'},
    {'companion_executions','CompanionExecutionsV1\ton=1\n','companion-executions.tsv'},
    {'unit_rules','UnitRulesV1\nBP_Monster_MoTian\tlock\tkill\n','unit-rules.tsv'},
    {'camera_track','CameraTrackV1\tframing=orbit\tresume=5\n','camera-track.tsv'},
    {'function_keybinds','FunctionKeysV2\t1\nspawn\t65\t0\n','function-keybinds.tsv'},
    {'npc_catalog','PhantomGladiatorCatalogV1\nclass\t/Test/Unit.Unit_C\n','catalog.tsv'},
    {'unit_keybinds','UnitKeysV2\t1\n/Test/Unit.Unit_C\t65\t0\tblue\t1\n','unit-keybinds.tsv'},
    {'function_keybinds','spawn\tF3\nstart\tF4\nstop\tF5\nrefresh_catalog\tF6\n','keybinds.tsv'},
    {'panel_bridge','command1\tstarted\ncommand2\tdone\tok\tdone\t1\n','command-journal.tsv'},
}
for _,spec in ipairs(modules)do
    local module,valid,file=table.unpack(spec)
    test(module..' '..file..' accepts empty, truncated, future and malformed input without aborting construction',function()
        local samples={'','OldFormatV0\n',valid,valid..'future\t1e309\n',valid:gsub('%d','x'),valid:gsub('%d',string.rep('9',320)),false}
        for i=1,#valid do samples[#samples+1]=valid:sub(1,i)end
        for i,sample in ipairs(samples)do
            local fs=filesystem({['memory/'..file]=sample})
            local reads=0;local original=fs.open
            fs.open=function(path,mode)if path=='memory/'..file and mode:find('r',1,true)then reads=reads+1 end;return original(path,mode)end
            local open=io.open;io.open=fs.open
            local ok,result=pcall(function()
                constructed=constructed+1
                local instance=require(module).new({path=module=='npc_catalog' and 'memory/'..file or 'memory',io=fs,
                    os={remove=function()return false end,rename=function()return false end},
                    log=function()end,clock=function()return 0 end,now=function()return 0 end,
                    members=function()return {}end,renderer={},router={},knownPaths={}})
                if module=='unit_keybinds' then instance:start()end
                return instance
            end)
            io.open=open
            assert(ok,module..' sample '..i..': '..tostring(result))
            assert(reads>0,'fixture was not read: '..file)
        end
    end)
end
print(string.format('runtime input: %d passed, %d failed; %d constructor/startup samples',passed,failed,constructed))
if failed>0 then os.exit(1)end
