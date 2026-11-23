package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local U=require('ue_observe')
local Materials=require('hun_outfit_materials')
local seq=0
local function obj(fields)
    local o=fields or {};seq=seq+1;local key=seq
    function o:IsValid()return not self.gone end
    function o:GetAddress()return key end
    return o
end
local function call(o,name,...)
    if not U.valid(o) or type(o[name])~='function' then return false end
    return pcall(o[name],o,...)
end
local function param(name,value)return {ParameterInfo={Name=name,Association=0,Index=-1},ParameterValue=value} end
local function mid(base,outer,value)
    return obj({base=base,GetOuter=function()return outer end,
        ScalarParameterValues={param('Skin',value)},VectorParameterValues={param('Tint',{R=0,G=1,B=0,A=1})},
        TextureParameterValues={param('Decal',nil)}})
end
local function fixture(n)
    local h={allocations=0,copies=0,reads=0,records={}}
    local player,base,mesh=obj(),obj(),obj()
    h.base,h.player=base,player
    local source=obj({owner=player,asset=mesh});h.src=source
    source.mat=mid(base,source,.4)
    function source:GetOwner()return self.owner end
    function source:GetNumMaterials()return 1 end
    function source:GetMaterial()h.reads=h.reads+1;return self.mat end
    h.watch=Materials.new({call=call,asset=function(o)return o.asset end,base=function(m)return m and (m.base or m) end,
        text=function(x)return x end,phantom=function()return false end,say=function()end,fname=function(x)return x end})
    function h:add()
        local actor=obj();local dest=obj({owner=actor,asset=mesh,mat=base})
        function dest:GetOwner()return self.owner end
        function dest:GetNumMaterials()return 1 end
        function dest:GetMaterial()return self.mat end
        function dest:SetMaterial(_,m)self.mat=m end
        function dest:CreateDynamicMaterialInstance(_,parent)
            h.allocations=h.allocations+1
            self.mat=mid(parent,self,0)
            function self.mat:K2_CopyMaterialInstanceParameters(m,quick)
                assert(quick and self~=m and self:GetOuter()==dest)
                h.copies=h.copies+1
                if h.ignoreCopy then return end
                self.ScalarParameterValues={param('Skin',m.ScalarParameterValues[1].ParameterValue)}
                self.VectorParameterValues={param('Tint',{R=m.VectorParameterValues[1].ParameterValue.R,G=1,B=0,A=1})}
                self.TextureParameterValues={param('Decal',m.TextureParameterValues[1].ParameterValue)}
            end
            return self.mat
        end
        local r={name='Hun',actor=actor,dest=dest,still=function()return not actor.gone end,appearance={nextCheck=0}}
        self.records[#self.records+1]=r;self.watch:bind(r,dest,source,'身体')
        return r
    end
    function h:step(t)
        local sweep={materialJobs={}}
        for _,r in ipairs(self.records) do
            if r.appearance and t>=r.appearance.nextCheck then
                r.appearance.nextCheck=t+4
                self.watch:offer(r,r,t,U.key(player),sweep)
            end
        end
        local before=self.reads;self.watch:flush(sweep.materialJobs,t)
        return self.reads-before
    end
    for _=1,n do h:add() end
    return h
end
do
    local h=fixture(24);local peak=0
    for i=0,20 do peak=math.max(peak,h:step(i*.5)) end
    local before=h.copies
    for i=21,45 do peak=math.max(peak,h:step(i*.5)) end
    print('MEASURE 24 Hun, maximum inspected slots per support pulse='..peak..', steady native parameter copies='..(h.copies-before))
    assert(peak<=12 and before==h.copies)
    local newTexture=obj();local source=h.src.mat
    source.ScalarParameterValues[1].ParameterValue=.9
    source.VectorParameterValues[1].ParameterValue.R=.6
    source.TextureParameterValues[1].ParameterValue=newTexture
    for i=46,70 do assert(h:step(i*.5)<=12) end
    for _,r in ipairs(h.records) do
        local m=r.dest.mat
        assert(m.ScalarParameterValues[1].ParameterValue==.9 and m.VectorParameterValues[1].ParameterValue.R==.6
            and m.TextureParameterValues[1].ParameterValue==newTexture)
    end
    assert(h.allocations==24 and h.copies==before+24,'each clone reuses one owned instance per changed slot')
    h.records[1].dest.mat.ScalarParameterValues[1].ParameterValue=0
    for i=71,83 do h:step(i*.5) end
    assert(h.records[1].dest.mat.ScalarParameterValues[1].ParameterValue==.9 and h.copies==before+25)
end
do
    local h=fixture(0);h.src.mat=h.base
    local r=h:add();assert(h.allocations==0)
    h.src.mat=mid(h.base,h.src,.8);h:step(1)
    assert(h.allocations==1 and r.dest.mat.ScalarParameterValues[1].ParameterValue==.8)
    local external=mid(h.base,r.dest,.2);r.dest.mat=external
    h.src.mat=mid(h.base,h.src,.6);h:step(6)
    assert(r.dest.mat==external and external.ScalarParameterValues[1].ParameterValue==.2)
end
do
    local h=fixture(1);local r=h.records[1];local owned=r.dest.mat
    h.src.owner=obj();h.src.mat=mid(h.base,h.src,.8);h:step(1)
    assert(owned.ScalarParameterValues[1].ParameterValue==.4)
    h.src.owner=h.player;r.dest.owner=obj();h:step(5)
    assert(h.copies==1)
    r.dest.owner=r.actor;r.dead=true;h:step(9);assert(h.copies==1)
    r.dead=false;r.actor.gone=true;h:step(13);assert(h.copies==1)
end
do
    local h=fixture(1);h:step(0);local dest=h.records[1].dest.mat
    h.src.mat.ScalarParameterValues[1].ParameterValue=.8;h.ignoreCopy=true;h:step(4)
    assert(dest.ScalarParameterValues[1].ParameterValue==.4)
    h.ignoreCopy=false
    for t=5,18 do h:step(t) end
    assert(dest.ScalarParameterValues[1].ParameterValue==.8 and h.allocations==1,'an unread parameter update should be retried')
end
print('PASS stable and late dynamic overrides, material ownership, crowd budget and cleanup')
