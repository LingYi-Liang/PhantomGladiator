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
    return U.className(object) or '?'
end
local function addr(object)
    if object==nil then return nil end
    local ok,key=pcall(function()if object:IsValid() then return object:GetAddress() end end)
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
    local names={}
    local function fname(name)
        if names[name]==nil then names[name]=FName(name)end
        return names[name]
    end
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
    local requested,retryHook={},{}
    local hookVersion,auditStart=0,1
    local witness,witnessName,answered
    local function checkedValue(unit,library,name)
        witness,witnessName,answered=unit,name,false
        local back=find(library,unit.controller,name)
        local observed=answered
        witness,witnessName,answered=nil,nil,false
        return back,observed
    end
    local function answer(kind,controller,name)
        if bypass or not self.alive or not next(controllers) then return nil end
        if type(IsInGameThread)=='function' and not IsInGameThread() then return nil end
        local c=U.unwrap(controller)
        local key=addr(c)
        local unit=key and controllers[key]
        if not unit then return nil end
        local ok,text=pcall(function()return U.unwrap(name):ToString()end)
        local value=ok and unit.values[text]
        if value==nil or value==false or KIND[text]~=kind then return nil end
        if not U.valid(c) then return nil end
        local read,pawn=pcall(function()return U.unwrap(c.Pawn)end)
        if not read or U.key(pawn)~=unit.key then return nil end
        if unit.identity then
            local got,full=pcall(function()return pawn:GetFullName()end)
            if not got or full~=unit.identity then return nil end
        end
        if unit.private then
            if addr(U.field(unit.comp,'AIController'))~=key then return nil end
            local current,values=pcall(options.privateValues,unit.actor)
            if not current or values~=unit.values then return nil end
        end
        if unit==witness and text==witnessName then answered=true end
        return wire(kind,value)
    end
    local function hook(kind,now)
        requested[kind]=true
        if hooks[kind] then hooks[kind].active=true;return true end
        if now<(retryHook[kind] or 0) or type(RegisterHook)~='function' then return false end
        local h={}
        local ok,pre,post=pcall(RegisterHook,HOOKS..FIND[kind],function(_,controller,name)
            if h.active then return answer(kind,controller,name)end
        end,function()end)
        if ok and type(pre)=='number' and type(post)=='number' then
            h.pre,h.post,h.active=pre,post,true;hooks[kind]=h
            retryHook[kind]=nil;hookVersion=hookVersion+1;self.hooked=true
            say('参数挂钩注册读回 '..FIND[kind]..' pre='..pre..' post='..post)
            return true
        end
        retryHook[kind]=now+3;say('挂钩未确认 '..FIND[kind]..'：'..tostring(pre))
        return false
    end
    local function retire(kind,now)
        requested[kind]=nil;retryHook[kind]=nil
        local h=hooks[kind]
        if not h then return end
        h.active=false
        if now<(h.releaseAt or 0) then return end
        local ok,result=pcall(UnregisterHook,HOOKS..FIND[kind],h.pre,h.post)
        if ok and result~=false then hooks[kind]=nil else h.releaseAt=now+3 end
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
    local function write(unit,library,name,value,now)
        local kind=KIND[name]
        local wanted=wire(kind,value)
        local called,err=false,'已改用挂钩'
        if not namesBroken and not (hooks[kind] and hooks[kind].active) then
            if unit.original[name]==nil then unit.original[name]=readEntry(unit,name) end
            if unit.original[name]~=nil then
                called,err=writeEntry(unit,name,wanted)
                local back=find(library,unit.controller,name)
                if same(kind,back,wanted) then return true,back,called,err,false end
            end
            called,err=false,'写表没读回，已改用挂钩'
        end
        if not hook(kind,now) then return false,nil,false,'参数挂钩未就绪',false end
        if namesBroken then return false,nil,false,'等游戏使用原参数名',false end
        local back,observed=checkedValue(unit,library,name)
        return same(kind,back,wanted),back,called,err,observed
    end
    local function restoreRemoved(unit,now)
        local bad=0
        for name,before in pairs(unit.original)do
            if unit.values[name]==nil then
                local called=writeEntry(unit,name,before)
                local back=readEntry(unit,name)
                local verified=back==before or (back~=ABSENT and before~=ABSENT and same(KIND[name],back,before))
                if verified then unit.original[name]=nil else bad=bad+1 end
                if lines<APPLY_LINES then
                    lines=lines+1
                    say(string.format('%s %s 恢复原值=%s 调用=%s 读回=%s 已确认=%s',unit.name,name,describeEntry(before),tostring(called),describeEntry(back),tostring(verified)))
                end
            end
        end
        if bad==0 then unit.restoreAt=nil;unit.restoreDelay=nil
        else
            unit.restoreDelay=math.min(30,(unit.restoreDelay or .5)*2)
            unit.restoreAt=now+unit.restoreDelay
        end
        return bad
    end
    local function apply(unit,library,now)
        local done,bad=0,0
        unit.audit={};unit.auditIndex=1;unit.repairs={}
        for _,field in ipairs(Params.fields)do
            local name=field[1];local value=unit.values[name]
            if value~=nil then
                local good,back,called,err,observed=write(unit,library,name,value,now)
                if good then done=done+1 else bad=bad+1 end
                if not (observed and good) and not namesBroken then unit.audit[#unit.audit+1]=name end
                if lines<APPLY_LINES then
                    lines=lines+1
                    local original=unit.original[name]
                    if original==nil and not namesBroken then original=gameValue(library,unit.controller,name) end
                    say(string.format('%s %s 原值=%s -> 目标=%s 写表=%s%s 读回=%s 结果=%s',unit.name,name,describeEntry(original),tostring(value),tostring(called),
                        called and '' or '('..tostring(err)..')',tostring(back),good and '生效' or '没生效'))
                end
            end
        end
        bad=bad+restoreRemoved(unit,now)
        self.applied=self.applied+done;self.failures=self.failures+bad
        unit.generation,unit.hookVersion=self.generation,hookVersion
    end
    local function auditUnits(list,library,now)
        if #list==0 then auditStart=1;return end
        local remaining=32
        local index=(auditStart-1)%#list+1
        for _=1,#list do
            local unit=list[index]
            index=index%#list+1
            local fields=unit.audit
            for _=1,math.min(#fields,8,remaining)do
                local slot=unit.auditIndex;local name=fields[slot]
                remaining=remaining-1
                local finished=false
                if not same(KIND[name],find(library,unit.controller,name),wire(KIND[name],unit.values[name])) then
                    local tries=(unit.repairs[name] or 0)+1;unit.repairs[name]=tries
                    local good,_,_,_,observed=write(unit,library,name,unit.values[name],now)
                    self.rewritten=self.rewritten+1
                    if good then self.applied=self.applied+1 else self.failures=self.failures+1 end
                    finished=(good and observed) or tries>=RETRIES
                end
                if finished then
                    table.remove(fields,slot)
                    if #fields==0 then unit.auditIndex=1;break end
                    unit.auditIndex=slot<=#fields and slot or 1
                else
                    unit.auditIndex=slot%#fields+1
                end
            end
            if remaining==0 then break end
        end
        auditStart=index
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
        local members=options.members() or {}
        controllers={}
        if #members==0 then
            units={}
            for kind in pairs(FIND)do retire(kind,now) end
            self.hooked=false;return
        end
        local library=lib()
        if not library then return end
        checkNames()
        local seen,inUse,audits={},{},{}
        for _,member in ipairs(members)do
            local actor=member.actor;local key=U.key(actor)
            if key and not seen[key] then
                seen[key]=true
                local okName,identity=pcall(function()return actor:GetFullName()end)
                identity=okName and identity or nil
                local unit=units[key]
                if not unit or unit.identity~=identity then
                    unit={actor=actor,key=key,name=className(actor),identity=identity,original={},generation=-1}
                    units[key]=unit
                end
                unit.actor=actor
                local profileValues=options.privateValues and options.privateValues(actor)
                local values=profileValues or self.values
                unit.private=profileValues~=nil
                if unit.values~=values then
                    unit.values=values;unit.generation=-1;unit.kinds={}
                    for name in pairs(values)do
                        local kind=KIND[name];if kind then unit.kinds[kind]=true end
                    end
                end
                local comp=options.aiComp(actor)
                local componentKey=U.key(comp)
                if componentKey~=unit.componentKey then
                    unit.componentKey=componentKey;unit.original={};unit.generation=-1
                    unit.restoreAt=nil;unit.restoreDelay=nil
                end
                unit.comp=comp
                if componentKey and U.field(comp,'bAIStarted')==true then
                    local controller=U.field(comp,'AIController')
                    local controllerKey=U.key(controller)
                    if controllerKey and U.key(U.field(controller,'Pawn'))==key then
                        if controllerKey~=unit.controllerKey then unit.generation=-1 end
                        unit.controller,unit.controllerKey=controller,controllerKey
                        if next(values) then
                            controllers[controllerKey]=unit
                            for kind in pairs(unit.kinds)do inUse[kind]=true end
                        end
                        for kind in pairs(requested)do
                            if inUse[kind] and not (hooks[kind] and hooks[kind].active) then hook(kind,now) end
                        end
                        probe(unit,library)
                        if unit.generation~=self.generation or unit.hookVersion~=hookVersion then
                            apply(unit,library,now)
                        else
                            if unit.restoreAt and now>=unit.restoreAt then
                                self.failures=self.failures+restoreRemoved(unit,now)
                            end
                            if #unit.audit>0 then audits[#audits+1]=unit end
                        end
                    else unit.controllerKey=nil end
                else unit.controllerKey=nil end
            end
        end
        for key in pairs(units)do if not seen[key] then units[key]=nil end end
        self.hooked=false
        for kind in pairs(FIND)do
            if not inUse[kind] or (hooks[kind] and not hooks[kind].active and not requested[kind]) then retire(kind,now)
            elseif hooks[kind] and hooks[kind].active then self.hooked=true end
        end
        auditUnits(audits,library,now)
        if next(seen) then tension(now) end
    end
    function self:status()return {count=count(),applied=self.applied,failures=self.failures,rewritten=self.rewritten,hooked=self.hooked,message=self.message} end
    function self:silence(onGameThread)
        self.alive=false;controllers={}
        if onGameThread==nil then
            local ok,gameThread=pcall(IsInGameThread)
            onGameThread=ok and gameThread==true
        end
        for kind,h in pairs(hooks)do
            h.active=false
            if onGameThread then retire(kind,math.huge) end
        end
        self.hooked=false
    end
    return self
end
return Params
