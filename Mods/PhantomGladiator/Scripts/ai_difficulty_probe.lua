-- Read-only AI difficulty probe. Answers whether Hellwalker's AI can follow a single summoned unit.
-- 1. Once a map is loaded: which parts of GlobalConfig_Combined_<difficulty> differ between the five
--    difficulties. The three sub-configs and every reflected field on them are compared
--    (PDA_GlobalConfig_Combined.hpp, PDA_GlobalCombatConfig.hpp, PDA_GlobalMechanicConfig.hpp,
--    PDA_GlobalTechnicalConfig.hpp), and each Combat config's OverrideAIParameters is listed
--    (SGameAI.hpp FSGameAIParameterCollection).
-- 2. While an arena fight runs, a bounded window shows who asks for the difficulty: the blueprint
--    behaviour-tree check BTDecorator_SwitchDifficulty_C and
--    UPBZBlueprintFunctionLibrary.GetDiffcultMode/GetDifficulty, with the pawn or context object of
--    each call and whether it belongs to the app's units.
-- Hooks only count and log; they never return a value or write a field.
local U=require('ue_observe')
local Probe={}
local DIFFICULTIES={'Handicapped','Easy','Normal','Hard','Nightmare'}
local SUBCONFIGS={'Combat Config','Mechanic Config','Technical Config'}
local AI_MAPS={'BoolParameters','IntParameters','FloatParameters','VectorParameters','RotatorParameters','ObjectParameters',
    'InstancedObjectParameters','ClassParameters','EnumParameters','StringParameters','NameParameters'}
local DECORATOR='/PBZCombatAsset/Prototypes/AI/BTDecorator_SwitchDifficulty.BTDecorator_SwitchDifficulty_C:PerformConditionCheckAI'
local LIBRARY='/Script/ProjectPBZ.PBZBlueprintFunctionLibrary:'
local WINDOW_SECONDS,MAX_LINES,MAX_TEXT=150,60,360
local function assetPath(name)return '/PBZCombatAsset/Config/GlobalConfig_Combined_'..name..'.GlobalConfig_Combined_'..name end
local function clip(s,limit)s=tostring(s);limit=limit or MAX_TEXT;return #s<=limit and s or s:sub(1,limit)..'…' end

local function objectName(object)
    local ok,full=pcall(function()return object:GetFullName()end)
    if ok and type(full)=='string' then return full:match('^%S+ (.+)$') or full end
    return U.kind(object)
end
local function className(object)
    if not U.valid(object) then return 'invalid' end
    local ok,class=pcall(function()return object:GetClass()end)
    if not ok or not U.valid(class) then return objectName(object) end
    local okName,name=pcall(function()return class:GetFName():ToString()end)
    return okName and type(name)=='string' and name or objectName(class)
end

