-- Enable the existing hit-triggered grab path, rather than starting another move.
-- BP_BulletEvent_Grab.Trigger branches to GE_GrabHit for non-player targets when
-- NonPlayerGE is set. The native ToNpc data leaves that optional class empty.
local U=require('ue_observe')
local Grabs={}
local FALLBACK='/PBZCombatAsset/Prototypes/GameplayEffects/Inflictions/GE_GrabHit.GE_GrabHit_C'
local EVENT_CLASS='/SGameExecution/Bullet/Events/BP_BulletEvent_Grab.BP_BulletEvent_Grab_C'
local function full(obj)
    if not U.valid(obj) then return nil end
    local ok,name=pcall(function()return obj:GetFullName()end)
    return ok and type(name)=='string' and name or nil
end
local function path(obj)local name=full(obj);return name and name:match('^%S+ (/.+)$')end
local function family(classPath)return type(classPath)=='string' and classPath:match('^(/PBZCombatAsset/ActorData/Mobs/[^/]+/)')end
local function same(a,b)local key=U.key(a);return key~=nil and key==U.key(b)end
local function weak(v)
    local kind=U.kind(v)
    if kind=='WeakObjectPtr' or kind=='FWeakObjectPtr' or kind=='TWeakObjectPtr' then
        local ok,obj=pcall(function()return v:Get()end);return ok and U.valid(obj) and obj or nil
    end
    return U.valid(v) and v or nil
