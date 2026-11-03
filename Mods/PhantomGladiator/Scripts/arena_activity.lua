-- Keep only arena-owned NPCs on the game's full update path.
-- NPC_Optimizator.hpp: DisableAllOptimizations / GetOptimizationWave.
-- EOptimizationWave.NoOptimization == 1 (0 is Invisible).
local U=require('ue_observe')
local Activity={}
function Activity.new(options)
    local self={records={},camera=nil,count=0,boneCount=0,ticks=0,contextSamples=0}
    local log=options.log or function()end
    local function attribute(attributes,name)
        local data=U.field(attributes,name)
        local value=U.struct(data,'CurrentValue')
        return type(value)=='number' and value or 'UNKNOWN'
    end
    local function stateTag(component)
        local tag=U.field(component,'CurrentStateTag')
        local name=U.struct(tag,'TagName')
        if name==nil then return 'UNKNOWN' end
        if type(name)=='string' then return name end
        local ok,text=pcall(function()return name:ToString()end)
        return ok and tostring(text) or 'UNKNOWN'
    end
    function self:prepare(actor)
        if not U.valid(actor) then return end
        local before,read=U.field(actor,'bDisableAllOptimizationsOnBeginPlay')
        if not read or type(before)~='boolean' then return end
        local called=pcall(function()actor.bDisableAllOptimizationsOnBeginPlay=true end)
        local actual=U.field(actor,'bDisableAllOptimizationsOnBeginPlay')
        log('[ArenaActivity] 参赛NPC登场配置：关闭距离/视野降频；before='..tostring(before)..' after='..tostring(actual)..' verified='..tostring(called and actual==true))
    end
    function self:sync(members)
        local camera=options.freeCam and options.freeCam()==true or false
        local changed=camera~=self.camera;self.camera=camera
        self.ticks=self.ticks+1
        local sample=changed or self.ticks%10==0
        if sample and #members>0 and self.contextSamples<120 and options.context then
            self.contextSamples=self.contextSamples+1
            local ok,value=pcall(options.context)
            log('[F6Readback] 上下文 freecam='..tostring(camera)..' '..(ok and tostring(value) or 'UNKNOWN'))
        end
        local kept,count,boneCount,sampled={},0,0,0
        local verify=changed or sample or self.ticks%10==0
        for _,unit in ipairs(members)do
            local settled=not verify and self.records[U.key(unit.actor) or '']
            if settled and settled.settled then
                kept[U.key(unit.actor)]=settled
                if settled.full then count=count+1 end
                if settled.bone then boneCount=boneCount+1 end
            elseif U.valid(unit.actor) and options.isNPC(unit.actor) then
                local key=U.key(unit.actor);local proxy=U.field(unit.actor,'OptimizationProxy')
                if key and U.valid(proxy) then
                    local ok,owner=pcall(function()return proxy:GetOwner()end)
                    if ok and U.key(owner)==key then
                        local record=self.records[key] or {attempts=0,boneAttempts=0,samples=0}
                        kept[key]=record
                        local beforeOK,before=pcall(function()return proxy:GetOptimizationWave()end)
                        local current=beforeOK and before or nil
                        if not record.applied and record.attempts<3 then
                            record.attempts=record.attempts+1
                            local called,err=pcall(function()proxy:DisableAllOptimizations()end)
                            local read,after=pcall(function()return proxy:GetOptimizationWave()end)
                            record.applied=called and read and after==1
                            current=read and after or nil
                            log('[ArenaActivity] 仅对已登记NPC停用优化；before='..tostring(beforeOK and before)..' after='..tostring(read and after)..' verified='..tostring(record.applied)..(called and '' or (' error='..tostring(err))))
                        end
                        if record.applied and current==1 then count=count+1 end
                        local mesh=U.field(unit.actor,'Mesh')
                        if U.valid(mesh) then
                            local ownerOK,meshOwner=pcall(function()return mesh:GetOwner()end)
                            if ownerOK and U.key(meshOwner)==key then
                                local mode=U.field(mesh,'VisibilityBasedAnimTickOption')
                                -- One-variable F6 experiment: force bone refresh, leaving
                                -- tick intervals, URO and the camera implementation unchanged.
                                if type(mode)=='number' and mode>=1 and mode<=4 and record.boneAttempts<3 then
                                    record.boneAttempts=record.boneAttempts+1
                                    local called=pcall(function()mesh.VisibilityBasedAnimTickOption=0 end)
                                    local after=U.field(mesh,'VisibilityBasedAnimTickOption')
                                    log('[ArenaActivity] 骨骼刷新对照 actor='..tostring(unit.class_path)..'；visibility '..tostring(mode)..' -> '..tostring(after)..' verified='..tostring(called and after==0)..' attempt='..record.boneAttempts)
                                    mode=after
                                end
                                if mode==0 then boneCount=boneCount+1 end
                                record.bone=mode==0
                            end
                        end
                        record.full=record.applied and current==1
                        record.settled=record.full and record.bone==true
                        if changed then
                            local waveOK,wave=pcall(function()return proxy:GetOptimizationWave()end)
                            local tick='UNKNOWN';local visibility
                            if U.valid(mesh) then
                                local read,value=pcall(function()return mesh:GetComponentTickInterval()end)
                                if read then tick=value end
                                visibility=U.field(mesh,'VisibilityBasedAnimTickOption')
                            end
                            log('[ArenaActivity] 观察模式读回 freecam='..tostring(camera)..' actor='..tostring(unit.class_path)..' wave='..tostring(waveOK and wave)..' mesh_tick='..tostring(tick)..' anim_visibility='..tostring(visibility))
                        end
                        if sample and record.samples<120 and sampled<4 then
                            record.samples=record.samples+1;sampled=sampled+1
                            local attributes=U.field(unit.actor,'AttributeSetBase')
                            local controller=U.field(unit.actor,'Controller')
                            local ai=U.field(controller,'SGameAIComponent')
                            log('[F6Readback] 只读 actor='..tostring(unit.class_path)..' freecam='..tostring(camera)
                                ..' HP='..attribute(attributes,'Health')..' Shachi='..attribute(attributes,'Shachi')
                                ..' Attack='..attribute(attributes,'Attack')..' ShachiAttack='..attribute(attributes,'ShachiAttack')
                                ..' can_damage='..tostring(U.field(unit.actor,'bCanBeDamaged'))
                                ..' actor_time='..tostring(U.field(unit.actor,'CustomTimeDilation'))
                                ..' ai_state='..stateTag(ai)..' wave='..tostring(current)
                                ..' anim_visibility='..tostring(U.field(mesh,'VisibilityBasedAnimTickOption')))
                        end
                    end
                end
            end
        end
        self.records,self.count,self.boneCount=kept,count,boneCount
    end
    function self:status()return {full_update_count=self.count,bone_refresh_count=self.boneCount,free_camera=self.camera==true}end
    return self
end
return Activity
