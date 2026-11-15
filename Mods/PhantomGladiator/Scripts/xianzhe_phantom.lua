-- XianZhe's timed phasing uses GAA_DodgeInvulnerable in eight native actions.
-- Remove only that action's own dodge effect/overlap collider, preserving movement and other effects.
local U=require('ue_observe')
local Retry=require('lookup_retry')
local Phantom={}
local ACTOR='/PBZCombatAsset/ActorData/Mobs/071_XianZhe/BP_Monster_XianZhe.BP_Monster_XianZhe_C'
local ACTION='/PBZCombatAsset/Prototypes/Actions/GAA_DodgeInvulnerable.GAA_DodgeInvulnerable_C'
local EFFECT='/PBZCombatAsset/Prototypes/GameplayEffects/GE_DodgeInvulnerable.GE_DodgeInvulnerable_C'
local LIB='/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'
local OWN_ABILITIES={}
for _,name in ipairs({'Dodge_B','Dodge_L','Dodge_L_02','Dodge_R','Dodge_R_02','EnterCombat','ExitCombat','Skill_07'})do
    local package='/PBZCombatAsset/ActorData/Mobs/071_XianZhe/Ability/GA_XianZhe_'..name
    OWN_ABILITIES[package..'.GA_XianZhe_'..name..'_C']=true
end
Phantom.path=ACTION..':Received_ActionBegin'
Phantom.endPath=ACTION..':Received_ActionEnd'
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args={...}
    local ok,value=pcall(function()return object[method](object,table.unpack(args))end)
    if not ok then return nil end
    return U.unwrap(value)
end
local function full(object)return call(object,'GetFullName')end
local function classPath(object)
    local cls=call(object,'GetClass')
    local name=full(cls)
    return type(name)=='string' and name:match('^%S+ (/.+)$') or nil
end
local function same(a,b)
    local key=U.key(a)
    local name=full(a)
    return key~=nil and key==U.key(b) and type(name)=='string' and name==full(b)
end
local function handleID(value)
    local id=U.struct(value,'Handle')
    return type(id)=='number' and id%1==0 and id>=0 and id or nil
