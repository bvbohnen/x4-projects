
-- Table holding lib functions to be returned, or lib params that can
-- be modified.
local L = {
    debug = {
        print_to_log = false,
    },
}

-- Include stuff from the shared library.
local Lib_shared = require("extensions.sn_mod_support_apis.lua.Library")
Lib_shared.Table_Update(L, Lib_shared)

-- Shared function to raise a named galaxy signal with an optional
-- return value.
function L.Raise_Signal(name, return_value)
    -- Clumsy way to lookup the galaxy.
    -- local player = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    -- local galaxy = GetComponentData(player, "galaxyid" )
    -- SignalObject( galaxy, name, return_value)
    
    -- Switching to AddUITriggeredEvent
    -- This will give the return_value in event.param3
    -- Use <event_ui_triggered screen="'Named_Pipes'" control="'<name>'" />
    AddUITriggeredEvent("Named_Pipes", name, return_value)
    
    if L.debug.print_to_log then
        if return_value == nil then
            return_value = "nil"
        end
        DebugError("UI Event: Named_Pipes, "..name.." ; value: "..return_value)
    end
end



---- Split a string on the first semicolon.
---- Note: works on the MD passed arrays of characters.
---- Returns two substrings.
--function L.Split_String(this_string)
--
--    -- Get the position of the separator.
--    local position = string.find(this_string, ";")
--    if position == nil then
--        -- Debug error printout gets a nicer log heading.
--        DebugError("No ';' separator found in: "..tostring(this_string))
--        -- Hard error.
--        error("Bad separator")
--    end
--
--    -- Split into pre- and post- separator strings.
--    local left  = string.sub(this_string, 0, position -1)
--    local right = string.sub(this_string, position +1)
--    
--    return left, right
--end


return L