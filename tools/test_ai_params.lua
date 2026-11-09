package.path='Mods/PhantomGladiator/Scripts/?.lua;'..package.path
local Params=require('ai_params')
local address=0
local function object(name,fields)
    address=address+1;local a=address
    local o=fields or {}
    o.alive=true
    o.IsValid=function(self)return self.alive end
    o.GetAddress=function()return a end
    local class={GetFName=function()return {ToString=function()return name end}end,IsValid=function()return true end}
    o.GetClass=function()return class end
    return o
end
FName=function(text)return {name=text,ToString=function()return text end} end
local function map(store,broken)
    return {
        Add=function(_,key,value)if broken then error('no map write') end;store[key.name]=value end,
        Contains=function(_,key)return store[key.name]~=nil end,
        Find=function(_,key)
            local value=store[key.name]
            if value==nil then error('missing map entry') end
            return value
        end,
        Remove=function(_,key)store[key.name]=nil end,
    }
end
local function harness(opts)
    opts=opts or {}
    local h={t=0,logs={},members={},files={},hooks={},now=0}
    local real={open=io.open}
    io.open=function(path,mode)
        if mode=='r' then
            if not h.files[path] then return nil end
            local text=h.files[path]
            return {read=function()return text end,close=function()end}
        end
        if h.readOnly then return nil end
        return {write=function(_,s)h.files[path]=s;return true end,close=function()return not h.closeError or nil end}
    end
    h.fileOps={
        remove=function(path)
            h.files[path]=nil
            return true
        end,
        rename=function(from,to)
            if h.failRename==from or not h.files[from] or h.files[to] then return nil end
            h.files[to],h.files[from]=h.files[from],nil
            return true
        end,
    }
    h.restore=function()io.open=real.open end
    RegisterHook=function(path,pre,post)h.hooks[path]=pre;return #h.logs+1,2 end
    UnregisterHook=function(path)h.hooks[path]=nil end
    function h.unit(name,started,defaults,boss)
        local store={}
        for k,v in pairs(defaults or {})do store[k]=v end
        local controller=object('Controller',{store=store})
        local comp=object('AIComp',{bAIStarted=started~=false,AIController=controller,
            MergedParameterCollection={FloatParameters=map(store,opts.broken),BoolParameters=map(store,opts.broken),IntParameters=map(store,opts.broken)}})
        local actor=object(name,{comp=comp})
        h.members[#h.members+1]={actor=actor,team='blue',boss=boss}
        return actor,comp,controller,store
    end
    local function ask(kind,library,controller,name)
        local hook=h.hooks['/Script/SGameAI.SGameAIFunctionLibrary:'..kind]
        if hook then
            local answer=hook(library,controller,name)
            if answer~=nil then return answer end
        end
        return controller.store[name.name]
    end
    h.library=object('Lib',{FindFloatParameter=function(l,c,n)return ask('FindFloatParameter',l,c,n)end,
        FindBoolParameter=function(l,c,n)return ask('FindBoolParameter',l,c,n)end,FindIntParameter=function(l,c,n)return ask('FindIntParameter',l,c,n)end})
    h.tensionLib=object('Tension',{HasActiveSession=function()return true end,GetTensionReadout=function()return {Raw=12,Confidence=0.5,PeakLast10s=20} end})
    h.world=object('World')
    h.params=Params.new({path='R',os=h.fileOps,log=function(m)h.logs[#h.logs+1]=m end,clock=function()return h.now end,members=function()return h.members end,
        aiComp=function(actor)return actor.comp end,lib=function()return h.library end,tension=function()return h.tensionLib,h.world end})
    function h.all()return table.concat(h.logs,'\n') end
    function h.step(seconds)h.now=h.now+(seconds or 1);h.params:tick() end
    function h.send(rev,body)
        h.files['R/ai-params-request.tsv']='AIParamsV1\t'..rev..'\n'..body
        return h.params:setRequest(rev)
    end
    return h
end
local function test(name,fn)fn();print('ok - '..name)end

test('no values: nothing is written; the first unit of a class logs what the game gave it',function()
    local h=harness()
    local _,_,_,store=h.unit('BP_Monster_A_C',true,{['近距离进攻概率']=0.4})
    h.unit('BP_Monster_A_C',true,{})
    h.step()
    assert(store['近距离进攻概率']==0.4 and h.params:status().applied==0)
    assert(h.all():find('读回 BP_Monster_A_C 游戏给的 近距离进攻概率=0.4',1,true),h.all())
    local _,n=h.all():gsub('游戏给的','')
    assert(n==1,'once per class')
    h.restore()
end)

test('values reach a unit once its AI has started, and are read back',function()
    local h=harness()
    local _,comp,_,store=h.unit('BP_Monster_A_C',false,{['近距离进攻概率']=0.4})
    assert(h.send('R1','近距离进攻概率\t1\n减帧时允许格挡\t0\n受击-正面脱离计数\t3\nBogus\t9\n').ok)
    h.step()
    assert(store['近距离进攻概率']==0.4,'AI not started yet')
    comp.bAIStarted=true
    h.step()
    assert(store['近距离进攻概率']==1 and store['减帧时允许格挡']==false and store['受击-正面脱离计数']==3 and store.Bogus==nil)
    assert(h.all():find('近距离进攻概率 原值=0.4 -> 目标=1 写表=true 读回=1 结果=生效',1,true),h.all())
    assert(h.params:status().count==3 and h.params:status().applied==3 and h.params:status().failures==0)
    h.restore()
end)

test('values that could not be saved say so, and still apply for now',function()
    local h=harness()
    h.readOnly=true
    local answer=h.send('R4','中距离进攻概率\t0.5\n')
    h.readOnly=false
    assert(answer.ok==false and answer.message:find('保存未确认',1,true) and h.params:status().count==1,tostring(answer.message))
    h.restore()
end)

test('a close or replacement failure reports unsaved and preserves the last settings',function()
    local h=harness()
    local name='近距离进攻概率'
    local path='R/ai-params-settings.tsv'
    local original='AIParamsV1\n'..name..'\t0.25\n'
    h.files[path]=original
    h.closeError=true
    assert(not h.send('R1',name..'\t1\n').ok,'buffered write success is not a saved file')
    assert(h.files[path]==original and h.params.values[name]==1)
    h.closeError=false
    h.failRename=path..'.pending'
    assert(not h.send('R2',name..'\t0.75\n').ok)
    assert(h.files[path]==original and h.params.values[name]==0.75)
    h.restore()
end)

test('a reload recovers the previous settings if replacement was interrupted',function()
    local h=harness()
    local path='R/ai-params-settings.tsv'
    local text='AIParamsV1\n近距离进攻概率\t0.25\n'
    h.files[path..'.previous']=text
    local reloaded=Params.new({path='R',os=h.fileOps,members=function()return {} end,aiComp=function()end})
    assert(reloaded.values['近距离进攻概率']==0.25 and h.files[path]==text)
    h.restore()
end)

test('a request with the wrong revision is refused; saved values come back after a reload',function()
    local h=harness()
    h.files['R/ai-params-request.tsv']='AIParamsV1\tR2\n近距离进攻概率\t1\n'
    assert(h.params:setRequest('R9').ok==false and h.params:status().count==0)
    assert(h.send('R3','中距离进攻概率\t0.5\n').ok)
    assert(h.files['R/ai-params-settings.tsv']:find('^AIParamsV1\n中距离进攻概率\t0.5\n'),h.files['R/ai-params-settings.tsv'])
    local again=Params.new({path='R',members=function()return {} end,aiComp=function()end})
    assert(again:status().count==1)
    h.restore()
end)

test('taking a value off puts back what the game gave that unit',function()
    local h=harness()
    local _,_,_,store=h.unit('BP_Monster_A_C',true,{['远距离进攻概率']=0.25})
    h.send('R1','远距离进攻概率\t1\n');h.step()
    assert(store['远距离进攻概率']==1)
    h.send('R2','');h.step()
    assert(store['远距离进攻概率']==0.25,tostring(store['远距离进攻概率']))
    assert(h.params:status().count==0)
    h.restore()
end)

test('clearing settings restores a false entry and removes a newly added one',function()
    local h=harness()
    local boolean,absent='减帧时允许格挡','远距离进攻概率'
    local _,_,_,store=h.unit('BP_Monster_A_C',true,{[boolean]=false})
    assert(h.send('R1',boolean..'\t1\n'..absent..'\t0.75\n').ok)
    h.step()
    assert(store[boolean]==true and store[absent]==0.75)
    assert(h.send('R2','').ok)
    h.step()
    assert(store[boolean]==false and store[absent]==nil,'restore the original map entries')
    h.restore()
end)

test('a failed restoration keeps the original for the next attempt',function()
    local h=harness()
    local key='减帧时允许格挡'
    local _,comp,_,store=h.unit('BP_Monster_A_C',true,{[key]=false})
    assert(h.send('R1',key..'\t1\n').ok)
    h.step()
    local map=comp.MergedParameterCollection.BoolParameters
    local add=map.Add
    map.Add=function()error('temporary map write failure')end
    assert(h.send('R2','').ok)
    h.step()
    assert(store[key]==true)
    map.Add=add
    h.step()
    assert(store[key]==false,'the retry restores the first snapshot')
    h.restore()
end)

test('a map override is restored even after a later override needs the hook',function()
    local h=harness()
    local flag,chance='减帧时允许格挡','远距离进攻概率'
    local _,comp,controller,store=h.unit('BP_Monster_A_C',true,{[flag]=false,[chance]=0.2})
    assert(h.send('R1',flag..'\t1\n').ok)
    h.step()
    assert(store[flag]==true)
    comp.MergedParameterCollection.FloatParameters.Add=function()error('map write blocked')end
    assert(h.send('R2',flag..'\t1\n'..chance..'\t0.75\n').ok)
    h.step()
    assert(h.params:status().hooked and h.library:FindFloatParameter(controller,FName(chance))==0.75)
    assert(h.send('R3','').ok)
    h.step()
    assert(store[flag]==false and h.library:FindFloatParameter(controller,FName(chance))==0.2)
    h.restore()
end)

test('drift in a later configured parameter is detected',function()
    local h=harness()
    local a,b='近距离进攻概率','远距离进攻概率'
    local _,_,_,store=h.unit('BP_Monster_A_C',true,{[a]=0.2,[b]=0.2})
    assert(h.send('R1',a..'\t1\n'..b..'\t1\n').ok)
    h.step()
    local first=next(h.params.values)
    local later=first==a and b or a
    store[later]=0.2
    h.step()
    assert(store[later]==1 and h.params:status().rewritten==1,'the second key is checked as well')
    h.restore()
end)

test('a value that drifts back (the game merged again) is written again, a few times at most',function()
    local h=harness()
    local _,_,_,store=h.unit('BP_Monster_A_C',true,{['近距离进攻概率']=0.4})
    h.send('R1','近距离进攻概率\t1\n');h.step()
    store['近距离进攻概率']=0.4;h.step()
    assert(store['近距离进攻概率']==1 and h.params:status().rewritten==1)
    for _=1,8 do store['近距离进攻概率']=0.4;h.step() end
    assert(h.params:status().rewritten==5,'gives up after a few')
    h.restore()
end)

test('when the map write does not take, the Find functions are hooked for these units only',function()
    local h=harness({broken=true})
    local _,_,controller,store=h.unit('BP_Monster_A_C',true,{['近距离进攻概率']=0.4,['减帧时允许格挡']=true})
    h.send('R1','近距离进攻概率\t1\n减帧时允许格挡\t0\n');h.step()
    assert(store['近距离进攻概率']==0.4,'nothing written')
    assert(h.params:status().hooked==true and h.hooks['/Script/SGameAI.SGameAIFunctionLibrary:FindFloatParameter'],h.all())
    assert(h.library:FindFloatParameter(controller,FName('近距离进攻概率'))==1)
    assert(h.library:FindBoolParameter(controller,FName('减帧时允许格挡'))==false,'false is an answer too')
    local stranger=object('Controller',{store={['近距离进攻概率']=0.7}})
    assert(h.library:FindFloatParameter(stranger,FName('近距离进攻概率'))==0.7,'other AI keeps its own')
    assert(h.library:FindFloatParameter(controller,FName('中距离进攻概率'))==nil,'a value not set: the game answers')
    local second=h.unit('BP_Monster_B_C',true,{['近距离进攻概率']=0.2})
    h.step()
    assert(h.all():find('读回 BP_Monster_B_C 游戏给的 近距离进攻概率=0.2',1,true),'with the hook on, what the game gave is still read: '..h.all())
    assert(h.params:status().failures==0,h.all())
    assert(h.all():find('近距离进攻概率 原值=0.4 %-> 目标=1 写表=false%(.-%) 读回=1 结果=生效'),h.all())
    h.params:silence();assert(next(h.hooks)==nil)
    h.restore()
end)

test('parameter names that do not survive FName go to the hook, without writing to a wrong key',function()
    local real=FName
    FName=function(text)return {name='?'..text,ToString=function()return '??' end} end
    local h=harness()
    local _,_,controller,store=h.unit('BP_Monster_A_C',true,{['近距离进攻概率']=0.4})
    h.send('R1','近距离进攻概率\t1\n');h.step()
    assert(h.all():find('一致=false',1,true) and h.params:status().hooked==true,h.all())
    assert(store['近距离进攻概率']==0.4 and store['?近距离进攻概率']==nil,'no write to a wrong key')
    local hook=h.hooks['/Script/SGameAI.SGameAIFunctionLibrary:FindFloatParameter']
    assert(hook(h.library,controller,{ToString=function()return '近距离进攻概率' end})==1,'the game\'s own name is matched as text')
    FName=real
    h.restore()
end)

test('a gone unit is forgotten; a unit logs the tension meter now and then',function()
    local h=harness()
    local actor=h.unit('BP_Monster_Boss_C',true,{},true)
    h.step()
    assert(h.all():find('压力值 BP_Monster_Boss_C 会话=true Raw=12 Confidence=0.5 峰值10秒=20',1,true),h.all())
    local count=#h.logs
    h.step(5);assert(#h.logs==count,'not every second')
    actor.alive=false;h.step(20)
    h.step(20);assert(h.params:status().applied==0)
    h.restore()
end)
print('ai_params: all tests passed')
