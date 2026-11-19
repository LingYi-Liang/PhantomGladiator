package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local W=require('map_weather')
local serial=0
local function object(name,outer)
    serial=serial+1;local id=serial
    return {valid=true,IsValid=function(s)return s.valid end,GetAddress=function()return id end,
        GetOuter=function()return outer end,GetFullName=function()return name end}
end
local world=object('Map');local actor=object('Weather Actor',world)
local original=object('Original');actor.Weather=original;actor['Random Weather Variation']=0
local changes,scans=0,0
actor['Change Weather']=function(a,p)changes=changes+1;a.Weather=p;a['Random Weather Variation']=0 end
actor['Change to Random Weather Variation']=function(a,_,mode)a['Random Weather Variation']=mode end
local assets={};local rows={actor};local w=W.new({world=function()return world end,log=function()end,
    load=function(path)assets[path]=assets[path] or object('UDS_Weather_Settings_C '..path);return assets[path]end,
    findAll=function()scans=scans+1;return rows end})
for _,p in ipairs(W.presets)do assert(w:set(p:lower()).ok and w:status()==p:lower())end
assert(scans==1 and w:set('next').ok and w:status()=='clear_skies')
assert(w:set('previous').ok and w:status()=='sand_dust_storm')
assert(w:set('restore').ok and actor.Weather==original and w:status()=='map')
local null={IsValid=function()return false end}
actor.Weather=null;actor['Random Weather Variation']='UDS_RandomWeatherTiming::NewEnumerator3'
assert(w:set('snow').ok,'wrapped empty native Weather is the manual map state')
local switch=actor['Change Weather'];actor['Change Weather']=function(a,p,t)switch(a,p or null,t)end
assert(w:set('restore').ok and actor.Weather==null)
actor['Change Weather']=switch;actor.Weather=original
actor['Random Weather Variation']='not a weather mode';assert(not w:set('rain').ok)
actor['Random Weather Variation']=2;assert(w:set('rain').ok and w:set('restore').ok and actor['Random Weather Variation']==2)
actor.Weather=original;actor['Random Weather Variation']=0;assert(w:set('snow').ok)
actor.Weather=object('Story override');local n=changes;assert(w:set('restore').ok and changes==n)
actor['Currently in a Weather Override Volume']=true;assert(not w:set('foggy').ok);actor['Currently in a Weather Override Volume']=false
rows={actor,object('Another',world)};assert(not w:set('rain').ok and changes==n)
rows={actor};assert(w:set('rain').ok);world=object('New map');assert(w:status()=='map' and not w:set('rain').ok)
assert(w:set('restore').ok and changes==n+1)
print('PASS 13 direct presets, wraparound, restoration, story takeover, wrong world and ambiguous controllers')
