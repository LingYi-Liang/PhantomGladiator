package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local cases={
    {'unit_rules',function(m)return m:set('BP_Demo','lock','kill')end,function(m)return m:get('BP_Demo','lock')=='execute'end},
    {'companion_executions',function(m)return m:set('ON')end,function(m)return not m.on end},
    {'battle_clock_hud',function(m)return m:set('ON')end,function(m)return not m.on end},
    {'execution_camera',function(m)return m:set('ON')end,function(m)return not m.on end},
    {'fun_features',function(m)return m:set('SHACHI','ON')end,function(m)return not m.on.SHACHI end},
    {'immortal_teams',function(m)return m:set('blue','ON')end,function(m)return not m.on.blue end},
    {'stat_match',function(m)return m:setMode('MATCH')end,function(m)return m.mode=='game'end},
}
local failed=0
for _,case in ipairs(cases)do
    local files={}
    local fs={open=function(path,mode)
        if mode:find('r',1,true) then
            if not files[path] then return nil end
            return {read=function()return files[path]end,close=function()return true end}
        end
        return {write=function(self,text)files[path]=text;return self end,
            close=function()return nil,'simulated close/flush failure' end}
    end}
    local ok,err=pcall(function()
        local module=require(case[1]).new({path='isolated',io=fs,cameras={},members=function()return {}end})
        local result=case[2](module)
        assert(result and result.ok==false,'a close failure must not be acknowledged as saved')
        assert(case[3](module),'a failed save must keep the previous runtime setting')
    end)
    if not ok then failed=failed+1;print('FAIL '..case[1]..': '..tostring(err))
    else print('PASS '..case[1]..' rejects a close failure even when the text can be read back')end
end
assert(failed==0,tostring(failed)..' settings accepted a failed close')
