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
    local retained=0
    -- Each sampled pair lives only as long as both roster identities do.
    local function forget(row)
        for source in pairs(row.decisions)do
            source.targets[row]=nil;retained=retained-1
        end
        for target in pairs(row.targets)do
            target.decisions[row]=nil;retained=retained-1
        end
        row.decisions,row.targets={},{}
    end
    function self:sync(members,active)
        self.enabled=active and o.configured and o.configured()==true or false
        if not self.enabled then records={};retained=0;self.draws=0;return end
        if o.world then
            local currentWorld=U.key(o.world())
            if not currentWorld then records={};retained=0;return end
            if currentWorld~=world then records={};retained=0;self.draws=0;world=currentWorld end
        end
        local current={}
        for _,m in ipairs(members)do
            if(m.team=='blue'or m.team=='red')and not m.reserve and not m.stand and not m.aid then
                local key=U.key(m.actor)
                if key then
                    local id=(m.class_path or''):match('([^/%.]+)$');if id then id=id:gsub('_C$','')end
                    local row=records[key]
                    if not row or row.id~=id or row.team~=m.team then row={id=id,decisions={},targets={}}end
                    row.actor=m.actor;row.team=m.team;current[key]=row
                end
            end
        end
        for key,row in pairs(records)do if current[key]~=row then forget(row) end end
        records=current
    end
    function self:allow(executor,target,isMob)
        if not isMob or not self.enabled then return true end
        local e,t=records[U.key(executor)or''],records[U.key(target)or'']
        if not e or not t or e.team==t.team then return false end
        local en,tn=name(executor),name(target)
        if not en or not tn then return false end
        if e.name~=en then forget(e);e.name=en;e.boss=nil end
        if t.name~=tn then forget(t);t.name=tn;t.boss=nil end
        local setting=e.id and o.rule(e.id)or'on_100'
        if setting=='on_100'then return true end
        if e.boss==nil then e.boss=boss(executor)end
        if e.boss==nil then return false end
        if not e.boss then return true end
        if setting:sub(1,4)=='off_'then return false end
        local percent=tonumber(setting:match('^on_(%d+)$'))
        if not percent or percent<0 or percent>100 then return false end
        if percent==0 then return false end
        local d=t.decisions[e]
        if d and d.setting==setting then return d.allowed end
        if not d and retained>=4096 then return false end
        local ok,roll=pcall(random)
        if not ok or type(roll)~='number'or roll~=roll or roll<0 or roll>=1 then return false end
        local allowed=roll*100<percent
        if not d then retained=retained+1;e.targets[t]=true end
        t.decisions[e]={setting=setting,allowed=allowed};self.draws=self.draws+1
        if lines<40 then lines=lines+1;(o.log or function()end)('[ExecutionPolicy] 处决小怪抽签：源='..e.name..'；目标='..t.name..'；概率='..percent..'；读回='..tostring(allowed))end
        return allowed
    end
    return self
end
return Policy
