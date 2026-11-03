-- Experiment (Config.EnableAttackFactionScan), read only: which loaded attacks can reach the attacker's own
-- allies. A bullet's data decides whom it may hit: FactionTarget Enemy/Ally/Both/None and FactionCanTargetSelf
-- (PBZCombatAsset.hpp UPBZ_DamageBulletDataBase, UPBZ_ProjectileEmitterData). In normal play an "Ally" or
-- "Both" attack only reaches other monsters; on a companion the player is one of its allies (v0.37.15:
-- B_Hun_KnockPush from GA_MobUtilitiesPassive could hit the player). About once a minute the loaded bullet
-- data are listed (FindAllOf BulletDataBase) and read a chunk per support tick; each one not seen since the
-- mod loaded goes into Runtime/attack-faction-scan.tsv, and those that can reach an ally are logged with
-- their damage data. Nothing in the game is written.
local U=require('ue_observe')
local Scan={}
local TARGETS={[0]='只打敌人',[1]='只打友方',[2]='都打',[3]='都不打'}
local HEADER='pass\tpath\tclass\tfamily\tfaction_target\tcan_target_self\tdamage\tattack_type\tdamage_cause\n'

local function rawValid(object)
    if object==nil then return false end
    local ok,valid=pcall(function()return object:IsValid()end)
    return ok and valid==true
end
local function fullName(object)
    local ok,name=pcall(function()return object:GetFullName()end)
    return ok and type(name)=='string' and name or nil
end
local function className(object)
    local ok,class=pcall(function()return object:GetClass()end)
    local name=ok and rawValid(class) and fullName(class) or nil
    return name and (name:match('%.([^.]+)$') or name) or '?'
end
local function tagName(tag)
    local name=U.struct(tag,'TagName')
    if name==nil then return '?' end
    local ok,text=pcall(function()return name:ToString()end)
    return ok and type(text)=='string' and text or '?'
end
-- DamageData is a TMap<FGameplayTag,float>: "tag=value;…" and the sum of the absolute values.
local function damage(map)
    if map==nil then return '?',nil end
    local parts,total={},0
    local ok=pcall(function()map:ForEach(function(key,value)
        local amount=U.unwrap(value)
        parts[#parts+1]=tagName(U.unwrap(key))..'='..(type(amount)=='number' and string.format('%.4g',amount) or tostring(amount))
        if type(amount)=='number' then total=total+math.abs(amount) end
    end)end)
    if not ok then return '?',nil end
    return #parts>0 and table.concat(parts,';') or '无',total
end
local function clean(text)return (tostring(text):gsub('[\t\r\n]',' ')) end

function Scan.new(options)
    local log=options.log or function()end
    local findAll=options.findAll or function(name)return FindAllOf(name)end
    local clock=options.clock or os.clock
    local fs=options.io or io
    local file=options.path..'/attack-faction-scan.tsv'
    local firstDelay,interval=options.firstDelay or 15,options.interval or 60
    local perTick,maxLines=options.perTick or 400,options.lines or 150
    local self={pass=0,seen={},lines=0,pending=nil,nextAt=nil,
        totals={[0]=0,[1]=0,[2]=0,[3]=0,unknown=0,self=0,reach=0,reachDamage=0}}

    local function describe(data,name,job)
        local path=name:match('^%S+ (/.+)$') or name
        local family=path:match('/Mobs/([^/]+)/') or path:match('/ActorData/[^/]+/([^/]+)/') or path:match('^/([^/]+/[^/]+)/') or '?'
        local target=tonumber(U.unwrap(U.field(data,'FactionTarget')))
        local canSelf=U.unwrap(U.field(data,'FactionCanTargetSelf'))
        if type(canSelf)~='boolean' then canSelf=nil end
        local damageText,total=damage(U.field(data,'DamageData'))
        local t=self.totals
        if target and t[target] then t[target]=t[target]+1 else t.unknown=t.unknown+1 end
        if canSelf then t.self=t.self+1 end
        local reach=target==1 or target==2 or canSelf==true
        if reach then
            t.reach=t.reach+1
            if total and total>0 then t.reachDamage=t.reachDamage+1 end
        end
        local targetText=target and (TARGETS[target] or tostring(target)) or '?'
        job.rows[#job.rows+1]=table.concat({self.pass,clean(path),clean(className(data)),clean(family),targetText,
            tostring(canSelf==nil and '?' or canSelf),clean(damageText),clean(tagName(U.field(data,'AttackType'))),
            clean(tagName(U.field(data,'DamageCause')))},'\t')
        if reach and self.lines<maxLines then
            self.lines=self.lines+1
            log('[AttackScan] 能打到友方的攻击 族='..family..' 数据='..(path:match('([^/.:]+)$') or path)..' 打谁='..targetText
                ..' 能打同阵营='..tostring(canSelf==nil and '?' or canSelf)..' 伤害='..damageText..' 类='..className(data)..' 路径='..path)
        end
    end
    local function save(rows)
        if #rows==0 then return true end
        local existing=fs.open(file,'r')
        if existing then existing:close() end
        local out=fs.open(file,'a')
        if not out then return false end
        local text=(existing and '' or HEADER)..table.concat(rows,'\n')..'\n'
        local wrote=out:write(text)
        local closed=out:close()
        return wrote~=nil and wrote~=false and closed~=false
    end
    local function finish(job)
        local saved=save(job.rows)
        local t=self.totals
        if self.pass==1 or job.fresh>0 then
            log(string.format('[AttackScan] 第%d轮：已加载子弹数据 %d 个，新增 %d 个（写入 attack-faction-scan.tsv=%s）；Mod 加载以来 只打敌人 %d、只打友方 %d、都打 %d、都不打 %d、读不到 %d；能打同阵营 %d；能打到友方的 %d 个，其中带伤害 %d 个',
                self.pass,#job.list,job.fresh,tostring(saved),t[0],t[1],t[2],t[3],t.unknown,t.self,t.reach,t.reachDamage))
        end
        self.pending=nil
    end

    function self:tick()
        if options.ready and not options.ready() then return end
        local now=clock()
        self.nextAt=self.nextAt or now+firstDelay
        if not self.pending then
            if now<self.nextAt then return end
            self.nextAt=now+interval
            local ok,list=pcall(findAll,'BulletDataBase')
            if not ok or type(list)~='table' then return end
            self.pass=self.pass+1
            self.pending={list=list,index=0,fresh=0,rows={}}
        end
        local job=self.pending
        local stop=math.min(#job.list,job.index+perTick)
        for i=job.index+1,stop do
            local data=job.list[i]
            if rawValid(data) then
                local name=fullName(data)
                if name and not self.seen[name] then
                    self.seen[name]=true
                    job.fresh=job.fresh+1
                    describe(data,name,job)
                end
            end
        end
        job.index=stop
        if job.index>=#job.list then finish(job) end
    end
    function self:status()return {pass=self.pass,totals=self.totals}end
    return self
end
return Scan
