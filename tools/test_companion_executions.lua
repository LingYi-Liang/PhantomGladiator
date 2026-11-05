package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Setting=require('companion_executions')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('ok - '..name)end
local function memory(files,failWrite)
    return {open=function(path,mode)
        if mode:find('w',1,true) then
            if failWrite then return nil end
            return {write=function(_,text)files[path]=text;return true end,close=function()return true end}
        end
        if files[path]==nil then return nil end
        return {read=function()return files[path] end,close=function()return true end}
    end}
end
local FILE='memory/companion-executions.tsv'
test('off by default',function()
    local s=Setting.new({path='memory',io=memory({})})
    assert(s.on==false and s:status().on==false)
end)
test('the switch is saved, read back and still there the next time',function()
    local files={}
    local s=Setting.new({path='memory',io=memory(files)})
    local r=s:set('ON')
    assert(r.ok and r.message=='随从处决已开启' and s.on==true and files[FILE]=='CompanionExecutionsV1\ton=1\n')
    assert(Setting.new({path='memory',io=memory(files)}).on==true,'on after a restart')
    r=s:set('OFF')
    assert(r.ok and r.message=='随从处决已关闭' and s.on==false)
    assert(Setting.new({path='memory',io=memory(files)}).on==false,'off after a restart')
end)
test('a save that does not read back changes nothing and says so',function()
    local logs={}
    local s=Setting.new({path='memory',io=memory({},true),log=function(l)logs[#logs+1]=l end})
    local r=s:set('ON')
    assert(not r.ok and s.on==false and r.message=='随从处决设置没有保存')
    assert(logs[1]:find('保存读回=false',1,true),logs[1])
end)
test('only ON and OFF are taken',function()
    local files={}
    local s=Setting.new({path='memory',io=memory(files)})
    for _,bad in ipairs({'',nil,'on',1,true})do
        local r=s:set(bad);assert(not r.ok and s.on==false and files[FILE]==nil)
    end
end)
test('a file of another kind or format means off',function()
    for _,text in ipairs({'','OldFormat\ton=1\n','CompanionExecutionsV1','CompanionExecutionsV1\ton=0\n'})do
        assert(Setting.new({path='memory',io=memory({[FILE]=text})}).on==false,text)
    end
end)
print('companion_executions: '..passed..' tests passed')
