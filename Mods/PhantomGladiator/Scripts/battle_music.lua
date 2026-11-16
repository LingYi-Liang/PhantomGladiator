-- Optional music for mod-owned arena fights. The native music subsystem owns playback.
local U=require('ue_observe')
local Catalog=require('battle_music_catalog')
local Music={}
Music.paths={
    '/Script/ProjectPBZ.MusicSubsystem:PlayMusicAndSetState',
    '/Script/ProjectPBZ.MusicSubsystem:SetMusicState',
    '/Script/ProjectPBZ.MusicSubsystem:ClearMusic',
}
local function call(object,method,...)
    if not U.valid(object) then return false end
    local args={...}
    local ok,value=pcall(function()return object[method](object,table.unpack(args))end)
    return ok,U.unwrap(value)
end
local function nameOf(object)
    local ok,name=call(object,'GetFullName')
    return ok and type(name)=='string' and name or nil
end
local function finite(value)return type(value)=='number' and value==value and value~=math.huge and value~=-math.huge end
local function playingId(value)
    if not finite(value) or value%1~=0 or value < -2147483648 or value > 4294967295 then return nil end
    if value==0 or value==-1 or value==4294967295 then return 0 end
    return value<0 and value+4294967296 or value
end
function Music.new(options)
    local fs,ops,clock=options.io or io,options.os or os,options.clock or os.clock
    local find,load=options.find or StaticFindObject,options.load or LoadAsset
    local register,unregister=options.register or RegisterHook,options.unregister or UnregisterHook
    local self={alive=true,mode='NATIVE',track='MOYUAN_P1',state='native',message='保留原版音乐',lease=nil,suspended=false}
    local file=options.path..'/battle-music.tsv'
    local hooks,assets={},{}
    local nativeDepth,retryAt,hookRetryAt,unhookRetryAt=0,0,0,0
    local attemptKey,attempts=nil,0
    local notices={}
    local function log(kind,text)
        if notices[kind]==text then return end
        notices[kind]=text;(options.log or function()end)('[BattleMusic] '..text)
    end
    local function state(value,text)self.state=value;self.message=text end
    local function read(path)
        local f=fs.open(path,'rb');if not f then return nil end
        local text=f:read(512);f:close();return text
    end
    local function valid(mode,track)return (mode=='NATIVE' or mode=='AUTO' or mode=='TRACK') and Catalog.tracks[track]~=nil end
    for _,path in ipairs({file,file..'.bak'})do
        local text=read(path)
        local mode,track
        if type(text)=='string' then mode,track=text:match('^BattleMusicV1\t([A-Z]+)\t([A-Z0-9_]+)\n$')end
        if valid(mode,track) then self.mode,self.track=mode,track;break end
    end
    local function persist(mode,track)
        local text='BattleMusicV1\t'..mode..'\t'..track..'\n'
        local tmp,backup=file..'.tmp',file..'.bak'
        local f=fs.open(tmp,'wb');if not f then return false end
        local wrote,flushed,closed=f:write(text),f:flush(),f:close()
        if wrote==nil or wrote==false or flushed==nil or flushed==false or closed~=true or read(tmp)~=text then return false end
        local old=read(file)
        if old then
            if read(backup) and not ops.remove(backup) then return false end
            if not ops.rename(file,backup) then return false end
        end
        local moved=ops.rename(tmp,file)
        if not moved or read(file)~=text then
            if moved then ops.remove(file)end
            if old then ops.rename(backup,file)end
            return false
        end
        return true
    end
    local function gameThread()
        if not options.inGameThread then return true end
        local ok,yes=pcall(options.inGameThread);return ok and yes==true
    end
    local function supported()return type(find)=='function' and type(load)=='function' and type(register)=='function' and type(unregister)=='function'end
    local function context()
        if not gameThread() or (options.ready and options.ready()~=true) then return nil end
        local world=options.world();local worldKey=U.key(world)
        if not worldKey then return nil end
        local subsystem=options.subsystem()
        local key,name=U.key(subsystem),nameOf(subsystem)
        if not key or not name or not U.inWorld(subsystem,world) then return nil end
        return {object=subsystem,key=key,name=name,world=worldKey,worldObject=world}
    end
    local function snapshot(ctx)
        if not ctx or not U.valid(ctx.object) then return nil end
        local id,readId=U.field(ctx.object,'CurPlayingID_Gameplay')
        local event,readEvent=U.field(ctx.object,'CurPlayingEvent_Gameplay')
        local story,readStory=U.field(ctx.object,'CurPlayingID_Story')
        local blocked,readBlocked=U.field(ctx.object,'bDontInitMusic')
        local disabled,readDisabled=U.field(ctx.object,'bDisableBossMusicOnUI')
        local normalized,storyNormalized=playingId(id),playingId(story)
        if not readId or normalized==nil or not readEvent or not readStory or storyNormalized==nil
            or not readBlocked or type(blocked)~='boolean' then return nil end
        return {id=normalized,rawId=id,event=event,eventName=nameOf(event),story=storyNormalized,rawStory=story,blocked=blocked,uiBossDisabled=readDisabled and disabled==true}
    end
    local function native(ctx,method,...)
        if not ctx or not U.valid(ctx.object) then return false end
        nativeDepth=nativeDepth+1
        local ok,result=call(ctx.object,method,...)
        nativeDepth=nativeDepth-1
        return ok,result
    end
    local function unhook(force)
        if not force and clock()<unhookRetryAt then return end
        unhookRetryAt=clock()+3
        for path,ids in pairs(hooks)do
            local ok,result=pcall(unregister,path,ids[1],ids[2])
            if ok and result~=false then hooks[path]=nil else log('unhook:'..path,'注销音乐观察未确认 '..path)end
        end
    end
    local function ensureHooks()
        if clock()<hookRetryAt then return false end
        local complete=true
        for _,path in ipairs(Music.paths)do
            if not hooks[path] then
                local found,fn=pcall(find,path)
                if not found or not U.valid(fn) then complete=false
                else
                    local ok,pre,post=pcall(register,path,function(ctx)
                        if not self.alive or nativeDepth>0 or not self.lease then return end
                        if not gameThread() then self.suspended=true;return end
                        local object=U.unwrap(ctx)
                        if U.key(object)==self.lease.subKey and nameOf(object)==self.lease.subName then self.suspended=true end
                    end)
                    if ok and type(pre)=='number' and type(post)=='number' then hooks[path]={pre,post}
                    else complete=false end
                end
            end
        end
        if not complete then hookRetryAt=clock()+3 end
        return complete
    end
    local function asset(path,class)
        local function correct(object)return U.valid(object) and U.className(object)==class and nameOf(object)==class..' '..path end
        if correct(assets[path]) then return assets[path] end
        assets[path]=nil
        local ok,object=pcall(find,path)
        if not ok or not correct(object) then ok,object=pcall(load,path)end
        if ok and correct(object) then assets[path]=object;return object end
    end
    local function unitId(member)
        local path=member.class_path or ''
        return (path:match('([^/%.]+)$') or ''):gsub('_C$','')
    end
    local function eligible(member)
        return (member.team=='blue' or member.team=='red') and not member.reserve and not member.stand and not member.aid and not member.summoner
    end
    local function actorState(member,ctx)
        if not U.inWorld(member.actor,ctx.worldObject)then return nil end
        local key,name=U.key(member.actor),nameOf(member.actor)
        if not key or not name then return nil end
        local ok,hp=pcall(options.hp,member.actor)
        return {key=key,name=name,actor=member.actor,alive=ok and finite(hp) and hp>0,known=ok and finite(hp)}
    end
    local function restoreNative(ctx,after,restore)
        if not restore or after.id~=0 or after.story>0 or after.blocked then self.restorePending=nil;return true end
        self.restorePending={world=ctx.world,key=ctx.key,name=ctx.name}
        local restored=native(ctx,'UpdateGameplayMusic',false)
        local back=snapshot(ctx)
        log('restore','原版音乐重算调用='..tostring(restored)..'；读回ID='..tostring(back and back.id))
        if not restored or not back then state('failed','曲目已停止，原版音乐重算未确认');return false end
        self.restorePending=nil
        return true
    end
    local function release(ctx,restore)
        local held=self.lease
        if not held then return not self.restorePending end
        if not ctx then state('waiting','等待游戏就绪以确认音乐停止');return false end
        if ctx.world~=held.world or ctx.key~=held.subKey or ctx.name~=held.subName then
            self.lease=nil;state('native','旧世界音乐记录已释放');return true
        end
        local before=snapshot(ctx)
        if not before then state('waiting','音乐播放读回未知，保留恢复记录');return false end
        if before.id~=held.id or before.eventName~=held.eventName then
            self.lease=nil
            if before.id==0 and held.stopAt then
                if not restoreNative(ctx,before,restore)then return false end
                state('native','音乐淡出已读回，原版接管音乐');return true
            end
            state('native','音乐已由原版切换，不清理新的曲目');return true
        end
        if clock()<(held.stopAt or 0) then return false end
        local ok=native(ctx,'ClearMusic',0.25,true,false)
        held.stopAttempts=(held.stopAttempts or 0)+1
        held.stopAt=clock()+(held.stopAttempts<=3 and 0.6 or 3)
        local after=snapshot(ctx)
        log('stop','停止模组战斗曲：调用='..tostring(ok)..'；原ID='..held.id..'；原生读回ID='..tostring(after and after.rawId)..'；归一ID='..tostring(after and after.id))
        if not after or after.id==held.id then state('waiting','已请求淡出，等待音乐停止读回');return false end
        self.lease=nil
        if not restoreNative(ctx,after,restore)then return false end
        state('native','模组曲目停止已读回，原版接管音乐');return true
    end
    function self:tick()
        if not self.alive or not gameThread() then return end
        if self.mode=='NATIVE' and not self.lease and not self.restorePending then if next(hooks)then unhook()end;state('native','保留原版音乐');return end
        local status=options.status() or {};local active=status.battle_active==true
        if not active and not self.lease and not self.restorePending then
            self.suspended=false;attemptKey=nil;attempts=0
            if next(hooks)then unhook()end
            state('waiting','等待蓝红对战，音乐设置已保留');return
        end
        local ctx=context();local current=ctx and snapshot(ctx)
        if self.restorePending then
            local pending=self.restorePending
            if not ctx or not current then state('waiting','等待原版音乐恢复读回');return end
            if pending.world~=ctx.world or pending.key~=ctx.key or pending.name~=ctx.name or current.id>0 or current.story>0 or current.blocked then self.restorePending=nil
            elseif not restoreNative(ctx,current,true) then return end
        end
        if not active or self.mode=='NATIVE' then
            if release(ctx,true) then self.suspended=false end
            return
        end
        if not current then state('waiting','等待当前世界音乐系统读回');return end
        if self.suspended or current.story>0 or current.blocked then
            log('yield','交还原版：外部请求='..tostring(self.suspended)..'；剧情ID='..current.story..'；原版禁用标记='..tostring(current.blocked))
            if not release(ctx,current.story==0 and not current.blocked)then return end
            self.suspended=true;state('native','原版或剧情音乐已接管，本场不再抢占');return
        end
        if self.lease and (ctx.world~=self.lease.world or ctx.key~=self.lease.subKey or ctx.name~=self.lease.subName) then
            self.lease=nil
        end
        if self.lease and (current.id~=self.lease.id or current.eventName~=self.lease.eventName) then
            self.lease=nil;self.suspended=true;state('native','原版已更换音乐，本场不再抢占');return
        end
        local members=options.members() or {};local selected,owner
        for _,member in ipairs(members)do
            if eligible(member) then
                local id=self.mode=='TRACK' and self.track or Catalog.units[unitId(member)]
                if id then
                    local actor=actorState(member,ctx)
                    if actor and self.lease and actor.key==self.lease.ownerKey and actor.name==self.lease.ownerName then
                        if not actor.known then state('waiting','配乐来源血量未确认，暂不切换');return end
                        if actor.alive and id==self.lease.track then state('playing','正在播放 '..Catalog.tracks[id].label);return end
                    end
                    if not selected and actor and actor.alive then selected,owner=id,actor end
                end
            end
        end
        if self.lease and not release(ctx,selected==nil) then return end
        if not selected then state('waiting','暂无可用的存活参战来源，可手动指定曲目');return end
        local key=ctx.world..'|'..owner.key..'|'..owner.name..'|'..selected
        if attemptKey~=key then attemptKey=key;attempts=0 end
        if attempts>=3 then state('failed','音乐连续读回失败，本场暂停重试；可重新保存设置再试');return end
        if clock()<retryAt then return end
        if not supported() or not ensureHooks() then state('waiting','音乐接口或观察挂钩尚未就绪');return end
        attempts=attempts+1
        local track=Catalog.tracks[selected]
        local event,setting=asset(track.event,'AkAudioEvent'),asset(track.state,'AkStateValue')
        if not event or not setting then
            log('assets','音乐资源核对：曲目='..selected..'；事件有效='..tostring(event~=nil)..'；状态有效='..tostring(setting~=nil))
            retryAt=clock()+5;state('waiting','所选音乐资源尚未加载');return
        end
        local ok=native(ctx,'PlayMusicAndSetState',event,setting,1,true)
        local after=context();after=after and after.key==ctx.key and after.world==ctx.world and snapshot(after)
        log('play','请求曲目='..selected..'；调用='..tostring(ok)..'；读回ID='..tostring(after and after.id)..'；事件='..tostring(after and after.eventName))
        if ok and after and after.id>0 and after.eventName==nameOf(event) then
            self.lease={id=after.id,eventName=after.eventName,subKey=ctx.key,subName=ctx.name,world=ctx.world,ownerKey=owner.key,ownerName=owner.name,track=selected}
            state('playing','播放对象已读回 '..track.label)
        else
            retryAt=clock()+5
            if after and after.id==0 and current.id>0 then restoreNative(ctx,after,true)end
            state('failed','音乐请求未获得有效播放读回')
        end
    end
    function self:set(mode,track)
        if not valid(mode,track) then return {ok=false,message='无效的战斗音乐选项'} end
        local saved=persist(mode,track)
        log('setting','保存音乐设置='..mode..'/'..track..'；读回='..tostring(saved))
        if not saved then return {ok=false,message='战斗音乐设置保存未确认，旧设置继续生效'} end
        if self.lease and (mode~=self.mode or track~=self.track) then self.lease.track=''end
        self.mode,self.track,self.suspended=mode,track,false;retryAt=0;attemptKey=nil;attempts=0
        self:tick()
        return {ok=true,message='音乐设置已保存；'..self.message}
    end
    function self:stop()
        self.suspended=true
        if not self.lease and not self.restorePending then return {ok=true,message='没有模组音乐需要停止'}end
        if self.restorePending then self:tick()end
        local ok=release(context(),true)
        return {ok=ok,message=ok and '战斗音乐停止已读回' or self.message}
    end
    function self:status()
        return {supported=supported(),mode=self.mode,track=self.track,state=self.state,message=self.message,playing=self.lease and self.lease.id or 0,pending=self.restorePending~=nil or (self.lease~=nil and self.lease.stopAt~=nil)}
    end
    function self:silence()
        self.alive=false;unhook(true)
        if self.lease then log('unload','音乐恢复记录仍在；卸载不访问游戏对象，重载前需停止清理')end
    end
    return self
end
return Music
