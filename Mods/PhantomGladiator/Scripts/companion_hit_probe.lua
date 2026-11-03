-- Experiment (Config.EnableCompanionHitProbe), read only: why a companion's area attacks hit the player
-- (reported on v0.37.2). A hit is decided per bullet, not per actor pair: every bullet (sweep, overlap,
-- particle, projectile; SGameCombatSystem.hpp UBulletObjectBase/ABulletActorBase) carries its data's
-- FactionTarget (Enemy/Ally/Both/None) and FactionCanTargetSelf (PBZCombatAsset.hpp UPBZ_DamageBulletDataBase),
-- and an attack module with a faction calculator, required/ignored tags and IsValidTarget. A companion only
-- has the player's faction tag and a friendly relation override on its own Faction Component.
-- While a companion is out, about once a second the live bullets it owns are found, and each kind of attack
-- is logged once: bullet class, source ability, data, those rules, and IsValidTarget(player) next to
-- IsValidTarget(its current enemy). Every player HP drop is logged with the attacks live at that moment
-- (any owner) that the module says may hit the player. The companion's and the player's faction tags and
-- relations are logged once per companion. Nothing is written.
local U=require('ue_observe')
local Probe={}
local SCAN_SECONDS,SUMMARY_SECONDS=1,10
local SCAN_LIMIT,QUERY_LIMIT=2500,10
local KIND_LINES,DROP_LINES,FACTION_LINES=80,120,20
local TARGETS={[0]='只打敌人',[1]='只打友方',[2]='都打',[3]='都不打'}
local ATTITUDES={[0]='友好',[1]='中立',[2]='敌对'}
local RUNNING=2 -- EBulletStatus::Running
local BASES={'BulletObjectBase','BulletActorBase'}

local function short(s)
    s=tostring(s):gsub('[\r\n]',' ')
    return #s>160 and s:sub(1,160)..'…' or s
end
local function fullName(object)
    if not U.valid(object) then return nil end
    local ok,name=pcall(function()return object:GetFullName()end)
    return ok and type(name)=='string' and name or nil
end
-- "Class /Script/M.Name" -> "Name"; "BlueprintGeneratedClass /P/BP_X.BP_X_C" -> "BP_X_C";
-- "PBZ_OverlapBulletData /P/DA_X.DA_X" -> "DA_X"; "... /P/GA_X.GA_X:Bullet_3" -> "GA_X:Bullet_3"
local function objectName(object)
    local name=fullName(object)
    if not name then return '?' end
    local tail=name:match('([^/%s]+)$') or name
    local outer,inner=tail:match('^([^.]+)%.(.+)$')
    if not outer then return tail end
    if inner==outer then return outer end
    local sub=inner:match(':(.+)$')
    return sub and (outer..':'..sub) or inner
end
-- The pool scan touches every bullet: a plain IsValid per object; the engine check (U.valid) is kept for
-- the few bullets that belong to a companion.
local function rawValid(object)
    if object==nil then return false end
    local ok,valid=pcall(function()return object:IsValid()end)
    return ok and valid==true
end
local function rawKey(object)
    if not rawValid(object) then return nil end
    local ok,address=pcall(function()return object:GetAddress()end)
    return ok and address~=nil and tostring(address) or nil
end
local function className(object)
    if not U.valid(object) then return '?' end
    local ok,class=pcall(function()return object:GetClass()end)
    return ok and objectName(class) or '?'
end
local function tagName(tag)
    local name=U.struct(tag,'TagName')
    if name==nil then return '?' end
    local ok,text=pcall(function()return name:ToString()end)
    return ok and type(text)=='string' and text or '?'
