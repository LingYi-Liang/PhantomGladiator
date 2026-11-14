-- Classify the hit source, including a melee trace emitted by a ranged parent. Distance is not an attack type.
local U=require('ue_observe')
local Remote={}
local DATA={PBZ_ProjectileBulletData=true,PBZ_ProjectileEmitterData=true,PBZ_ParticleBulletData=true,PBZ_OverlapBulletData=true}
local BULLETS={PBZ_ProjectileBullet=true,PBZ_ProjectileEmitter=true,PBZ_ParticleBullet=true,PBZ_OverlapBullet=true}
local EXECUTION={PBZ_ExecutionBullet=true,PBZ_ExecutionBulletData=true,BP_PBZ_ExecutionBullet_C=true,BP_PBZ_ExecutionBulletData_C=true}
local function call(object,method,...)
    if not U.valid(object) then return nil end
    local args={...}
    local ok,result=pcall(function()return object[method](object,table.unpack(args))end)
    return ok and U.unwrap(result) or nil
end
function Remote.tag(value)
    value=U.unwrap(value)
    if type(value)=='string' then return value end
    local name=U.struct(value,'TagName')
    if type(name)=='string' then return name end
    local ok,text=pcall(function()return name:ToString()end)
    return ok and type(text)=='string' and text or nil
end
function Remote.isA(object,names)
    local cls=call(object,'GetClass')
    for _=1,24 do
        if not U.valid(cls) then return false end
        local name=call(cls,'GetFName')
        local ok,text=pcall(function()return name:ToString()end)
        if ok and names[text] then return true end
        cls=call(cls,'GetSuperStruct')
    end
    return false
end
function Remote.new(options)
    options=options or {}
    local self={}
    local function dataOf(bullet)
        local data=call(bullet,'GetData')
        if not U.valid(data) then data=U.field(bullet,'MyData') end
        if not U.valid(data) then data=U.field(bullet,'BulletData') end
        return U.valid(data) and data or nil
    end
    function self:bullet(bullet)
        local visited={}
        local original=bullet
        local known=false
        for depth=1,8 do
            local key=U.key(bullet)
            if not key or visited[key] then break end
            visited[key]=true
            local data=dataOf(bullet)
            if Remote.isA(bullet,EXECUTION) or Remote.isA(data,EXECUTION) then
                if depth==1 then return false,'投技' end
                break
            end
            if Remote.isA(bullet,BULLETS) or Remote.isA(data,DATA) then return true,depth==1 and '远程弹体' or '远程父弹体' end
            local attackType=U.valid(data) and Remote.tag(U.field(data,'AttackType'))
            if attackType and (attackType:find('HitReact.AttackType.Physical.Projectile',1,true)==1
                or attackType:lower():find('hitreact.attacktype.energy',1,true)==1) then return true,'远程攻击标签' end
            if options.fname then
                local tag={TagName=options.fname('Bullet.Tag.Feature.ControlledBullet')}
                if call(bullet,'HasMatchingTag',tag,false)==true or call(bullet,'HasTag',tag,false)==true then return true,'受控子弹' end
            end
            if options.isProjectile then
                local ok,value=pcall(options.isProjectile,bullet)
                if ok and value==true then return true,'原版飞行弹丸' end
            end
            if Remote.isA(bullet,{PBZ_SweepTraceBullet=true}) or Remote.isA(data,{PBZ_SweepTraceBulletData=true}) then known=true end
            bullet=U.field(bullet,'ParentBullet')
        end
        if known then return false,'近战扫掠' end
        return nil,U.valid(original) and '未识别弹体' or '无有效弹体'
    end
    function self:source(source)
        if not U.valid(source) then return nil,'无有效伤害源' end
        local bullet=U.field(source,'Bullet')
        if U.valid(bullet) then return self:bullet(bullet) end
        if Remote.isA(source,BULLETS) or Remote.isA(source,{PBZ_SweepTraceBullet=true}) then return self:bullet(source) end
        return nil,'非弹体伤害源'
    end
    return self
end
return Remote
