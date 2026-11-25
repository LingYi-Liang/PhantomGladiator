-- Settings have a closed schema so camera presets can be read as data, never executed.
local N=require('photo_native')
local S={}
local F={
    {'fov',60,20,115,2},{'roll',0,-180,180,2},{'focus',350,50,15000,50},
    {'aperture',0,0,16,.1},{'autofocus',false},{'focusMark',false},{'bars',true},
    {'filter',1,1,4,1},{'strength',100,0,100,5},{'exposure',0,-4,4,.25},
    {'saturation',100,0,200,5},{'contrast',100,40,180,5},{'gamma',100,60,160,5},
    {'temperature',6500,2000,12000,250},{'tint',0,-1,1,.1},
    {'bloom',-1,-1,6,.2},{'fringe',-1,-1,5,.2},{'grain',-1,-1,1,.05},
    {'vignette',-1,-1,1,.05},{'blur',-1,-1,1,.05},{'blurMax',-1,-1,100,5},{'zoomBlur',0,0,100,5},{'environment',-1,-1,3,.2},
    {'lightSlot',1,1,3,1},{'grid',false},{'border',1,1,4,1},{'mark',1,1,4,1},
    {'captureHDR',false},{'show1',true},{'show2',true},{'eyes1',1,1,6,1},{'eyes2',1,1,6,1},
}
local L={
    {'power',0,0,100,5},{'color',1,1,5,1},{'angle',0,-180,180,10},
    {'height',120,-120,500,15},{'distance',235,50,1200,25},{'radius',1100,200,4000,100},
    {'hue',0,0,360,10},{'sat',70,0,100,5},{'brightness',100,0,100,5},
    {'channels',1,1,7,1},{'scatter',1,0,5,.25},{'shadows',false},
}
local fields,light={},{ }
for _,d in ipairs(F)do fields[d[1]]=d end
for _,d in ipairs(L)do light[d[1]]=d end
S.fields,S.light=fields,light
local function normalized(d,value)
    if type(d[2])=='boolean' then
        if type(value)=='boolean' then return value end
        return d[2]
    end
    if not N.number(value) then return d[2] end
    if d[5]==1 then value=math.floor(value+.5) end
    return N.limit(value,d[3],d[4])
end
function S.defaults(fov)
    local s={lights={}}
    for _,d in ipairs(F)do s[d[1]]=d[2] end
    s.fov=normalized(fields.fov,fov)
    for i=1,3 do
        local r={}
        for _,d in ipairs(L)do r[d[1]]=d[2] end
        r.angle=({0,-65,145})[i]
        s.lights[i]=r
    end
    return s
end
function S.step(s,id,step)
    local d=fields[id]
    local owner=s
    if not d and id:sub(1,2)=='l_' then
        id=id:sub(3);d=light[id];owner=s.lights[s.lightSlot]
    end
    if not d then return nil end
    local old=owner[id]
    if type(old)=='boolean' then owner[id]=not old
    elseif id=='filter' or id=='border' or id=='mark' or id=='lightSlot' or id=='color' or id=='channels' or id=='eyes1' or id=='eyes2' then
        owner[id]=(old+step-d[3])%(d[4]-d[3]+1)+d[3]
    else
        owner[id]=normalized(d,old+step*d[5])
    end
    return owner,id,old
end
local function token(v)
    if type(v)=='boolean' then return v and 'on' or 'off' end
    return string.format('%.5f',v)
end
function S.encode(s)
    local out={'PhotoPresetV1'}
    for _,d in ipairs(F)do local k=d[1];out[#out+1]=k..'='..token(s[k]) end
    for i,r in ipairs(s.lights)do
        for _,d in ipairs(L)do local k=d[1];out[#out+1]='l'..i..'.'..k..'='..token(r[k]) end
    end
    return table.concat(out,'\n')..'\n'
end
function S.decode(text)
    if type(text)~='string' or #text>8192 or text:match('^[^\r\n]+')~='PhotoPresetV1' then return nil end
    local s=S.defaults(60)
    local seen={}
    for k,v in text:gmatch('\n([A-Za-z0-9.]+)=([^\r\n]+)')do
        if seen[k] then return nil end
        seen[k]=true
        local slot,key=k:match('^l([123])%.([A-Za-z]+)$')
        local d=slot and light[key] or fields[k]
        if d then
            local value
            if v=='on' then value=true elseif v=='off' then value=false else value=tonumber(v) end
            if type(value)~=type(d[2]) or type(value)=='number' and not N.number(value) then return nil end
            if slot then s.lights[tonumber(slot)][key]=normalized(d,value)
            else s[k]=normalized(d,value) end
        end
    end
    return s
end
function S.presets(path,files)
    local lib=files or io
    local function loc(i)return path and (path..'/photo-preset-'..i..'.tsv') end
    local function read(p)
        if not p then return nil end
        local f=lib.open(p,'rb')
        if not f then return nil end
        local data=f:read(8193);f:close();return data
    end
    local function put(p,data)
        if not p then return false end
        local f=lib.open(p,'wb')
        if not f then return false end
        local wrote=f:write(data)
        local closed=f:close()
        return wrote~=nil and wrote~=false and closed==true and read(p)==data
    end
    return {
        load=function(i)
            local path=loc(i)
            return S.decode(read(path)) or S.decode(read(path and path..'.bak'))
        end,
        save=function(i,s)
            local p=loc(i)
            if not p then return false end
            local old=read(p)
            if S.decode(old) and not put(p..'.bak',old) then return false end
            return put(p,S.encode(s))
        end,
    }
end
return S
