-- Follow the player's dynamic material values on private NPC instances. Geometry and animation stay in hun_look.
local U=require('ue_observe')
local Materials={}
local SLOT_BUDGET=12
local OVERRIDES={'ScalarParameterValues','VectorParameterValues','TextureParameterValues'}

-- Native scalar, color and texture overrides. Bound reflection on unusually large or opaque materials.
-- Those still receive the engine's quick parameter copy at a slower interval.
local function arrayAt(a,i)return U.unwrap(a[i]) end
local function length(a)return #a end
local function fingerprint(material,text)
    local values,entries={},{}
    local total=0
    for _,field in ipairs(OVERRIDES) do
        local rows=U.field(material,field)
        if not rows then return end
        local ok,n=pcall(length,rows)
        if not ok or type(n)~='number' or n<0 or total+n>32 then return end
        total=total+n
        for i=1,n do
            local got,row=pcall(arrayAt,rows,i)
            if not got or not row then return end
            local info=U.struct(row,'ParameterInfo')
            local name=text(U.struct(info,'Name'))
            local layer=U.struct(info,'Association')
            local index=U.struct(info,'Index')
            if not name or type(layer)~='number' or type(index)~='number' then return end
            local key=field..':'..#name..':'..name..':'..layer..':'..index
            local val,read=U.struct(row,'ParameterValue')
            if not read then return end
            local value
            if field=='ScalarParameterValues' then
                if type(val)~='number' then return end
                value=tostring(val)
            elseif field=='VectorParameterValues' then
                local r,g,b,a=U.struct(val,'R'),U.struct(val,'G'),U.struct(val,'B'),U.struct(val,'A')
                if type(r)~='number' or type(g)~='number' or type(b)~='number' or type(a)~='number' then return end
                value=table.concat({r,g,b,a},',')
            else
                value=U.key(val) or '-'
            end
            entries[key]=value
            values[#values+1]=key..'='..value
        end
    end
    return {key=table.concat(values,'|'),entries=entries}
end
local function copiedOverrides(source,destination)
    if not source or not destination then return false end
    for k,v in pairs(source.entries) do if destination.entries[k]~=v then return false end end
    return true
end

function Materials.new(o)
    local self={}
    local call=o.call
    local function ownerKey(comp)
        local _,owner=call(comp,'GetOwner')
        return U.key(owner)
    end
    local function stamp(material,cache)
        local key=U.key(material)
        if not key then return end
        if cache[key]==nil then cache[key]=fingerprint(material,o.text) or false end
        return cache[key] or nil
    end
    local function write(group,part,b,mine,theirs,base,now,cache)
        local target,createdKey=base,nil
        local baseKey,sourceKey=U.key(base),U.key(theirs)
        local dynamic=baseKey~=sourceKey
        local function attached()
            return U.valid(group.actor) and ownerKey(part.dest)==U.key(group.actor) and ownerKey(part.source)==part.sourceOwner
                and U.key(o.asset(part.dest))==part.asset and (not group.still or group.still())
        end
        if dynamic then
            if now and b.retrySource==sourceKey and b.retryAt and now<b.retryAt and b.retryAt-now<=32 then return end
            local _,outer=call(mine,'GetOuter')
            local reuse=b.owned and U.key(mine)==b.owned and b.base==baseKey and U.key(outer)==U.key(part.dest)
            local materialStamp=now and stamp(theirs,cache)
            if reuse and b.source==sourceKey and now then
                if materialStamp and materialStamp.key==b.sourceStamp and b.destStamp then
                    local observed=stamp(mine,cache)
                    if observed and observed.key==b.destStamp then return end
                elseif (not materialStamp or not b.destStamp) and b.copiedAt and now>=b.copiedAt and now-b.copiedAt<8 then return end
            end
            local mid=mine
            if not reuse then
                local _,made=call(part.dest,'CreateDynamicMaterialInstance',b.slot,base,o.fname('None'))
                mid=made
            end
            local key=U.key(mid)
            local _,parent=call(mid,'GetOuter')
            if not attached() then return false end
            local visible,assigned=call(part.dest,'GetMaterial',b.slot)
            if not visible or (key and U.key(assigned)~=U.key(mine) and U.key(assigned)~=key and U.key(assigned)~=baseKey) then return false end
            if key and key~=sourceKey and U.key(parent)==U.key(part.dest) and (reuse or key~=U.key(mine)) then createdKey=key end
            if key and not createdKey and U.key(assigned)==key and U.key(mine)~=key then return false end
            if createdKey and call(mid,'K2_CopyMaterialInstanceParameters',theirs,true) then
                target=mid
                b.retrySource,b.retryAt,b.retryDelay=nil,nil,nil
                b.owned,b.base,b.source,b.copiedAt=key,baseKey,sourceKey,now
                if cache then cache[key]=nil end
                local observed=materialStamp and stamp(mid,cache)
                b.sourceStamp=materialStamp and materialStamp.key
                b.destStamp=copiedOverrides(materialStamp,observed) and observed.key or nil
            else
                if now then
                    local delay=b.retrySource==sourceKey and math.min(32,(b.retryDelay or 1)*2) or 2
                    b.retrySource,b.retryDelay,b.retryAt=sourceKey,delay,now+delay
                end
                if reuse then return false end
                b.owned=nil
            end
        else b.owned=nil end
        if not dynamic and U.key(mine)==baseKey then return end
        if not attached() then return false end
        local received,current=call(part.dest,'GetMaterial',b.slot)
        if not received then return false end
        if U.key(current)~=U.key(target) then
            if now and U.key(current)~=b.installed and U.key(current)~=baseKey and U.key(current)~=createdKey then return false end
            call(part.dest,'SetMaterial',b.slot,target)
        end
        local _,actual=call(part.dest,'GetMaterial',b.slot)
        if U.key(actual)~=U.key(target) then return false end
        b.installed=U.key(actual)
        if part.body and group.bodyOverrides then group.bodyOverrides.written[b.slot]=target end
        return true
    end
    function self:bind(group,dest,source,label)
        if not U.valid(source) or not U.valid(dest) then return end
        local got,count=call(source,'GetNumMaterials')
        if not got or type(count)~='number' then return end
        local ok,destCount=call(dest,'GetNumMaterials')
        count=math.min(count,ok and type(destCount)=='number' and destCount or count,32)
        if count<=0 then return end
        local actorKey=U.key(group.actor)
        local sourceOwner=ownerKey(source)
        if not actorKey or not sourceOwner or sourceOwner==actorKey or ownerKey(dest)~=actorKey then return end
        local part={dest=dest,source=source,asset=U.key(o.asset(dest)),sourceAsset=U.key(o.asset(source)),
            sourceOwner=sourceOwner,body=label=='身体'}
        local entries
        if not group.snapshotLook then
            entries=group.materialSlots or {}
            group.materialSlots=entries
        end
        local wrote,failed=0,0
        for i=0,count-1 do
            local read,theirs=call(source,'GetMaterial',i)
            local found,mine=call(dest,'GetMaterial',i)
            local b={part=part,slot=i,installed=U.key(mine)}
            if found and entries then entries[#entries+1]=b end
            local base=read and o.base(theirs)
            if found and base and (U.key(base)~=b.installed or U.key(theirs)~=U.key(base)) and not o.phantom(base) then
                if wrote+failed==0 then o.say('即将 抄材质 实例='..group.name..' '..label..' SetMaterial（槽 '..i..' 起，玩家只读）') end
                if write(group,part,b,mine,theirs,base) then wrote=wrote+1 else failed=failed+1 end
            end
        end
        if wrote+failed>0 then o.say('抄材质 读回 实例='..group.name..' '..label..' 写入='..wrote..' 没读回='..failed) end
    end
    local function refresh(job,now,limit,cache)
        local r,group=job.r,job.group
        if r.dead or not r.appearance or not r.still or not r.still() or (r.activeRig or r)~=group then return 0 end
        local list=group.materialSlots
        local actorKey=U.key(r.actor)
        if not list or not actorKey then return 0 end
        local start=group.materialCursor or 1
        local stop=math.min(#list,start+limit-1)
        local previous,mayWrite
        for i=start,stop do
            local b=list[i];local part=b.part
            if previous~=part then
                previous=part
                mayWrite=job.player==part.sourceOwner and ownerKey(part.source)==job.player
                    and ownerKey(part.dest)==actorKey and U.key(o.asset(part.dest))==part.asset and U.key(o.asset(part.source))==part.sourceAsset
            end
            if mayWrite and not b.detached then
                local found,mine=call(part.dest,'GetMaterial',b.slot)
                if found and U.key(mine)~=b.installed then
                    -- A third-party system owns this slot now.
                    b.detached=true
                elseif found then
                    local read,theirs=call(part.source,'GetMaterial',b.slot)
                    local base=read and o.base(theirs)
                    if base and not o.phantom(base) then
                        local written=write(group,part,b,mine,theirs,base,now,cache)
                        if written~=nil and (not group.materialReport or now-group.materialReport>=60) then
                            group.materialReport=now
                            o.say('复查跟随材质 实例='..r.name..' 槽='..b.slot..' 材质槽读回='..tostring(written)
                                ..' 参数读回='..(b.destStamp and '已核对' or '未核实'))
                        end
                    end
                end
            end
        end
        group.materialCheck=now
        if stop<#list then
            group.materialCursor=stop+1
            r.appearance.nextCheck=math.min(r.appearance.nextCheck,now+.5)
        else group.materialCursor=1 end
        return stop-start+1
    end
    function self:offer(r,group,now,player,sweep)
        if not group.materialSlots or #group.materialSlots==0 or not player then return end
        local job={r=r,group=group,player=player}
        if sweep and sweep.materialJobs then
            local jobs=sweep.materialJobs;jobs[#jobs+1]=job
        else refresh(job,now,SLOT_BUDGET,{}) end
    end
    function self:flush(jobs,now)
        if #jobs==0 then return end
        -- Oldest first so a large simultaneous batch cannot starve the last clone.
        if #jobs>1 then table.sort(jobs,function(a,b)return (a.group.materialCheck or -math.huge)<(b.group.materialCheck or -math.huge) end) end
        local left,cache=SLOT_BUDGET,{}
        for i,job in ipairs(jobs) do
            if left>0 then
                local share=math.max(1,math.floor(left/(#jobs-i+1)))
                left=left-refresh(job,now,share,cache)
            elseif job.r.appearance then
                job.r.appearance.nextCheck=math.min(job.r.appearance.nextCheck,now+.5)
            end
        end
    end
    return self
end
return Materials
