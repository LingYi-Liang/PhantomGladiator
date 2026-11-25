
-- Opening conditions and numeric provenance for the actual participants of the latest arena match.
local U=require('ue_observe')
local Stats=require('character_stats')
local Formula=require('stat_formula_probe')
local Files=require('companion_profile')
local Report={}
local MAX_PER_SIDE=64
local MAX_BYTES=512*1024
local ATTRIBUTES={'Health','Health_Min','Health_Max','Shachi','Shachi_Min','Shachi_Max','Attack','ShachiAttack',
    'Health_Max_Lv1','Shachi_Max_Lv1','Attack_Lv1','ShachiAttack_Lv1','Resistance_Physical',
    'TakenReductionMultiplier_Physical','TakenVulnerabilityMultiplier_Physical','Resistance_Poise',
    'Resistance_ImpactShachi','Resistance_DefenceShachi'}
local CONTEXT_TEXT={'map','levelMode','statsMode','defaultDifficulty','difficultyMode'}
local LEVEL_TEXT={'levelSource','levelArea','levelMap','spawnLevelMode'}
local LEVEL_NUMERIC={'requestedLevel','preparedLevel','originalLevel','levelBase','difficultyOffset','cycleBonus','levelReference','referenceCycle'}
local DIFFICULTIES={Handicapped=true,Easy=true,Normal=true,Hard=true,Nightmare=true}

local function finite(v)
    return type(v)=='number' and v==v and math.abs(v)<math.huge and v or nil
end
local function short(v)
    return type(v)=='string' and v~='' and #v<=4096 and v or nil
end
local function call(actor,method)
    if not U.valid(actor) then return nil end
    local ok,result=pcall(function()return actor[method](actor)end)
    return ok and U.unwrap(result) or nil
end
local function text(v)
    if type(v)=='string' then return short(v) end
    if v==nil then return nil end
    local ok,name=pcall(function()return v:ToString()end)
    return ok and short(name) or nil
end
local function plainPosition(actor)
    local p=call(actor,'K2_GetActorLocation')
    local x,y,z=finite(U.struct(p,'X')),finite(U.struct(p,'Y')),finite(U.struct(p,'Z'))
    if x and y and z then return {x=x,y=y,z=z} end
end
local function bool(v)
    if type(v)=='boolean' then return v end
end
local function stamp()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end
local function quote(v)
    v=v:gsub('[%z\1-\31\\"]',function(c)
        if c=='"' or c=='\\' then return '\\'..c end
        return string.format('\\u%04x',c:byte())
    end)
    return '"'..v..'"'
