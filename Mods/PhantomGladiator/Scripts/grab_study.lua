-- Read-only, bounded inspection of the game's paired grab assets and functions.
-- No actors are created, no abilities activated, no hooks or UObject writes.
local U=require('ue_observe')
local Study={}
local root='/PBZCombatAsset/ActorData/Mobs/003_MaleThug/Ability/Weapon_Sword/Abilities/LevelShow/'
local event='/SGameExecution/Bullet/Events/BP_BulletEvent_Grab.BP_BulletEvent_Grab_C'
local assets={
    {name='grab_event',path=event,fields={'Only Grab Ability Target','WaitEventToSuccess','Deactivate Bullet','Jump Point','Success Timeline','Executed Ability','NonPlayerGE'}},
    {name='npc_executor',path=root..'GA_MaleThug_Sword_Gex_ToNpc_01.GA_MaleThug_Sword_Gex_ToNpc_01_C'},
    {name='npc_receiver',path=root..'GA_MaleThug_Sword_Ged_ToNpc_01.GA_MaleThug_Sword_Ged_ToNpc_01_C'},
}
local functions={event..':Trigger',
    '/SGameExecution/GA/GA_ExecutionAbilityBase_Grab.GA_ExecutionAbilityBase_Grab_C:K2_ActivateAbility',
    '/SGameExecution/GA/GA_ExecutionAbilityBase_Grab.GA_ExecutionAbilityBase_Grab_C:PlayGrabTimeline',
    '/SGameExecution/GA/GA_ExecutedAbilityBase_Grab.GA_ExecutedAbilityBase_Grab_C:K2_ActivateAbility',
    '/Script/Engine.Pawn:IsPlayerControlled','/Script/Engine.Controller:IsPlayerController',
    '/Script/Engine.KismetSystemLibrary:IsValid',
    '/Script/Engine.KismetMathLibrary:Not_PreBool',
    '/Script/SGameExecution.ExecutionComponent:PlayExactExecution',
    '/Script/SGameExecution.GrabExecutionAbilityInterface:PlayGrabTimeline',
    '/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:SendGameplayEventToActor',
    '/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:GetAbilitySystemComponent',
}
local function clean(v)return tostring(v or ''):gsub('[\t\r\n]',' '):sub(1,1500)end
local function name(obj)
    if not U.valid(obj) then return 'INVALID' end
    local ok,value=pcall(function()return obj:GetFullName()end)
    return ok and tostring(value) or 'UNKNOWN'
end
local function value(v)
    if U.valid(v) then return name(v)..' @'..tostring(U.key(v)) end
    if v==nil or type(v)=='boolean' or type(v)=='number' or type(v)=='string' then return tostring(v) end
    local ok,s=pcall(function()return v:ToString()end)
    return ok and tostring(s) or U.kind(v)
end
function Study.new(options)
    local self={step=0,done=false,rows={'kind\tlabel\taddress\tname\tvalue'}}
    local log=options.log or function()end
    local function emit(kind,label,obj,data)
        self.rows[#self.rows+1]=table.concat({clean(kind),clean(label),clean(U.key(obj)),clean(name(obj)),clean(data)},'\t')
        log('[GrabStudy] '..kind..' '..label..' '..clean(name(obj))..' '..clean(data))
    end
    local function fields(obj,label,names)
        if not U.valid(obj) then return end
        for _,field in ipairs(names)do
            local v,read=U.field(obj,field)
            emit('field',label..'.'..field,obj,'read='..tostring(read)..' value='..value(v))
        end
    end
    local function properties(obj,label)
        if not U.valid(obj) then return end
        local count=0
        pcall(function()obj:ForEachProperty(function(property)
            count=count+1;if count>48 then return true end
            -- Reflection properties are FFields, not UObjects.
            local ok,pname,address=pcall(function()return property:GetFullName(),property:GetAddress()end)
            if ok then self.rows[#self.rows+1]=table.concat({'property',clean(label),clean(address),clean(pname),''},'\t') end
        end)end)
    end
    local function flush()
        local text=table.concat(self.rows,'\n')..'\n'
        local f,err=io.open(options.path..'/grab-study.tsv','w')
        if not f then log('[GrabStudy] 写入失败 '..tostring(err));return end
        f:write(text);f:close()
        f=io.open(options.path..'/grab-study.tsv','r')
        local actual=f and f:read('*a');if f then f:close()end
        log('[GrabStudy] 只读报告保存 rows='..(#self.rows-1)..' verified='..tostring(actual==text))
    end
    function self:tick()
        if self.done or not options.ready() then return end
        self.step=self.step+1
        local item=assets[self.step]
        if item then
            local cls=StaticFindObject(item.path)
            if not U.valid(cls) then
                log('[GrabStudy] 仅加载注册表已确认的投技类 '..item.path)
                local ok,loaded=pcall(LoadAsset,item.path)
                if ok and U.valid(loaded) then cls=loaded else cls=StaticFindObject(item.path) end
            end
            if not U.valid(cls) then emit('missing',item.name,nil,item.path);flush();return end
            local checked,isClass=pcall(function()return cls:IsAnyClass()end)
            local actual=name(cls):match('^%S+ (/.+)$')
            if not checked or isClass~=true or actual~=item.path then
                emit('class_unverified',item.name,cls,'expected='..item.path);flush();return
            end
            emit('class',item.name,cls,'read_only=true');properties(cls,item.name)
            local ok,cdo=pcall(function()return cls:GetCDO()end)
            if ok and U.valid(cdo) then
                emit('cdo',item.name,cdo,'read_only=true')
                fields(cdo,item.name,item.fields or {'ExecutionTimeline','GrabSuccess','DisableCollisionOnExecution','Invulnerable','Disable Focus'})
            end
            local timelines=U.array(U.field(cls,'AbilityTimelines'))
            for index,timeline in ipairs(timelines or {})do
                if index>12 then break end
                fields(timeline,item.name..'.timeline'..index,{'SequenceLength','bAutoPlay','bLooping','bStopAbility','MasterCollisionBehavior','bMasterNeedRestoreMovement'})
            end
            flush();return
        end
        if self.step==#assets+1 then
            for _,path in ipairs(functions)do
                local fn=StaticFindObject(path)
                local flags='UNKNOWN'
                if U.valid(fn) and name(fn):match('^Function ') then
                    local ok,n=pcall(function()return fn:GetFunctionFlags()end);if ok then flags=n end
                else fn=nil end
                emit('function',path,fn,'flags='..tostring(flags));properties(fn,path)
            end
            local ok,instances=pcall(FindAllOf,'BP_BulletEvent_Grab_C')
            for i,obj in ipairs(ok and instances or {})do
                if i>24 then break end
                fields(obj,'loaded_event'..i,{'Only Grab Ability Target','WaitEventToSuccess','Executed Ability','NonPlayerGE'})
            end
            self.done=true;flush()
            log('[GrabStudy] 读取完成；未触发投技、未修改NonPlayerGE、未挂钩')
        end
    end
    return self
end
return Study
