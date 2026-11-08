package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Writes=require('story_writes')
local function object(fields)
    local o=fields or {}
    o.alive=o.alive~=false
    o.IsValid=function(self)return self.alive end
    return o
end
local function fname(text)return {text=text,ToString=function(self)return self.text end} end
local function class(name)return object({GetFName=function()return fname(name) end}) end
local WIN='lz.龙柱.战斗胜利5'
local MOYUAN='/PBZCombatAsset/ActorData/Mobs/067_MoTian/Ability/ExE/GA_Hun_BEx_MoYuan'
local function action(full,tags)
    local list={}
    for _,t in ipairs(tags)do list[#list+1]={TagName=fname(t)} end
    return object({GetFullName=function()return 'GAA_FlowTag_C '..full end,Tags={GameplayTags=list}})
end
local function harness()
    local h={logs={},now=0,present={},actions={},scans=0,throws=false,pipelineOn=true}
    h.queries=0
    h.pipeline=object({HasTagWithOutSource=function(_,tag)
        h.queries=h.queries+1
        if h.throws then error('no') end
        if h.answer~=nil then return h.answer end
        return h.present[tag.TagName.text]==true end})
    h.writes=Writes.new({log=function(m)h.logs[#h.logs+1]=m end,clock=function()return h.now end,
        fname=function(t)if h.badName==t then return fname(t..'?') end;return fname(t)end,
        findAll=function(kind)assert(kind=='GAA_FlowTag_C');h.scans=h.scans+1;return h.actions end,
        pipeline=function()return h.pipeline_on~=false and h.pipelineOn and h.pipeline or nil end})
    function h.all()return table.concat(h.logs,'\n') end
    return h
end
local tests=0
local function test(name,fn)fn();tests=tests+1;print('ok - '..name) end

test('魔渊\'s finisher is refused while the fifth trial is not won in the story, and allowed once it is',function()
    local h=harness()
    h.actions={action(MOYUAN..'.GA_Hun_BEx_MoYuan_C:ExecutionTimeline.GAA_FlowTag_C_0',{WIN})}
    local ok,why=h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))
    assert(ok==false and why:find(WIN,1,true) and why:find('剧情里还没有',1,true),tostring(why))
    assert(h.all():find('GA_Hun_BEx_MoYuan_C 会给剧情加 ['..WIN..']，剧情里还没有：模组的处决不用它',1,true),h.all())
    local n=#h.logs
    assert(not h.writes:allows(class('GA_Hun_BEx_MoYuan_C')) and #h.logs==n,'said once')
    assert(h.scans==1,'its actions are read once')
    h.present[WIN]=true
    assert(h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))==true)
    assert(h.all():find('写的剧情标记 ['..WIN..'] 剧情里已有，用它处决不改变剧情',1,true),h.all())
    local s=h.writes:status()
    assert(s.refused==2 and s.allowed==1)
end)

test('an instance of the move counts as the move; a move with a longer name does not',function()
    local h=harness()
    h.actions={action('/Game/Maps/X.X:PersistentLevel.BP_Monster_A_C_1.GA_Hun_BEx_MoYuan_C_0.ExecutionTimeline.GAA_FlowTag_C_0',{WIN})}
    assert(h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))==false,'the instance is read')
    local g=harness()
    g.actions={action('/PBZCombatAsset/X/GA_Hun_BEx_MoYuan_02.GA_Hun_BEx_MoYuan_02_C:ExecutionTimeline.GAA_FlowTag_C_0',{WIN})}
    local ok,why=g.writes:allows(class('GA_Hun_BEx_MoYuan_C'))
    assert(ok==false and why:find('没加载',1,true),'another move\'s action is not this one\'s: '..tostring(why))
    assert(g.writes:allows(class('GA_Hun_BEx_MoYuan_02_C'))==false,'that one is read for its own class (found in the files at run time)')
end)

test('a move with no story action is allowed and looked up once',function()
    local h=harness()
    h.actions={action(MOYUAN..'.GA_Hun_BEx_MoYuan_C:ExecutionTimeline.GAA_FlowTag_C_0',{WIN})}
    assert(h.writes:allows(class('GA_Hun_BEx_Common_PengMeng_V2_C'))==true)
    assert(h.writes:allows(class('GA_Hun_BEx_Common_PengMeng_V2_C'))==true and h.scans==1,'remembered')
    assert(#h.logs==0,'nothing to say')
end)

test('a known story move whose actions are not loaded is refused, and looked for again later',function()
    local h=harness()
    local ok,why=h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))
    assert(ok==false and why:find('没加载',1,true) and h.scans==1)
    h.now=5;assert(h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))==false and h.scans==1,'not every call')
    h.actions={action(MOYUAN..'.GA_Hun_BEx_MoYuan_C:ExecutionTimeline.GAA_FlowTag_C_0',{WIN})}
    h.present[WIN]=true
    h.now=10;assert(h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))==true and h.scans==2)
end)

test('without the story system, or when it cannot answer, the move is refused',function()
    local h=harness()
    h.actions={action(MOYUAN..'.GA_Hun_BEx_MoYuan_C:ExecutionTimeline.GAA_FlowTag_C_0',{WIN})}
    h.pipelineOn=false
    local ok,why=h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))
    assert(ok==false and why=='读不到剧情系统')
    h.pipelineOn=true;h.throws=true
    ok,why=h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))
    assert(ok==false and why:find('（读不到）',1,true),tostring(why))
    assert(h.writes:allows(nil)==false,'no class')
end)