end
local function tags(container)
    local list=U.array(U.struct(container,'GameplayTags'))
    if not list then return '?' end
    if #list==0 then return '无' end
    local out={}
    for i=1,math.min(#list,8)do out[#out+1]=tagName(list[i]) end
    return table.concat(out,',')..(#list>8 and ('…共'..#list) or '')
end
local function kindOf(class)
    if class:find('Overlap') then return '范围' end
    if class:find('SweepTrace') or class:find('ShachiHook') then return '挥砍' end
    if class:find('Particle') then return '特效范围' end
    if class:find('Emitter') then return '发射器' end
    if class:find('Projectile') then return '飞行物' end
    return '其他'
end

function Probe.new(options)
    local log=options.log or function()end
    local findAll=options.findAll or function(name)return FindAllOf(name)end
    local clock=options.clock or os.clock
    local self={kinds={},order={},factionDone={},lines={kind=0,drop=0,faction=0},offsets={},
        window={attacks=0,drops=0,lost=0,scanned={}},lastScan=-math.huge,lastSummary=nil}
    local function say(kind,text)
        if self.lines[kind]>=({kind=KIND_LINES,drop=DROP_LINES,faction=FACTION_LINES})[kind] then return end
        self.lines[kind]=self.lines[kind]+1
        log('[CompanionHit] '..text)
    end
    local function query(module,target)
        if not U.valid(module) or not U.valid(target) then return nil end
        local ok,value=pcall(function()return module:IsValidTarget(target)end)
        if not ok then return nil end
        value=U.unwrap(value)
        if type(value)=='boolean' then return value end
        return nil
    end
    local function attackModule(bullet)
        local module=U.field(bullet,'AttackModule')
        if U.valid(module) then return module end
        for _,item in ipairs(U.array(U.field(bullet,'Modules')) or {})do
            if U.valid(item) and className(item):find('AttackModule') then return item end
        end
        return nil
    end
    -- The first live enemy on the companion's hatred list, for comparison with the player.
    local function enemyOf(actor,player)
        local hm=U.field(actor,'BP_PBZHatredManagerComponent')
        for _,entry in ipairs(U.array(U.field(hm,'HatredList')) or {})do
            if U.valid(entry) and U.key(entry)~=U.key(player) then return entry end
        end
        return nil
    end
    local function distance(a,b)
        if not options.location then return nil end
        local pa,pb=options.location(a),options.location(b)
        if not pa or not pb then return nil end
        local ok,d=pcall(function()return math.sqrt((pa.X-pb.X)^2+(pa.Y-pb.Y)^2+(pa.Z-pb.Z)^2)/100 end)
        return ok and d or nil
    end
    local function show(v)return v==nil and '?' or tostring(v) end

    -- Faction tags and relations, once per companion.
    local function factions(actor,player)
        local key=U.key(actor)
        if not key or self.factionDone[key] or not U.valid(player) then return end
        self.factionDone[key]=true
        local mine,theirs=U.field(actor,'Faction Component'),U.field(player,'Faction Component')
        local function current(component)
            local ok,tag=pcall(function()return component:GetCurrnetFaction()end)
            return ok and U.unwrap(tag) or nil
        end
        local function relation(component,other)
            local ok,value=pcall(function()return component:GetFactionRelation(other)end)
            value=ok and tonumber(U.unwrap(value)) or nil
            return value and (ATTITUDES[value] or tostring(value)) or '?'
        end
        local myTag,playerTag=current(mine),current(theirs)
        -- The tag table alone (no per-actor override), the way a bullet compares two factions.
        local tagged='?'
        local subsystem=options.factionSubsystem and options.factionSubsystem()
        if U.valid(subsystem) and myTag~=nil and playerTag~=nil then
            local ok,value=pcall(function()return subsystem:GetFactionRelationFromTags(myTag,playerTag)end)
            value=ok and tonumber(U.unwrap(value)) or nil
            tagged=value and (ATTITUDES[value] or tostring(value)) or '?'
        end
        say('faction','阵营 随从='..className(actor)..' 随从阵营='..(myTag and tagName(myTag) or '?')..' 玩家阵营='..(playerTag and tagName(playerTag) or '?')
            ..' 组件关系 随从→玩家='..relation(mine,player)..' 玩家→随从='..relation(theirs,actor)..' 阵营表 随从阵营→玩家阵营='..tagged)
    end

    -- Live bullets of the given owners (companions), or of anyone when `everyone` (an HP drop).
    local function scan(owners,player,everyone)
        local found={}
        local playerKey=U.key(player)
        for _,base in ipairs(BASES)do
            local ok,list=pcall(findAll,base)
            if ok and type(list)=='table' then
                self.window.scanned[base]=#list
                local offset=(self.offsets[base] or 0)%math.max(#list,1)
                local checked=0
                for step=1,math.min(#list,SCAN_LIMIT)do
                    local bullet=list[(offset+step-1)%#list+1]
                    checked=step
                    local owner
                    if rawValid(bullet) then
                        local got,value=pcall(function()return bullet.BulletOwnerAvatar end)
                        owner=got and U.unwrap(value) or nil
                    end
                    local ownerKey=rawKey(owner)
                    local ours=ownerKey and owners[ownerKey]
                    if (ours or (everyone and ownerKey and ownerKey~=playerKey)) and U.valid(bullet) and U.valid(owner) then
                        local status=U.unwrap(U.field(bullet,'BulletStatus'))
                        local destroyed=U.unwrap(U.field(bullet,'Destroyed'))
                        if tonumber(status)==RUNNING and destroyed~=true then
                            found[#found+1]={bullet=bullet,owner=owner,companion=ours~=nil}
                        end
                    end
                end
                self.offsets[base]=(offset+checked)%math.max(#list,1)
            end
        end
        return found
    end
    -- One record per kind of attack (owner class + bullet data), described and queried once; the player
    -- query is repeated every 10 s and logged again only when its answer changes.
    local function record(entry,player,now,budget)
        local bullet,owner=entry.bullet,entry.owner
        local data=U.field(bullet,'BulletData')
        local class=className(bullet)
        local key=className(owner)..'|'..objectName(data)
        local kind=self.kinds[key]
        if not kind then
            kind={owner=className(owner),data=objectName(data),class=class,count=0}
            self.kinds[key]=kind;self.order[#self.order+1]=key
        end
        kind.companion=kind.companion or entry.companion
        kind.count=kind.count+1
        if entry.companion then self.window.attacks=self.window.attacks+1 end
        local module=attackModule(bullet)
        if not kind.described or (budget.n>0 and now-(kind.askedAt or -math.huge)>=10) then
            budget.n=budget.n-1;kind.askedAt=now
            local hitsPlayer=query(module,player)
            local enemy=entry.companion and enemyOf(owner,player) or nil
            local hitsEnemy
            if enemy then hitsEnemy=query(module,enemy) end
            local changed=kind.described and hitsPlayer~=kind.hitsPlayer
            kind.hitsPlayer,kind.hitsEnemy=hitsPlayer,hitsEnemy
            if not kind.described or changed then
                local target=tonumber(U.unwrap(U.field(data,'FactionTarget')))
                say('kind',(changed and '攻击判定变化 ' or (entry.companion and '随从攻击 ' or '其他单位攻击 '))
                    ..'所属='..kind.owner..' 类型='..kindOf(class)..'('..class..') 招式='..className(U.field(bullet,'BulletSourceAbility'))
                    ..' 数据='..kind.data..' 打谁='..(target and (TARGETS[target] or tostring(target)) or '?')
                    ..' 能打同阵营='..show(U.unwrap(U.field(data,'FactionCanTargetSelf')))
                    ..' 必需标签='..tags(U.field(module,'TargetRequiredTags'))..' 忽略标签='..tags(U.field(module,'TargetIgnoredTags'))
                    ..' 阵营计算器='..objectName(U.field(module,'FactionCalculator'))
                    ..' 能打玩家='..show(hitsPlayer)..(entry.companion and (' 能打当前敌人('..(enemy and className(enemy) or '无')..')='..show(hitsEnemy)) or ''))
            end
            kind.described=true
        end
        return kind
    end

    function self:tick()
        local now=clock()
        local player=options.getPlayer and options.getPlayer()
        local owners,companions={},{}
        for _,member in ipairs(options.members and options.members() or {})do
            local key=member.team=='companion' and U.key(member.actor)
            if key then owners[key]=member.actor;companions[#companions+1]=member.actor end
        end
        if #companions==0 or not U.valid(player) then self.playerHP=nil;return end
        for _,actor in ipairs(companions)do factions(actor,player) end
        self.lastSummary=self.lastSummary or now
        local hp=options.hp and options.hp(player)
        if type(hp)=='number' and type(self.playerHP)=='number' and hp<self.playerHP-0.5 then
            -- Who could have done it: every live attack that may hit the player, any owner.
            local budget={n=QUERY_LIMIT}
            local suspects,nearest,nearestD={},nil,nil
            for _,entry in ipairs(scan(owners,player,true))do
                local kind=record(entry,player,now,budget)
                if kind.hitsPlayer then suspects[#suspects+1]=(entry.companion and '随从 ' or '')..kind.owner..':'..kind.data end
            end
            for _,actor in ipairs(companions)do
                local d=distance(actor,player)
                if d and (not nearestD or d<nearestD) then nearest,nearestD=actor,d end
            end
            self.window.drops=self.window.drops+1;self.window.lost=self.window.lost+(self.playerHP-hp)
            say('drop',string.format('玩家掉血 %.1f→%.1f（-%.1f） 最近的随从=%s %s 此刻能打到玩家的攻击=%s',self.playerHP,hp,self.playerHP-hp,
                nearest and className(nearest) or '?',nearestD and string.format('%.1fm',nearestD) or '?',
                #suspects>0 and table.concat(suspects,'；') or '无（命中可能已结束）'))
            self.lastScan=now
        elseif now-self.lastScan>=SCAN_SECONDS then
            self.lastScan=now
            local budget={n=QUERY_LIMIT}
            for _,entry in ipairs(scan(owners,player,false))do record(entry,player,now,budget) end
        end
        self.playerHP=hp
        if now-self.lastSummary>=SUMMARY_SECONDS then
            self.lastSummary=now
            if self.window.attacks>0 or self.window.drops>0 then
                local risky,seen={},0
                for _,key in ipairs(self.order)do
                    local kind=self.kinds[key]
                    if kind.companion then
                        seen=seen+1
                        if kind.hitsPlayer then risky[#risky+1]=kind.owner..':'..kind.data..'×'..kind.count end
                    end
                end
                log(string.format('[CompanionHit] 近%d秒 随从活动攻击 %d 次；随从至今用过 %d 种攻击，能打到玩家的 %d 种：%s；玩家掉血 %d 次共 %.1f；扫描 子弹对象 %s 个、子弹Actor %s 个',
                    SUMMARY_SECONDS,self.window.attacks,seen,#risky,#risky>0 and table.concat(risky,'、') or '无',
                    self.window.drops,self.window.lost,show(self.window.scanned.BulletObjectBase),show(self.window.scanned.BulletActorBase)))
            end
            self.window={attacks=0,drops=0,lost=0,scanned={}}
        end
    end
    function self:status()return {kinds=#self.order,lines=self.lines}end
    return self
end
return Probe
