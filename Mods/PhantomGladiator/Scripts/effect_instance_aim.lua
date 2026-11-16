-- Private Niagara systems and collections for owned attacks; the world's player position is never written.
local U=require('ue_observe')
local Effects={}
Effects.paths={asset='/Script/Niagara.NiagaraComponent:SetAsset',activate='/Script/Engine.ActorComponent:Activate'}
Effects.systems={NS_ZuoShangLongTi_SwordFormation_202=true,
    NS_MengHua_SpaceTear_001=true,NS_Troop_WireAtk_001_Wire=true,
    NS_ChiYingGuRen_MaskRing_001=true,NS_ChiYingGuRen_MaskRing_002=true}
local COLLECTION='/PBZVFXPack/VFX/A_Niagara/CommonNPC/NPC_CharInfo_001.NPC_CharInfo_001'
local LIB='/Script/Niagara.Default__NiagaraFunctionLibrary'
local LIMIT_SECONDS=20
local function call(object,method,...)
    if not U.valid(object) then return false end
    local args={...};local ok,value=pcall(function()return object[method](object,table.unpack(args))end)
    return ok,U.unwrap(value)
end
local function name(object)
    local ok,value=call(object,'GetFullName');return ok and type(value)=='string' and value or nil
end
local function short(object)
    if not U.valid(object)then return nil end
    local ok,value=pcall(function()return object:GetFName():ToString()end)
    return ok and type(value)=='string' and value or nil
end
local function color(value)
    if not value then return nil end
    local ok,r,g,b,a=pcall(function()return value.R,value.G,value.B,value.A end)
    if ok and type(r)=='number' and type(g)=='number' and type(b)=='number' and type(a)=='number' then return {R=r,G=g,B=b,A=a}end
end
local function same(a,b)
    return a and b and math.abs(a.R-b.R)<0.5 and math.abs(a.G-b.G)<0.5 and math.abs(a.B-b.B)<0.5 and math.abs(a.A-b.A)<0.001
end
local function privateArray(copy,template,field)
    local a,b=U.field(copy,field),U.field(template,field)
    if U.kind(a)=='table'and U.kind(b)=='table'then return a~=b end
    if U.kind(a)~='TArray'or U.kind(b)~='TArray'then return false end
    local ok,x,y=pcall(function()return a:GetArrayDataAddress(),b:GetArrayDataAddress()end)
    return ok and type(x)=='number'and type(y)=='number'and(x==0 or y==0 or x~=y)
end
local function at(actor)
    local mesh=U.field(actor,'Mesh')
    local ok,spot=call(mesh,'K2_GetComponentLocation')
    if not ok then ok,spot=call(actor,'K2_GetActorLocation')end
    if not ok or not spot then return nil end
    local got,x,y,z=pcall(function()return spot.X,spot.Y,spot.Z end)
    local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
    if got and finite(x)and finite(y)and finite(z)then return {R=x,G=y,B=z,A=1}end
