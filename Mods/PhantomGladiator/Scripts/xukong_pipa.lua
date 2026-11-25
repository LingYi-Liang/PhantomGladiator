-- 虚空 carries two main weapons (ActorC_XuKong Main Weapons): 0 the fan Weapon_XuKong, 1 the pipa Weapon_XianZhe. Every move
-- of her attack tree is played on the pipa. In the game's own fight BT_XuKong_EnterCombat runs GA_XuKong_EnterCombat_02
-- first, whose GAA_SwitchWeapon (StartWeapon 1, Armed) puts the pipa in her hands; a direct summon has no entrance and
-- kept the fan for good. The same two calls are made here: SetCurrentWeapon(Main, 1), then SetArmed(Main, true).
-- The 虚空 that 梦华 summons herself has had her entrance and is left to the game. Both weapons have the same multipliers
-- and grant no ability, so nothing but the weapon in her hands changes.
local U=require('ue_observe')
local Pipa={path='/PBZCombatAsset/ActorData/Mobs/079_XuKong/BP_Monster_XuKong.BP_Monster_XuKong_C',
    weapon='/PBZCombatAsset/ActorData/Mobs/071_XianZhe/Weapon/Weapon_XianZhe.Weapon_XianZhe'}
local SLOT,PIPA='Weapon.Slot.Main',1
local FIRST=1          -- s between two tries while her weapons are not ready
local TRIES=12
local CHECK=3          -- s between two looks afterwards: GA_XuKong_GEx_01 switches to a third, empty index
local AGAIN=5          -- times she is given the pipa back
local BUSY_TAGS={'Ability.Action','Ability.Action.Execution','Ability.Executed','CharacterState.HitReact.State.Executing','CharacterState.Dead'}

local function call(o,m,...)
    if not U.valid(o)then return false end
    local args=table.pack(...)
    local ok,value=pcall(function()return o[m](o,table.unpack(args,1,args.n))end)
    return ok,U.unwrap(value)
end
local function fullName(o)
    local ok,name=call(o,'GetFullName')
    return ok and type(name)=='string' and name or nil
end
local function config(value)
    value=U.unwrap(value)
    if U.valid(value)then return value end
    local pointer=U.struct(value,'ObjectPointer');if U.valid(pointer)then return pointer end
    local ok,object=pcall(function()return value:GetObject()end)
    return ok and U.valid(object) and object or nil
end

function Pipa.new(options)
    local self={alive=true,given=0}
    local records={}
    local clock=options.clock or os.clock
    local fname=options.fname or FName
    local function say(text)(options.log or function()end)('[XuKongPipa] '..text)end
    local function slot()return {TagName=fname(SLOT)}end
    local function current(wc)
        local ok,index=call(wc,'GetCurrentWeaponIndex',slot(),false)
        return ok and type(index)=='number' and index or nil
    end
    local function acting(actor)
        local asc=U.field(actor,'AbilitySystemComponent')
        for _,name in ipairs(BUSY_TAGS)do
            local ok,count=call(asc,'GetGameplayTagCount',{TagName=fname(name)})
            if not ok or type(count)~='number' then return nil end
            if count>0 then return true end
        end
        return false
    end
    -- 'held': she has the pipa; 'given': she has it since this call. Nil with a reason: not now.
    local function give(r,actor)
        local wc=U.field(actor,'Character Weapons Component')
        if not U.valid(wc)then return nil,'武器组件未就绪'end
        local index=current(wc)
        if index==nil then return nil,'当前武器序号未读回'end
        local _,holding=call(wc,'IsArmed',slot())
        if index==PIPA and holding==true then return 'held' end
        local busy=acting(actor)
        if busy then return 'deferred' end
        if busy==nil then return nil,'动作状态未读回' end
        if options.actionBusy and options.actionBusy(actor)~=false then return 'deferred' end
        local data={}
        local read=call(wc,'GetSlotWeapon',slot(),PIPA,data)
        local name=read and fullName(config(data.WeaponConfig))
        if not name then return nil,'备用武器未读回'end
        if name:match('^%S+ (/.+)$')~=Pipa.weapon then r.done=true;return nil,'一号武器不是琵琶 '..name end
        local switched=index~=PIPA
        if switched then
            say('即将 换上琵琶 '..r.name..' SetCurrentWeapon(Main,1) 当前序号='..index)
            local called,accepted=call(wc,'SetCurrentWeapon',slot(),PIPA)
            local after=current(wc)
            say('切换琵琶 读回 '..r.name..' 调用='..tostring(called==true)..' 返回='..tostring(accepted)..' 序号 '..index..'→'..tostring(after))
            if after~=PIPA then return nil,accepted==true and '切换未读回' or '切换未接受' end
        else
            say('即将 补持握琵琶 '..r.name..' SetArmed(Main,true)')
        end
        call(wc,'SetArmed',slot(),true)
        local after=current(wc)
        local _,isArmed=call(wc,'IsArmed',slot())
        local complete=after==PIPA and isArmed==true
        say('换上琵琶 读回 '..r.name..' 序号 '..index..'→'..tostring(after)
            ..' 持握='..tostring(isArmed)..' 已换上='..tostring(complete))
        if complete then self.given=self.given+1;return 'given' end
        return nil,'持握未读回'
    end
    function self:tick()
        if not self.alive then return end
        local seen,now=nil,nil
        for _,member in ipairs(options.members() or {})do
            if member.class_path==Pipa.path and not member.summoner and not member.aid and not member.stand then
                local actor=member.actor
                local key=U.key(actor)
                local name=key and fullName(actor)
                if name then
                    seen=seen or {};seen[key]=true;now=now or clock()
                    local r=records[key]
                    if not r or r.name~=name then r={name=name,tries=0,again=0,at=now};records[key]=r end
                    r.team=member.team
                    if not r.done and (now>=r.at or r.at-now>CHECK+FIRST) then
                        local state,why=give(r,actor)
                        if state=='deferred' then
                            r.at=now+FIRST
                        elseif state then
                            if state=='given' then
                                if r.had then r.again=r.again+1 end
                                if r.again>=AGAIN then r.done=true;say('已换回 '..AGAIN..' 次，不再检查 '..name) end
                            end
                            r.had,r.tries=true,0;r.at=now+CHECK
                        else
                            r.tries=r.tries+1;r.at=now+FIRST
                            if r.done or r.tries>=TRIES then r.done=true;say('没有换上琵琶 '..name..' 原因='..tostring(why)) end
                        end
                    end
                end
            end
        end
        if next(records)then for key in pairs(records)do if not seen or not seen[key] then records[key]=nil end end end
    end
    function self:started(actor,skill)
        local key=U.key(actor)
        local r=key and records[key]
        if not self.alive or not r or r.team~='companion' or r.name~=fullName(actor)
            or (r.casts or 0)>=10 or not options.mapOpponent then return end
        local enemy=options.mapOpponent(actor)
        if not U.valid(enemy) then return end
        local wc=U.field(actor,'Character Weapons Component')
        local index=current(wc)
        local _,armed=call(wc,'IsArmed',slot())
        r.casts=(r.casts or 0)+1
        say('随从打地图敌人 '..tostring(fullName(enemy))..' 出招='..skill
            ..' 武器序号='..tostring(index)..' 持琵琶读回='..tostring(index==PIPA and armed==true))
    end
    function self:silence()self.alive=false;records={}end
    return self
end
return Pipa
