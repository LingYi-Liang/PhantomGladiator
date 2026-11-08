-- 卡顿测量: a summary line every minute for a pass that repeats (a free-camera frame, a panel pump, the support loop),
-- kept up for the whole session. The single slow-pass lines stop after 60 a session and had stopped long before a
-- stutter reported later in it.
-- A pass gives what it cost and, if it likes, what its named parts cost; the gap from one pass to the next shows the
-- frames the game itself took long over. The parts that cost most in the minute are listed, at most PARTS of them.
local Meter={}
local PARTS=6
function Meter.new(options)
    local label,log=options.label,options.log or function()end
    local every,slow,hitch=options.every or 60,options.slow or 8,options.hitch or 50
    local self={}
    local w
    local function fresh(now)return {start=now,n=0,total=0,max=0,slow=0,gaps=0,gapMax=0,gapSum=0,gapN=0,parts={}} end
    -- The pass stops (the camera is put away): the next one does not count the time between as a gap.
    function self:pause()if w then w.last=nil end end
    -- spent: ms the pass took; now: seconds when it started; parts: {name=ms}.
    function self:add(spent,now,parts)
        if type(spent)~='number' or type(now)~='number' then return end
        w=w or fresh(now)
        if w.last then
            local gap=(now-w.last)*1000
            if gap>=hitch then w.gaps=w.gaps+1 end
            if gap>w.gapMax then w.gapMax=gap end
            w.gapSum,w.gapN=w.gapSum+gap,w.gapN+1
        end
        w.last=now
        w.n=w.n+1;w.total=w.total+spent
        if spent>w.max then w.max=spent end
        if spent>=slow then w.slow=w.slow+1 end
        for name,ms in pairs(parts or {})do
            if type(ms)=='number' then
                local p=w.parts[name] or {total=0,max=0};w.parts[name]=p
                p.total=p.total+ms;if ms>p.max then p.max=ms end
            end
        end
        if now-w.start<every then return end
        local names={}
        for name in pairs(w.parts)do names[#names+1]=name end
        table.sort(names,function(a,b)
            if w.parts[a].total~=w.parts[b].total then return w.parts[a].total>w.parts[b].total end
            return a<b
        end)
        local shown={}
        for i=1,math.min(PARTS,#names)do
            local p=w.parts[names[i]]
            shown[#shown+1]=string.format('%s 平均%.2f/最长%.1f',names[i],p.total/w.n,p.max)
        end
        log(string.format('[Perf] %s 近%.0f秒：%d次 平均%.2fms 最长%.1fms ≥%dms有%d次；平均间隔%.1fms 间隔≥%dms有%d次 最长间隔%.0fms%s',
            label,now-w.start,w.n,w.total/w.n,w.max,slow,w.slow,w.gapN>0 and w.gapSum/w.gapN or 0,hitch,w.gaps,w.gapMax,
            #shown>0 and ('；'..table.concat(shown,' ')) or ''))
        local last=w.last
        w=fresh(now);w.last=last
    end
    return self
end
return Meter
