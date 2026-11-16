-- Experimental, owned NPC body only. Never possesses a player or edits a shared config.
local U=require('ue_observe')
local Body={path='/PBZCombatAsset/ActorData/Mobs/000_Hun/BP_Monster_Hun.BP_Monster_Hun_C'}
local CONFIG='/PBZCombatAsset/ActorData/Mobs/000_Hun/ActorConfig/ActorC_Monster_Hun.ActorC_Monster_Hun'
local REMOVE={['AI.Hatred.CanNotBeHatred']=true,['CharacterState.Unselectable.Force.Hide']=true}
local function call(o,m,...)
    if not U.valid(o)then return false end
    local a,n={...},select('#',...);local ok,value=pcall(function()return o[m](o,table.unpack(a,1,n))end)
    return ok,U.unwrap(value)
end
local function name(o)local ok,n=call(o,'GetFullName');return ok and type(n)=='string'and n or nil end
local function tag(t)
    local v=U.struct(t,'TagName');if type(v)=='string'then return v end
    local ok,s=pcall(function()return v:ToString()end);return ok and s or nil
end
local function tags(config)
    local container=U.field(config,'InitialTags');local array=U.struct(container,'GameplayTags');local values=U.array(array)
    if not values then return nil end
    local result={};for _,v in ipairs(values)do local s=tag(v);if not s then return nil end;result[#result+1]=s end
    return result,array
end
local function signature(values)return values and table.concat(values,'|')or nil end
local function separateArrays(a,b)
    if U.kind(a)=='table'and U.kind(b)=='table'then return a~=b end
    if U.kind(a)~='TArray'or U.kind(b)~='TArray'then return false end
    local ok,x,y=pcall(function()return a:GetArrayDataAddress(),b:GetArrayDataAddress()end)
    return ok and type(x)=='number'and type(y)=='number'and(x==0 or y==0 or x~=y)
end
function Body.new(o)
    local self={alive=true,prepared=0,failed=0,message='完整魂角色尚未接入；可进行独立本体验证'}
    local context,records,serial,epoch=nil,{},0,0
    local function say(s)(o.log or function()end)('[HunBody] '..s)end
    local function current(actor,record)
        local world=o.world();local player=o.player()
        return self.alive and U.valid(world)and U.inWorld(actor,world)and U.key(actor)~=U.key(player)
            and U.npcPath(actor)==Body.path and(not record or record.epoch==epoch and record.world==U.key(world)and record.name==name(actor))
    end
    function self:spawn(arena,team,count,revision)
        if context or not self.alive then return {ok=false,message='魂本体验证正在处理',spawned_count=0}end
        if team~='blue'and team~='red'and team~='neutral'and team~='companion'then return {ok=false,message='阵营无效',spawned_count=0}end
        if type(count)~='number'or count%1~=0 or count<1 or count>100 then return {ok=false,message='数量须为1～100',spawned_count=0}end
        local world=o.world();if not U.valid(world)then return {ok=false,message='当前世界未就绪',spawned_count=0}end
        context={world=U.key(world),revision=revision,epoch=epoch}
        local ok,result=pcall(arena.spawn,arena,Body.path,team,count)
        context=nil
        if not ok then return {ok=false,uncertain=true,message='魂本体生成未确认，停止继续尝试并先清理',spawned_count='unknown'}end
        if type(result)=='table'then result.message=(result.message or'')..'；仅本体验证，全配装/防御AI尚未应用'end
        return result
    end
    function self:capture(actor,path)
        if not context or path~=Body.path then return end
        local key,n=U.key(actor),name(actor)
        if not key then return end
        records[key]={actor=actor,name=n,world=context.world,revision=context.revision,epoch=context.epoch,phase='captured',
            refused=context.epoch~=epoch or not n or not current(actor)or context.world~=U.key(o.world())}
    end
    function self:prepare(actor)
        local r=records[U.key(actor)or''];if not r then return true end
        if r.refused or not current(actor,r)then return false,'魂本体身份或世界已变化'end
        local source=U.field(actor,'Actor Config');local sourceName=name(source)
        if not sourceName or sourceName:match(' (/.+)$')~=CONFIG then return false,'魂原始配置来源未确认'end
        local before,sourceArray=tags(source);if not before then return false,'魂初始标签未读回'end
        local ok,cls=call(source,'GetClass');local isClass,yes=call(cls,'IsAnyClass')
        if not ok or not isClass or yes~=true then return false,'魂配置类型未确认'end
        serial=serial+1
        local construct=o.construct or StaticConstructObject
        local copied,private=pcall(construct,cls,actor,FName('PG_HunBody_'..serial),0x40,0,false,false,source)
        if not copied or not U.valid(private)or U.key(private)==U.key(source)then return false,'魂私有配置未构造成功'end
        local gotOuter,outer=call(private,'GetOuter');local gotClass,privateClass=call(private,'GetClass')
        local _,privateArray=tags(private)
        local separate=separateArrays(sourceArray,privateArray)
            and separateArrays(U.struct(U.field(source,'InitialTags'),'ParentTags'),U.struct(U.field(private,'InitialTags'),'ParentTags'))
        if not gotOuter or U.key(outer)~=U.key(actor)or not gotClass or U.key(privateClass)~=U.key(cls)or not separate then return false,'魂配置归属或标签内存独立性未确认'end
        local filtered,values={},{}
        for _,s in ipairs(before)do if not REMOVE[s]then filtered[#filtered+1]=s;values[#values+1]={TagName=FName(s)}end end
        local make=o.container
        local container
        if make then container=make(values)
        else
            local found,lib=pcall(StaticFindObject,'/Script/GameplayTags.Default__BlueprintGameplayTagLibrary')
            local made,value=call(found and lib or nil,'MakeGameplayTagContainerFromArray',values)
            if made then container=value end
        end
        if container==nil or not current(actor,r)or not U.valid(private)or not U.valid(source)then return false,'魂标签容器或实例失效'end
        local assigned=pcall(function()private.InitialTags=container end)
        if not assigned or signature(tags(private))~=signature(filtered)or signature(tags(source))~=signature(before)then
            return false,'魂标签配置读回失败；不继续初始化'
        end
        if not current(actor,r)or U.key(U.field(actor,'Actor Config'))~=U.key(source)then return false,'魂配置被其他逻辑接管'end
        local applied=pcall(function()actor['Actor Config']=private end)
        local verified=applied and U.key(U.field(actor,'Actor Config'))==U.key(private)
        say('私有本体配置：实例='..r.name..'；独立标签=true；隐藏/不可仇恨标签剔除='..(#before-#filtered)..'；原模板不变='..tostring(signature(tags(source))==signature(before))..'；ActorConfig读回='..tostring(verified))
        if not verified then return false,'魂私有配置绑定未确认'end
        r.source,r.private,r.phase,r.original=source,private,'prepared',signature(before)
        self.prepared=self.prepared+1;self.message='魂私有配置已读回，等待游戏内可见性和行为验证'
        return true
    end
    function self:finished(actor)
        local r=records[U.key(actor)or''];if not r then return true end
        if not current(actor,r)or not U.valid(r.private)or U.key(U.field(actor,'Actor Config'))~=U.key(r.private)
            or signature(tags(r.source))~=r.original then return false,'魂出生后的配置隔离未确认'end
        r.phase='finished';return true
    end
    function self:tick(members)
        if not self.alive or not next(records)then return end
        local owned={};for _,m in ipairs(members or{})do local key=U.key(m.actor);if key then owned[key]=true end end
        for key,r in pairs(records)do
            if not owned[key]or not current(r.actor,r)then records[key]=nil
            elseif r.phase=='finished'then
                local ai=o.aiOf and o.aiOf(r.actor);local controller=U.field(r.actor,'Controller')
                local read,hp=pcall(o.hp,r.actor)
                say('本体初始化读回：实例='..r.name..'；HP='..tostring(read and hp)..'；隐藏='..tostring(U.field(r.actor,'bHidden'))..'；Controller有效='..tostring(U.valid(controller))..'；AI有效='..tostring(U.valid(ai))..'；完整配装已应用=false')
                r.phase='observed'
            end
        end
    end
    function self:status()return {probe_supported=true,full_ready=false,prepared=self.prepared,message=self.message}end
    function self:cancel()epoch=epoch+1 end
    function self:silence()self.alive=false;epoch=epoch+1;context=nil end
    return self
end
return Body