end
function Effects.new(options)
    local self={alive=true,changed=0,failed=0,state='idle'}
    local clock=options.clock or os.clock
    local find,construct=options.find or StaticFindObject,options.construct or StaticConstructObject
    local register,unregister=options.register or RegisterHook,options.unregister or UnregisterHook
    local groups,records,hooks,failAt={},{},{},{}
    local serial,frame,armedUntil,nextScan,loop,internal=0,0,0,0,nil,0
    local nextHook=0
    local messages={}
    local messageKeys,messageAt={},0
    local function log(key,text)
        if messages[key]==text then return end
        if messages[key]==nil then
            messageAt=messageAt%256+1
            local expired=messageKeys[messageAt]
            if expired then messages[expired]=nil end
            messageKeys[messageAt]=key
        end
        messages[key]=text;(options.log or function()end)('[EffectAim] '..text)
    end
    local function thread()
        if not options.inGameThread then return true end
        local ok,yes=pcall(options.inGameThread);return ok and yes==true
    end
    local function world()
        local value=options.world();return U.valid(value) and value or nil
    end
    local function own(comp)
        local ok,owner=call(comp,'GetOwner')
        return options.ownerOf(ok and U.valid(owner) and owner or comp)
    end
    local function allowed(key)
        return key and options.allowed(key)==true
    end
    local function mutate(comp,method,...)
        internal=internal+1;local ok,value=call(comp,method,...);internal=internal-1
        return ok,value
    end
    local function copy(template,outer,label)
        if type(construct)~='function' or not U.valid(template) or not U.valid(outer) then return nil end
        local got,class=call(template,'GetClass')
        local valid,isClass=call(class,'IsAnyClass')
        if not got or not valid or isClass~=true then return nil end
        serial=serial+1
        local ok,value=pcall(construct,class,outer,FName('PG_Aim_'..label..'_'..serial),0x40,0,false,false,template)
        if not ok or not U.valid(value) or U.key(value)==U.key(template) then return nil end
        local sameClass,readClass=call(value,'GetClass')
        local sameOuter,readOuter=call(value,'GetOuter')
        if not sameClass or U.key(readClass)~=U.key(class) or not sameOuter or U.key(readOuter)~=U.key(outer)then return nil end
        return value
    end
    local function defaultColor(currentWorld,parent)
        local found,lib=pcall(find,LIB)
        if not found or not U.valid(lib)then return nil end
        local ok,instance=call(lib,'GetNiagaraParameterCollection',currentWorld,parent)
        local read,value=call(instance,'GetColorParameter','CharRootPos')
        return ok and read and color(value) or nil
    end
    local function makeGroup(key,actor,currentWorld)
        local old=groups[key]
        if old and old.name==name(actor) and old.world==U.key(currentWorld) and U.valid(old.collection) then return old end
        local found,parent=pcall(find,COLLECTION)
        local template=found and U.field(parent,'DefaultInstance')
        if not U.valid(parent) or not U.valid(template) or U.key(U.field(template,'Collection'))~=U.key(parent) then return nil,'原版集合或模板未确认' end
        local instance=copy(template,actor,'Collection')
        if not instance or U.key(U.field(instance,'Collection'))~=U.key(parent) or U.valid(U.field(instance,'SourceMaterialCollectionInstance'))then return nil,'集合副本或材质来源未隔离' end
        local original=U.struct(U.field(template,'ParameterStorage'),'ParameterData')
        local cloned=U.struct(U.field(instance,'ParameterStorage'),'ParameterData')
        local unique,sourceAddress,copyAddress=pcall(function()return original:GetArrayDataAddress(),cloned:GetArrayDataAddress()end)
        if not unique or type(sourceAddress)~='number' or type(copyAddress)~='number' or sourceAddress==0 or copyAddress==0 or sourceAddress==copyAddress then return nil,'参数内存独立性未确认' end
        local before=defaultColor(currentWorld,parent)
        local variables=U.array(U.field(parent,'Parameters'))
        local overrides={}
        for _,variable in ipairs(variables or {})do
            local id=U.struct(variable,'Name')
            local ok,label=pcall(function()return id:ToString()end)
            if ok and type(label)=='string'and (label=='CharRootPos'or label:match('%.CharRootPos$'))then overrides[#overrides+1]=variable end
        end
        if #overrides~=1 then return nil,'CharRootPos参数声明未确认' end
        if not privateArray(instance,template,'OverridenParameters')then return nil,'集合覆盖列表内存未隔离' end
        local marked=pcall(function()
            local old=instance.OverridenParameters
            if U.kind(old)=='TArray'then old:Empty()end
            instance.OverridenParameters=overrides
        end)
        local markedBack=U.array(U.field(instance,'OverridenParameters'))
        if not marked or not markedBack or #markedBack~=1 then return nil,'集合覆盖列表写后读回失败' end
        local probe={R=31415.5,G=-27182.25,B=16180.75,A=1}
        local wrote=call(instance,'SetColorParameter','CharRootPos',probe)
        local read,value=call(instance,'GetColorParameter','CharRootPos')
        local unchanged=defaultColor(currentWorld,parent)
        if not wrote or not read or not same(color(value),probe) or not same(before,unchanged)then return nil,'私有参数探针或世界原值读回失败' end
        local group={actor=actor,name=name(actor),world=U.key(currentWorld),collection=instance,parent=parent,systems={},last=clock()}
        groups[key]=group
        log('collection:'..key,'创建私有目标集合：源='..tostring(group.name)..'；参数内存独立=true；写后读回=true；世界玩家参数未变=true')
        return group
    end
    local function system(group,original)
        local id=U.key(original);local known=id and group.systems[id]
        if known and known.name==name(original) and U.valid(known.copy)then return known.copy end
        if U.className(original)~='NiagaraSystem' then return nil,'系统类型不匹配' end
        local value=copy(original,group.actor,'System')
        if not value then return nil,'系统副本构造未确认' end
        local a,b=U.array(U.field(original,'EmitterHandles')),U.array(U.field(value,'EmitterHandles'))
        if not a or not b or #a==0 or #a~=#b then return nil,'系统发射器副本未确认' end
        for _,field in ipairs({'SystemSpawnScript','SystemUpdateScript'})do
            local source=U.field(original,field)
            if not U.valid(source) or U.key(U.field(value,field))~=U.key(source)then return nil,'系统脚本副本未确认：'..field end
        end
        local existing=U.array(U.field(original,'ParameterCollectionOverrides'))
        if not existing then return nil,'原版系统覆盖列表未确认' end
        local wanted={}
        for _,instance in ipairs(existing)do
            if not U.valid(instance)then return nil,'原版系统含失效覆盖集合' end
            if U.key(U.field(instance,'Collection'))~=U.key(group.parent)then wanted[#wanted+1]=instance end
        end
        wanted[#wanted+1]=group.collection
        if not privateArray(value,original,'ParameterCollectionOverrides')then return nil,'系统覆盖列表内存未隔离' end
        local wrote=pcall(function()
            local previous=value.ParameterCollectionOverrides
            if U.kind(previous)=='TArray'then previous:Empty()end
            value.ParameterCollectionOverrides=wanted
        end)
        local back=U.array(U.field(value,'ParameterCollectionOverrides'))
        if not wrote or not back or #back~=#wanted then return nil,'系统覆盖数量读回失败' end
        for i,instance in ipairs(wanted)do if U.key(back[i])~=U.key(instance)then return nil,'系统覆盖集合读回不一致' end end
        group.systems[id]={copy=value,name=name(original)}
        return value
    end
    local function updateGroup(group,key)
        local currentWorld=world()
        if not currentWorld or group.world~=U.key(currentWorld)or not U.inWorld(group.actor,currentWorld)then return false end
        if group.frame==frame then return true end
        local target=options.targetOf(key)
        if not U.valid(target)then return false end
        local spot=at(target)
        if not spot then return false end
        local wrote=call(group.collection,'SetColorParameter','CharRootPos',spot)
        local read,value=call(group.collection,'GetColorParameter','CharRootPos')
        if not wrote or not read or not same(color(value),spot)then return false end
        group.frame=frame;group.last=clock();group.point=spot
        return true
    end
    local function restore(item,reason,reactivate)
        if not U.valid(item.comp)or not U.valid(item.original)then return true end
        if U.key(U.field(item.comp,'Asset'))~=U.key(item.copy)then return true end
        local currentWorld=world()
        if not currentWorld or item.world~=U.key(currentWorld) or not U.inWorld(item.comp,currentWorld)then return true end
        local _,active=call(item.comp,'IsActive')
        local changed=mutate(item.comp,'SetAsset',item.original,false)
        local good=U.key(U.field(item.comp,'Asset'))==U.key(item.original)
        if good and (active==true or reactivate==true)then mutate(item.comp,'Activate',true)end
        log('restore:'..tostring(U.key(item.comp)),'还原特效资产（'..reason..'）：调用='..tostring(changed)..'；读回='..tostring(good))
        return good
    end
    local function bind(comp,key,original)
        local currentWorld=world();local actor=options.actorOf(key)
        if options.paused and options.paused()then return nil end
        if not allowed(key) or not U.valid(actor) or not currentWorld or not U.inWorld(actor,currentWorld)
            or not U.valid(comp) or not U.inWorld(comp,currentWorld) or not Effects.systems[short(original)] then return nil end
        local stamp=key..'|'..tostring(U.key(original))
        if clock()<(failAt[stamp] or 0)then return nil end
        local group,problem=makeGroup(key,actor,currentWorld)
        local asset
        if group then asset,problem=system(group,original)end
        if not asset or not updateGroup(group,key)then
            failAt[stamp]=clock()+5;self.failed=self.failed+1
            log('failed:'..stamp,'私有特效目标准备未确认：'..tostring(problem or '当前敌人或坐标读回失败')..'；源='..tostring(name(actor))..'；系统='..tostring(name(original))..'；未写世界玩家坐标')
            return nil
        end
        return {comp=comp,key=key,actor=actor,actorName=name(actor),original=original,copy=asset,group=group,world=U.key(currentWorld),since=clock()}
    end
    local function ensure(comp,key,original)
        local id=U.key(comp);if not id then return end
        local previous=records[id]
        if previous and previous.key==key and U.key(U.field(comp,'Asset'))==U.key(previous.copy)then return end
        if previous then if not restore(previous,'归属变化')then return end;records[id]=nil end
        local item=bind(comp,key,original)
        if not item then return end
        local known,active=call(comp,'IsActive')
        if not known or type(active)~='boolean'then return end
        records[id]=item
        if not mutate(comp,'SetAsset',item.copy,false)or U.key(U.field(comp,'Asset'))~=U.key(item.copy)then
            if restore(item,'绑定未确认',active)then records[id]=nil end
            return
        end
        if active then
            local read,running=call(comp,'IsActive')
            if not read or not running then mutate(comp,'Activate',true)end
            local checked,playing=call(comp,'IsActive')
            if not checked or playing~=true then if restore(item,'副本未运行',true)then records[id]=nil end;return end
        end
        records[id]=item;self.changed=self.changed+1
        log('bind:'..id,'隔离特效目标：源='..tostring(item.actorName)..'；系统='..tostring(short(original))..'；组件资产读回=true；世界玩家参数不写入')
    end
    local function scan()
        local ok,bullets=pcall(options.collect or FindAllOf,'PBZ_ParticleBullet')
        if not ok or type(bullets)~='table'then return end
        for _,bullet in ipairs(bullets)do
            local status=U.field(bullet,'BulletStatus')
            if status==1 or status==2 then
                local key=options.ownerOf(bullet)
                local comp=U.field(bullet,'ParticleComponent')
                local got,owner=call(comp,'GetOwner')
                if allowed(key) and U.valid(comp)and got and U.key(owner)==U.key(bullet)then
                    local current=U.field(comp,'Asset')
                    if U.valid(current)and Effects.systems[short(current)]then ensure(comp,key,current)end
                end
            end
        end
    end
    local function stopLoop()
        if loop then local ok,result=pcall(options.cancel or CancelDelayedAction,loop);if ok and result~=false then loop=nil end end
    end
    local function run()
        if not self.alive or not thread()then return end
        if not options.active()then armedUntil=0 end
        frame=frame+1
        if clock()<armedUntil and clock()>=nextScan then nextScan=clock()+0.25;scan()end
        for id,item in pairs(records)do
            local key=U.valid(item.comp)and own(item.comp)
            local bullet=select(2,call(item.comp,'GetOwner'))
            local status=U.field(bullet,'BulletStatus')
            local ended=status~=nil and status~=1 and status~=2 or clock()-item.since>LIMIT_SECONDS
            if not U.valid(item.comp)or U.key(U.field(item.comp,'Asset'))~=U.key(item.copy)then records[id]=nil
            elseif key~=item.key or not allowed(key)or name(item.actor)~=item.actorName or ended then
                if restore(item,'结束或移交')then records[id]=nil end
            elseif not options.paused or not options.paused()then updateGroup(item.group,key)end
        end
        if clock()>=armedUntil and not next(records)then stopLoop()end
    end
    local function startLoop()
        if loop then return end
        local ok,handle=pcall(options.loop or LoopInGameThreadWithDelay,50,run)
        if ok and handle~=nil then loop=handle else log('loop','特效隔离循环注册未确认')end
    end
    function self:arm()
        if not self.alive or not thread()then return end
        armedUntil=math.max(armedUntil,clock()+LIMIT_SECONDS);startLoop()
    end
    function self:tick()
        if not self.alive or not thread()then return end
        if options.active()and clock()>=nextHook then
            nextHook=clock()+3
            for kind,path in pairs(Effects.paths)do
                if not hooks[kind]then
                    local found,fn=pcall(find,path)
                    if found and U.valid(fn)then
                        local ok,a,b=pcall(register,path,function(context,asset)
                            if not self.alive or internal>0 or not thread()or not options.active()and not next(records)then return end
                            local comp=U.unwrap(context);local id=U.key(comp)
                            if not id then return end
                            local original=kind=='asset'and U.unwrap(asset)or U.field(comp,'Asset')
                            if not records[id]and(not U.valid(original)or not Effects.systems[short(original)])then return end
                            local old=records[id];local source=own(comp)
                            if old and source~=old.key then if restore(old,'激活前归属变化')then records[id]=nil end end
                            if kind=='asset' and allowed(source)then
                                if U.valid(original)and Effects.systems[short(original)]then self:arm()end
                            elseif kind=='activate'and allowed(source)then
                                if U.valid(original)and Effects.systems[short(original)]then ensure(comp,source,original);startLoop()end
                            end
                        end,function()end)
                        if ok and type(a)=='number'and type(b)=='number'then hooks[kind]={a,b}end
                    end
                end
            end
        end
        local used={};for _,item in pairs(records)do used[item.group]=true end
        for key,group in pairs(groups)do
            if not U.valid(group.actor)or group.name~=name(group.actor)or clock()-group.last>5 and not used[group]then groups[key]=nil end
        end
        for key,untilAt in pairs(failAt)do if clock()>=untilAt then failAt[key]=nil end end
    end
    function self:status()return {changed=self.changed,failed=self.failed,running=next(records)~=nil}end
    function self:silence()
        self.alive=false;stopLoop()
        for kind,ids in pairs(hooks)do pcall(unregister,Effects.paths[kind],ids[1],ids[2])end
    end
    return self
end
return Effects
