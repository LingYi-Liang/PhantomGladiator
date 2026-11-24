-- Windows VK_GAMEPAD identifiers in saved bindings, Unreal input names at runtime.
local Xbox={}
local buttons={
    [195]={'A','Gamepad_FaceButton_Bottom'},[196]={'B','Gamepad_FaceButton_Right'},
    [197]={'X','Gamepad_FaceButton_Left'},[198]={'Y','Gamepad_FaceButton_Top'},
    [199]={'RB','Gamepad_RightShoulder'},[200]={'LB','Gamepad_LeftShoulder'},
    [201]={'LT','Gamepad_LeftTriggerAxis'},[202]={'RT','Gamepad_RightTriggerAxis'},
    [203]={'D-pad ↑','Gamepad_DPad_Up'},[204]={'D-pad ↓','Gamepad_DPad_Down'},
    [205]={'D-pad ←','Gamepad_DPad_Left'},[206]={'D-pad →','Gamepad_DPad_Right'},
    [207]={'Menu','Gamepad_Special_Right'},[208]={'View','Gamepad_Special_Left'},
    [209]={'LS','Gamepad_LeftThumbstick'},[210]={'RS','Gamepad_RightThumbstick'},
}
local LB,RB=200,199
local function shoulder(code)return code==LB or code==RB end
function Xbox.button(code)return buttons[code]~=nil end
function Xbox.valid(code,mask)
    return buttons[code]~=nil and type(mask)=='number' and mask%1==0 and mask>=0 and mask<=3
        and (mask==0 or not shoulder(code))
end
function Xbox.label(code,mask)
    return 'Xbox '..(mask&1~=0 and 'LB+' or '')..(mask&2~=0 and 'RB+' or '')..buttons[code][1]
end
function Xbox.new(fkey,fire)
    local self={count=0}
    local keys,chords,down,armed,used={},{},{},{},{}
    local function add(code)
        if not keys[code] then keys[code]=fkey(buttons[code][2]) end
    end
    function self.register(code,mask,callback)
        if not Xbox.valid(code,mask) then return false end
        add(LB);add(RB);add(code)
        chords[code]=chords[code] or {}
        if chords[code][mask] then return false end
        chords[code][mask]=callback;self.count=self.count+1
        return true
    end
    function self:reset()
        down,armed,used={},{},{}
    end
    local function state(pc,code)
        if code==201 or code==202 then
            local ok,v=pcall(function()return pc:GetInputAnalogKeyState(keys[code])end)
            if ok and type(v)=='number' then return v>(down[code] and .40 or .55) end
        else
            local ok,v=pcall(function()return pc:IsInputKeyDown(keys[code])end)
            if ok and type(v)=='boolean' then return v end
            ok,v=pcall(function()return pc:GetInputAnalogKeyState(keys[code])end)
            if ok and type(v)=='number' then return v>.5 end
        end
    end
    local function finish(code,held)
        if not held then
            if down[code] and armed[code] and not used[code] and chords[code] then fire(chords[code][0]) end
            armed[code],used[code]=nil,nil
        end
        down[code]=held
    end
    function self:tick(pc)
        if self.count==0 then return end
        local left,right=state(pc,LB),state(pc,RB)
        if left==nil or right==nil then self:reset();return end
        if down[LB]==false and left then armed[LB]=true end
        if down[RB]==false and right then armed[RB]=true end
        if left and right then used[LB],used[RB]=true,true end
        local mask=(left and 1 or 0)+(right and 2 or 0)
        for code,bindings in pairs(chords)do
            if not shoulder(code) then
                local held=state(pc,code)
                if held and down[code]==false then
                    if left then used[LB]=true end
                    if right then used[RB]=true end
                    if bindings[mask] then fire(bindings[mask]) end
                end
                down[code]=held
            end
        end
        finish(LB,left);finish(RB,right)
    end
    return self
end
return Xbox
