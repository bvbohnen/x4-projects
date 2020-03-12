
--[[
Module for adding new context menu actions.
Note: not dependend on the simple menu flow directly, except for
some library functions.

TODO: maybe split off into separate extension.
    
menu.display() calls menu.prepareActions() 

menu.onUpdate() calls menu.prepareActions() if it thinks things have 
changed (eg. a scan completed)
    
prepareActions() 
- Bunch of logic for different possible actions.
- Standard action list obtained externally from:
    - C.GetCompSlotPlayerActions(buf, n, menu.componentSlot)
    - Action list depends on target component?
- Makes many conditional calls to insertInteractionContent() 
    to register the actions.
            
        
insertInteractionContent(section, entry)
    Appears to register a new action.
    * section
        String, matching something in config.sections
        Observed:
            main
            player_interaction
            selected_orders
            playersquad_orders
            etc.
    * entry
        Table with some subfields.
        * type
            - String, often called actiontype, eg. "teleport", "upgrade", etc.
            - Doesn't seem to have other uses in the lua, but was for the
            C labelling to lua to read.
        * text
            - String, display text
        * helpOverlayID
            - String, unique gui id?  Never seems to be used.
        * helpOverlayText
            - String, often blank
        * helpOverlayHighlightOnly
            - Bool, often true
        * script
            - Lua function callback, no input args.
            - Often given as a "menu.button..." function in this lue module.
        * hidetarget
            - Bool, often true
        * active
            - Lua function, returns bool?
        * mouseOverText
            - String
]]

-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
]]

-- Import config and widget_properties tables.
local Tables = require("extensions.simple_menu_api.lua.Tables")
--local debugger = Tables.debugger
-- Use local debug flags.
local debugger = {
    verbose = false,
}

-- Import library functions for strings and tables.
local Lib = require("extensions.simple_menu_api.lua.Library")



-- Table of locals.
local L = {
    -- Component of the player.
    player_id = nil,

    -- List of queued command args.
    queued_args = {},

    -- List of custom actions.
    actions = {},

    -- Current table of target object flags.
    flags = nil,
}

-- Convenience link to the egosoft interact menu.
local menu

function L.Init()
    
    -- MD triggered events.
    RegisterEvent("Interact_Menu.Process_Command", L.Handle_Process_Command)
    
    -- Signal to md that a reload event occurred.
    AddUITriggeredEvent("Interact_Menu_API", "reloaded")

    -- Cache the player component id.
    L.player_id = ConvertStringTo64Bit(tostring(C.GetPlayerID()))

    L.Init_Patch_Menu()
end

function L.Get_Next_Args()

    -- If the list of queued args is empty, grab more from md.
    if #L.queued_args == 0 then
    
        -- Args are attached to the player component object.
        local args_list = GetNPCBlackboard(L.player_id, "$interact_menu_args")
        
        -- Loop over it and move entries to the queue.
        for i, v in ipairs(args_list) do
            table.insert(L.queued_args, v)
        end
        
        -- Clear the md var by writing nil.
        SetNPCBlackboard(L.player_id, "$interact_menu_args", nil)
    end
    
    -- Pop the first table entry.
    local args = table.remove(L.queued_args, 1)

    return args
end


function L.Handle_Process_Command(_, param)
    local args = L.Get_Next_Args()

    -- Process command.
    if args.command == "Register_Action" then
        table.insert(L.actions, args)
    else
        DebugError("Unrecognized command: "..tostring(args.command))
    end
end


-- Patch the egosoft menu to insert custom actions.
function L.Init_Patch_Menu()

    -- Stop if something went wrong.
    if Menus == nil then
        error("Menus global not yet initialized")
    end
    
    for i, ego_menu in ipairs(Menus) do
        if ego_menu.name == "InteractMenu" then
            menu = ego_menu
        end
    end
    
    -- Stop if something went wrong.
    if menu == nil then
        error("Failed to find egosoft's InteractMenu")
    end

    -- Patch the action prep.
    local ego_prepareActions = menu.prepareActions
    menu.prepareActions = function (...)
        -- Run the standard setup first.
        ego_prepareActions(...)

        -- Safety call to add in the new actions.
        local success, error = pcall(L.Add_Actions, ...)
        if not success then
            DebugError("prepareActions error: "..tostring(error))
        end
    end
    
end

