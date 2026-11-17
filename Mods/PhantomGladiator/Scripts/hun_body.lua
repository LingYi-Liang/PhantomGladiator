-- Experimental, owned NPC body only. Never possesses a player or edits a shared config.
-- The body is born through the normal summon chain with its template untouched. The two tags its
-- template starts with (cannot be hated, forced hide) are then cleared on that one instance and read back.
local U=require('ue_observe')
local Body={path='/PBZCombatAsset/ActorData/Mobs/000_Hun/BP_Monster_Hun.BP_Monster_Hun_C'}
local CONFIG='/PBZCombatAsset/ActorData/Mobs/000_Hun/ActorConfig/ActorC_Monster_Hun.ActorC_Monster_Hun'
local ABILITY_UTILS='/Script/SGameUtils.Default__AbilityUtils'
local CLEAR={'AI.Hatred.CanNotBeHatred','CharacterState.Unselectable.Force.Hide'}
local MESH_CLASSES={'SkeletalMeshComponent','StaticMeshComponent','GroomComponent'}
local ASSET_FIELDS={'SkeletalMeshAsset','SkinnedAsset','StaticMesh','GroomAsset'}
-- Support cycles after birth during which the tags are read again, in case the game adds them late.
local WATCH=20
local MAX_COMPONENT_LINES=48
local function call(o,m,...)
    if not U.valid(o)then return false end
    local a,n={...},select('#',...);local ok,value=pcall(function()return o[m](o,table.unpack(a,1,n))end)
    return ok,U.unwrap(value)
end
local function name(o)local ok,n=call(o,'GetFullName');return ok and type(n)=='string'and n or nil end
local function short(o)local n=name(o);return n and(n:match('[%.:]([^%.:]+)$')or n)or'?'end
local function tag(t)
    local v=U.struct(t,'TagName');if type(v)=='string'then return v end
    local ok,s=pcall(function()return v:ToString()end);return ok and s or nil