end
local function json(v)
    local kind=type(v)
    if kind=='boolean' then return v and 'true' or 'false' end
    if kind=='number' then return finite(v) and (string.format('%.17g',v):gsub(',','.')) or 'null' end
    if kind=='string' then return quote(v) end
    if kind~='table' then return 'null' end
    local result={}
    if #v>0 then
        for i,item in ipairs(v)do result[i]=json(item) end
        return '['..table.concat(result,',')..']'
    end
    local keys={}
    for name in pairs(v)do keys[#keys+1]=name end
    table.sort(keys)
    for i,name in ipairs(keys)do result[i]=quote(name)..':'..json(v[name]) end
    return '{'..table.concat(result,',')..'}'
end
local function value(unit,field)
    local stat=unit.stats[field]
    return stat and finite(stat.current)
end
local function damageExample(attacker,defender)
    local hp,baseHp=value(defender,'Health_Max'),value(defender,'Health_Max_Lv1')
    local attack,shachiAttack=value(attacker,'Attack_Lv1'),value(attacker,'ShachiAttack_Lv1')
    local example={attackerSlot=attacker.slot,defenderSlot=defender.slot}
    if not hp or not baseHp or not (hp>0 and baseHp>0) then return example end
    if attack and attack>0 then
        example.npcPhysicalBase=finite(hp*attack/baseHp)
        if example.npcPhysicalBase then example.npcPhysicalRatio=finite(example.npcPhysicalBase/hp) end
    end
    if shachiAttack and shachiAttack>0 then
        example.npcShachiBase=finite(hp*shachiAttack/baseHp)
        local targetShachi=value(defender,'Shachi_Max')
        if example.npcShachiBase and targetShachi and targetShachi>0 then
            example.npcShachiRatio=finite(example.npcShachiBase/targetShachi)
        end
    end
    return example
end

function Report.new(options)
    local stats=options.attributes or Stats.new()
    local formula=Formula.new({})
    local savedMeta=setmetatable({},{__mode='k'})
    local self={}
    local latest
    local function info(actor)
        local row=savedMeta[actor]
        if not row then row={key=U.key(actor)};savedMeta[actor]=row end
        return row
    end
    function self:rememberLevel(actor,decision,leader)
        if not U.valid(actor) or type(decision)~='table' then return end
        local row=info(actor)
        local original=leader and savedMeta[leader]
        local copy={}
        for _,field in ipairs(LEVEL_TEXT)do copy[field]=short(decision[field]) end
        for _,field in ipairs(LEVEL_NUMERIC)do copy[field]=finite(decision[field]) end
        copy.cycle=finite(decision.cycle)
        copy.cycleExempt=bool(decision.cycleExempt)
        copy.levelWriteVerified=bool(decision.levelWriteVerified)
        if original and original.level and copy.levelSource=='escort' and copy.levelWriteVerified==true then
            copy.cycle=original.level.cycle
            copy.cycleExempt=original.level.cycleExempt
        end
        row.level=copy
    end
    function self:rememberStats(actor,mode)
        if U.valid(actor) then info(actor).statsMode=short(mode) end
    end
    function self:forgetMissing(keys)
        for actor,row in pairs(savedMeta)do
            if not row.key or not keys[row.key] then savedMeta[actor]=nil end
        end
    end
    local function write(report)
        local data=json(report)..'\n'
        if #data>MAX_BYTES then return false end
        local ok,written=pcall(options.write or Files.write,options.path..'/match-report.json',data)
        if options.log then
            options.log('[MatchReport] '..(report.result and '收尾' or '开战')..'记录 '..#report.units..' 条；写入读回='..tostring(ok and written==true))
        end
        return ok and written==true
    end
    local function statsFor(actor)
        local result={}
        local values=stats:readMany(actor,ATTRIBUTES) or {}
        for _,field in ipairs(ATTRIBUTES)do
            local entry=values[field]
            if entry then result[field]={base=finite(entry.base),current=finite(entry.current)} end
        end
        return result
    end
    local function unitFor(member,curveCache)
        local actor=member.actor
        local classPath=short(member.class_path)
        if not classPath or not U.valid(actor) then return nil end
        local row={team=member.team,classPath=classPath,slot=finite(member.slot),formation=bool(member.formation),
            escort=member.escort==true,summoned=member.summoned==true,reserve=member.reserve==true}
        row.spawnLevel=finite(U.field(actor,'Level'))
        row.combatLevel=finite(call(actor,'GetCombatLevel'))
        row.position=plainPosition(actor)
        local configuration=call(actor,'GetGlobalCombatConfig')
        local globalName=text(call(configuration,'GetFName'))
        row.combatConfig=globalName
        local difficulty=globalName and globalName:match('^GlobalConfig_Combat_([A-Za-z]+)$')
        if DIFFICULTIES[difficulty] then row.difficulty=difficulty end
        if options.difficultyOf then row.spawnDifficulty=short(options.difficultyOf(actor)) end
        if options.storyLinkOf then
            local ok,mode=pcall(options.storyLinkOf,actor)
            if ok and (mode=='keep' or mode=='skip') then row.storyLink=mode end
        end
        local metadata=savedMeta[actor]
        if metadata then
            row.statsMode=metadata.statsMode
            local level=metadata.level
            if level then
                for _,field in ipairs(LEVEL_TEXT)do row[field]=level[field] end
                for _,field in ipairs(LEVEL_NUMERIC)do row[field]=level[field] end
                row.levelWriteVerified=level.levelWriteVerified
                if level.levelWriteVerified==true and level.cycle and level.cycle>=0 then
                    row.ng=level.cycle+1
                    row.cycleExempt=level.cycleExempt
                end
            end
        end
        row.stats=statsFor(actor)
        row.levelCurve=formula:forReport(actor,row.combatLevel,configuration,curveCache)
        return row
    end
    function self:capture(members,relay)
        latest=nil
        local context=options.context and options.context() or {}
        local report={schema=1,build=short(options.build),createdAt=(options.stamp or stamp)(),units={},
            counts={blue=0,red=0},truncated=false}
        for _,field in ipairs(CONTEXT_TEXT)do report[field]=short(context[field]) end
        local saveCycle=finite(context.saveCycle)
        if saveCycle and saveCycle>=0 and saveCycle%1==0 then report.saveCycle=saveCycle;report.saveNg=saveCycle+1 end
        if type(relay)=='table' then
            report.relay={enabled=relay.enabled==true,blue=finite(relay.blue),red=finite(relay.red)}
        end
        local captured,first={},{}
        local curveCache={}
        for _,member in ipairs(members)do
            local team=member.team
            if team=='blue' or team=='red' then
                report.counts[team]=report.counts[team]+1
                if (captured[team] or 0)<MAX_PER_SIDE then
                    local unit=unitFor(member,curveCache)
                    if unit then
                        report.units[#report.units+1]=unit
                        captured[team]=(captured[team] or 0)+1
                        if not first[team] and U.npcPath(member.actor)==unit.classPath then first[team]=unit end
                    else
                        report.truncated=true
                    end
                else
                    report.truncated=true
                end
            end
        end
        if not next(report.units) then return false end
        report.damageFormula={verifiedGameBuild=26367565,
            npcPhysicalBase='target.Health_Max.current * attacker.Attack_Lv1.current / target.Health_Max_Lv1.current',
            npcShachiBase='target.Health_Max.current * attacker.ShachiAttack_Lv1.current / target.Health_Max_Lv1.current',
            npcPhysicalRatio='npcPhysicalBase / target.Health_Max.current',
            npcShachiRatio='npcShachiBase / target.Shachi_Max.current'}
        if first.blue and first.red then
            report.damageFormula.examples={blue=damageExample(first.blue,first.red),red=damageExample(first.red,first.blue)}
        end
        latest=report
        return write(report)
    end
    function self:finish(result)
        if not latest or latest.result or type(result)~='table' then return false end
        latest.result={seconds=finite(result.seconds),blueAlive=finite(result.blueAlive),redAlive=finite(result.redAlive),
            winner=short(result.winner),reason=short(result.reason)}
        return write(latest)
    end
    return self
end

return Report
