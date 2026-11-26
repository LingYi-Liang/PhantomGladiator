-- Publish plain roster data from the same arena snapshot that supplies the battlefield counts.
local Files=require('companion_profile')
local Roster={}

function Roster.new(options)
    local self={revision=0}
    local nextAt,lastBody=0,nil
    local clock=options.clock or os.time
    local write=options.write or Files.write
    local path=options.path..'/arena-roster.tsv'

    function self:due()return clock()>=nextAt end
    function self:refresh()nextAt=0 end

    function self:publish(session,editable,units)
        nextAt=clock()+1
        if type(session)~='string' or not session:match('^[%w_-]+$') then return end
        local lines={}
        for _,unit in ipairs(units)do
            if type(unit.path)=='string' and not unit.path:find('%c') then
                local hp=unit.hp
                local display=(type(hp)=='number' and hp>=0 and hp<math.huge) and string.format('%.0f',hp) or ''
                lines[#lines+1]=table.concat({unit.id,unit.team,unit.path,unit.ordinal,unit.state,display},'\t')
            end
        end
        local header=table.concat({'PGAR1',session,editable and 'edit' or 'view'},'\t')
        local rows=table.concat(lines,'\n')
        local body=header..'\n'..rows
        if body==lastBody then return end
        local revision=self.revision+1
        local data=header..'\t'..revision..'\n'
        if #lines>0 then data=data..rows..'\n' end
        if #data>2*1024*1024 or not write(path,data) then return end
        lastBody=body
        self.revision=revision
    end
    return self
end

return Roster
