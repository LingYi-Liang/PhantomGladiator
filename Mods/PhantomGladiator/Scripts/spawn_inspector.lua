-- Read-only check of APBZCharacter.CharacterName -> current World spawn mapping.
-- ProjectPBZ.hpp:4018,13175-13186. Never guesses a row name or invokes Spawn/PostSpawn.
local Inspector={}
function Inspector.new(options)
    options=options or {}
    local function valid(o)
        if o==nil then return false end
        local ok,value=pcall(function() return o:IsValid() end)
        return ok and value==true
    end
    local function read(o,key)
        if not valid(o) then return nil end
        local ok,value=pcall(function() return o[key] end)
        if ok then return value end
    end
    local function call(o,key,...)
        if not valid(o) then return false,nil end
        local args=table.pack(...)
        return pcall(function() return o[key](o,table.unpack(args,1,args.n)) end)
    end
    local function address(o)
        local ok,value=call(o,'GetAddress')
        if ok and (type(value)=='number' or type(value)=='string') then return tostring(value) end
    end
    local function classpath(o)
        local ok,isclass=call(o,'IsAnyClass')
        if not ok or isclass~=true then return nil end
        local named,name=call(o,'GetFullName')
        return named and type(name)=='string' and name:match(' (/.+)$') or nil
    end
    local function log(text)
        if options.log then pcall(options.log,'[SpawnInspect] '..text) end
    end
    local function name(o)
        local ok,value=call(o,'GetFullName')
        return ok and tostring(value) or 'UNKNOWN'
    end
    local function scalar(v)
        return (type(v)=='boolean' or type(v)=='number' or type(v)=='string') and tostring(v) or 'UNKNOWN'
    end
    local instance={}
    function instance:inspect(actor,world)
        if not valid(actor) or not valid(world) then log('UNKNOWN: Actor/World无效'); return false end
        local okDestroy,destroying=call(actor,'IsActorBeingDestroyed')
        if not okDestroy or destroying~=false then log('UNKNOWN: Actor销毁状态不可读或已进入销毁'); return false end
        local okClass,cls=call(actor,'GetClass')
        local path=okClass and classpath(cls)
        local policyOk,allowed=pcall(options.canSpawn,path)
        if not policyOk or allowed~=true then log('未检查未经许可的类'); return false end
        local row=read(actor,'CharacterName')
        local okText,text=pcall(function() return row:ToString() end)
        if not okText or type(text)~='string' or text=='' or text=='None' or text:find('%c') then
            log('读回 CharacterName=UNKNOWN/None；未猜名称，未调用映射'); return false
        end
        log('读取已生成单位 CharacterName='..text..' class='..path)
        local worldID=address(world)
        if not worldID then log('UNKNOWN: World身份未读回'); return false end
        local foundOk,candidates=pcall(options.findAll or FindAllOf,'PBZSpawnSubsystem')
        if not foundOk or type(candidates)~='table' or #candidates>64 then
            log('UNKNOWN: PBZSpawnSubsystem未找到/数量异常'); return false
        end
        local selected,matches,seen=nil,0,{}
        for _,subsystem in ipairs(candidates) do
            local okOuter,outer=call(subsystem,'GetOuter')
            if okOuter and address(outer)==worldID then
                local id=address(subsystem)
                if id and not seen[id] then selected=subsystem; matches=matches+1; seen[id]=true end
            end
        end
        if matches~=1 then log('UNKNOWN: 当前World刷怪子系统匹配数='..matches); return false end
        if not valid(actor) or not valid(world) or not valid(selected) then return false end
        log('操作=当前World PBZSpawnSubsystem:GetNPCClassByName(真实CharacterName)；不调用生成/后处理')
        local called,mapped=call(selected,'GetNPCClassByName',row)
        local mappedPath=called and classpath(mapped) or nil
        local same=mappedPath~=nil and mappedPath==path
        log('映射读回 call='..tostring(called)..' type='..type(mapped)..' class='..tostring(mappedPath or 'UNKNOWN')..' exact_match='..tostring(same))
        return same,text,mappedPath
    end
    function instance:combat(actor,opponent,label)
        if not valid(actor) or not valid(opponent) then return end
        local da,destroyA=call(actor,'IsActorBeingDestroyed')
        local db,destroyB=call(opponent,'IsActorBeingDestroyed')
        if not da or not db or destroyA~=false or destroyB~=false then return end
        local hm=read(actor,'BP_PBZHatredManagerComponent')
        local targetHM=read(opponent,'BP_PBZHatredManagerComponent')
        local canSelf,canTarget=read(hm,'CanBeHatredNow'),read(targetHM,'CanBeHatredNow')
        local gate1,g1=call(hm,'CheckActorCanBeHatred',opponent)
        local gate2,g2=call(hm,'CheckCanHatredTarget',opponent)
        local tc=read(actor,'Targeting Component')
        local handler=read(tc,'CurrentHandler')
        local bb=read(handler,'Blackboard')
        local key=read(handler,'Target Key')
        local targetOk,target=false,nil
        if key~=nil then targetOk,target=call(bb,'GetValueAsObject',key) end
        local lock=read(tc,'LockTarget')
        local socketOk,component=pcall(function() return lock.Component end)
        local ownerOk,owner=false,nil
        if socketOk then ownerOk,owner=call(component,'GetOwner') end
        log('战斗只读 '..tostring(label)..' actor='..name(actor)..' opponent='..name(opponent)
            ..' canBeHatred='..scalar(canSelf)..'/'..scalar(canTarget)
            ..' gateActor='..(gate1 and scalar(g1) or 'UNKNOWN')
            ..' gateTarget='..(gate2 and scalar(g2) or 'UNKNOWN')
            ..' handler='..name(handler)..' blackboard_target='..(targetOk and name(target) or 'UNKNOWN')
            ..' locked_actor='..(ownerOk and name(owner) or 'UNKNOWN'))
    end
    return instance
end
return Inspector
