--[[
    Misc functions split off into a library file.
    Mostly string or table processing.
]]

-- Table to hold lib functions.
local L = {}

-- Signalling results from lua to md.
-- Takes the row,col of the activated widget, and an optional new value
-- for that widget.
-- TODO: think about this more.
function L.Raise_Signal(name, value)
    AddUITriggeredEvent("Hotkey", name, value)
end

-- Print a table's contents to the log.
-- Optionally give the table a name.
-- TODO: maybe recursive.
function L.Print_Table(itable, name)
    if not name then name = "" end
    -- Construct a string with newlines between table entries.
    -- Start with header.
    local str = "Table "..name.." contents:\n"

    if not itable then
        str = str .."nil\n"
    else
        for k,v in pairs(itable) do
            str = str .. "["..k.."] = "..tostring(v).." ("..type(v)..")\n"
        end
    end
    DebugError(str)
end


return L