package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Rules=require('unit_rules')
local function filesystem(files)
    local fs={files=files or {}}
    function fs.open(path,mode)
        if mode:find('r',1,true) then
            local text=fs.files[path]
            if not text then return nil end
            return {read=function()return text end,close=function()return true end}
        end
        if fs.deny then return nil end
        local out={}
        return {write=function(_,s)out[#out+1]=s;return true end,
            close=function()if not fs.lose then fs.files[path]=table.concat(out) end;return true end}
    end
    return fs
end
local FILE='memory/unit-rules.tsv'
local function new(fs,lines)
    return Rules.new({path='memory',io=fs,log=function(s)if lines then lines[#lines+1]=s end end})
end
local function actor(class)
    return {GetClass=function()return {GetFName=function()return {ToString=function()return class end}end}end}
end
-- Defaults, a choice saved and read back, the default again takes the row away.
do
    local fs,lines=filesystem(),{}
    local rules=new(fs,lines)
    assert(rules:get('BP_Monster_MoTian','lock')=='execute' and rules:get('BP_Monster_MoTian','phantom')=='off')
    assert(rules:status().text=='')
    local result=rules:set('BP_Monster_MoTian','lock','kill')
    assert(result.ok and result.spawned_count==0 and result.message=='锁血后打死')
    assert(fs.files[FILE]=='UnitRulesV1\nBP_Monster_MoTian\tlock\tkill\n',fs.files[FILE])
    assert(rules:get('BP_Monster_MoTian','lock')=='kill' and rules:get(actor('BP_Monster_MoTian_C'),'lock')=='kill','by id or by an actor')
    assert(rules:get(actor('BP_Monster_AHua_C'),'lock')=='execute','others keep the default')
    assert(rules:set('BP_Monster_YanQianSui','phantom','keep').ok)
    assert(rules:status().text=='BP_Monster_MoTian:lock=kill;BP_Monster_YanQianSui:phantom=keep',rules:status().text)
    -- Saved rules come back at the next start.
    local again=new(fs)
    assert(again:get('BP_Monster_MoTian','lock')=='kill' and again:get('BP_Monster_YanQianSui','phantom')=='keep')
    assert(rules:set('BP_Monster_MoTian','lock','execute').ok)
    assert(fs.files[FILE]=='UnitRulesV1\nBP_Monster_YanQianSui\tphantom\tkeep\n',fs.files[FILE])
    assert(lines[1]:find('[UnitRules] 设置 单位=BP_Monster_MoTian lock=kill 保存读回=true',1,true),lines[1])
end
-- Refused: an unknown unit, rule or value; a value of the other rule. Nothing changes.
do
    local fs=filesystem()
    local rules=new(fs)
    for _,bad in ipairs({{'../x','lock','kill'},{'','lock','kill'},{'BP_Monster_MoTian','size','kill'},{'BP_Monster_MoTian','lock','keep'},{'BP_Monster_MoTian','phantom','kill'},{nil,'lock','kill'}})do
        assert(not rules:set(bad[1],bad[2],bad[3]).ok)
    end
    assert(fs.files[FILE]==nil and rules:status().text=='')
end
-- A save that does not read back keeps the rule as it was and says so.
do
    local fs,lines=filesystem(),{}
    local rules=new(fs,lines)
    fs.lose=true
    local result=rules:set('BP_Monster_MoTian','lock','kill')
    assert(not result.ok and result.message=='单位规则没有保存' and rules:get('BP_Monster_MoTian','lock')=='execute')
    assert(lines[1]:find('保存读回=false',1,true))
    fs.lose=false;fs.deny=true
    assert(not rules:set('BP_Monster_MoTian','lock','kill').ok)
end
-- A damaged file: only what is valid counts, defaults are not kept.
do
    local fs=filesystem({[FILE]='UnitRulesV1\nBP_Monster_MoTian\tlock\tkill\nBP_Bad/x\tlock\tkill\nBP_Monster_AHua\tlock\tboom\nBP_Monster_X\tsize\tkill\nBP_Monster_Y\tlock\texecute\n'})
    local rules=new(fs)
    assert(rules:status().text=='BP_Monster_MoTian:lock=kill',rules:status().text)
    assert(new(filesystem({[FILE]='OldV0\nBP_Monster_MoTian\tlock\tkill\n'})):status().text=='')
end
print('unit_rules: PASS')
