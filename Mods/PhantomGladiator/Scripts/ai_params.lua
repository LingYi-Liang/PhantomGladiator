-- AI 行为参数: the game's AI reads named parameters (near/mid/far attack chance, footsies weights, block and dodge
-- weights ...) through SGameAIFunctionLibrary.Find*Parameter, from the AI component's MergedParameterCollection. Blueprint
-- conditions ask each time they run (Condition_Probability), so a change takes effect at once. The panel's values go into
-- that collection on every unit of this mod once its AI has started, and are read back through the same function the game
-- uses. If a read-back disagrees (the map write did not take), the Find functions are hooked and answer for these units;
-- a pre-hook's return value replaces the result, the way GetDifficulty is answered in ai_difficulty.lua.
-- The first unit of each class also logs what the game gave it, so the defaults are on record, and the tension meter's
-- readout for a boss is logged now and then. That meter measures the player, not the AI's aggression.
local U=require('ue_observe')
local Params={}
Params.fields={
    {'近距离进攻概率','float'},{'中距离进攻概率','float'},{'远距离进攻概率','float'},{'目标在受击状态进攻概率','float'},{'咋呼概率','float'},
    {'重新规划-进攻欲望','float'},{'重新规划-起攻权重','float'},{'重新规划-摸奖权重','float'},{'重新规划-牵制权重','float'},
    {'重新规划-打差合概率','float'},{'事件反应-打差合概率','float'},{'事件反应-反蓄力动作概率','float'},{'autocombo权重','float'},
    {'非autocombo权重','float'},{'重新规划-全部攻击距离不满足时保底起攻','bool'},{'进攻-起攻最大距离','float'},{'进攻-摸奖最小距离','float'},
    {'进攻-摸奖最大距离','float'},{'进攻-牵制最小距离','float'},{'重新规划-差合最小距离','float'},{'重新规划-差合最大距离','float'},
    {'尝试远程攻击的距离','float'},{'格挡后-反击距离','float'},{'立回-退出立回距离','float'},{'立回-近距离分界线','float'},
    {'立回-远距离分界线','float'},{'立回-超远距离分界线','float'},{'立回-近距离二人转权重','float'},{'立回-近距离远离权重','float'},
    {'立回-近距离闪避权重','float'},{'立回-中距离二人转权重','float'},{'立回-中距离靠近权重','float'},{'立回-中距离远离权重','float'},
    {'立回-中距离闪避权重','float'},{'立回-远距离二人转权重','float'},{'立回-远距离靠近权重','float'},{'立回-近距离二人转最小持续时间','float'},
    {'立回-近距离二人转最大持续时间','float'},{'立回-中距离二人转最小持续时间','float'},{'立回-中距离二人转最大持续时间','float'},
    {'立回-远距离二人转最小持续时间','float'},{'立回-远距离二人转最大持续时间','float'},{'玩家开始近战攻击-格挡权重','float'},
    {'玩家开始近战攻击-闪避权重','float'},{'玩家开始近战攻击-无行为权重','float'},{'玩家开始近战攻击-针对动作权重','float'},
    {'玩家开始近战攻击-格挡距离','float'},{'玩家开始近战攻击-闪避距离','float'},{'远程攻击发射-格挡权重','float'},{'远程攻击发射-闪避权重','float'},
    {'远程攻击发射-无行为权重','float'},{'远程攻击发射-针对动作权重','float'},{'玩家靠近-抢招权重','float'},{'玩家靠近-闪避后撤权重','float'},
    {'玩家靠近-无行为权重','float'},{'受击-转格挡概率','float'},{'受击-允许转格挡计数','int'},{'受击-正面脱离计数','int'},{'受击-背面脱离计数','int'},
    {'重新规划-不进攻时闪避概率','float'},{'重新规划-不进攻时闪避最大距离','float'},{'玩家开始远程攻击-反制概率','float'},{'闪避敌人近战攻击的距离','float'},
    {'减帧时允许格挡','bool'},{'无视子弹开始事件','bool'},
}
local KIND={}
for _,row in ipairs(Params.fields)do KIND[row[1]]=row[2] end
Params.kind=KIND
local LIB='/Script/SGameAI.Default__SGameAIFunctionLibrary'
local HOOKS='/Script/SGameAI.SGameAIFunctionLibrary:'
local FIND={float='FindFloatParameter',bool='FindBoolParameter',int='FindIntParameter'}
local MAP={float='FloatParameters',bool='BoolParameters',int='IntParameters'}
local ABSENT={}
local PROBE={'近距离进攻概率','中距离进攻概率','远距离进攻概率','目标在受击状态进攻概率','重新规划-进攻欲望','立回-退出立回距离','玩家开始近战攻击-格挡权重','受击-转格挡概率'}
local SECONDS,TENSION_SECONDS,APPLY_LINES,CLASS_LINES,TENSION_LINES,RETRIES=1,15,30,30,8,5