end
local function tags(config)
    local container=U.field(config,'InitialTags');local array=U.struct(container,'GameplayTags');local values=U.array(array)
    if not values then return nil end
    local result={};for _,v in ipairs(values)do local s=tag(v);if not s then return nil end;result[#result+1]=s end
    return result
end
function Body.new(o)
    local self={alive=true,prepared=0,failed=0,message='完整魂角色尚未接入；可进行独立本体验证'}
    local context,records,batch,epoch,dumped=nil,{},0,0,{}
    local find=o.find or StaticFindObject
    local findAll=o.findAll or FindAllOf
    local fname=o.fname or FName
    local function say(s)(o.log or function()end)('[HunBody] '..s)end
    local function current(actor,record)
        local world=o.world();local player=o.player()
        return self.alive and U.valid(world)and U.inWorld(actor,world)and U.key(actor)~=U.key(player)
            and U.npcPath(actor)==Body.path and(not record or record.epoch==epoch and record.world==U.key(world)and record.name==name(actor))
    end
    -- Reads both tags on this instance, sets a non-zero one to zero and reads it again.
    -- Returns whether both read zero afterwards, plus one text with every value read.
    local function clear(r)
        local asc=U.field(r.actor,'AbilitySystemComponent')
        if not U.valid(asc)then return false,'ASC未就绪'end
        local parts,zero,lib={},true,nil
        for _,tagName in ipairs(CLEAR)do
            local value={TagName=fname(tagName)}
            local got,before=call(asc,'GetGameplayTagCount',value)
            before=got and type(before)=='number'and before or nil
            local wrote,after='未写',before
            if before and before>0 then
                if lib==nil then local found,object=pcall(find,ABILITY_UTILS);lib=found and U.valid(object)and object or false end
                if not lib then wrote='找不到AbilityUtils'
                elseif not current(r.actor,r)then wrote='实例已变化'
                else wrote=tostring(call(lib,'SetLooseGameplayTagCount',r.actor,value,0)==true)end
                local again,count=call(asc,'GetGameplayTagCount',value)
                after=again and type(count)=='number'and count or nil
            end
            if after~=0 then zero=false end
            parts[#parts+1]=tagName..' '..tostring(before)..'→'..tostring(after)..'（写入='..wrote..'）'
        end
        return zero,table.concat(parts,'；')
    end
    local function hidden(actor)local value=U.field(actor,'bHidden');if type(value)=='boolean'then return value end;return nil end
    -- Read-only list of the mesh components this instance owns, once per summon request.
    local function meshes(r)
        local key,lines,total=U.key(r.actor),{},0
        for _,className in ipairs(MESH_CLASSES)do
            local ok,list=pcall(findAll,className)
            for _,component in ipairs(ok and type(list)=='table'and list or{})do
                if U.valid(component)then
                    local gotOwner,owner=call(component,'GetOwner')
                    local level=gotOwner and U.key(owner)==key and 1 or nil
                    if not level and gotOwner and U.valid(owner)then
                        local gotParent,parent=call(owner,'GetOwner')
                        if gotParent and U.key(parent)==key then level=2 end
                    end
                    if level then
                        total=total+1
                        if #lines<MAX_COMPONENT_LINES then
                            local asset
                            for _,property in ipairs(ASSET_FIELDS)do
                                local value=U.field(component,property)
                                if U.valid(value)then asset=value;break end
                            end
                            local gotVisible,visible=call(component,'IsVisible')
                            lines[#lines+1]=(U.className(component)or'?')..' '..short(component)..(level==2 and'（挂件）'or'')
                                ..' 资源='..(asset and short(asset)or'无')..' 可见='..tostring(gotVisible and visible)
                                ..' 游戏内隐藏='..tostring(U.field(component,'bHiddenInGame'))..' 强制LOD='..tostring(U.field(component,'ForcedLodModel'))
                        end
                    end
                end
            end
        end
        say('网格组件：实例='..r.name..'；共'..total..'个'..(total>#lines and'，只列前'..#lines..'个'or''))
        for _,line in ipairs(lines)do say('  '..line)end
    end
    local function describe(r)
        local ai=o.aiOf and o.aiOf(r.actor);local controller=U.field(r.actor,'Controller')
        local read,hp=pcall(o.hp,r.actor)
        return 'HP='..tostring(read and hp)..'；隐藏='..tostring(hidden(r.actor))..'；Controller有效='..tostring(U.valid(controller))..'；AI有效='..tostring(U.valid(ai))
    end
    function self:spawn(arena,team,count,revision)
        if context or not self.alive then return {ok=false,message='魂本体验证正在处理',spawned_count=0}end
        if team~='blue'and team~='red'and team~='neutral'and team~='companion'then return {ok=false,message='阵营无效',spawned_count=0}end
        if type(count)~='number'or count%1~=0 or count<1 or count>100 then return {ok=false,message='数量须为1～100',spawned_count=0}end
        local world=o.world();if not U.valid(world)then return {ok=false,message='当前世界未就绪',spawned_count=0}end
        batch=batch+1
        context={world=U.key(world),revision=revision,epoch=epoch,batch=batch}
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
        records[key]={actor=actor,name=n,world=context.world,revision=context.revision,epoch=context.epoch,batch=context.batch,phase='captured',
            refused=context.epoch~=epoch or not n or not current(actor)or context.world~=U.key(o.world())}
    end
    -- Before the game initialises the body: identity only. Nothing is written and the template is only read.
    function self:prepare(actor)
        local r=records[U.key(actor)or''];if not r then return true end
        if r.refused or not current(actor,r)then return false,'魂本体身份或世界已变化'end
        local source=U.field(actor,'Actor Config');local sourceName=name(source)
        local initial=tags(source)
        say('出生前读回：实例='..r.name..'；配置='..tostring(sourceName and sourceName:match(' (/.+)$'))..'；是预期模板='..tostring(sourceName~=nil and sourceName:match(' (/.+)$')==CONFIG)
            ..'；模板初始标签='..(initial and table.concat(initial,'|')or'未读回')..'；不复制、不改模板')
        r.phase='prepared';return true
    end
    function self:finished(actor)
        local r=records[U.key(actor)or''];if not r then return true end
        if not current(actor,r)then return false,'魂本体身份或世界已变化'end
        local zero,text=clear(r)
        r.phase,r.checks,r.tags,r.zero='finished',0,text,zero
        say('出生后标签：实例='..r.name..'；'..text..'；两项都为0='..tostring(zero)..'；'..describe(r))
        self.prepared=self.prepared+1
        self.message=zero and'魂已正常出生，隐藏与不可仇恨标签读回为0，等待画面和行为验证'or'魂已正常出生，但隐藏或不可仇恨标签还没读回为0，可能看不见或不被索敌'
        return true
    end
    function self:tick(members)
        if not self.alive or not next(records)then return end
        local owned={};for _,m in ipairs(members or{})do local key=U.key(m.actor);if key then owned[key]=true end end
        for key,r in pairs(records)do
            if not owned[key]or not current(r.actor,r)then records[key]=nil
            elseif(r.phase=='finished'or r.phase=='observed')and r.checks<WATCH then
                r.checks=r.checks+1
                local zero,text=clear(r)
                if text~=r.tags then say('标签变化（第'..r.checks..'次复查）：实例='..r.name..'；'..text..'；两项都为0='..tostring(zero))end
                r.tags,r.zero=text,zero
                r.streak=zero and(r.streak or 0)+1 or 0
                if r.phase=='finished'then
                    say('本体初始化读回：实例='..r.name..'；'..describe(r)..'；完整配装已应用=false')
                    if not dumped[r.batch]then
                        dumped[r.batch]=true
                        local listed,why=pcall(meshes,r)
                        if not listed then say('网格组件读取中断：'..tostring(why))end
                    end
                    r.phase='observed'
                elseif r.streak>=2 and hidden(r.actor)==true and not r.shown then
                    -- The tags have read zero for two cycles in a row and the game still keeps the actor hidden.
                    r.shown=true
                    local wrote=call(r.actor,'SetActorHiddenInGame',false)
                    say('解除隐藏：实例='..r.name..'；SetActorHiddenInGame(false)调用='..tostring(wrote==true)..'；隐藏读回='..tostring(hidden(r.actor)))
                end
                if r.checks==WATCH then
                    say('复查结束：实例='..r.name..'；'..text..'；两项都为0='..tostring(zero)..'；'..describe(r))
                    self.message=zero and'魂标签持续为0；外观和战斗表现以画面为准'or'魂的隐藏或不可仇恨标签没能保持为0，见日志'
                end
            end
        end
    end
    function self:status()return {probe_supported=true,full_ready=false,prepared=self.prepared,message=self.message}end
    function self:cancel()epoch=epoch+1 end
    function self:silence()self.alive=false;epoch=epoch+1;context=nil end
    return self
end
return Body
