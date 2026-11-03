-- Fun features for the player's own character; the arena's units are never touched.
-- * Infinite Shachi: the player's Shachi_Min floor is raised to Shachi_Max (CharacterBasics.hpp)
--   through the same native override the observer guard uses for Health_Min. Turning it off puts
--   the original floor back; a journal keeps that floor across mod reloads.
-- * Auto perfect deflect / auto dodge of attacks that cannot be deflected: attackers announce every hit ahead of
--   time in the player's DeflectComponent ReceiveFrames (HitGameTime, IsDodge; PBZDeflectSystem.hpp).
--   While either is on, a game-thread loop reads them every frame and, just before the hit, presses
--   IA_Deflect or IA_Dodge through Enhanced Input the way a key press arrives. It presses during the
--   player's own attacks too. Attacks the player can deflect are deflected; the rest (IsDodge frames,
--   can't-deflect and red-eye attacks) are dodged.
local U=require('ue_observe')
local Stats=require('character_stats')
local Fun={}
Fun.features={'SHACHI','DEFLECT','DODGE'}
local HEADER='FunFeaturesV1'
local INPUT={DEFLECT='/PBZDeflectSystem/Input/IA_Deflect.IA_Deflect',DODGE='/PBZDeflectSystem/Input/IA_Dodge.IA_Dodge'}
local INTERFACE='/Script/EnhancedInput.EnhancedInputSubsystemInterface'
local INJECT=INTERFACE..':InjectInputVectorForAction'
local SUBSYSTEM='/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem'
local SUBSYSTEMS='/Script/Engine.Default__SubsystemBlueprintLibrary'
local KISMET='/Script/Engine.Default__KismetSystemLibrary'
local STATICS='/Script/Engine.Default__GameplayStatics'
-- The player's passive abilities that turn these presses into a deflect or a perfect dodge.
local PASSIVE={DEFLECT='BP_PlayerDeflectPassive_C',DODGE='BP_PerfectDodgePassive_C'}
-- Seconds before the announced hit at which the key goes in. Deflect uses half the passive's own
-- Perfect Window when that reads back as seconds; these are the fallbacks.
Fun.LEAD={DEFLECT=0.06,DODGE=0.10}
-- Deflect lead by the attack's strength tag. In v0.36.3 a press 0.04-0.06 s ahead made all 9 Light
-- attacks perfect deflects but only 6 of 30 Normal/Knockback ones. Earlier presses for the heavier
-- ones (0.09 s and 0.13 s in turn) were set up in v0.36.6 but never ran in game, so the release
-- presses every strength at the measured 0.06 s. Several leads listed here are tried in turn.
Fun.LIGHT_LEAD=0.06
Fun.HEAVY_LEADS={0.06}
local COOLDOWN=0.12   -- one press per kind per this many seconds; the game punishes quick re-clicks
local STALE=1         -- a frame still listed this long after its hit time is treated as ended
local LATE=0.03       -- a hit already this far past is not pressed for
local CHECK=0.8       -- seconds (wall clock) a press is watched for the game's answer
-- The deflect ability instance holds the result of each deflect (Current Result Data.DeflectResult) and
-- its timing windows (BP_StanceAction_Base_Player.hpp); it exists once the player has deflected.
local STANCE='BP_StanceAction_Base_Player_C'
local LOG_CAP=300     -- per-frame lines per Lua lifetime; the minute summary keeps counting
local EPS=0.01

local function name(obj)
    if not U.valid(obj) then return 'nil' end
    local ok,n=pcall(function()return obj:GetFName():ToString()end)
    return ok and type(n)=='string' and n or '?'
end
local function className(obj)
    if not U.valid(obj) then return 'nil' end
    local ok,cls=pcall(function()return obj:GetClass()end)
    return ok and name(cls) or '?'
end
local function tagName(tag)
    local n=U.struct(tag,'TagName')
    if n==nil then return '' end
    local ok,s=pcall(function()return n:ToString()end)
    return ok and type(s)=='string' and s or tostring(n)
end
local function weak(value)
    if value==nil then return nil end
    local ok,obj=pcall(function()return value:Get()end)
    if ok and U.valid(obj) then return obj end
    return U.valid(value) and value or nil