end
function Phantom.new(options)
    local self={state='idle',blocked=0,failures=0}
    local clock,find=options.clock or os.clock,options.find or StaticFindObject
    local register,unregister=options.register or RegisterHook,options.unregister or UnregisterHook
    local load,fname,inGameThread=options.load or LoadAsset,options.fname or FName,options.inGameThread or IsInGameThread
    local records,pending,active,colliderOwner={},{},{},{}
    local hook,endHook,alive=nil,nil,true
    local lastError=false
    local hookAt,loadAt,unhookAt=0,0,0
    local lines={}
    local function say(kind,text)
        lines[kind]=(lines[kind] or 0)+1
        if lines[kind]<=12 then (options.log or function()end)('[XianZhePhantom] '..text) end
    end
    local retry=Retry.new({clock=clock,log=function(text)say('lookup',text)end})
    local function lookup(path)return retry:find(path,find)end
    local function supported()return type(find)=='function' and type(register)=='function' and type(unregister)=='function' and fname~=nil end
    local function ready()return not options.ready or options.ready()==true end
    local function gameThread()
        if type(inGameThread)~='function' then return true end
        local ok,yes=pcall(inGameThread);return ok and yes==true
    end
    local function selected(actor)
        local key=U.key(actor)
        local row=key and records[key]
        if not row or not row.off or row.name~=full(actor) or not same(actor,row.actor) then return nil end
        if not options.members then return row end
        for _,member in ipairs(options.members() or {})do if same(member.actor,actor) then return row end end
    end
    local function activeIDs(asc)
        local list=U.array(call(asc,'GetActiveEffects',{}))
        if not list then return nil end
        local ids={};for _,value in ipairs(list)do local id=handleID(value);if not id then return nil end;ids[id]=true end
        return ids
    end
    local function current(row)
        if row.ended or active[row.actionKey]~=row or not U.valid(row.action) then return false end
        local name=full(row.action)
        if type(name)~='string' then return nil end
        if name~=row.actionName then return false end
        local id=U.struct(U.field(row.action,'Handle'),'Handle')
        if type(id)~='number' or id%1~=0 or id< -1 then return nil end
        return id==row.id or row.invalidated==true and id==-1
    end
    -- Read a fresh typed struct from the action. Never replace the reflected struct with a Lua table.
    local function invalidateAction(row)
        local owns=current(row)
        if owns==nil then return false elseif not owns then return true end
        local value=U.field(row.action,'Handle')
        local current=handleID(value)
        if not current or current~=row.id then return true end -- a newer activation owns its own handle
        local ok=pcall(function()value.Handle=-1 end)
        local after=U.struct(U.field(row.action,'Handle'),'Handle')
        say('handle','清空本次动作句柄='..row.id..'；整数读回='..tostring(after))
        row.invalidated=ok and after==-1
        return row.invalidated
    end
    local function disableCollider(row)
        local owns=current(row)
        if owns==nil then return false elseif not owns or colliderOwner[row.colliderKey]~=row then return true end
        if not U.valid(row.collider) then
            say('collider-gone','本次闪避碰撞组件已失效，不再访问；有效性读回=false')
            return true
        end
        if not same(call(row.collider,'GetOwner'),row.actor) then return false end
        local tagged,tag=pcall(fname,'Dodge Collider')
        if not tagged or call(row.collider,'ComponentHasTag',tag)~=true then return false end
        call(row.collider,'SetCollisionEnabled',0)
        local after=call(row.collider,'GetCollisionEnabled')
        say('collider','关闭本单位闪避碰撞；模式读回='..tostring(after))
        return after==0
    end
    local function remove(row)
        if not selected(row.actor) or not same(U.field(row.actor,'AbilitySystemComponent'),row.asc) then return true end
        local ids=activeIDs(row.asc)
        if not ids then return false end
        if ids[row.id] then
            local lib=lookup(LIB)
            local effect=call(lib,'GetGameplayEffectFromActiveEffectHandle',row.handle)
            if classPath(effect)~=EFFECT then return false end
            call(row.asc,'RemoveActiveGameplayEffect',row.handle,-1)
            ids=activeIDs(row.asc)
            if not ids or ids[row.id] then return false end
            row.removedVerified=true
            say('effect','移除本次技能闪避无敌 句柄='..row.id..'；所属ASC效果列表读回不存在=true')
        elseif not row.removedVerified then
            -- An absent local handle may already have ended, or may belong to somebody else's ASC.
            -- Only confirmed global inactivity permits retiring our field/collider.
            if call(lookup(LIB),'IsActiveGameplayEffectHandleActive',row.handle)~=false then return false end
            row.removedVerified=true
        end
        local fieldOK=invalidateAction(row)
        local colliderOK=disableCollider(row)
        return fieldOK and colliderOK
    end
    local function process(action)
        if not alive or not endHook or not gameThread() or not ready() or classPath(action)~=ACTION then return end
        local ability=call(action,'GetAbility')
        if not OWN_ABILITIES[classPath(ability)] then return end
        local actor=call(ability,'GetAvatarActorFromActorInfo')
        if not selected(actor) or classPath(actor)~=ACTOR or not same(call(action,'GetAvatarActor'),actor) then return end
        local asc=call(action,'GetAbilitySystemComponent')
        if not same(asc,U.field(actor,'AbilitySystemComponent')) or not same(asc,call(ability,'GetAbilitySystemComponentFromActorInfo')) then return end
        local value=U.field(action,'Handle')
        local id=handleID(value)
        local actionKey=U.key(action)
        local collider=U.field(action,'Collider')
        local colliderKey=U.key(collider)
        -- Function inputs use the same reflected handle argument shape as observer_guard. This snapshot is never
        -- assigned to a StructProperty; the action's live struct may be reused by a newer activation meanwhile.
        local row={action=action,actionKey=actionKey,actionName=full(action),actor=actor,asc=asc,id=id,collider=collider,colliderKey=colliderKey,nextAt=clock()+0.25}
        active[actionKey]=row
        if colliderKey then colliderOwner[colliderKey]=row end
        if not id then lastError=true;self.state='failed';self.failures=self.failures+1;say('missing','动作句柄未确认，未改其他效果');return end
        row.handle={Handle=id,bPassedFiltersAndWasExecuted=true}
        local key=actionKey..':'..id
        if remove(row) then lastError=false;self.blocked=self.blocked+1;pending[key]=nil
        else
            self.state='failed'
            self.failures=self.failures+1
            local count=0;for _ in pairs(pending)do count=count+1 end
            if pending[key] or count<128 then pending[key]=row end
            say('pending','本次技能虚化解除未确认；句柄='..id..'，保留限频重试')
        end
    end
    local function finish(action)
        if not alive or not gameThread() or classPath(action)~=ACTION then return end
        local key=U.key(action)
        local row=key and active[key]
        if not row or full(action)~=row.actionName then return end
        row.ended=true;active[key]=nil
        if row.colliderKey and colliderOwner[row.colliderKey]==row then colliderOwner[row.colliderKey]=nil end
        say('end','退休本次动作代次；后续重试不再写动作句柄/闪避碰撞')
    end
    local function install()
        if hook and endHook then return true end
        if not supported() or clock()<hookAt then return false end
        hookAt=clock()+1
        local fn=lookup(Phantom.path)
        if not U.valid(fn) and type(load)=='function' and clock()>=loadAt then
            loadAt=clock()+5
            local ok,cls=pcall(load,ACTION)
            if ok and U.valid(cls) then local found,value=pcall(find,Phantom.path);fn=found and value or nil end
            say('load','定点加载闪避动作类；函数读回有效='..tostring(U.valid(fn)))
        end
        if not U.valid(fn) then return false end
        if not endHook then
            local ending=lookup(Phantom.endPath)
            if not U.valid(ending) then return false end
            local ok,pre,post=pcall(register,Phantom.endPath,function(context)
                local called,err=pcall(finish,U.unwrap(context))
                if not called then lastError=true;self.failures=self.failures+1;say('end-failed','动作结束读回失败 '..tostring(err)) end
            end,function()end)
            if ok and pre~=nil and pre~=false then endHook={pre,post} else self.failures=self.failures+1;return false end
        end
        if hook then return true end
        local ok,pre,post=pcall(register,Phantom.path,function(context)
            local called,err=pcall(process,U.unwrap(context))
            if not called then lastError=true;self.state='failed';self.failures=self.failures+1;say('callback','处理失败 '..tostring(err)) end
        end,function()end)
        if ok and pre~=nil and pre~=false then hook={pre,post};say('hook','技能虚化挂钩安装；读回ID='..tostring(pre));return true end
        self.failures=self.failures+1;return false
    end
    local function uninstall(force)
        if not hook and not endHook or not force and clock()<unhookAt then return end
        unhookAt=clock()+1
        if hook then local ok,result=pcall(unregister,Phantom.path,hook[1],hook[2]);if ok and result~=false then hook=nil end end
        if endHook then local ok,result=pcall(unregister,Phantom.endPath,endHook[1],endHook[2]);if ok and result~=false then endHook=nil end end
        say('unhook','摘除技能虚化挂钩；剩余读回='..tostring(hook~=nil or endHook~=nil))
    end
    function self:capture(actor,path,escort)
        if path~=ACTOR or escort then return true end
        if not gameThread() then return false,'弦者技能虚化设置等待游戏线程' end
        if not alive or not U.valid(actor) or classPath(actor)~=ACTOR then return false,'弦者对象未确认，未设置技能虚化' end
        local key,name=U.key(actor),full(actor)
        if not key or type(name)~='string' then return false,'弦者身份未确认' end
        if not records[key] or records[key].name~=name then
            records[key]={actor=actor,name=name,off=options.rule and options.rule('BP_Monster_XianZhe')=='off' or false}
            say('capture','登记本次召唤技能虚化关闭='..tostring(records[key].off)..' 身份读回='..name)
        end
        if records[key].off and (not ready() or not install()) then
            self.state='waiting';return false,'弦者技能虚化拦截待就绪，暂保留原版，请查看面板状态'
        end
        self.state=records[key].off and 'on' or self.state
        return true
    end
    function self:tick()
        if not alive then return end
        if not gameThread() then return end
        if not next(records) and not next(pending) and not hook and not endHook then self.state='idle';return end
        if not ready() then uninstall();self.state='waiting';return end
        local present={}
        for _,member in ipairs(options.members and options.members() or {})do local key=U.key(member.actor);if key then present[key]=member.actor end end
        local off=false
        for key,row in pairs(records)do
            if not U.valid(row.actor) or row.name~=full(row.actor) or options.members and not same(row.actor,present[key]) then records[key]=nil
            else off=off or row.off end
        end
        for key,row in pairs(pending)do
            if not selected(row.actor) then pending[key]=nil
            elseif clock()>=row.nextAt then
                row.nextAt=clock()+0.25
                if remove(row) then pending[key]=nil;self.blocked=self.blocked+1 end
            end
        end
        for key,row in pairs(active)do
            if not selected(row.actor) or not U.valid(row.action) then
                active[key]=nil
                if row.colliderKey and colliderOwner[row.colliderKey]==row then colliderOwner[row.colliderKey]=nil end
            end
        end
        if off then self.state=install() and ((next(pending) or lastError) and 'failed' or 'on') or 'waiting'
        else uninstall();lastError=false;self.state='idle' end
    end
    function self:status()
        local count=0;for _ in pairs(pending)do count=count+1 end
        return {supported=supported(),state=self.state,hooks=(hook and 1 or 0)+(endHook and 1 or 0),blocked=self.blocked,failures=self.failures,pending=count}
    end
    function self:silence()
        alive=false
        if gameThread() then
            for _,row in pairs(pending)do
                local ok,done=pcall(remove,row)
                if not ok or not done then say('shutdown','卸载前仍有技能虚化处理未确认，请停止清理后重载') end
            end
        elseif next(pending) then
            say('shutdown','非游戏线程卸载，不访问技能对象；仍有未确认处理，请停止清理后重载')
        end
        records={};pending={};active={};colliderOwner={};uninstall(true)
    end
    return self
end
return Phantom
