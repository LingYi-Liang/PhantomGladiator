-- The in-game photography panel uses the camera input layer and owns its visual resources.
local U=require('ue_observe')
local N=require('photo_native')
local Face=require('photo_face')
local Visuals=require('photo_visuals')
local Overlay=require('photo_overlay')
local Settings=require('photo_settings')
local Studio={}
local TABS={'镜头','对焦','灯位','灯色','调色','质感','构图','预设','演员','人物'}
local BORDERS={'无','宽银幕','白边','黑边'}
local MARKS={'无','斗蛐蛐摄影','留影','影之刃零'}
local EYES={'随镜头','正前','左','右','上','下'}
local APERTURES={0,1.4,2,2.8,4,5.6,8,11,16}
local function lvalue(n)return n<0 and '原画面' or string.format('%.2f',n)end
local function channel(mask)
    local active={}
    for i=0,2 do if (mask&(1<<i))~=0 then active[#active+1]=i end end
    return table.concat(active,' + ')
end
local function word(value)return value and '开' or '关'end
local function wrap(i,n)return (i-1)%n+1 end
local function add(rows,id,label,value)
    rows[#rows+1]={id=id,label=label,value=tostring(value)}
end
local function lookRow(rows,r,role,label)
    local bound=r.lookBound and r.lookBound[role]
    local value='关'
    if r.look[role] then value=bound==true and '开' or bound==false and '未适配' or '等待' end
    add(rows,'look'..role,label..'看镜头',value)
end
local function rowsFor(r)
    local rows={}
    local s=r.settings
    local tab=r.menu.tab
    if tab==1 then
        add(rows,'mode','拍摄模式',r.mode=='duo' and '双人自拍' or '普通拍照')
        add(rows,'fov','视场角',s.fov..'°')
        add(rows,'roll','镜头倾斜',s.roll..'°')
        add(rows,'aperture','景深光圈',s.aperture==0 and '原景深' or 'f/'..s.aperture)
        add(rows,'focus','对焦距离',string.format('%.1f 米',s.focus/100))
        add(rows,'bars','隐藏血条',word(s.bars))
        add(rows,'shot','拍照','确认')
        add(rows,'leave','退出摄影','确认')
    elseif tab==2 then
        add(rows,'autofocus','自动对焦',word(s.autofocus))
        add(rows,'focus','对焦距离',string.format('%.1f 米',s.focus/100))
        add(rows,'focusMark','中心对焦标记',word(s.focusMark))
    elseif tab==3 or tab==4 then
        local l=s.lights[s.lightSlot]
        add(rows,'lightSlot','灯位',s.lightSlot..' / 3')
        if tab==3 then
            add(rows,'l_power','亮度',l.power==0 and '关' or l.power..'%')
            add(rows,'l_angle','方向',l.angle..'°')
            add(rows,'l_height','高度',l.height..' cm')
            add(rows,'l_distance','距主体',l.distance..' cm')
            add(rows,'l_radius','照明范围',l.radius..' cm')
            add(rows,'l_shadows','投射阴影',word(l.shadows))
            add(rows,'environment','场景间接光',lvalue(s.environment))
        else
            add(rows,'l_color','颜色',Visuals.LIGHTS[l.color].name)
            add(rows,'l_hue','自定义色相',l.hue..'°')
            add(rows,'l_sat','自定义饱和度',l.sat..'%')
            add(rows,'l_brightness','自定义明度',l.brightness..'%')
            add(rows,'l_scatter','体积散射',string.format('%.2f',l.scatter))
            add(rows,'l_channels','灯光通道',channel(l.channels))
        end
    elseif tab==5 then
        add(rows,'filter','滤镜',Visuals.PALETTES[s.filter].name)
        add(rows,'strength','滤镜强度',s.strength..'%')
        add(rows,'exposure','曝光',string.format('%+.2f EV',s.exposure))
        add(rows,'saturation','饱和度',s.saturation..'%')
        add(rows,'contrast','对比度',s.contrast..'%')
        add(rows,'gamma','中间调',s.gamma..'%')
        add(rows,'temperature','色温',s.temperature..' K')
        add(rows,'tint','色偏',string.format('%+.1f',s.tint))
    elseif tab==6 then
        add(rows,'bloom','泛光',lvalue(s.bloom))
        add(rows,'fringe','色差',lvalue(s.fringe))
        add(rows,'grain','胶片颗粒',lvalue(s.grain))
        add(rows,'vignette','暗角',lvalue(s.vignette))
        add(rows,'blur','动态模糊',lvalue(s.blur))
        add(rows,'blurMax','运动模糊范围',lvalue(s.blurMax))
        add(rows,'zoomBlur','缩放模糊',s.zoomBlur..'%')
    elseif tab==7 then
        add(rows,'grid','三分参考线',word(s.grid))
        add(rows,'border','相框',BORDERS[s.border])
        add(rows,'mark','署名',MARKS[s.mark])
        add(rows,'captureHDR','HDR 截图',word(s.captureHDR))
    elseif tab==8 then
        add(rows,'presetSlot','预设槽',r.menu.preset..' / 5')
        add(rows,'save','保存当前参数','确认')
        add(rows,'load','读取参数预设','确认')
        add(rows,'reset','恢复默认摄影参数','确认')
    elseif tab==9 then
        add(rows,'show1','主角入镜',word(s.show1))
        add(rows,'eyes1','主角眼神方向',EYES[s.eyes1])
        if r.mode=='duo' and r.other then
            add(rows,'show2','随从入镜',word(s.show2))
            add(rows,'eyes2','随从眼神方向',EYES[s.eyes2])
        end
    elseif r.mode=='duo' and r.other then
        local function person(role,label)
            local pose=r.poses[role]
            local sampled=r.poseRead and r.poseRead[role]
            local state=pose==0 and '原站姿' or (sampled and ('姿势 '..pose) or '原站姿')
            add(rows,'pose'..role,label..'姿势',state)
            local face=r.faces and r.faces[role]
            local option=face and face.options[r.expressions[role]]
            add(rows,'face'..role,label..'表情',option and option.name or '原表情')
            lookRow(rows,r,role,label)
        end
        person(1,'主角')
        add(rows,'next','切换同框随从',r.canCycle and '确认' or '仅一位随从')
        person(2,'随从')
    elseif tab==#TABS then
        lookRow(rows,r,1,'主角')
    end
    return rows
end
Studio.rowsFor=rowsFor

function Studio.new(o)
    local self={}
    local log=o.log or function()end
    local fx=o.visuals or Visuals.new(o)
    local overlay=o.overlay or Overlay.new(o)
    local presets=Settings.presets(o.path,o.files)
    local find=o.find or StaticFindObject
    local function notice(r,text,now)
        r.menu.notice=text
        r.menu.noticeUntil=now+2.2
    end
    function self:notice(r,text,now)notice(r,text,now)end
    function self:pending()return fx:pending() end
    function self:close()
        overlay:detach()
        local ok=fx:release()
        if not ok then log('[Photo] 摄影会话恢复待确认') end
        return ok
    end
    function self:open(r,fov)
        local pc=o.getController()
        r.settings=Settings.defaults(fov)
        r.menu={tab=1,selected=1,visible=true,keys={},notice='',noticeUntil=0,preset=1}
        r.lookBound,r.expressions={},{1,1}
        return overlay:open(o.world(),pc,function(widget)return fx:own(widget,'menu')end)
    end
    function self:prepare(r,now)
        if r.mode=='duo' then
            r.faces={Face.expressions(r.player,find),Face.expressions(r.other.actor,find)}
            for role,spec in ipairs(r.faces)do
                local chosen=spec.options[r.expressions[role]]
                if not chosen then r.expressions[role]=1;chosen=spec.options[1] end
                if r.expressions[role]>1 and not fx:expression(role,spec.mesh,chosen.weights) then
                    r.expressions[role]=1
                    notice(r,'表情未读回',now)
                end
            end
        else
            r.faces=nil
        end
        if not self:subjects(r) then notice(r,'人物显隐未读回',now) end
        if not r.opticsApplied then
            r.opticsApplied=true
            local ok=fx:optics(r.camera,r.settings)
            log('[Photo] 独立相机参数读回='..tostring(ok))
            if not ok then notice(r,'部分镜头参数未读回',now) end
            if not fx:bars(r.settings.bars,now) then notice(r,'血条隐藏未确认',now) end
        end
    end
    function self:subjects(r)
        local s=r.settings
        r.hidden=r.hidden or {}
        local ok=fx:subject(1,r.player,s.show1)
        if ok then r.hidden[1]=not s.show1 end
        local show=r.mode~='duo' or s.show2
        local other=fx:subject(2,r.other and r.other.actor,show)
        if other then r.hidden[2]=not show end
        return ok and other
    end
    function self:releaseSubjects(r)
        local first=fx:release('actor1')
        local second=fx:release('actor2')
        if first and second then r.hidden={} end
        return first and second
    end
    function self:releaseFaces()
        local player=fx:release('face1')
        return fx:release('face2') and player
    end
    function self:face(r,role,step)
        local f=r.faces and r.faces[role]
        if not f or #f.options<=1 or not U.valid(f.mesh) then return false,'该模型没有已适配的表情' end
        if U.key(N.call(f.mesh,'GetSkeletalMeshAsset'))~=f.asset then return false,'角色外观已变化，请重新打开摄影' end
        local index=wrap(r.expressions[role]+step,#f.options)
        local choice=f.options[index]
        if not fx:expression(role,f.mesh,choice.weights) then
            r.expressions[role]=1
            return false,'表情未读回'
        end
        r.expressions[role]=index
        return true
    end
    local function apply(r,id,now,roll)
        local s=r.settings
        if id=='bars' then return fx:bars(s.bars,now,true) end
        if id=='roll' then return roll(s.roll) end
        if id=='show1' or id=='show2' then return self:subjects(r) end
        if id:sub(1,2)=='l_' then return fx:light(r) end
        if id=='grid' or id=='border' or id=='mark' or id=='captureHDR' or id=='lightSlot' or id=='focusMark'
            or id=='eyes1' or id=='eyes2' or id=='autofocus' then return true end
        return fx:optics(r.camera,s)
    end
    local function applyAll(r,now,roll)
        local s=r.settings
        local a=fx:optics(r.camera,s)
        local b=fx:light(r)
        local c=fx:bars(s.bars,now,true)
        local d=self:subjects(r)
        return roll(s.roll) and a and b and c and d
    end
    function self:adjust(r,id,step,now,roll)
        local s=r.settings
        if id=='presetSlot' then r.menu.preset=wrap(r.menu.preset+step,5);return true end
        if id=='save' then
            local ok=presets.save(r.menu.preset,s)
            if ok then notice(r,'已保存摄影预设 '..r.menu.preset,now) end
            return ok,'预设写入未读回'
        end
        if id=='load' or id=='reset' then
            local loaded=id=='reset' and Settings.defaults(60) or presets.load(r.menu.preset)
            if not loaded then return false,'该槽没有摄影预设' end
            r.settings=loaded
            if applyAll(r,now,roll) then
                notice(r,id=='reset' and '已恢复默认参数' or '已读取摄影预设 '..r.menu.preset,now)
                return true
            end
            r.settings=s
            applyAll(r,now,roll)
            return false,'部分参数未读回，已尝试恢复'
        end
        local owner,key,old
        if id=='aperture' then
            local n=1
            for i,v in ipairs(APERTURES)do if v==s.aperture then n=i;break end end
            owner,key,old=s,id,s.aperture
            s.aperture=APERTURES[wrap(n+step,#APERTURES)]
        else
            owner,key,old=Settings.step(s,id,step)
        end
        if not owner then return false,'未知摄影设置' end
        if owner[key]==old then return true end
        if apply(r,id,now,roll) then
            log('[Photo] '..id..'='..tostring(owner[key])..' 读回=true')
            return true
        end
        owner[key]=old
        apply(r,id,now,roll)
        return false,'设置未读回，已尝试恢复'
    end
    function self:moved(r,now)
        local s=r.settings
        if s.autofocus and s.aperture>0 and o.focusFromCamera and now>=(r.focusAt or 0) then
            r.focusAt=now+.15
            local d=o.focusFromCamera(r.position,r.rotation,r.camera)
            if N.number(d) then
                d=N.limit(d,50,15000)
                if math.abs(d-s.focus)>1 and fx:focus(r.camera,s.aperture,d) then s.focus=d end
            end
        end
        if now>=(r.lightAt or 0) then
            r.lightAt=now+1/30
            for _,l in ipairs(s.lights)do if l.power>0 then return fx:light(r) end end
        end
        return true
    end
    function self:capture(r,now)
        if not overlay:hide(true) then return false end
        if overlay.composition and not overlay:composition(r.settings,true,now) then return false end
        if r.settings.bars and not fx:bars(true,now,true) then return false end
        return true
    end

    local KEYS={'menu','exit','capture','prevTab','nextTab','up','down','less','more','confirm'}
    local REPEAT={up=true,down=true,less=true,more=true}
    function self:input(r,input,now)
        local nav=input and input.nav
        if not nav then return end
        local m=r.menu
        local hit={}
        for _,k in ipairs(KEYS)do
            local before=m.keys[k]
            if nav[k] then
                if not before or REPEAT[k] and now>=before then
                    hit[k]=true
                    m.keys[k]=now+(before and .12 or .34)
                end
            else m.keys[k]=nil end
        end
        if not m.armed then
            -- Keys held while entering photography must be released before a new command.
            m.armed=true
            return
        end
        if hit.menu then m.visible=not m.visible end
        if hit.exit then return 'leave',1 end
        if hit.capture then return 'shot',1 end
        if not m.visible then return end
        local tabs=#TABS
        if hit.prevTab or hit.nextTab then
            m.tab=wrap(m.tab+(hit.nextTab and 1 or -1),tabs)
            m.selected=1
            return
        end
        if not (hit.up or hit.down or hit.less or hit.more or hit.confirm) then return end
        m.tab=math.min(m.tab,tabs)
        local rows=rowsFor(r)
        if not rows[1] then return end
        if hit.up or hit.down then
            m.selected=wrap(m.selected+(hit.down and 1 or -1),#rows)
        end
        local row=rows[math.min(m.selected,#rows)]
        if hit.less or hit.more or hit.confirm then return row.id,hit.less and -1 or 1 end
    end
    function self:render(r,now)
        local m=r.menu
        if overlay.composition and not overlay:composition(r.settings,r.shotQueued~=nil,now) and not m.composeFailed then
            m.composeFailed=true;notice(r,'构图层未读回',now)
        end
        local shown=m.visible and not r.shotQueued
        if not shown then m.drawAt=nil;return overlay:hide() end
        if now<(m.drawAt or 0) then return true end
        m.drawAt=now+1/30
        local rows=rowsFor(r)
        local t=TABS[wrap(m.tab-1,#TABS)]..'  ‹  〔'..TABS[m.tab]..'〕  ›  '..TABS[wrap(m.tab+1,#TABS)]
        local hint='鼠标、WASD / Q E 或摇杆移动镜头\n方向键选择和调整   PgUp/PgDn 或 LB/RB 换页\nTab / 菜单键显隐   空格 / X 拍照   Esc / B 退出'
        if m.noticeUntil>now then hint=m.notice..'\n'..hint end
        local selected=math.min(m.selected,#rows)
        local title=m.titleOverride or (r.mode=='duo' and '双人自拍' or '普通拍照')
        local signature={title,t,hint,selected}
        for _,row in ipairs(rows)do signature[#signature+1]=row.value;signature[#signature+1]=row.id end
        return overlay:render({visible=true,title=title,tabs=t,rows=rows,
            selected=selected,hint=hint,signature=table.concat(signature,'|')},now)
    end
    return self
end
return Studio