local function className(object)
    local ok,name=pcall(function()return object:GetClass():GetFName():ToString()end)
    return ok and type(name)=='string' and name or '?'
end
local function addr(object)
    if object==nil then return nil end
    local ok,key=pcall(function()return object:GetAddress()end)
    return ok and key~=nil and tostring(key) or nil
end
local function same(kind,a,b)
    if a==nil or b==nil then return false end
    if kind=='bool' then return (a==true or a==1)==(b==true or b==1) end
    return type(a)=='number' and type(b)=='number' and math.abs(a-b)<=math.max(1e-4,math.abs(b)*1e-4)
end
local function wire(kind,value)
    if kind=='bool' then return value~=0 end
    if kind=='int' then return math.floor(value+0.5) end
    return value
end
local function readFile(path)
    local file=io.open(path,'r')
    if not file then return nil end
    local text=file:read('*a');file:close()
    return text
end

function Params.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.clock
    local self={alive=true,values={},generation=0,applied=0,failures=0,rewritten=0,hooked=false,message='全部用游戏原值'}
    local settings=options.path and options.path..'/ai-params-settings.tsv'
    local request=options.path and options.path..'/ai-params-request.tsv'
    local fileOps=options.os or os
    local previousSettings=settings and settings..'.previous'
    local units,classes,hooks,controllers={},{},{},{}
    local lines,classLines,tensionLines,nextAt,tensionAt=0,0,0,0,0
    local function say(text)log('[AIParams] '..text)end
    local function fname(name)return FName(name)end
    local function lib()
        local ok,found=pcall(function()return options.lib and options.lib() or StaticFindObject(LIB)end)
        return ok and U.valid(found) and found or nil
    end
    local function find(library,controller,name)
        local kind=KIND[name]
        local ok,value=pcall(function()return library[FIND[kind]](library,controller,fname(name))end)
        if not ok then return nil end
        return U.unwrap(value)
    end
    -- What the game itself has, with the hook out of the way once it is on.
    local bypass=false
    local function gameValue(library,controller,name)
        bypass=true
        local value=find(library,controller,name)
        bypass=false
        return value
    end

    local function parse(text)
        local out={}
        for name,raw in (text or ''):gmatch('([^\t\r\n]+)\t([^\t\r\n]+)') do
            local number=tonumber(raw)
            if KIND[name] and number and number==number and math.abs(number)<=1e6 then out[name]=number end
        end
        return out
    end
    if settings then
        local text=readFile(settings)
        if not text then
            text=readFile(previousSettings)
            if text then
                local restored=fileOps.rename(previousSettings,settings)
                say('恢复上次设置 读回='..tostring(restored and readFile(settings)==text or false))
            end
        end
        if text and text:find('^AIParamsV1') then self.values=parse(text:gsub('^[^\n]*\n','',1)) end
    end
    local function saveSettings(text)
        local staged=settings..'.pending'
        local file=io.open(staged,'w')
        if not file then return false end
        local wrote=file:write(text)
        local closed=file:close()
        if not wrote or not closed or readFile(staged)~=text then
            fileOps.remove(staged)
            return false
        end
        local hadPrevious=readFile(settings)~=nil
        if hadPrevious then
            fileOps.remove(previousSettings)
            if not fileOps.rename(settings,previousSettings) then
                fileOps.remove(staged)
                return false
            end
        end
        if not fileOps.rename(staged,settings) then
            if hadPrevious then fileOps.rename(previousSettings,settings) end
            fileOps.remove(staged)
            return false
        end
        local saved=readFile(settings)==text
        if saved then fileOps.remove(previousSettings) end
        return saved
    end
    local function count()
        local n=0
        for _ in pairs(self.values)do n=n+1 end
        return n
    end

    -- The fallback: the Find functions answer for this mod's units.
    local function answer(_,controller,name)
        if bypass or not self.alive or not next(controllers) then return nil end
        local c=U.unwrap(controller)
        local key=addr(c)
        if not key or not controllers[key] then return nil end
        local ok,text=pcall(function()return U.unwrap(name):ToString()end)
        local value=ok and self.values[text]
        if value==nil or value==false then return nil end
        return wire(KIND[text],value)
    end
    local function hook()
        if self.hooked or type(RegisterHook)~='function' then return end
        self.hooked=true
        for _,fn in pairs(FIND)do
            local ok,pre,post=pcall(RegisterHook,HOOKS..fn,answer,function()end)
            if ok and type(pre)=='number' then hooks[fn]={pre=pre,post=post}
            else say('挂钩失败 '..fn..'：'..tostring(pre)) end
        end
        say('写入没读回，改用挂钩回答参数读取 挂钩数='..(next(hooks) and 3 or 0))
    end
    local function unhook()
        for fn,h in pairs(hooks)do pcall(UnregisterHook,HOOKS..fn,h.pre,h.post) end
        hooks={};self.hooked=false
    end

    -- A parameter name that does not survive FName would read back from its own wrong key and look fine, so the names are
    -- checked once; without them only the hook can answer (it compares the game's FName as text).
    local namesChecked,namesBroken=false,false
    local function checkNames()
        if namesChecked then return end
        namesChecked=true
        local sample=Params.fields[1][1]
        local ok,text=pcall(function()return fname(sample):ToString()end)
        namesBroken=not ok or text~=sample
        say('参数名读回 写='..sample..' 读='..tostring(text)..' 一致='..tostring(not namesBroken))
        if namesBroken then hook() end
    end
    local function mapOf(unit,kind)
        return U.struct(U.field(unit.comp,'MergedParameterCollection'),MAP[kind])
    end
    local function readEntry(unit,name)
        local kind=KIND[name]
        local ok,value=pcall(function()
            local map,key=mapOf(unit,kind),fname(name)
            local present=map:Contains(key)
            if present==false and type(map.Remove)=='function' then return ABSENT end
            if present~=true then return nil end
            return U.unwrap(map:Find(key))
        end)
        if not ok then return nil end
        if value==ABSENT then return value end
        if kind=='bool' then
            if type(value)=='boolean' or value==0 or value==1 then return value==true or value==1 end
        elseif type(value)=='number' then return value end
    end
    local function writeEntry(unit,name,value)
        return pcall(function()
            local map,key=mapOf(unit,KIND[name]),fname(name)
            if value==ABSENT then map:Remove(key) else map:Add(key,value) end
        end)
    end
    local function describeEntry(value)
        return value==ABSENT and '无条目' or tostring(value)
    end
    local function write(unit,library,name,value)
        local kind=KIND[name]
        local wanted=wire(kind,value)
        if namesBroken then return true,'挂钩回答',false,'参数名用不了' end
        if self.hooked then
            local back=find(library,unit.controller,name)
            return same(kind,back,wanted),back,false,'已改用挂钩'
        end
        if unit.original[name]==nil then
            local before=readEntry(unit,name)
            if before==nil then return false,nil,false,'原条目不可读' end
            unit.original[name]=before
        end
        local ok,err=writeEntry(unit,name,wanted)
        local back=find(library,unit.controller,name)
        return same(kind,back,wanted),back,ok,err
    end
    local function apply(unit,library)
        local done,bad=0,0
        for name,value in pairs(self.values)do
            local good,back,called,err=write(unit,library,name,value)
            if not good and not self.hooked then
                hook()
                back=find(library,unit.controller,name)
                good=same(KIND[name],back,wire(KIND[name],value))
                err='写表没读回，已改用挂钩'
                called=false
            end
            if good then done=done+1 else bad=bad+1 end
            if lines<APPLY_LINES then
                lines=lines+1
                local original=unit.original[name]
                if original==nil and not namesBroken then original=gameValue(library,unit.controller,name) end
                say(string.format('%s %s 原值=%s -> 目标=%s 写表=%s%s 读回=%s 结果=%s',unit.name,name,describeEntry(original),tostring(value),tostring(called),
                    called and '' or '('..tostring(err)..')',tostring(back),good and '生效' or '没生效'))
            end
        end
        unit.restorePending=false
        for name,before in pairs(unit.original)do
            if self.values[name]==nil then
                -- Restore the map even if a later override had to fall back to the hook.
                local called=writeEntry(unit,name,before)
                local back=readEntry(unit,name)
                local verified=back==before or (back~=ABSENT and before~=ABSENT and same(KIND[name],back,before))
                if verified then
                    unit.original[name]=nil
                else
                    unit.restorePending=true
                    bad=bad+1
                end
                if lines<APPLY_LINES then
                    lines=lines+1
                    say(string.format('%s %s 恢复原值=%s 调用=%s 读回=%s 已确认=%s',unit.name,name,describeEntry(before),
                        tostring(called),describeEntry(back),tostring(verified)))
                end
            end
        end
        self.applied=self.applied+done;self.failures=self.failures+bad
        unit.generation=self.generation
    end
    local function drifted(unit,library)
        for name,value in pairs(self.values)do
            if not same(KIND[name],find(library,unit.controller,name),wire(KIND[name],value)) then return true end
        end
        return false
    end
    local function probe(unit,library)
        if classes[unit.name] or classLines>=CLASS_LINES then return end
        classes[unit.name]=true;classLines=classLines+1
        local parts={}
        for _,name in ipairs(PROBE)do parts[#parts+1]=name..'='..tostring(gameValue(library,unit.controller,name)) end
        say('读回 '..unit.name..' 游戏给的 '..table.concat(parts,' '))
    end
    local function tension(now)
        if not options.tension or now<tensionAt or tensionLines>=TENSION_LINES then return end
        tensionAt=now+TENSION_SECONDS
        local ok,lib2,world=pcall(options.tension)
        if not ok or not U.valid(lib2) or not U.valid(world) then return end
        for _,unit in pairs(units)do
            if U.valid(unit.actor) then
                local okA,active=pcall(function()return lib2:HasActiveSession(world)end)
                local okR,read=pcall(function()return lib2:GetTensionReadout(world,unit.actor)end)
                tensionLines=tensionLines+1
                local raw=okR and U.struct(read,'Raw') or nil
                say(string.format('压力值 %s 会话=%s Raw=%s Confidence=%s 峰值10秒=%s',unit.name,okA and tostring(active) or '?',tostring(raw),
                    okR and tostring(U.struct(read,'Confidence')) or '?',okR and tostring(U.struct(read,'PeakLast10s')) or '?'))
                return
            end
        end
    end

    -- Revision in the panel's command; the values are in Runtime/ai-params-request.tsv.
    function self:setRequest(revision)
        local text=request and readFile(request)
        local rev,body=(text or ''):match('^AIParamsV1\t(%S+)\n(.*)$')
        if not rev or rev~=revision then
            local message='AI 参数文件和这条指令对不上 指令='..tostring(revision)..' 文件='..tostring(rev)
            say(message)
            return {ok=false,message=message,spawned_count=0}
        end
        self.values=parse(body)
        self.generation=self.generation+1
        local saved=true
        if settings then
            local out={'AIParamsV1'}
            for name,value in pairs(self.values)do out[#out+1]=name..'\t'..string.format('%.17g',value) end
            saved=saveSettings(table.concat(out,'\n')..'\n')
        end
        lines=0
        self.message=count()>0 and ('已改 '..count()..' 项') or '全部用游戏原值'
        say('收到 '..count()..' 项，场上和之后召唤的单位都会用（revision='..tostring(revision)..'）保存读回='..tostring(saved))
        nextAt=0
        return {ok=saved,message=saved and self.message or self.message..'，但保存未确认，重启后可能恢复上次设置',spawned_count=0}
    end

    function self:tick()
        if not self.alive then return end
        local now=clock()
        if now<nextAt then return end
        nextAt=now+SECONDS
        local library=lib()
        if not library then return end
        checkNames()
        local seen={}
        controllers={}
        for _,member in ipairs(options.members() or {})do
            local actor=member.actor
            local key=U.valid(actor) and U.key(actor)
            if key then
                seen[key]=true
                local unit=units[key]
                if not unit then
                    unit={actor=actor,name=className(actor),original={},generation=-1,retries=0}
                    units[key]=unit
                end
                local comp=unit.comp
                if not U.valid(comp) then
                    comp=options.aiComp(actor)
                    unit.comp=comp
                    unit.original={}
                    unit.generation=-1
                end
                if U.valid(comp) and U.field(comp,'bAIStarted')==true then
                    local controller=U.field(comp,'AIController')
                    if U.valid(controller) then
                        unit.controller=controller
                        local caddr=addr(controller)
                        if caddr then controllers[caddr]=true end
                        probe(unit,library)
                        if unit.generation~=self.generation then
                            unit.retries=0
                            apply(unit,library)
                        elseif unit.retries<RETRIES and (unit.restorePending or (next(self.values) and drifted(unit,library))) then
                            unit.retries=unit.retries+1;self.rewritten=self.rewritten+1
                            apply(unit,library)
                        end
                    end
                end
            end
        end
        for key in pairs(units)do if not seen[key] then units[key]=nil end end
        if next(seen) then tension(now) end
    end
    function self:status()return {count=count(),applied=self.applied,failures=self.failures,rewritten=self.rewritten,hooked=self.hooked,message=self.message} end
    function self:silence()unhook();self.alive=false end
    return self
end
return Params