-- A comparable text for one reflected value; maps and arrays list their entries (capped).
local text
local function entries(v,limit)
    local parts,count={},0
    local ok=pcall(function()
        v:ForEach(function(a,b)
            count=count+1
            if count<=limit then
                if b==nil then parts[#parts+1]=text(a,1) else parts[#parts+1]=text(a,1)..'='..text(b,1) end
            end
        end)
    end)
    if not ok then return nil end
    table.sort(parts)
    return parts,count
end
text=function(v,depth)
    v=U.unwrap(v);depth=depth or 0
    if v==nil then return 'nil' end
    if type(v)=='number' then return string.format('%.6g',v) end
    if type(v)=='boolean' or type(v)=='string' then return tostring(v) end
    local kind=U.kind(v)
    if kind=='TArray' or kind=='TMap' or kind=='TSet' then
        if depth>0 then return kind end
        local parts,count=entries(v,30)
        if not parts then return kind..'?' end
        return kind..'['..count..']{'..table.concat(parts,',')..'}'
    end
    local tag=U.struct(v,'TagName')
    if tag~=nil then return text(tag,depth) end
    local attribute=U.struct(v,'AttributeName')
    if attribute~=nil then return text(attribute,depth) end
    if U.valid(v) then return objectName(v) end
    local ok,s=pcall(function()return v:ToString()end)
    if ok and type(s)=='string' then return s end
    return kind
end
Probe.text=text

local function properties(object)
    local names,seen={},{}
    local ok,class=pcall(function()return object:GetClass()end)
    for _=1,4 do
        if not ok or not U.valid(class) then break end
        pcall(function()
            class:ForEachProperty(function(property)
                local okName,name=pcall(function()return property:GetFName():ToString()end)
                if okName and type(name)=='string' and not seen[name] then seen[name]=true;names[#names+1]=name end
            end)
        end)
        ok,class=pcall(function()return class:GetSuperStruct()end)
    end
    return names
end

function Probe.new(options)
    local log=options.log or function()end
    local clock=options.clock or os.time
    local self={configsDone=false,state='idle',alive=true,token=0}
    local function say(message)log('[AIDifficulty] '..message)end
    local hooks,tally,logged,cache={},{},{},{}
    local lines,calls,startedAt,uncertain=0,{},nil,false

    local function config(name)
        local path=assetPath(name)
        local object=StaticFindObject(path)
        local resident=U.valid(object)
        if not resident and options.load then
            local ok,value=pcall(LoadAsset,path)
            object=ok and value or nil
        end
        say(name..' Combined 已在内存='..tostring(resident)..' 可读='..tostring(U.valid(object)))
        return U.valid(object) and object or nil
    end

    function self:compareConfigs()
        say('开始只读对比5档 GlobalConfig_Combined：子配置引用、逐字段差异、OverrideAIParameters；不写任何游戏对象')
        local combined={}
        for _,name in ipairs(DIFFICULTIES)do combined[name]=config(name)end
        for _,sub in ipairs(SUBCONFIGS)do
            local objects,refs={}, {}
            for _,name in ipairs(DIFFICULTIES)do
                local value=combined[name] and U.field(combined[name],sub)
                objects[name]=U.valid(value) and value or nil
                refs[#refs+1]=name..'='..(objects[name] and objectName(objects[name]) or 'nil')
            end
            say(sub..' 引用：'..table.concat(refs,' | '))
            local first=objects.Easy or objects.Normal or objects.Hard
            if first then
                local same,different,skipped=0,0,{}
                for _,field in ipairs(properties(first))do
                    local texts,distinct,last={},0,nil
                    -- Structs have no generic reader; OverrideAIParameters is listed in full below.
                    local sample=U.field(first,field)
                    local kind=U.kind(sample)
                    if kind=='UScriptStruct' or (kind=='table' and not U.valid(sample)) then skipped[#skipped+1]=field;distinct=-1 end
                    for _,name in ipairs(DIFFICULTIES)do
                        -- U.field also returns its read flag; keep only the value.
                        local value=objects[name] and text((U.field(objects[name],field))) or 'nil'
                        if distinct>=0 then
                            texts[#texts+1]=name..'='..clip(value)
                            if value~=last then distinct=distinct+1;last=value end
                        end
                    end
                    if distinct<0 then
                    elseif distinct>1 then
                        different=different+1
                        say('  差异 '..sub..'.'..field..'：'..table.concat(texts,' | '))
                    else same=same+1 end
                end
                say(sub..' 字段相同='..same..' 不同='..different..' 未比较='..#skipped..(#skipped>0 and '（'..table.concat(skipped,',')..'）' or ''))
            end
            if sub=='Combat Config' then
                for _,name in ipairs(DIFFICULTIES)do
                    local params=objects[name] and U.field(objects[name],'OverrideAIParameters')
                    local filled={}
                    for _,map in ipairs(AI_MAPS)do
                        local value=U.struct(params,map)
                        if value~=nil then
                            local parts,count=entries(U.unwrap(value),40)
                            if parts and count>0 then filled[#filled+1]=map..'['..count..']{'..clip(table.concat(parts,','),600)..'}' end
                        end
                    end
                    say(name..' OverrideAIParameters='..(#filled>0 and table.concat(filled,' ') or '全空'))
                end
            end
        end
    end

    -- Which of the app's units an object belongs to: the pawn itself, its controller, or anything
    -- whose outer chain reaches one of them. Cached per object address for the window.
    local function owner(object)
        local key=U.key(object)
        if not key then return nil,'invalid' end
        local hit=cache[key]
        if hit then return hit.owner,hit.class end
        local units=self.units or {}
        local found
        local current=object
        for _=1,8 do
            if not U.valid(current) then break end
            local k=U.key(current)
            if units[k] then found=units[k];break end
            local okPawn,pawn=pcall(function()return current:K2_GetPawn()end)
            if okPawn and U.valid(pawn) and units[U.key(pawn)] then found=units[U.key(pawn)];break end
            local okOuter,outer=pcall(function()return current:GetOuter()end)
            if not okOuter then break end
            current=outer
        end
        hit={owner=found,class=className(object)}
        cache[key]=hit
        return hit.owner,hit.class
    end
    local function record(kind,detail,signature)
        calls[kind]=(calls[kind] or 0)+1
        tally[signature]=(tally[signature] or 0)+1
        if not logged[signature] and lines<MAX_LINES then
            logged[signature]=true;lines=lines+1
            say('首次 '..kind..' '..detail)
        end
    end

    local function onDecorator(token)
        return function(context,controller,pawn)
            if not self.alive or token~=self.token or self.state~='running' then return end
            local decorator=U.unwrap(context);pawn=U.unwrap(pawn)
            local difficulty=U.field(decorator,'Difficulty')
            local ours,class=owner(pawn)
            local label=ours or '否'
            local signature='decorator|'..class..'|'..tostring(difficulty)..'|'..label
            if logged[signature] then calls.decorator=(calls.decorator or 0)+1;tally[signature]=tally[signature]+1;return end
            local outer='?'
            pcall(function()outer=objectName(decorator:GetOuter())end)
            record('decorator','行为树难度节点 pawn='..class..' 本Mod单位='..label..' 节点难度='..tostring(difficulty)
                ..' 节点='..objectName(decorator)..' 外层='..outer,signature)
        end
    end
    local function onLibrary(name,token)
        return function(_,contextObject)
            if not self.alive or token~=self.token or self.state~='running' then return end
            local object=U.unwrap(contextObject)
            local ours,class=owner(object)
            local label=ours or '否'
            local signature=name..'|'..class..'|'..label
            if logged[signature] then calls[name]=(calls[name] or 0)+1;tally[signature]=tally[signature]+1;return end
            record(name,'函数库难度查询 '..name..' 上下文='..class..' 本Mod单位='..label..' 对象='..objectName(object),signature)
        end
    end

    local function install(name,path,script,callback)
        local okFind,found=pcall(StaticFindObject,path)
        if not okFind or not U.valid(found) then say('挂钩暂不可用（函数未加载）'..name);return false end
        local ok,pre,post
        if script then ok,pre,post=pcall(RegisterHook,path,callback)
        else ok,pre,post=pcall(RegisterHook,path,callback,function()end) end
        if ok and type(pre)=='number' and type(post)=='number' then
            hooks[#hooks+1]={name=name,path=path,pre=pre,post=post}
            say('挂钩注册ID读回 '..name..' pre='..pre..' post='..post..'（待实际回调验证）')
            return true
        end
        if ok then uncertain=true end
        say('挂钩注册失败或ID不明 '..name..'：'..clip(pre,160))
        return false
    end

    local function summary(reason)
        say('窗口结束 reason='..reason..' 行为树节点调用='..(calls.decorator or 0)..' GetDiffcultMode调用='..(calls.GetDiffcultMode or 0)
            ..' GetDifficulty调用='..(calls.GetDifficulty or 0)..' 挂钩='..#hooks)
        local rows={}
        for signature,count in pairs(tally)do rows[#rows+1]={signature,count}end
        table.sort(rows,function(a,b)return a[2]>b[2]end)
        for i=1,math.min(40,#rows)do say('  计数 '..rows[i][2]..' × '..rows[i][1])end
        say('读回说明：零回调不证明该路径不执行；原生C++直接调用不经过这些挂钩。')
    end
    function self:stop(reason)
        if self.state~='running' then return end
        self.state='done'
        local remaining={}
        for _,hook in ipairs(hooks)do
            local ok,err=pcall(UnregisterHook,hook.path,hook.pre,hook.post)
            if not ok then remaining[#remaining+1]=hook;say('注销失败（回调已静默）'..hook.name..'：'..clip(err,160))end
        end
        hooks=remaining
        summary(reason)
    end
    function self:silence(reason)
        self.alive=false
        if self.state=='running' then self.state='done';summary(reason or 'Mod卸载') end
    end

    local function start()
        for _,name in ipairs({'StaticFindObject','RegisterHook','UnregisterHook'})do
            if type(_G[name])~='function' then self.state='done';say('未启动：缺少 '..name);return end
        end
        self.token=self.token+1
        self.state='running';startedAt=clock()
        say('开战后只读观察窗口开始，'..WINDOW_SECONDS..'秒；只计数和记录调用者，不改返回值')
        install('decorator',DECORATOR,true,onDecorator(self.token))
        install('GetDiffcultMode',LIBRARY..'GetDiffcultMode',false,onLibrary('GetDiffcultMode',self.token))
        install('GetDifficulty',LIBRARY..'GetDifficulty',false,onLibrary('GetDifficulty',self.token))
        if #hooks==0 or uncertain then self:stop(#hooks==0 and '没有可用挂钩' or '注册ID不明') end
    end

    function self:tick()
        if not self.alive then return end
        if options.ready and not options.ready() then return end
        if not self.configsDone then
            self.configsDone=true
            local ok,err=pcall(function()self:compareConfigs()end)
            say('配置对比完成='..tostring(ok)..(ok and '' or ' 错误='..clip(err,200)))
        end
        local units={}
        for _,entry in ipairs(options.members and options.members() or {})do
            local key=U.key(entry.actor)
            if key then
                local level=options.levelOf and options.levelOf(entry.actor) or '游戏难度'
                units[key]=tostring(entry.team)..'/'..level
            end
        end
        self.units=units
        if self.state=='idle' and options.active and options.active() and next(units) then start()
        elseif self.state=='running' and clock()-startedAt>=WINDOW_SECONDS then self:stop('时间到') end
    end
    return self
end
return Probe