test('tags are read once each, None skipped, every one has to be there',function()
    local h=harness()
    h.actions={action(MOYUAN..'.GA_Hun_BEx_MoYuan_C:ExecutionTimeline.GAA_FlowTag_C_0',{WIN,'None'}),
        action('/X/Y.Z:PersistentLevel.A_1.GA_Hun_BEx_MoYuan_C_3.ExecutionTimeline.GAA_FlowTag_C_0',{WIN,'lz.龙柱.别的'})}
    h.present[WIN]=true
    local ok,why=h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))
    assert(ok==false and why=='会给剧情加 [lz.龙柱.别的]，剧情里还没有',tostring(why))
    h.present['lz.龙柱.别的']=true
    assert(h.writes:allows(class('GA_Hun_BEx_MoYuan_C'))==true)
    assert(h.all():find('['..WIN..',lz.龙柱.别的]',1,true),h.all())
end)

local LEIDANG='/PBZCombatAsset/ActorData/Mobs/047_LeiDang/BP_Monster_LeiDang.BP_Monster_LeiDang_C'
local GUNNER='/PBZCombatAsset/ActorData/Mobs/037_GuiChai/Blueprints/Rider/HorseCartCombat/BP_Monster_GuiChai_Black_Gun_Rider_HorseCartCombat_L.BP_Monster_GuiChai_Black_Gun_Rider_HorseCartCombat_L_C'
test('a unit that writes story progress is summoned only once the story holds what it writes',function()
    local h=harness()
    local ok,why=h.writes:allowsUnit(LEIDANG)
    assert(ok==false and why=='这个单位转阶段时会写剧情 [qsd.击杀.雷当]，存档里还没有：剧情打过这段之前不召唤它，免得坏档',tostring(why))
    assert(h.all():find('BP_Monster_LeiDang_C：这个单位转阶段时会写剧情',1,true),h.all())
    local n=#h.logs
    assert(h.writes:allowsUnit(LEIDANG)==false and #h.logs==n,'said once')
    h.present['qsd.击杀.雷当']=true
    assert(h.writes:allowsUnit(LEIDANG)==true and h.all():find('BP_Monster_LeiDang_C 会写的剧情标记 [qsd.击杀.雷当] 剧情里都有',1,true),h.all())
    local s=h.writes:status()
    assert(s.units_refused==2 and s.units_allowed==1,'counted apart from finishers')
end)

test('any other unit is summoned without asking the story',function()
    local h=harness()
    h.pipelineOn=false
    assert(h.writes:allowsUnit('/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue.BP_Monster_MaleThug_Sword_Blue_C')==true)
    assert(h.writes:allowsUnit(nil)==true and h.queries==0 and #h.logs==0)
end)

test('every mark of a unit has to be there; what is missing is named',function()
    local h=harness()
    h.present['rzgd.马车战.抵挡射击2']=true;h.present['rzgd.马车战.抵挡射击3']=true
    local ok,why=h.writes:allowsUnit(GUNNER)
    assert(ok==false and why=='这个单位玩家接住它开枪的 QTE 时会写剧情 [rzgd.击败.两个枪鬼差]，存档里还没有：剧情打过这段之前不召唤它，免得坏档',tostring(why))
    h.present['rzgd.击败.两个枪鬼差']=true
    assert(h.writes:allowsUnit(GUNNER)==true)
end)

test('when the story cannot be read, or a name does not read back as itself, the unit is not summoned',function()
    local h=harness()
    h.pipelineOn=false
    local ok,why=h.writes:allowsUnit(LEIDANG)
    assert(ok==false and why=='读不到剧情里有没有 [qsd.击杀.雷当]，这个单位转阶段时会写它，先不召唤',tostring(why))
    local g=harness()
    g.badName='qsd.击杀.雷当';g.present['qsd.击杀.雷当']=true
    ok,why=g.writes:allowsUnit(LEIDANG)
    assert(ok==false and why:find('读不到',1,true) and g.queries==0,tostring(why))
    assert(g.writes:has('qsd.击杀.雷当')==nil)
    local k=harness()
    k.throws=true
    assert(k.writes:has('qsd.击杀.雷当')==nil and k.writes:allowsUnit(LEIDANG)==false)
end)

test('has: true, false or nil',function()
    local h=harness()
    h.present['a.b']=true
    assert(h.writes:has('a.b')==true and h.writes:has('a.c')==false)
    h.pipelineOn=false
    assert(h.writes:has('a.b')==nil)
    h.pipelineOn=true;h.answer={}
    assert(h.writes:has('a.b')==nil,'an answer that is not a boolean is unread')
end)

test('the list: full class paths, each with marks and when they are written',function()
    local n=0
    for path,unit in pairs(Writes.UNITS)do
        n=n+1
        local dir,name,again=path:match('^(/.+/)([%w_]+)%.([%w_]+)_C$')
        assert(dir and name==again,path)
        assert(type(unit.tags)=='table' and #unit.tags>0 and type(unit.how)=='string' and unit.how~='',path)
        for _,t in ipairs(unit.tags)do assert(t:find('^[%w]+%.'),path..' '..t) end
    end
    assert(n==18,'eighteen classes: '..n)
    assert(Writes.UNITS[LEIDANG] and Writes.UNITS['/PBZCombatAsset/ActorData/Mobs/077_LengTu/BP_Monster_LengTu.BP_Monster_LengTu_C'].tags[1]=='qsd.击杀.雷当')
end)

print('story_writes: PASS ('..tests..' groups)')
