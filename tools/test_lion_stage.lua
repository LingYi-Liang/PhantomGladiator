package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local LionStage=require('lion_stage')
local bossPath='/Game/RenewalContent/Actors/Mobs/Normal/BP_Monster_LionDancer_P2.BP_Monster_LionDancer_P2_C'
local areaPath='/Game/PBZContent/Blueprint/TriggerVolume/BP_LionDance_Area.BP_LionDance_Area_C'
local nextAddress=0

local function object(fields)
    nextAddress=nextAddress+1
    fields=fields or {}
    fields.address=nextAddress
    fields.GetAddress=function(self)return self.address end
    fields.IsValid=function(self)return not self.gone end
    fields.GetOuter=function(self)return self.outer end
    fields.K2_DestroyActor=function(self)self.gone=true end
    return fields
end

local function harness()
    local h={time=0,areas={},events={},logs={},builds=0,loaded=false,world=object()}
    local function pawn(fields)
        fields.outer=h.world
        fields.IsOverlappingActor=function(self,area)
            return area.collision==true and not self.outside and not h.preventOverlap
        end
        return object(fields)
    end
    h.boss=pawn({at={X=100,Y=200,Z=300},hp=100})
    h.player=pawn({at={X=101,Y=200,Z=300}})
    local cls=object({GetFullName=function()return 'BlueprintGeneratedClass '..areaPath end})
    local primitives=object({AppendBox=function(_,mesh,params,transform,w,horizontal,height)
        assert(params.PolygroupMode==0 and transform.Scale3D.X==1 and w==horizontal and w>=4000 and height>=1000)
        assert(mesh.clean)
        mesh.box=true
        return mesh
    end})
    local collisions=object({SetDynamicMeshCollisionFromMesh=function(_,mesh,component,opts)
        assert(mesh.box and opts.Method==0 and component.MeshBodySetup)
        component.MeshBodySetup.AggGeom.BoxElems={{X=10400,Y=10400,Z=3800}}
        h.builds=h.builds+1
    end})
    function h:makeArea(owner,native)
        local area=object({outer=self.world,Owner=owner,collision=native==true,InTriggerActors={},
            ActivatedLinks={},DeactivatedLinks={},ActivatedPoles={},DeactivatedPoles={}})
        area.SetActorEnableCollision=function(self,on)
            if on then
                assert(self.DynamicMeshComponent.MeshBodySetup.AggGeom.BoxElems[1])
                assert(self.DynamicMeshComponent.profile=='Profile_Trigger'
                    and self.DynamicMeshComponent.mode==1 and self.DynamicMeshComponent.events)
            end
            self.collision=on
        end
        area.GetActorEnableCollision=function(self)return self.collision end
        area.TryUpdateActorInTriggerState=function(self,actor,inside)
            assert(inside and self.collision)
            self.InTriggerActors[#self.InTriggerActors+1]=actor
        end
        area.DeactivateAllPoles=function(self)
            assert(self.collision and not self.deactivated)
            self.deactivated=true
            for _,part in ipairs(self.ActivatedPoles)do self.DeactivatedPoles[#self.DeactivatedPoles+1]=part end
            self.ActivatedPoles={}
        end
        area.SetEnabled=function(self,on)assert(not on);self.InTriggerActors={}end
        local comp=object({outer=area,MeshBodySetup=object({AggGeom={BoxElems={}}})})
        local mesh=object({outer=comp,Reset=function(self)self.clean=true end})
        comp.GetDynamicMesh=function()return mesh end
        comp.SetDeferredCollisionUpdatesEnabled=function()end
        comp.SetComplexAsSimpleCollisionEnabled=function()end
        comp.UpdateCollision=function()end
        comp.SetCollisionProfileName=function(self,profile)self.profile=profile end
        comp.SetCollisionResponseToChannel=function(_,channel,response)assert((channel==1 or channel==2 or channel==19) and response==1)end
        comp.SetCollisionEnabled=function(self,mode)self.mode=mode end
        comp.GetCollisionEnabled=function(self)return self.mode end
        comp.SetGenerateOverlapEvents=function(self,on)self.events=on end
        area.DynamicMeshComponent=comp
        self.areas[#self.areas+1]=area
        return area
    end
    local statics=object({
        BeginDeferredActorSpawnFromClass=function(_,world,class,transform,mode,owner)
            assert(world==h.world and class==cls and owner==h.boss)
            assert(transform.Translation.X==100 and mode==1)
            return h:makeArea(owner,false)
        end,
        FinishSpawningActor=function(_,area)assert(not area.collision);return area end,
    })
    h.stage=LionStage.new({
        log=function(line)h.logs[#h.logs+1]=line end,
        player=function()return h.player end,
        world=function()return h.world end,
        statics=function()return statics end,
        location=function(actor)return actor.at end,
        isDestroying=function(actor)return actor.gone==true end,
        hp=function(actor)return actor.hp end,
        now=function()return h.time end,
        find=function(path)
            if path==areaPath then return h.loaded and cls or nil end
            if path:find('MeshPrimitiveFunctions',1,true)then return primitives end
            if path:find('CollisionFunctions',1,true)then return collisions end
        end,
        load=function(path)assert(path==areaPath);h.loaded=true;return cls end,
        findAll=function(class)assert(h.loaded and class=='BP_LionDance_Area_C');return h.areas end,
        fname=function(name)return name end,
    })
    return h
end

do
    local h=harness()
    assert(h.stage:prepare(h.boss,bossPath,h.world,true) and #h.areas==0)
    assert(h.stage:prepare(h.boss,bossPath,h.world))
    local area=h.areas[1]
    assert(#h.areas==1 and h.builds==1 and h.stage:count()==1 and area.collision)
    assert(area.InTriggerActors[1]==h.boss and area.InTriggerActors[2]==h.player)
    assert(h.stage:prepare(h.boss,bossPath,h.world) and #h.areas==1,'reuse the already registered area')
    local poleA=object({outer=h.world,Area=area})
    local poleB=object({outer=h.world,Area=area})
    local link=object({outer=h.world,LinkedPoleA=poleA,LinkedPoleB=poleB})
    area.ActivatedPoles={poleA,poleB}
    area.ActivatedLinks={link}
    h.stage:releaseActor(h.boss)
    assert(area.deactivated and not area.collision and #area.InTriggerActors==0)
    assert(not h.stage:prepare(h.boss,bossPath,h.world),'wait for pending scene cleanup')
    h.time=4
    h.stage:tick()
    assert(not poleA.gone and not area.gone)
    h.time=5
    h.stage:tick()
    assert(area.gone and poleA.gone and poleB.gone and link.gone and h.stage:count()==0)
end

do
    local h=harness()
    local native=h:makeArea(nil,true)
    assert(h.stage:prepare(h.boss,bossPath,h.world) and h.builds==0 and h.stage:count()==0)
    h.stage:releaseActor(h.boss)
    assert(native.collision and not native.gone and not native.deactivated,'leave native level areas alone')
end

do
    local h=harness()
    h.preventOverlap=true
    local ready=h.stage:prepare(h.boss,bossPath,h.world)
    local area=h.areas[1]
    assert(not ready and area and not area.collision and #area.InTriggerActors==0)
    h.stage:tick()
    assert(area.gone and h.stage:count()==0,'discard the owned area on overlap readback failure')
end

print('lion_stage: PASS (native reuse, owned trigger readback, F4 exit and fade cleanup, fail closed)')