end
local function handle(v)return U.struct(v,'Handle')end
local function tags(obj,field)
    local values=U.array(U.struct(U.field(obj,field),'GameplayTags'))
    if not values then return 'UNKNOWN' end
    local names={}
    for i,tag in ipairs(values)do
        if i>16 then names[#names+1]='...';break end
        local name=U.struct(tag,'TagName')
        local ok,text=pcall(function()return name:ToString()end)
        names[#names+1]=ok and tostring(text) or tostring(name)
    end
    return '['..table.concat(names,',')..']'
end
function Grabs.new(options)
    local self={records={},observed={},pairs={},ticks=0,signature=nil,scans=0,recovering=false}
    local log=options.log or function()end
    local fs=options.io or io
    local filePath=options.path..'/npc-grab-policy.tsv'
    local function persist()
        local lines={'NPCGrabPolicyV1'};local keys={}
        for name in pairs(self.records)do keys[#keys+1]=name end;table.sort(keys)
        for _,name in ipairs(keys)do lines[#lines+1]=name..'\t'..self.records[name].key end
        local text=table.concat(lines,'\n')..'\n'
        local file=fs.open(filePath,'w');if not file then return false end
        local wrote=file:write(text);local closed=file:close()
        file=fs.open(filePath,'r');local actual=file and file:read('*a');if file then file:close()end
        return wrote~=nil and closed~=nil and actual==text
    end
    do
        local f=fs.open(filePath,'r')
        if f then
            local text=f:read('*a');f:close()
            if text:match('^NPCGrabPolicyV1\n') then
                for name,key in text:gmatch('\n([^\t\r\n]+)\t(%d+)')do
                    if family(name) and not name:find('[^%w_/%-%.:]') then self.records[name]={key=key} end
                end
                self.recovering=next(self.records)~=nil
            end
        end
    end
    local function isEvent(obj)
        if not U.valid(obj) then return false end
        local ok,cls=pcall(function()return obj:GetClass()end)
        return ok and path(cls)==EVENT_CLASS
    end
    local function emptyClass()
        local cls=StaticFindObject(EVENT_CLASS)
        if not U.valid(cls) then return nil,'grab event class unavailable' end
        local got,cdo=pcall(function()return cls:GetCDO()end)
        if not got or not U.valid(cdo) then return nil,'grab event defaults unavailable' end
        local empty,read=U.field(cdo,'NonPlayerGE')
        -- A null UClass userdata is a legitimate class value. Never dereference it.
        -- Lua nil is not accepted by this build's reflected ClassProperty setter.
        if read and U.kind(empty)=='UClass' and not U.valid(empty) then return empty end
        return nil,'default NonPlayerGE is not a confirmed null UClass'
    end
    local function snapshot(obj)
        local name,key=path(obj),U.key(obj)
        if not name or not key then return nil end
        local prior=self.records[name]
        if prior and prior.key==key then return prior end
        local record={key=key,event=obj};self.records[name]=record
        if not persist() then self.records[name]=prior;log('[NPCGrab] 快照保存未读回，未修改 '..name);return nil end
        return record
    end
    function self:restore()
        local pending=0;local original
        for name,record in pairs(self.records)do
            local event=record.event
            if not U.valid(event) or U.key(event)~=record.key or path(event)~=name then
                local ok,obj=pcall(StaticFindObject,name);event=ok and obj or nil
            end
            if not U.valid(event) or U.key(event)~=record.key or path(event)~=name then
                -- Only this exact asset instance was changed; a new instance uses serialized defaults.
                self.records[name]=nil
                log('[NPCGrab] 原事件已失效/被重建，丢弃旧实例记录 '..name)
            elseif not isEvent(event) then pending=pending+1
            else
                if not U.valid(original) then
                    original=StaticFindObject(FALLBACK)
                    if not U.valid(original) and options.ready() then
                        local ok,value=pcall(LoadAsset,FALLBACK);if ok then original=value end
                    end
                end
                local classOK,isClass=pcall(function()return U.valid(original) and original:IsAnyClass()end)
                if not classOK or isClass~=true or path(original)~=FALLBACK then pending=pending+1
                else
                    local called=pcall(function()if not U.valid(event) or not U.valid(original) then error('expired restore object')end;event.NonPlayerGE=original end)
                    local actual,read=U.field(event,'NonPlayerGE')
                    local verified=called and read and path(actual)==FALLBACK
                    log('[NPCGrab] 恢复共享事件 NonPlayerGE verified='..tostring(verified)..' '..name)
                    if verified then self.records[name]=nil else pending=pending+1 end
                end
            end
        end
        local saved=persist();self.recovering=next(self.records)~=nil
        if not self.recovering then self.signature=nil;self.observed={};self.pairs={} end
        return pending==0 and saved
    end
    -- Blue and Red count only while their fight runs with both sides alive; companions whenever they
    -- are out, so their grabs work on the map's own enemies too.
    local function scope(members,battleActive)
        local families,owners,signature={}, {}, {};local blue,red=false,false
        local arena,companions={},{}
        for _,unit in ipairs(members)do
            local root=family(unit.class_path)
            local team=unit.team
            if root and (team=='blue' or team=='red' or team=='companion') and U.valid(unit.actor) then
                local ok,hp=pcall(options.hp,unit.actor)
                local key=U.key(unit.actor)
                if ok and type(hp)=='number' and hp>0 and key then
                    local entry={actor=unit.actor,key=key,root=root}
                    if team=='companion' then companions[#companions+1]=entry
                    else arena[#arena+1]=entry;blue=blue or team=='blue';red=red or team=='red' end
                end
            end
        end
        local function add(list)
            for _,entry in ipairs(list)do
                families[entry.root]=true;owners[entry.key]=entry.actor;signature[#signature+1]=entry.key..':'..entry.root
            end
        end
        if battleActive and blue and red then add(arena) end
        add(companions)
        table.sort(signature)
        return families,owners,table.concat(signature,'|'),next(families)~=nil
    end
    local function scan(families)
        self.scans=self.scans+1
        local ok,list=pcall(options.findEvents or FindAllOf,'BP_BulletEvent_Grab_C')
        if not ok or type(list)~='table' then log('[NPCGrab] 投技事件枚举未确认');return false end
        local matched,changed=0,0
        for index,event in ipairs(list)do
            if index>512 then log('[NPCGrab] 事件检查达到512条，未宣称全覆盖');break end
            local name=path(event);local root=family(name)
            if root and families[root] and isEvent(event) then
                matched=matched+1
                local old,read=U.field(event,'NonPlayerGE')
                if read and path(old)==FALLBACK then
                    local record=snapshot(event)
                    if record and (record.attempts or 0)<3 then
                        record.attempts=(record.attempts or 0)+1
                        local empty,why=emptyClass()
                        local called,err=false,why
                        if empty~=nil then called,err=pcall(function()if not U.valid(event) then error('expired event')end;event.NonPlayerGE=empty end) end
                        local actual,got=U.field(event,'NonPlayerGE')
                        local verified=called and got and not U.valid(actual)
                        record.applied=verified
                        if verified then changed=changed+1 end
                        log('[NPCGrab] 参赛族共享投技事件：NonPlayerGE GE_GrabHit -> native_empty_class called='..tostring(called)..' read='..tostring(got)
                            ..' after='..tostring(path(actual) or U.kind(actual))..' verified='..tostring(verified)..' '..name
                            ..(called and '' or (' error='..tostring(err):gsub('[\r\n]',' '):sub(1,240))))
                        log('[NPCGrab] 保留原生条件 required='..tags(event,'Target Required Tags')..' ignored='..tags(event,'Target Ignored Tags')
                            ..' executed_ability='..tostring(path(U.field(event,'Executed Ability'))))
                    end
                end
            end
        end
        if changed>0 or self.scans==1 then log('[NPCGrab] 事件读回 matched='..matched..' changed='..changed..'；原生命中/目标Tag/配对动画仍由游戏处理') end
        return true
    end
    local function activeCount(component,ownHandle)
        if type(ownHandle)~='number' or ownHandle<=0 then return nil end
        local asc=U.field(component,'AbilitySystem')
        local container=U.field(asc,'ActivatableAbilities')
        local specs=U.array(U.struct(container,'Items'))
        if not specs then return nil end
        for i,spec in ipairs(specs)do
            if i>512 then break end
            if handle(U.struct(spec,'Handle'))==ownHandle then
                local active=U.struct(spec,'ActiveCount');return type(active)=='number' and active or nil
            end
        end
    end
    local function observe(members,owners)
        local kept={}
        for _,unit in ipairs(members)do
            local actor=unit.actor;local key=U.key(actor)
            if key and owners[key] then
                local component=U.field(actor,'Execution Component')
                if U.valid(component) then
                    local ok,owner=pcall(function()return component:GetOwner()end)
                    if ok and same(owner,actor) then
                        local info=U.field(component,'CurrentExecutionInfo')
                        local executor=weak(U.struct(info,'Executor'));local target=weak(U.struct(info,'Target'))
                        local exKey,tgKey=U.key(executor),U.key(target)
                        local exHandle=handle(U.struct(info,'ExecutionHandle'));local tgHandle=handle(U.struct(info,'ExecutedHandle'))
                        local isTarget=U.struct(info,'IsTarget')
                        local count=activeCount(component,isTarget==true and tgHandle or exHandle)
                        local pair=exKey and tgKey and owners[exKey] and owners[tgKey]
                        local signature=table.concat({tostring(exKey),tostring(tgKey),tostring(exHandle),tostring(tgHandle),tostring(count)},':')
                        kept[key]=signature
                        if signature~=self.observed[key] and (pair or self.observed[key] or (type(exHandle)=='number' and exHandle>0) or (type(tgHandle)=='number' and tgHandle>0)) then
                            local capsule=U.field(actor,'CapsuleComponent');local collision='UNKNOWN'
                            if U.valid(capsule) then local got,v=pcall(function()return capsule:GetCollisionEnabled()end);if got then collision=v end end
                            log('[NPCGrab] 原生配对读回 actor='..key..' name='..tostring(unit.class_path)..' executor='..tostring(exKey)..' target='..tostring(tgKey)
                                ..' handles='..tostring(exHandle)..'/'..tostring(tgHandle)..' is_target='..tostring(isTarget)..' active_count='..tostring(count)..' collision='..tostring(collision)
                                ..' ref_types='..U.kind(U.struct(info,'Executor'))..'/'..U.kind(U.struct(info,'Target')))
                            if pair and type(count)=='number' and count>0 then self.pairs[tostring(exKey)..':'..tostring(tgKey)..':'..tostring(exHandle)..':'..tostring(tgHandle)]=true end
                        end
                    end
                end
            end
        end
        self.observed=kept
    end
    function self:sync(members,battleActive,force)
        if self.recovering then if not self:restore() then return false end end
        local families,owners,signature,active=scope(members,battleActive)
        if not active then
            if next(self.records) then return self:restore() end
            return true
        end
        if self.signature and signature~=self.signature and next(self.records) then
            if not self:restore() then return false end
        end
        self.ticks=self.ticks+1
        -- The rescan walks every loaded object (FindAllOf): every 5 s in a fight, every 30 s when only
        -- companions are out, since they keep the scope alive for as long as they follow the player.
        if force or signature~=self.signature or self.ticks%(battleActive and 10 or 60)==0 then
            self.signature=signature
            scan(families)
        end
        observe(members,owners)
        return true
    end
    function self:status()
        local count,pairsCount=0,0
        for _,record in pairs(self.records)do if record.applied then count=count+1 end end
        for _ in pairs(self.pairs)do pairsCount=pairsCount+1 end
        return {events=count,observed_pairs=pairsCount,restore_pending=self.recovering}
    end
    return self
end
return Grabs