-- Injected code which adds new action entries to the menu.
function L.Add_Actions()
    -- Most actions filter based on this flag check, but not all.
    -- TODO: consider if this should be filtered or not.
    --if not menu.showPlayerInteractions then return end

    local convertedComponent = ConvertStringTo64Bit(tostring(menu.componentSlot.component))

    -- Update object flags.
    L.Update_Flags(menu.componentSlot.component)

    for i, action in ipairs(L.actions) do

        -- Skip disabled actions.
        if action.disabled == 1 then

        -- Skip if flag check fails.
        elseif not L.Check_Flags(action) then

        else
            -- Table of generic data to return to the call.
            local ret_table = {
                id = action.id,
                component = convertedComponent,
            }

            -- Do conditional checks.
            -- TODO

            -- Make a new entry.
            menu.insertInteractionContent(
                action.section, { 
                type = action.id, 
                text = action.name, 
                helpOverlayID = "interactmenu_"..action.id,
                -- TODO: anything useful for this text?
                helpOverlayText = "", 
                helpOverlayHighlightOnly = true,
                script = function () return L.Interact_Callback(ret_table) end, 
                -- TODO: conditionally grey out the action.
                active = true, 
                mouseOverText = action.mouseover })
            menu.insertInteractionContent("player_interaction", entry)
        end

    end
end

-- Convert a value to a boolean true/false.
-- Treats 0 as false.
local function tobool(value)
    if value and value ~= 0 then 
        return true 
    else 
        return false 
    end
end

-- Returns a table of flag values (true/false) that can be referenced by
-- user actions to determine when they show.
function L.Update_Flags(component)

    -- Note: it is unclear when component, component64, and convertedComponent
    -- should be used; just trying to match ego code in each instance.

    local component = menu.componentSlot.component
    --local component64 = ConvertIDTo64Bit(component) -- Errors
    local convertedComponent = ConvertStringTo64Bit(tostring(component))

    local flags = {}

    -- Component class checks.
    for key, name in pairs({
        ship    = "ship", 
        gate    = "gate", 
        station = "station",
    }) do
        -- Note: C.IsComponentClass returns 0 for false, so needs cleanup.
        flags[key] = tobool(C.IsComponentClass(component, name))
    end

    -- Component data checks.
    -- TODO: more complicated logic, eg. shiptype and purpose comparisons
    -- to different possibilities.
    for key, name in pairs({
        playerowned = "isplayerowned", 
        enemy       = "isenemy",
    }) do
        flags[key] = tobool(GetComponentData(convertedComponent, name))
    end
    
    -- For every flag, also offer the negated version.
    -- Do in two steps; can't modify the original table in the loop without
    -- new entries showing up in the same loop (eg. multiple ~~~flags).
    local negated_flags = {}
    for key, value in pairs(flags) do
        negated_flags["~"..key] = not value
    end
    for key, value in pairs(negated_flags) do
        flags[key] = value
    end
    
    if debugger.verbose then
        -- Debug printout.
        Lib.Print_Table(flags, "flags")
    end

    L.flags = flags
end


-- Check an action against the current flags
function L.Check_Flags(action, flags)

    if debugger.verbose then
        Lib.Print_Table(action.enabled_conditions, "enabled_conditions")
    end
    
    if debugger.verbose then
        Lib.Print_Table(action.disabled_conditions, "disabled_conditions")
    end

    -- If there are requirements, check those.
    if #action.enabled_conditions ~= 0 then
        local match_found = false
        -- Only need one to match.
        for i, flag in ipairs(action.enabled_conditions) do
            if L.flags[flag] then
                match_found = true
                break
            end
        end
        -- If no match, failure.
        if not match_found then 
            if debugger.verbose then
                DebugError("Enable condition not matched for action "..action.id)
            end
            return false 
        end
    end

    -- If there are blacklisted flags, check those.
    if #action.disabled_conditions ~= 0 then
        -- Failure on any match.
        for i, flag in ipairs(action.disabled_conditions) do
            if L.flags[flag_req] then
                if debugger.verbose then
                    DebugError("Disable condition matched for action "..action.id)
                end
                return false
            end
        end
    end

    -- If here, should be good to go.
    return true
end


-- Handle callbacks when the player selects the action.
function L.Interact_Callback(ret_table)

    if debugger.verbose then
        Lib.Print_Table(ret_table, "ret_table")
    end

    --CallEventScripts("directChatMessageReceived", "InteractMenu;lua action: "..ret_table.id)

    -- Signal md with the component/object.
    AddUITriggeredEvent("Interact_Menu", "Selected", ret_table)
    -- Close the context menu.
    menu.onCloseElement("close")
end


L.Init()