end
local function num(v)return type(v)=='number' and v==v and v or nil end
-- EDeflectBulletType (PBZDeflectSystem_enums.hpp), read from the frame's SourceAction.
local TYPES={[0]='不能格挡',[1]='普通',[2]='蓝光',[3]='红光',[4]='重击',[5]='按住格挡'}
-- The only rule: an attack the player cannot deflect is dodged, everything else is deflected.
-- It cannot be deflected when its frame is IsDodge or its type is can't-deflect or red-eye.
local NO_DEFLECT={[0]=true,[3]=true}
local function deflectable(record)return not record.dodge and not (record.type and NO_DEFLECT[record.type]) end
local function describe(record)
    return (record.type and TYPES[record.type] or '类型未知')..(deflectable(record) and '→格挡' or '→闪避')
end
local function fmt(v)return v and string.format('%.3f',v) or 'nil' end

function Fun.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local clock=options.clock or os.clock
    local stats=options.attributes or Stats.new()
    local settings=options.path..'/fun-features.tsv'
    local journal=options.path..'/fun-shachi-floor.tsv'
    local self={alive=true,on={SHACHI=false,DEFLECT=false,DODGE=false},
        shachi={state='off',message='',relocks=0,refills=0,failures=0},
        guard={state='off',message='',frames=0,pressed={DEFLECT=0,DODGE=0},received=0,perfectDodges=0,
            consumed=0,hits=0,failures=0,results=0,perfect=0,damage=0,unannounced=0}}
    local function say(m)log('[Fun] '..m)end
    local function readFile(path)
        local f=fs.open(path,'r');if not f then return nil end
        local text=f:read('*a');f:close();return text
    end
    local function writeFile(path,text)
        local f=fs.open(path,'w');if not f then return false end
        local wrote=f:write(text);local closed=f:close()
        return wrote~=nil and wrote~=false and closed~=false and readFile(path)==text
    end
    do
        local text=readFile(settings)
        if type(text)=='string' and text:sub(1,#HEADER+1)==HEADER..'\t' then
            for feature,value in text:gmatch('([A-Z]+)=([01])')do
                if self.on[feature]~=nil then self.on[feature]=value=='1' end
            end
        end
    end
    local function save()
        local parts={HEADER}
        for _,feature in ipairs(Fun.features)do parts[#parts+1]=feature..'='..(self.on[feature] and '1' or '0') end
        return writeFile(settings,table.concat(parts,'\t')..'\n')
    end

    -- ---------- Infinite Shachi ----------
    -- lock = the pawn whose floor is raised and the floor it had before.
    local lock={}
    local logged={relock=0,refill=0}
    local function readJournal()
        local key,floor=(readFile(journal) or ''):match('^ShachiFloorV1\t(%S+)\t(%S+)\n$')
        return key,num(tonumber(floor))
    end
    local function lockShachi(pawn)
        local key=U.key(pawn);if not key then return end
        local shachi,why=stats:read(pawn,'Shachi')
        local floor=stats:read(pawn,'Shachi_Min');local max=stats:read(pawn,'Shachi_Max')
        if not shachi or not floor or not max or max.current<=0 then
            if self.shachi.state~='failed' then say('无限杀气：属性不可读 '..tostring(why)) end
            self.shachi.state='failed';self.shachi.message='杀气属性不可读';return
        end
        if lock.key~=key then
            -- A new pawn (first lock, map change, load). A floor journaled for this same pawn is its
            -- original: this one was raised by an earlier Lua instance before a mod reload.
            local journaled,original=readJournal()
            original=journaled==key and original or floor.base
            lock={key=key,floor=original}
            local kept=writeFile(journal,'ShachiFloorV1\t'..key..'\t'..string.format('%.6f',original)..'\n')
            say(string.format('无限杀气开始 pawn=%s 杀气=%.1f 下限=%.1f(原始%.1f) 上限=%.1f 记录原始下限=%s',
                key,shachi.current,floor.current,original,max.current,tostring(kept)))
        end
        local target=max.current
        if floor.current>=target-EPS then lock.raised=true end
        if floor.current<target-EPS then
            local ok,err=stats:writeBase(pawn,'Shachi_Min',target)
            local after=stats:read(pawn,'Shachi_Min')
            local good=ok and after and after.current>=target-EPS
            if not good then self.shachi.failures=self.shachi.failures+1 end
            if lock.raised then self.shachi.relocks=self.shachi.relocks+1 end
            if not lock.raised or logged.relock<10 then
                if lock.raised then logged.relock=logged.relock+1 end
                say(string.format('%s杀气下限 写入=%s 目标=%.1f 读回=%s/%s %s',lock.raised and '重新锁定' or '锁定',
                    tostring(ok),target,after and fmt(after.base) or 'nil',after and fmt(after.current) or 'nil',err and ('错误='..tostring(err)) or ''))
            end
            lock.raised=lock.raised or good
        end
        if shachi.current<target-EPS then
            -- The floor did not hold the bar up (or a skill just spent it): fill it directly.
            local ok,err=stats:writeBase(pawn,'Shachi',target)
            local after=stats:read(pawn,'Shachi')
            self.shachi.refills=self.shachi.refills+1
            if logged.refill<10 then
                logged.refill=logged.refill+1
                say(string.format('补满杀气 原值=%.1f 写入=%s 读回=%s 目标=%.1f %s',shachi.current,tostring(ok),
                    after and fmt(after.current) or 'nil',target,err and ('错误='..tostring(err)) or ''))
            end
        end
        self.shachi.state=lock.raised and 'locked' or 'failed'
        self.shachi.message=lock.raised and '杀气已锁满' or '杀气下限写入未读回'
    end
    local function releaseShachi(reason)
        if not lock.key then
            -- Nothing locked by this instance; an earlier one may have left a raised floor behind.
            local key,original=readJournal()
            local pawn=options.getPlayer and options.getPlayer()
            if key and original and U.valid(pawn) and U.key(pawn)==key then lock={key=key,floor=original}
            else
                if key then writeFile(journal,'') end
                self.shachi.state='off';self.shachi.message='';return
            end
        end
        local pawn=options.getPlayer and options.getPlayer()
        if U.valid(pawn) and U.key(pawn)==lock.key then
            local ok,err=stats:writeBase(pawn,'Shachi_Min',lock.floor)
            local after=stats:read(pawn,'Shachi_Min')
            say(string.format('无限杀气关闭（%s）恢复下限 写入=%s 目标=%.1f 读回=%s %s',reason,tostring(ok),lock.floor,
                after and fmt(after.current) or 'nil',err and ('错误='..tostring(err)) or ''))
            if not ok or not after or math.abs(after.current-lock.floor)>EPS then self.shachi.failures=self.shachi.failures+1 end
        else
            say('无限杀气关闭（'..reason..'）：锁定过的角色已不在，不用恢复')
        end
        writeFile(journal,'')
        lock={};self.shachi.state='off';self.shachi.message=''
    end

    -- ---------- Auto deflect / dodge ----------
    local input={}
    local player={}
    local frames={}        -- handle -> what was seen and pressed for it
    local presses={}       -- presses still waiting for the game's answer
    local ended={}         -- the last frames that ended, to tell where damage came from
    local health           -- the player's HP on the previous frame
    local damageLines=0
    -- Hit readback: the app's units (refreshed by the slow tick) and their HP last frame, the player's
    -- Shachi last frame. Logs each HP drop with the Shachi the player had before and after it.
    local targets,targetHp,lastShachi={}, {},nil
    local hitLines,hitTotals=0,{on=0,off=0,onHits=0,offHits=0,spent=0}
    local last={DEFLECT=-math.huge,DODGE=-math.huge}
    local lines=0
    local function line(m)if lines<LOG_CAP then lines=lines+1;say(m)end end
    local function guardFail(message)
        if self.guard.message~=message then say('自动防御/闪避：'..message) end
        self.guard.state='failed';self.guard.message=message
    end
    local function describeAction(kind,action)
        local triggers={}
        for _,trigger in ipairs(U.array(U.field(action,'Triggers')) or {})do triggers[#triggers+1]=className(trigger) end
        say(string.format('输入动作 %s=%s ValueType=%s 动作触发器=[%s]',kind,name(action),tostring(U.field(action,'ValueType')),table.concat(triggers,',')))
    end
    local function resolveInput()
        if U.valid(input.subsystem) and U.valid(input.fn) and U.valid(input.actions.DEFLECT) and U.valid(input.actions.DODGE) then return true end
        if input.failedAt and clock()-input.failedAt<5 then return false end
        input={failedAt=clock(),actions={}}
        local pc=options.getController and options.getController()
        local lib,class,iface,fn,kismet=StaticFindObject(SUBSYSTEMS),StaticFindObject(SUBSYSTEM),StaticFindObject(INTERFACE),StaticFindObject(INJECT),StaticFindObject(KISMET)
        if not U.valid(pc) or not U.valid(lib) or not U.valid(class) or not U.valid(iface) or not U.valid(fn) or not U.valid(kismet) then
            guardFail('输入系统对象不可用 pc='..tostring(U.valid(pc))..' 注入函数='..tostring(U.valid(fn)));return false
        end
        local ok,sub=pcall(function()return lib:GetLocalPlayerSubSystemFromPlayerController(pc,class)end)
        sub=ok and U.unwrap(sub) or nil
        if not U.valid(sub) then guardFail('取不到玩家输入子系统');return false end
        local checked,implements=pcall(function()return kismet:DoesImplementInterface(sub,iface)end)
        if not checked or implements~=true then guardFail('输入子系统没有实现注入接口 读回='..tostring(implements));return false end
        for kind,path in pairs(INPUT)do
            local action=StaticFindObject(path)
            if not U.valid(action) then
                local loaded,value=pcall(LoadAsset,path);if loaded and U.valid(value) then action=value else action=StaticFindObject(path) end
            end
            if not U.valid(action) then guardFail('输入动作未加载 '..path);return false end
            input.actions[kind]=action;describeAction(kind,action)
        end
        input.subsystem,input.fn,input.failedAt=sub,fn,nil
        say('输入注入就绪 子系统='..name(sub)..' 实现接口=true')
        if self.guard.state=='failed' then self.guard.state='waiting';self.guard.message='' end
        return true
    end
    local function findPassive(kind,component)
        local ok,list=pcall(FindAllOf,PASSIVE[kind])
        if not ok or type(list)~='table' then return nil end
        local key=U.key(component)
        for _,obj in ipairs(list)do
            if U.valid(obj) and U.key(U.field(obj,'Deflect Component'))==key then return obj end
        end
    end
    -- Slow tick: the player's deflect component and the two passives, found once per pawn.
    local function refreshPlayer(pawn)
        local key=U.key(pawn)
        if not key then player={};return end
        if player.key==key and U.valid(player.component) then return end
        local component=U.field(pawn,'Deflect Component')
        if not U.valid(component) then
            local cls=StaticFindObject('/Script/PBZDeflectSystem.DeflectComponent')
            if U.valid(cls) then
                local ok,value=pcall(function()return pawn:GetComponentByClass(cls)end)
                component=ok and U.unwrap(value) or nil
            end
        end
        if not U.valid(component) then player={};guardFail('玩家没有格挡组件');return end
        if self.guard.state=='failed' and self.guard.message=='玩家没有格挡组件' then self.guard.state='waiting';self.guard.message='' end
        player={key=key,pawn=pawn,component=component,passives={DEFLECT=findPassive('DEFLECT',component),DODGE=findPassive('DODGE',component)}}
        health=nil
        local deflect=player.passives.DEFLECT
        say(string.format('玩家格挡组件=%s 格挡被动=%s 完美闪避被动=%s 完美窗口=%s 普通窗口=%s 惩罚计数=%s',name(component),
            name(deflect),name(player.passives.DODGE),fmt(num(U.field(deflect,'Perfect Window'))),
            fmt(num(U.field(deflect,'Normal Window'))),tostring(U.field(deflect,'Current Perfect Window Counter'))))
    end
    local function windows(stance)
        return string.format('完美前置=%s 完美窗口=%s 优秀窗口=%s 普通窗口=%s',fmt(num(U.field(stance,'Perfect Pre Hit Time'))),
            fmt(num(U.field(stance,'Perfect Window'))),fmt(num(U.field(stance,'Great Window'))),fmt(num(U.field(stance,'Normal Window'))))
    end
    -- Slow tick, after the first deflect press: a full object search, at most every 3 seconds.
    local function findStance()
        if U.valid(player.stance) or not U.valid(player.component) then return end
        if player.stanceAt and clock()-player.stanceAt<3 then return end
        player.stanceAt=clock()
        local ok,list=pcall(FindAllOf,STANCE)
        if not ok or type(list)~='table' then return end
        local key=U.key(player.component)
        for _,obj in ipairs(list)do
            if U.valid(obj) and U.key(U.field(obj,'Deflect Component'))==key then
                player.stance=obj
                say('格挡技能实例='..name(obj)..' '..windows(obj))
                return
            end
        end
    end
    local function stanceResult()
        local data=U.field(player.stance,'Current Result Data')
        return num(U.struct(data,'HitGameTime')),tagName(U.struct(data,'DeflectResult'))
    end
    local trials=0
    -- Chosen once per frame, so its press and its result are logged against the same lead.
    local function lead(kind,record)
        if kind~='DEFLECT' then return Fun.LEAD[kind] end
        if not record.lead then
            if (record.strength or ''):find('Light',1,true) then record.lead=Fun.LIGHT_LEAD
            else trials=trials+1;record.lead=Fun.HEAVY_LEADS[(trials-1)%#Fun.HEAVY_LEADS+1] end
        end
        return record.lead
    end
    local statics
    local function gameTime()
        if not U.valid(statics) then statics=StaticFindObject(STATICS) end
        if not U.valid(statics) or not U.valid(player.pawn) then return nil end
        local ok,t=pcall(function()return statics:GetTimeSeconds(player.pawn)end)
        return ok and num(U.unwrap(t)) or nil
    end
    local function press(kind,handle,record,now,remaining)
        if not resolveInput() then return end
        local action,sub,fn=input.actions[kind],input.subsystem,input.fn
        if not U.valid(action) or not U.valid(sub) or not U.valid(fn) then return end
        -- What the passives show before the press, to tell afterwards whether the game took it.
        local click=num(U.field(player.passives.DEFLECT,'Last Deflect Click'))
        local dodge=num(U.struct(U.field(player.component,'PerfectDodgeResultData'),'HitGameTime'))
        local ok,err=pcall(function()fn(sub,action,{X=1.0,Y=0.0,Z=0.0},{},{})end)
        last[kind]=now
        record.pressed={kind=kind,at=now,ok=ok}
        if ok then
            presses[#presses+1]={handle=handle,kind=kind,wall=clock(),click=click,dodge=dodge,
                strength=record.strength,lead=record.lead,remaining=remaining,
                result=U.valid(player.stance) and (stanceResult()) or nil}
        end
        if ok then self.guard.pressed[kind]=self.guard.pressed[kind]+1;self.guard.state='ready';self.guard.message=''
        else self.guard.failures=self.guard.failures+1 end
        line(string.format('按下 %s handle=%s 距命中=%.3fs 提前量=%.3f 调用=%s %s',kind=='DEFLECT' and '格挡' or '闪避',
            tostring(handle),remaining,lead(kind,record),tostring(ok),ok and '' or ('错误='..tostring(err))))
    end
    -- After a press: did the passive take it (Last Deflect Click moved), which deflect result came out,
    -- did a perfect dodge result come in? Watched every frame for CHECK seconds.
    local function checkPresses()
        local t=clock()
        for i=#presses,1,-1 do
            local p=presses[i]
            if p.kind=='DEFLECT' then
                local passive=player.passives.DEFLECT
                if not p.clickSeen then
                    local click=num(U.field(passive,'Last Deflect Click'))
                    if click and click~=p.click then
                        p.clickSeen=true;self.guard.received=self.guard.received+1
                        line(string.format('读回 handle=%s 格挡被动收到按键 Last Deflect Click %s→%s 被动完美窗口=%s 被动普通窗口=%s 连点惩罚=%s',
                            tostring(p.handle),fmt(p.click),fmt(click),fmt(num(U.field(passive,'Perfect Window'))),
                            fmt(num(U.field(passive,'Normal Window'))),tostring(U.field(passive,'Current Perfect Window Counter'))))
                    end
                end
                if not p.resultSeen and U.valid(player.stance) then
                    local at,tag=stanceResult()
                    if at and at~=p.result then
                        p.resultSeen=true;self.guard.results=self.guard.results+1
                        if tag:find('Perfect',1,true) then self.guard.perfect=self.guard.perfect+1 end
                        line(string.format('读回 handle=%s 格挡结果=%s 强度=%s 提前量=%s 按键时距命中=%s',tostring(p.handle),tag,
                            tostring(p.strength),fmt(p.lead),fmt(p.remaining)))
                    end
                end
            elseif not p.dodgeSeen then
                local result=num(U.struct(U.field(player.component,'PerfectDodgeResultData'),'HitGameTime'))
                if result and result~=p.dodge then
                    p.dodgeSeen=true;self.guard.perfectDodges=self.guard.perfectDodges+1
                    line(string.format('读回 handle=%s 完美闪避结果更新 HitGameTime %s→%s',tostring(p.handle),fmt(p.dodge),fmt(result)))
                end
            end
            if t-p.wall>CHECK then
                if p.kind=='DEFLECT' and U.valid(player.stance) and not p.resultSeen then
                    line('读回 handle='..tostring(p.handle)..' '..CHECK..' 秒内没有新的格挡结果')
                end
                table.remove(presses,i)
            end
        end
    end
    -- Every frame: a drop in the player's HP is logged with the frames around it, so a hit can be
    -- told apart as unannounced (no frame), from a frame that was pressed for, or from one that was not.
    local function checkHealth()
        local hp=num(U.struct(U.field(U.field(player.pawn,'AttributeSetBase'),'Health'),'CurrentValue'))
        if not hp then return end
        if health and hp<health-0.5 then
            self.guard.damage=self.guard.damage+1
            local active,recent,t={},{},clock()
            for handle,record in pairs(frames)do
                active[#active+1]=tostring(handle)..':'..describe(record)..(record.pressed and '(已按)' or '')
            end
            for _,e in ipairs(ended)do
                if t-e.at<=0.5 then recent[#recent+1]=string.format('%s:%s 按过=%s %.2fs前',tostring(e.handle),e.label,e.pressed,t-e.at) end
            end
            local bare=#active==0 and #recent==0
            if bare then self.guard.unannounced=self.guard.unannounced+1 end
            if damageLines<60 then
                damageLines=damageLines+1
                say(string.format('玩家掉血 %.1f→%.1f(-%.1f) 进行中预告=[%s] 刚结束=[%s]%s',health,hp,health-hp,
                    table.concat(active,', '),table.concat(recent,', '),bare and ' 没有预告的攻击' or ''))
            end
        end
        health=hp
    end
    local timeChecked=false
    local stale={}         -- handles the game left listed long after their hit; ignored until they go
    local function readFrames(component)
        local map=U.field(component,'ReceiveFrames')
        if map==nil then return end
        local seen,present={}, {}
        local ok=pcall(function()map:ForEach(function(k,v)
            local handle=tonumber(U.unwrap(k));local frame=U.unwrap(v)
            if not handle then return end
            present[handle]=true
            if stale[handle] then return end
            local entry={hit=num(U.struct(frame,'HitGameTime')),dodge=U.struct(frame,'IsDodge')==true,isHit=U.struct(frame,'IsHit')==true}
            if not frames[handle] then
                entry.strength=tagName(U.struct(frame,'DeflectStrength'));entry.direction=tagName(U.struct(frame,'DeflectDirection'))
                local source=weak(U.struct(frame,'SourceAction'))
                entry.source=className(source)
                -- Duration actions call it DeflectBulletType, bullet bursts DeflectType.
                entry.type=num(U.field(source,'DeflectBulletType')) or num(U.field(source,'DeflectType'))
                local counter=U.struct(frame,'CounterAbility')
                entry.counter=U.valid(counter) and name(counter) or nil
            end
            seen[handle]=entry
        end)end)
        if not ok then return end
        for handle in pairs(stale)do if not present[handle] then stale[handle]=nil end end
        local now
        if next(seen)~=nil or next(frames)~=nil then now=gameTime() end
        if not now then return end
        for handle,entry in pairs(seen)do
            local record=frames[handle]
            if record and record.hit and now-record.hit>STALE then
                stale[handle]=true;seen[handle]=nil
                line('预告 handle='..tostring(handle)..' 命中后 '..fmt(now-record.hit)..' 秒仍未消失，按已结束处理')
            end
        end
        for handle,entry in pairs(seen)do
            local record=frames[handle]
            if not record then
                record={first=now,hit=entry.hit,dodge=entry.dodge,type=entry.type,counter=entry.counter,strength=entry.strength}
                frames[handle]=record;self.guard.frames=self.guard.frames+1
                line(string.format('预告 handle=%s %s 类型值=%s IsDodge=%s 距命中=%s 强度=%s 方向=%s 来源=%s 反击=%s',tostring(handle),describe(record),
                    tostring(entry.type),tostring(entry.dodge),entry.hit and fmt(entry.hit-now) or 'nil',entry.strength,entry.direction,entry.source,tostring(entry.counter)))
                if not timeChecked and entry.hit then
                    timeChecked=true
                    if math.abs(entry.hit-now)>30 then say('时间基准对不上：HitGameTime='..fmt(entry.hit)..' 游戏时间='..fmt(now)..'；不会自动按键') end
                end
            end
            record.hit=entry.hit or record.hit;record.dodge=entry.dodge;record.isHit=record.isHit or entry.isHit
            local kind=deflectable(record) and 'DEFLECT' or 'DODGE'
            if self.on[kind] and not record.pressed and record.hit and math.abs(record.hit-now)<=30 then
                local remaining=record.hit-now
                if remaining<=lead(kind,record) and remaining>-LATE and now-last[kind]>=COOLDOWN then press(kind,handle,record,now,remaining) end
            end
        end
        for handle,record in pairs(frames)do
            if not seen[handle] then
                local early=record.hit and now<record.hit-EPS
                if record.pressed and early then self.guard.consumed=self.guard.consumed+1 end
                if record.isHit then self.guard.hits=self.guard.hits+1 end
                line(string.format('预告结束 handle=%s %s 结束时距命中=%s 按过=%s 被打中=%s',tostring(handle),describe(record),
                    record.hit and fmt(record.hit-now) or 'nil',record.pressed and ((record.pressed.kind=='DODGE' and '闪避' or '格挡')..(record.pressed.ok and '' or '(调用失败)')) or '否',tostring(record.isHit)))
                table.insert(ended,1,{handle=handle,label=describe(record),at=clock(),
                    pressed=record.pressed and (record.pressed.kind=='DODGE' and '闪避' or '格挡') or '否'})
                ended[9]=nil
                frames[handle]=nil
            end
        end
    end
    local function attribute(actor,field)
        return num(U.struct(U.field(U.field(actor,'AttributeSetBase'),field),'CurrentValue'))
    end
    local function checkTargets()
        local pawn=self.pawn
        local shachi=U.valid(pawn) and attribute(pawn,'Shachi') or nil
        for key,actor in pairs(targets)do
            local hp=U.valid(actor) and attribute(actor,'Health') or nil
            local before=targetHp[key]
            if hp and before and hp<before-0.5 then
                local lock=self.on.SHACHI and 'on' or 'off'
                hitTotals[lock]=hitTotals[lock]+(before-hp);hitTotals[lock..'Hits']=hitTotals[lock..'Hits']+1
                if lastShachi and shachi and shachi<lastShachi then hitTotals.spent=hitTotals.spent+(lastShachi-shachi) end
                if hitLines<150 then
                    hitLines=hitLines+1
                    say(string.format('单位受伤 %s -%.1f (HP %.1f→%.1f) 玩家杀气 %s→%s 下限当前=%s 无限杀气=%s',className(actor),before-hp,before,hp,
                        fmt(lastShachi),fmt(shachi),fmt(U.valid(pawn) and attribute(pawn,'Shachi_Min') or nil),self.on.SHACHI and '开' or '关'))
                end
            end
            targetHp[key]=hp
        end
        lastShachi=shachi
    end
    local function frameTick()
        if options.paused and options.paused() then return end
        checkTargets()
        if not (self.on.DEFLECT or self.on.DODGE) then return end
        local component=player.component
        if not U.valid(component) then return end
        readFrames(component)
        checkPresses()
        checkHealth()
    end
    -- The loop runs while any feature is on. Its first two seconds log how often it ran.
    local loopHandle
    local function syncLoop()
        local want=self.alive and (self.on.SHACHI or self.on.DEFLECT or self.on.DODGE)
        if want and loopHandle==nil then
            if type(LoopInGameThreadWithDelay)~='function' then guardFail('缺少游戏线程循环接口');return end
            local started,calls,reported,slow,lastError=clock(),0,false,0,nil
            local ok,handle=pcall(LoopInGameThreadWithDelay,1,function()
                if not self.alive or loopHandle==nil then return end
                local t=clock()
                local fine,err=xpcall(frameTick,debug.traceback)
                if not fine and lastError~=tostring(err) then lastError=tostring(err);say('逐帧检查失败: '..lastError) end
                calls=calls+1
                local spent=(clock()-t)*1000
                if spent>=2 and slow<20 then slow=slow+1;say(string.format('[Perf] 逐帧检查耗时 %.1fms',spent)) end
                if not reported and clock()-started>=2 then
                    reported=true;say(string.format('逐帧检查实测：%.1f 秒内 %d 次',clock()-started,calls))
                end
            end)
            if not ok or handle==nil or handle==false then guardFail('逐帧检查注册失败 '..tostring(handle));return end
            loopHandle=handle;self.guard.state='waiting';self.guard.message=''
            say('逐帧检查已注册 handle='..tostring(handle))
        elseif not want and loopHandle~=nil then
            local handle=loopHandle;loopHandle=nil;frames={}
            local ok,result=pcall(CancelDelayedAction,handle)
            say('逐帧检查已取消 调用='..tostring(ok)..' 返回='..tostring(result))
            self.guard.state='off';self.guard.message=''
        end
    end

    function self:set(feature,value)
        if self.on[feature]==nil then return {ok=false,message='未知功能：'..tostring(feature),spawned_count=0} end
        if value~='ON' and value~='OFF' then return {ok=false,message='开关值无效：'..tostring(value),spawned_count=0} end
        local before=self.on[feature]
        self.on[feature]=value=='ON'
        if not save() then
            self.on[feature]=before
            return {ok=false,message='趣味功能设置保存未读回，未切换',spawned_count=0}
        end
        say('设置读回 '..feature..'='..value)
        if feature=='SHACHI' and not self.on.SHACHI then releaseShachi('开关关闭') end
        syncLoop()
        local labels={SHACHI='无限杀气',DEFLECT='自动精准防御',DODGE='自动闪避红光'}
        return {ok=true,message=labels[feature]..(self.on[feature] and '已开启' or '已关闭'),spawned_count=0}
    end
    local minute=clock()
    function self:tick()
        if not self.alive then return end
        if options.ready and not options.ready() then return end
        syncLoop()
        local pawn=options.getPlayer and options.getPlayer()
        self.pawn=U.valid(pawn) and pawn or nil
        local fresh,count={},0
        for _,unit in ipairs(options.members and options.members() or {})do
            local key=U.key(unit.actor);if key then fresh[key]=unit.actor;count=count+1 end
        end
        -- The per-frame hit probe reads every unit's health: a one-on-one diagnostic (v0.36.4), stopped
        -- with more than four units on the field (50 would mean 50 health reads every frame).
        if count>4 then fresh={} end
        for key in pairs(targetHp)do if not fresh[key] then targetHp[key]=nil end end
        targets=fresh
        if self.on.SHACHI then
            if U.valid(pawn) then lockShachi(pawn) end
        elseif lock.key or not self.journalChecked then
            self.journalChecked=true
            releaseShachi('开关未开启')
        end
        if self.on.DEFLECT or self.on.DODGE then
            if U.valid(pawn) then refreshPlayer(pawn) end
            resolveInput()
            if self.guard.pressed.DEFLECT>0 then findStance() end
        end
        if clock()-minute>=60 then
            minute=clock()
            if self.on.SHACHI or self.on.DEFLECT or self.on.DODGE then
                local g=self.guard
                say(string.format('每分钟汇总 杀气=%s 重锁=%d 补满=%d 预告=%d 按格挡=%d 格挡收到=%d 格挡结果=%d 完美格挡=%d 按闪避=%d 完美闪避=%d 提前结束=%d 被打中=%d 掉血=%d 无预告掉血=%d 失败=%d',
                    self.shachi.state,self.shachi.relocks,self.shachi.refills,g.frames,g.pressed.DEFLECT,g.received,g.results,g.perfect,
                    g.pressed.DODGE,g.perfectDodges,g.consumed,g.hits,g.damage,g.unannounced,g.failures))
                say(string.format('每分钟汇总 召唤单位受伤 无限杀气开=%.1f(%d次) 关=%.1f(%d次) 受伤时玩家杀气减少合计=%.1f',
                    hitTotals.on,hitTotals.onHits,hitTotals.off,hitTotals.offHits,hitTotals.spent))
            end
        end
    end
    function self:status()
        return {shachi=self.on.SHACHI,deflect=self.on.DEFLECT,dodge=self.on.DODGE,
            shachi_state=self.shachi.state,shachi_failures=self.shachi.failures,
            guard_state=(self.on.DEFLECT or self.on.DODGE) and self.guard.state or 'off',guard_message=self.guard.message,
            deflect_pressed=self.guard.pressed.DEFLECT,deflect_received=self.guard.received,
            dodge_pressed=self.guard.pressed.DODGE,perfect_dodges=self.guard.perfectDodges}
    end
    -- Mod unload: only stop the loop. The raised floor stays journaled; the next instance restores it
    -- on the game thread if the switch is off by then.
    function self:silence()
        self.alive=false
        if loopHandle~=nil then local handle=loopHandle;loopHandle=nil;pcall(CancelDelayedAction,handle) end
    end
    return self
end
return Fun
