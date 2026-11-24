-- Character profiles contain plain values. A live companion takes a snapshot at birth.
local P={}
P.first='/PBZCombatAsset/ActorData/Mobs/062_MuXiaoKui/BP_Monster_MuXiaoKui.BP_Monster_MuXiaoKui_C'
P.second='/PBZCombatAsset/ActorData/Mobs/064_MuXiaoKui_P2/BP_Monster_MuXiaoKui_P2.BP_Monster_MuXiaoKui_P2_C'
function P.phase(path)
    if path==P.first then return 1 elseif path==P.second then return 2 end
end
P.fields={'behavior','distance','unstuck','targetable','regen','rate','policy','threshold','delay'}
P.defaults={behavior='active',distance=5,unstuck=1,targetable=1,regen='game',rate=1,policy='auto_return',threshold=50,delay=10}
local ranges={distance={2,25},unstuck={0,1},targetable={0,2},rate={0,10},threshold={1,99},delay={2,120}}
local allowed={behavior={active=true,assist=true,peace=true},regen={game=true,custom=true},
    policy={auto_return=true,auto_stay=true,manual=true,first=true,second=true}}
function P.copy(p)local out={};for _,k in ipairs(P.fields)do out[k]=p[k] end;return out end
function P.encode(p)
    local fields={}
    for i,k in ipairs(P.fields)do fields[i]=tostring(p[k]) end
    return table.concat(fields,',')
end
function P.decode(text)
    if type(text)~='string' or #text>120 then return end
    local p,i={},0
    for v in (text..','):gmatch('([^,]*),')do
        i=i+1;local k=P.fields[i]
        if not k then return end
        if ranges[k] then
            if not v:match('^%d+$') then return end
            local n=tonumber(v);if n<ranges[k][1] or n>ranges[k][2] then return end
            p[k]=n
        elseif allowed[k][v] then p[k]=v else return end
    end
    if i==#P.fields then return p end
end
function P.read(file,limit)
    local f=io.open(file,'rb');if not f then return end
    limit=limit or 512
    local data,err=f:read(limit+1);f:close()
    if not err and (not data or #data<=limit) then return data or '' end
end
-- Preserve the last verified file over Windows rename and power-loss failures.
function P.write(file,data)
    local temp,backup=file..'.tmp',file..'.bak'
    local f=io.open(temp,'wb');if not f then return false end
    local written=f:write(data);local closed=f:close()
    if not written or not closed or P.read(temp,#data)~=data then return false end
    local previous=io.open(file,'rb')
    if previous then
        previous:close()
        os.remove(backup)
        if not os.rename(file,backup) then return false end
    end
    if os.rename(temp,file) and P.read(file,#data)==data then return true end
    if previous then os.remove(file);os.rename(backup,file) end
    return false
end
return P