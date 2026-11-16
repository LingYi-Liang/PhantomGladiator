-- Handshake only. Local decoding and playback stay outside the game process.
local Local={}
function Local.new(o)
    local self={lease=nil,token='',unit='',client='',ready=false,serial=0}
    local nextRead,cached=0,nil
    local function clear()self.token,self.unit,self.client,self.ready='','','',false end
    local function link()
        if o.clock()<nextRead then return cached end
        nextRead=o.clock()+0.5;cached=nil
        local text=o.read()
        if type(text)~='string'or #text>24576 then return nil end
        local stamp,session,client,prepared,ids=text:match('^LocalMusicLinkV1\t(%d+)\t([%w_:%-]+)\t([a-f0-9]+)\t([%w_:%-]+)\t([%w_,]*)\n$')
        stamp=tonumber(stamp)
        if not stamp or #client~=32 or session~=o.session()or o.wall()-stamp>2 or stamp-o.wall()>1 then return nil end
        local units,n={},0
        for id in ids:gmatch('[^,]+')do n=n+1;if n>128 or #id>180 then return nil end;units[id]=true end
        cached={client=client,prepared=prepared,units=units,expires=stamp+2};return cached
    end
    function self:owns()return self.lease~=nil end
    function self:yield(key,name)if self.lease and self.lease.key==key and self.lease.name==name then self.lease.yielded=true;return true end;return false end
    function self:stop()
        clear();local r=self.lease;if not r then return true end
        if r.mutating then o.state('waiting','音乐调用正在收尾，保留恢复责任');return false end
        local ctx=o.context()
        if not ctx then o.state('waiting','等待音乐系统就绪以交还原版');return false end
        if ctx.world~=r.world or ctx.key~=r.key or ctx.name~=r.name then self.lease=nil;return true end
        local now=o.snapshot(ctx)
        if not now then o.state('waiting','音乐读回未知，保留恢复责任');return false end
        if now.id~=0 or now.story>0 or now.blocked then self.lease=nil;return true end
        if o.clock()<(r.retryAt or 0)then return false end
        r.retryAt=o.clock()+1
        if not o.restore(ctx,now,true)then return false end
        self.lease=nil;o.state('native','本地音乐结束，已交还原版');return true
    end
    function self:tick(enabled)
        if not enabled then if self.lease then self:stop();return true end;clear();return false end
        self.ready=false
        local active=o.active();local info=link()
        if not active then self.failed=false;self:stop();o.state('waiting','等待开战');return true end
        if self.failed then self:stop();o.state('failed','本场本地音乐已停用，可重新保存音乐设置再试');return true end
        if not info or o.wall()>info.expires then self:stop();o.state('waiting','等待助手音频准备');return true end
        local ctx=o.context();local now=ctx and o.snapshot(ctx)
        if not now then clear();o.state('waiting','音乐系统读回未确认，跳过本地替换');return true end
        local owner,id
        for _,member in ipairs(o.members()or{})do
            local unit=o.unitId(member)
            if info.units[unit]and o.eligible(member)then
                local actor=o.actorState(member,ctx)
                if actor and actor.known==false then
                    self:stop();o.state('waiting','参战来源血量未确认，暂停本地音乐');return true
                end
                if actor and actor.alive then
                    if not owner then owner,id=actor,unit end
                    if self.lease and actor.key==self.lease.ownerKey and actor.name==self.lease.ownerName then owner,id=actor,unit;break end
                end
            end
        end
        local r=self.lease
        if r and (not owner or r.ownerKey~=owner.key or r.ownerName~=owner.name or ctx.world~=r.world or ctx.key~=r.key or ctx.name~=r.name or info.client~=r.client)then
            if not self:stop()then return true end;r=nil
        end
        if not owner then clear();o.state('waiting','当前没有已配置本地音乐的存活 BOSS');return true end
        if now.story>0 or now.blocked or r and r.yielded then
            self:stop();o.state('native','原版或剧情音乐接管，本地曲目已退让');return true
        end
        if not r then
            if self.unit~=id or self.client~=info.client or self.ownerKey~=owner.key or self.ownerName~=owner.name or self.world~=ctx.world or self.token==''then
                self.serial=self.serial+1
                self.token=info.client..':'..tostring(math.floor(o.clock()*1000000))..':'..self.serial
            end
            self.unit,self.client,self.ownerKey,self.ownerName,self.world=id,info.client,owner.key,owner.name,ctx.world
            if info.prepared~=self.token then o.state('waiting','等待独立播放器准备，保留原版音乐');return true end
            if not o.hooks()then o.state('waiting','音乐观察未就绪，跳过本地替换');return true end
            -- Recheck liveness and context after preparation callbacks, before any native write.
            local live=o.actorState({actor=owner.actor},ctx);local fresh=o.context();local after=fresh and o.snapshot(fresh)
            if not o.active()or not live or not live.alive or not fresh or fresh.world~=ctx.world or fresh.key~=ctx.key or fresh.name~=ctx.name or not after or after.story>0 or after.blocked then clear();return true end
            r={world=ctx.world,key=ctx.key,name=ctx.name,ownerKey=owner.key,ownerName=owner.name,client=info.client,token=self.token,original=after.id,originalEvent=after.eventName,retryAt=0}
            self.lease=r
        end
        if info.prepared~=r.token then self:stop();return true end
        now=o.snapshot(ctx)
        if not now then o.state('waiting','音乐状态未知，暂停本地播放');return true end
        if now.id~=0 then
            if r.cleared or now.id~=r.original or now.eventName~=r.originalEvent then
                self.failed=true;self:stop();o.state('native','原版已切换曲目，本地播放退让');return true
            end
            if o.clock()<(r.clearAt or 0)then return true end
            r.clearAt=o.clock()+1;r.attempts=(r.attempts or 0)+1
            if r.attempts>3 then self.failed=true;self:stop();o.state('failed','原版音乐未确认停止，跳过本地播放');return true end
            r.mutating=true
            local sent=o.native(ctx,'ClearMusic',0.25,true,false)
            r.mutating=false;now=o.snapshot(ctx)
            o.log('本地替换准备：停止游戏战斗音乐调用='..tostring(sent)..'；播放ID读回='..tostring(now and now.id))
            local live=o.actorState({actor=owner.actor},ctx);local fresh=o.context()
            if not o.active()or self.lease~=r or not live or not live.alive or not fresh or fresh.world~=ctx.world or fresh.key~=ctx.key or fresh.name~=ctx.name then self:stop();return true end
        end
        if now and now.id==0 and now.story==0 and not now.blocked and not r.yielded then
            r.cleared=true;self.ready=true;self.unit=id;self.client=info.client;self.token=r.token
            o.state('playing','本地曲目播放许可已确认')
        end
        return true
    end
    function self:status()return {local_token=self.token,local_unit=self.unit,local_client=self.client,local_ready=self.ready,local_pending=self.lease~=nil and not self.ready}end
    return self
end
return Local
