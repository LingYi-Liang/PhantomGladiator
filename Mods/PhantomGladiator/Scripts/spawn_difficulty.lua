-- Spawn difficulty: units summoned by the app take the difficulty picked in the app instead of the
-- game's. Characters such as BP_RenewalNPC_C hold their own `Global Config <difficulty>` references
-- (PDA_GlobalConfig_Combined_C) and their config getters pick one by the game difficulty
-- (BP_RenewalNPC.hpp). Before FinishSpawn every slot of the new actor points at the chosen
-- difficulty's config, so the game itself applies that difficulty to this unit only. Nothing shared
-- is written: not the class defaults, not the config assets, not the game's difficulty or save.
local U=require('ue_observe')
local Attributes=require('character_stats')
local Difficulty={}
local HEADER='SpawnDifficultyV1\t'
local SLOTS={'Handicapped','Easy','Normal','Hard','Nightmare'}
-- Panel token -> config slot. FOLLOW leaves the unit on the game's difficulty.
local LEVELS={EASY='Easy',NORMAL='Normal',HARD='Hard',NIGHTMARE='Nightmare'}
local GAME={[0]='Handicapped',[1]='Easy',[2]='Normal',[3]='Hard',[4]='Nightmare'} -- EDifficultMode
local LIBRARY='/Script/ProjectPBZ.Default__PBZBlueprintFunctionLibrary'
local STATS={'Health_Max','Shachi_Max','Attack','ShachiAttack'}
Difficulty.tokens={'FOLLOW','EASY','NORMAL','HARD','NIGHTMARE'}

function Difficulty.new(options)
    local log=options.log or function()end
    local fs=options.io or io
    local clock=options.clock or os.clock
    local adapter=options.adapter or Attributes.new()
    local settings=options.path..'/spawn-difficulty.tsv'
    local self={level='FOLLOW',game='',applied=0,skipped=0,failures=0,message='跟随游戏难度',pending={},byKey={}}
    local f=fs.open(settings,'r')
    if f then
        local text=f:read('*a');f:close()
        local token=type(text)=='string' and text:match('^SpawnDifficultyV1\t([A-Z]+)\n$')
        if token=='FOLLOW' or LEVELS[token] then self.level=token end
    end
    local function say(message)log('[SpawnDifficulty] '..message)end
    local function slotName(slot)return 'Global Config '..slot end

    -- The game's own difficulty, read at most every two seconds and only once a map is loaded.
    local checkedAt
    local function readGame(force)
        if not force and checkedAt and clock()-checkedAt<2 then return self.game end
        checkedAt=clock()
        if options.ready and not options.ready() then return self.game end
        local library=StaticFindObject(LIBRARY)
        local world=options.getWorld and options.getWorld()
        if not U.valid(library) or not U.valid(world) then return self.game end
        local ok,value=pcall(function()return library:GetDiffcultMode(world)end)
        value=ok and tonumber(U.unwrap(value)) or nil
        self.game=GAME[value] or ''
        return self.game
    end

    function self:set(token)
        if token~='FOLLOW' and not LEVELS[token] then return {ok=false,message='未知难度：'..tostring(token),spawned_count=0} end
        local text=HEADER..token..'\n'
        local file=fs.open(settings,'w')
        if not file then return {ok=false,message='召唤难度保存失败，未切换',spawned_count=0} end
        local wrote=file:write(text);local closed=file:close()
        file=fs.open(settings,'r');local actual=file and file:read('*a');if file then file:close()end
        if not wrote or not closed or actual~=text then return {ok=false,message='召唤难度保存未读回，未切换',spawned_count=0} end
        self.level=token
        self.message=token=='FOLLOW' and '跟随游戏难度' or ('之后召唤的单位按'..LEVELS[token]..'生成；已在场的单位不变')
        say('设置读回 level='..token..' 游戏难度='..readGame(true))
        return {ok=true,message=self.message,spawned_count=0}
    end

    -- Before FinishSpawn. A unit without the five slots, or a write that does not read back, keeps the
    -- game's difficulty; the spawn itself is never blocked.
    function self:prepare(actor,unitPath)
        local game=readGame(true)
        if self.level=='FOLLOW' or not U.valid(actor) then return {ok=true,applied=false} end
        local wanted=LEVELS[self.level]
        local original={}
        for _,slot in ipairs(SLOTS)do
            local value,read=U.field(actor,slotName(slot))
            if not read or not U.valid(value) then
                self.skipped=self.skipped+1
                self.message='该单位没有按难度区分的配置，按游戏难度生成'
                say('跳过 unit='..tostring(unitPath)..' 缺少 '..slotName(slot)..'；按游戏难度='..game)
                return {ok=true,applied=false,message=self.message}
            end
            original[slot]=value
        end
        local target=original[wanted]
        local targetKey=U.key(target)
        local function pointAll(pick)
            local matched=0
            for _,slot in ipairs(SLOTS)do
                local value=pick(slot)
                if U.valid(actor) then pcall(function()actor[slotName(slot)]=value end) end
                local actual=U.field(actor,slotName(slot))
                if U.key(actual)==U.key(value) then matched=matched+1 end
            end
            return matched
        end
        local matched=pointAll(function()return target end)
        if matched==#SLOTS then
            self.applied=self.applied+1
            self.pending[U.key(actor) or '']={unit=unitPath,target=targetKey,level=wanted}
            self.byKey[U.key(actor) or '']=wanted
            self.message='最近一只按'..wanted..'生成'
            say('写入并读回 unit='..tostring(unitPath)..' 游戏难度='..game..' 目标='..wanted..' 槽位='..matched..'/'..#SLOTS)
            return {ok=true,applied=true,message=self.message}
        end
        local restored=pointAll(function(slot)return original[slot] end)
        self.failures=self.failures+1
        self.message='难度配置写入未读回，已恢复原配置='..tostring(restored==#SLOTS)..'；按游戏难度生成'
        say(self.message..' unit='..tostring(unitPath)..' 目标槽位='..matched..'/'..#SLOTS)
        return {ok=false,applied=false,message=self.message,rollback_verified=restored==#SLOTS}
    end

    -- After activation: do the slots still point at the chosen config, and what did the game hand out.
    -- Logged for every unit (game difficulty too) so the same unit can be compared across difficulties.
    function self:verify(actor,unitPath)
        local key=U.key(actor) or ''
        local record=self.pending[key];self.pending[key]=nil
        local parts={}
        for _,field in ipairs(STATS)do
            local entry=adapter:read(actor,field)
            parts[#parts+1]=field..'='..(entry and string.format('%.6g',entry.current) or '不可读')
        end
        local kept=''
        if record then
            local matched=0
            for _,slot in ipairs(SLOTS)do
                if U.key(U.field(actor,slotName(slot)))==record.target then matched=matched+1 end
            end
            kept=' 生成后槽位读回='..matched..'/'..#SLOTS
        end
        say('出生属性 unit='..tostring(unitPath)..' 难度='..(record and record.level or '游戏'..readGame())..kept..' '..table.concat(parts,' '))
    end

    -- The level this mod gave a unit, or nil when it follows the game.
    function self:levelOf(actor)return self.byKey[U.key(actor) or ''] end
    function self:levelOfKey(key)return key and self.byKey[key] or nil end
    -- Forget units that left the arena, so a reused address never inherits a level.
    function self:prune(keys)
        for key in pairs(self.byKey)do if not keys[key] then self.byKey[key]=nil end end
    end

    function self:status()
        return {level=self.level,game=readGame(),applied=self.applied,skipped=self.skipped,failures=self.failures,message=self.message}
    end
    return self
end
return Difficulty
