-- The combat XuKong finds MengHua by class on BeginPlay and OnDead. A direct arena spawn
-- skips that lookup for its own instance, so it cannot claim or clear the story partner.
local U=require('ue_observe')
local Standalone={}
local LOOKUP='/Script/Engine.GameplayStatics:GetActorOfClass'
local XUKONG='/PBZCombatAsset/ActorData/Mobs/079_XuKong/BP_Monster_XuKong.BP_Monster_XuKong_C'
local MENGHUA='/PBZCombatAsset/ActorData/Mobs/078_MengHua/BP_Monster_MengHua.BP_Monster_MengHua_C'
local MENGHUA_FOLDED=MENGHUA:lower()

local function fullName(object)
    if not U.valid(object) then return nil end
    local ok,name=pcall(function()return object:GetFullName()end)
    return ok and type(name)=='string' and name or nil
end

function Standalone.new(options)
    local find=options.staticFind or StaticFindObject
    local register=options.registerHook or RegisterHook
    local createInvalid=options.createInvalidObject or CreateInvalidObject
    local inGameThread=options.inGameThread or IsInGameThread
    local owned={}
    local alive,installed=true,false
    local nullActor
    local self={}
    local function say(message)options.log('[XuKong] '..message)end
    local function lookup(_,context,actorClass)
        if not alive or not next(owned) or (type(inGameThread)=='function' and not inGameThread()) then return end
        local actor=U.unwrap(context)
        local key=U.key(actor)
        local entry=key and owned[key]
        if not entry or fullName(actor)~=entry.name then return end
        local name=fullName(U.unwrap(actorClass))
        local path=name and name:match('^%S+ (/.+)$')
        if not path or path:lower()~=MENGHUA_FOLDED then return end
        entry.lookups=entry.lookups+1
        return nullActor
    end

    function self:prepare(actor)
        if not alive or U.npcPath(actor)~=XUKONG then return nil,'虚空战斗类未读回' end
        local key,name=U.key(actor),fullName(actor)
        if not key or not name then return nil,'虚空对象未读回' end
        local statics=options.statics()
        local found,dream=pcall(find,MENGHUA)
        if not U.valid(statics) or not found or not U.valid(dream) then
            say('独立初始化未确认，查找接口或梦华类不可读')
            return nil,'无法验证虚空与梦华的拆分'
        end
        if not installed then
            local created,empty=pcall(createInvalid)
            if not created or empty==nil or U.valid(empty) then
                say('空 Actor 回传对象未读回')
                return nil,'虚空拆分需要 UE4SS 的空 Actor 回传接口'
            end
            nullActor=empty
            local registered,pre,post=pcall(register,LOOKUP,lookup)
            installed=registered and type(pre)=='number' and type(post)=='number'
            say('查找挂钩注册读回='..tostring(installed)..(installed and ' ID='..pre..'/'..post or ''))
            if not installed then return nil,'虚空拆分挂钩注册未确认' end
        end
        local entry={name=name,lookups=0}
        owned[key]=entry
        -- Verify the real return slot for this deferred actor before its story BeginPlay runs.
        local called,result=pcall(function()return statics:GetActorOfClass(actor,dream)end)
        local returnedActor=called and U.valid(U.unwrap(result))
        local confirmed=called and not returnedActor and entry.lookups==1
        say('拆分探测 '..name..' 调用='..tostring(called)..' 返回梦华='..tostring(returnedActor)
            ..' 回调次数='..entry.lookups..' 确认='..tostring(confirmed))
        if not confirmed then
            owned[key]=nil
            return nil,'虚空拆分读回未确认'
        end
        entry.lookups=0
        return entry
    end

    function self:verify(entry)
        say('独立生成读回 '..entry.name..' 剧情查找被拦截次数='..entry.lookups)
        return entry.lookups>0
    end

    function self:prune(units)
        if not next(owned) then return end
        local retained={}
        for _,unit in ipairs(units)do
            if unit.class_path==XUKONG then
                local key=U.key(unit.actor)
                local entry=key and owned[key]
                if entry and fullName(unit.actor)==entry.name then retained[key]=entry end
            end
        end
        owned=retained
    end

    function self:silence()
        alive=false
        owned={}
    end
    return self
end

return Standalone
