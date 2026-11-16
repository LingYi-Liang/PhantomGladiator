-- Stable per executor/victim decisions for optional boss-to-minion finishers.
local U=require('ue_observe')
local Policy={}
local function name(a)
    if not U.valid(a)then return nil end
    local ok,n=pcall(function()return a:GetFullName()end);return ok and type(n)=='string'and n or nil
end
local function boss(a)
    local cfg=U.field(a,'Actor Config');local value=U.struct(U.field(cfg,'Difficulty Tag'),'TagName')
    local ok,t=pcall(function()return type(value)=='string'and value or value:ToString()end)
    if not ok or type(t)~='string'or not t:find('^CharacterType%.Difficulty%.')then return nil end
    return t:match('Boss$')~=nil
end
function Policy.new(o)
    local self={enabled=false,draws=0};local records,lines,world={},0,nil
    local random=o.random or math.random
    function self:sync(members,active)
        self.enabled=active and o.configured and o.configured()==true or false
        if not self.enabled then records={};self.draws=0;return end
        if o.world then
            local currentWorld=U.key(o.world())
            if not currentWorld then records={};return end
            if currentWorld~=world then records={};self.draws=0;world=currentWorld end
        end
        local current={}
        for _,m in ipairs(members)do
            if(m.team=='blue'or m.team=='red')and not m.reserve and not m.stand and not m.aid then
                local key,n=U.key(m.actor),name(m.actor)
                if key and n then
                    local row=records[key]
                    if not row or row.name~=n then row={name=n,decisions={}}end
                    row.id=(m.class_path or''):match('([^/%.]+)$');if row.id then row.id=row.id:gsub('_C$','')end
                    row.actor=m.actor;row.team=m.team;current[key]=row
                end
            end
        end
        records=current
    end
    function self:allow(executor,target,isMob)
        if not isMob or not self.enabled then return true end
        local e,t=records[U.key(executor)or''],records[U.key(target)or'']
        if not e or not t or e.team==t.team or e.name~=name(executor)or t.name~=name(target)then return false end
        local setting=e.id and o.rule(e.id)or'on_100'
        if setting=='on_100'then return true end
        if e.boss==nil then e.boss=boss(executor)end
        if e.boss==nil then return false end
        if not e.boss then return true end
        if setting:sub(1,4)=='off_'then return false end
        local percent=tonumber(setting:match('^on_(%d+)$'))
        if not percent or percent<0 or percent>100 then return false end
        if percent==0 then return false end
        local key=U.key(executor);local d=t.decisions[key]
        if d and d.name==e.name and d.setting==setting then return d.allowed end
        if self.draws>=4096 then return false end
        local ok,roll=pcall(random)
        if not ok or type(roll)~='number'or roll~=roll or roll<0 or roll>=1 then return false end
        local allowed=roll*100<percent
        t.decisions[key]={name=e.name,setting=setting,allowed=allowed};self.draws=self.draws+1
        if lines<40 then lines=lines+1;(o.log or function()end)('[ExecutionPolicy] 处决小怪抽签：源='..e.name..'；目标='..t.name..'；概率='..percent..'；读回='..tostring(allowed))end
        return allowed
    end
    return self
end
return Policy
