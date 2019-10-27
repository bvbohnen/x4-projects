--[[
Top level of the lua side of the simple menu api.
Interfaces with MD script commands which will populate the menu and
capture callbacks.

Handy ego reference code:
- widget_fullscreen.lua
  Has a variety of element fundamental settings near the top.
  Around ~1476 starts some global functions.
- helper.lua
  Has scattered documentation on widget creation properties.
  Around ~2963 are default args for various widgets.
]]


-- Global config customization.
-- A lot of ui config is in widget_fullscreen.lua, where its 'config'
-- table is global, allowing editing of various values.
-- Rename the global config, to not interfere with local.
local global_config = config
if global_config == nil then
    error("Failed to find global config from widget_fullscreen.lua")
end


-- Import config and widget_properties tables.
local Tables = require("extensions.simple_menu_api.lua.Tables")
local widget_properties = Tables.widget_properties
local widget_defaults   = Tables.widget_defaults
local config            = Tables.config
local menu_data         = Tables.menu_data
local debugger          = Tables.debugger
local custom_menu_specs = Tables.custom_menu_specs

-- Import library functions for strings and tables.
local Lib = require("extensions.simple_menu_api.lua.Library")

-- Import the user options menu handler.
local Options_Menu = require("extensions.simple_menu_api.lua.Options_Menu")

-- Import the standalone menu handler.
local Standalone_Menu = require("extensions.simple_menu_api.lua.Standalone_Menu")


-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef uint64_t UniverseID;
    UniverseID GetPlayerID(void);
]]


-- Note on forward declarations: any functions (or other locals) refernced
-- in code need to be declared local before that code point.
-- This is a lexical scoping issue for locals, not a runtime timing issue.
-- These functions need to not be specified as local when declared later,
-- because lua.
-- Since this is a headache to manage, a local table will be used to capture
-- all misc functions, so that lookups are purely a runtime issue.
local loc = {}


local function Init()

    -- MD triggered events.
    RegisterEvent("Simple_Menu.Process_Command", loc.Handle_Process_Command)    
    RegisterEvent("Simple_Menu.Register_Options_Menu", loc.Handle_Register_Options_Menu)
    
    -- Signal to md that a reload event occurred.
    Lib.Raise_Signal("reloaded")
    
    -- Cache the player component id.
    loc.player_id = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    
    -- Bugfix for editboxes, where were limited to 5 instead of 50.
    -- Removed; doesn't work, since the original value already was used
    -- to initialize a data structure with room for only 5, and that
    -- sturcture is private.
    -- global_config.editbox.maxElements = 50
    
    -- Increase mouseover font size, since 9 is a bit small, and there
    -- is no way for increasing it through widget text properties or similar.
    -- TODO: make this configurable, maybe in a menu.
    -- Removed; works fine, but want to eventually put it in a menu
    -- for per-player customization.
    --global_config.mouseOverText.fontsize = 12
end


-------------------------------------------------------------------------------
-- MD/lua event handling.

-- Read the next args table from md and return them.
--[[
Behavior:
    MD may queue up many signals in a frame before lua has a chance to
    process them. To handle this, the arg tables will be put into a list
    attached to the player component, named "$simple_menu_args".

    GetNPCBlackboard is capable of retrieving a copy of this list, as a lua
    table. However, lua cannot write back an edited table with one set of
    args removed, since SetNPCBlackboard will only write a table.
    
    So, this function will store the list of args locally, and overwrite
    the blackboard with nil, deleting the var. MD will recreate a list when
    needed to pass more args.

    Note: "none" entries in md convert to lua nil, and hence will not
    show up in the args table.
]]
function loc.Get_Next_Args()

    -- If the list of queued args is empty, grab more from md.
    if #menu_data.queued_args == 0 then
    
        -- Args are attached to the player component object.
        local args_list = GetNPCBlackboard(loc.player_id, "$simple_menu_args")
        
        -- Loop over it and move entries to the queue.
        for i, v in ipairs(args_list) do
            table.insert(menu_data.queued_args, v)
        end
        
        -- Clear the md var by writing nil.
        SetNPCBlackboard(loc.player_id, "$simple_menu_args", nil)
    end
    
    -- Pop the first table entry.
    local args = table.remove(menu_data.queued_args, 1)
    
    -- Debug printout of passed args; kinda messy.
    --DebugError("Args received:")
    --for k,v in pairs(args) do
    --    DebugError(""..k.." type = "..type(v))
    --    if type(v) ~= "userdata" then
    --        DebugError(""..k.." = "..v)
    --    end
    --end

    -- Support the user giving strings matching Helper consts, replacing
    -- them here.
    Lib.Replace_Helper_Args(args)

    return args
end


-- Handle command events coming in.
-- Menu creation and closing will be processed immediately, while
-- other events are delayed until a menu is created by the backend.
-- Param unused currently.
function loc.Handle_Process_Command(_, param)
    local args = loc.Get_Next_Args()
    
    if args.command == "Create_Menu" then
        loc.Process_Command(args)
    elseif args.command == "Close_Menu" then
        loc.Process_Command(args)
    elseif menu_data.delay_commands == false then
        loc.Process_Command(args)
    else
        table.insert(menu_data.queued_events, args)
    end
end


-- Handle registration of user options menus.
function loc.Handle_Register_Options_Menu(_, param)
    local args = loc.Get_Next_Args()
    
    -- Validate all needed args are present.
    Lib.Validate_Args(args, {
        {n="id"},
        {n="title"}, 
        {n="columns", t='int'},
        {n="private", t='int', d=0},
    })
    
    -- Verify the id appears unique, at least among registered submenus.
    if custom_menu_specs[args.id] then
        error("Submenu id conflicts with prior registrated id: "..args.id)
    end
    
    -- Record to the global table.
    custom_menu_specs[args.id] = args
    
    if debugger.verbose then
        DebugError("Registered submenu: "..args.id)
    end
end


-------------------------------------------------------------------------------
-- General event processing.

-- Process all of the delayed events, in order.
function loc.Process_Delayed_Commands()
    -- Loop until the list is empty; each iteration removes one event.
    while #menu_data.queued_events ~= 0 do
        -- Process the next event.
        local args = table.remove(menu_data.queued_events, 1)
        loc.Process_Command(args)
    end
end
-- This will attach to the standalone menu, which calls it when it
-- sets up the delayed frame.
Standalone_Menu.Process_Delayed_Commands = loc.Process_Delayed_Commands


-- Generic handler for all signals.
-- They could also be split into separate functions, but this feels
-- a little cleaner.
function loc.Process_Command(args)
    
    if debugger.announce_commands then
        DebugError("Processing command: "..args.command)
    end
    
    -- Create a new menu; does not display.
    -- TODO: does the shell of the menu display anyway?
    if args.command == "Create_Menu" then
        -- Hand off to the standalone menu.
        Standalone_Menu.Open(args)
    
    -- Close the menu if open.
    elseif args.command == "Close_Menu" then
        -- Hand off to the standalone menu.
        Standalone_Menu.Close()
        
    -- Display a menu that has been finished.
    elseif args.command == "Display_Menu" then
        menu_data.frame:display()
        
    -- Add a new row.
    elseif args.command == "Add_Row" then
        -- Add one generic row.
        -- First arg is selectability; must be true for rows with widgets.
        local new_row = menu_data.ftable:addRow(true, { bgColor = Helper.color.transparent })
        -- Store in user row table for each reference.
        table.insert(menu_data.user_rows, new_row)
        
        
    -- Add a submenu link, for options menus.
    -- Note: this automatically adds a row, but it will not be tracked
    -- in user_rows for now.
    elseif args.command == "Add_Submenu_Link" then
        Lib.Validate_Args(args, {
            {n="text"},
            {n="id"}
        })
        
        -- TODO: verify this is for an options menu, not standalone.
        -- Just skip for now if in wrong mode.
        if not menu_data.mode == "options" then
            DebugError("Add_Submenu_Link not supported for options menus")
            return
        end
        -- TODO: make text optional, and just use the title of the submenu
        -- by default.
        
        -- Hand off to the options menu.
        Options_Menu.Add_Submenu_Link(args)
        
    
    
    -- Various widget makers begin with 'Make'.
    -- Note: most of these take a 'properties' table of args.
    -- Except where such args are non-string or non-optional, this will
    -- not do validation on them, but just passes along a filtered table.
    elseif string.sub(args.command, 1, #"Make") == "Make" then
    
        -- Handle common args to all options.
        Lib.Validate_Args(args, {
            {n="col", t='int'},
            -- TODO: colspan, other cell-level stuff.
        })
        
        -- Rename the column for convenience.
        local col = args.col
        -- There may or may not be an implicit column for a back arrow.
        -- Arrows are in options menus, not standalone.
        if menu_data.mode == "options" then
            col = col + 1
        end
        
        -- Error if no rows present yet.
        if #menu_data.user_rows == 0 then
            error("Simple_Menu.Make_Label: no user rows for Make command")
        end
        -- Set the last row index, and pick out the row object.
        local row_index = #menu_data.user_rows
        local row = menu_data.user_rows[row_index]
        
        -- Plain text label.
        if args.command == "Make_Label" then
            -- Filter for widget properties.
            -- Note: the widget creator does some property name validation,
            -- printing harmless debugerror messages on mismatch.
            -- Filtering will reduce debug spam.
            local properties = Lib.Filter_Table(args, widget_properties.text)
            -- Fill in extra defaults.
            Lib.Fill_Defaults(properties, config.standardTextProperties)
            -- Get general defaults for subtables.
            Lib.Fill_Defaults(properties, widget_defaults["text"])
            -- Set up a text box.
            row[col]:createText(args.text, properties)
        
        
        -- Simple clickable buttons.
        elseif args.command == "Make_Button" then

            local properties = Lib.Filter_Table(args, widget_properties.button)
            -- Get custom defaults.
            Lib.Fill_Defaults(properties, config.standardButtonProperties)
            -- Get general defaults for subtables.
            Lib.Fill_Defaults(properties, widget_defaults["button"])
            -- Make the widget.
            row[col]:createButton(properties)
            
            -- Handler function.
            row[col].handlers.onClick = function()
                -- Debug
                if debugger.actions_to_chat then
                    CallEventScripts("directChatMessageReceived", 
                    "Menu;Button clicked on ("..row_index..","..args.col..")")
                end
                    
                -- Return a table of results.
                -- Note: this should not prefix with '$' like the md, but
                -- the conversion to md will add such prefixes automatically.
                -- Note: this row/col does not include title row or arrow
                -- column; use args.col for the original user-view column.
                Lib.Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = args.col
                    })
            end
            
        
        -- Editable text boxes.
        elseif args.command == "Make_EditBox" then
            Lib.Validate_Args(args, {
                {n="text", d=""}
            })
            row[col]:createEditBox():setText(args.text, config.standardTextProperties)
            
            -- Capture changed text.
            row[col].handlers.onTextChanged = function(_, text) 
                if debugger.actions_to_chat then
                    CallEventScripts("directChatMessageReceived", 
                    "Menu;Text on ("..row_index..","..args.col..") changed to: "..text)
                end
                
                Lib.Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = args.col,
                    ["text"] = text,
                    })
                end
                
        
        -- Sliders for picking a value in a range.
        elseif args.command == "Make_Slider" then
            Lib.Validate_Args(args, {
                {n="min"       , t='int'},
                {n="minSelect" , t='int' , d="nil"},
                {n="max"       , t='int'},
                {n="maxSelect" , t='int' , d="nil"},
                {n="start"     , t='int' , d="nil"},
                {n="step"      , t='int' , d="nil"},
                {n="suffix"    , d=""}
            })
            
            row[col]:createSliderCell({ 
                valueColor = config.sliderCellValueColor, 
                min = args.min, 
                minSelect = args.minSelect, 
                max = args.max, 
                maxSelect = args.maxSelect, 
                start = args.start, 
                step = args.step, 
                suffix = args.suffix, 
                -- Set some default flags for now.
                exceedMaxValue = false, 
                hideMaxValue = true, 
                readOnly = false }
                ):setText(args.text, { color = Helper.color.white})
                
            -- Capture changed value.
            row[col].handlers.onSliderCellChanged = function(_, value)
                if debugger.actions_to_chat then
                    CallEventScripts("directChatMessageReceived", 
                    "Menu;Slider on ("..row_index..","..args.col..") changed to: "..value)
                end
                
                Lib.Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = args.col,
                    ["value"] = value,
                    })
                end
                
        
        -- Dropdown menu of options.
        elseif args.command == "Make_Dropdown" then
            Lib.Validate_Args(args, {
                {n="options"},
                {n="start"  , d="nil", t='int'},
            })
            
            -- The options will be passed as a comma separated list; split
            -- them apart here.
            local option_names = Lib.Split_String_Multi(args.options, ',')
            -- It seems the widget treats each option as a subtable with
            -- the following fields; fill them all in.
            local options = {}
            for i = 1, #option_names do
                table.insert(options, {
                    -- Set the id to match the index.
                    id = i,
                    text = option_names[i], 
                    -- Don't use any icon (ego code set this "" instead of nil).
                    icon = "", 
                    -- Unclear what this would do.
                    displayremoveoption = false 
                    })
            end
            
            row[col]:createDropDown(options, { 
                active = true, 
                -- This appears to take the id of the start option, an int,
                -- so convert from the md string.
                startOption = tonumber(args.start), 
                -- Unclear what this is.
                textOverride = "" 
                })
                
            -- Capture changed option, using its id/index.
            row[col].handlers.onDropDownConfirmed = function(_, option_id)
                if debugger.actions_to_chat then
                    CallEventScripts("directChatMessageReceived", 
                    "Menu;Dropdown on ("..row_index..","..args.col..") changed to: "..option_id)
                end
                
                Lib.Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = args.col,
                    -- Convert this back into a number for easy usage in md.
                    ["option"] = tonumber(option_id),
                    })
                end            
        end
        
    else
        -- If here, the command wasn't recognized.
        DebugError("Simple_Menu.Process_Command: unknown command: "..args.command)
    end
    
    -- To make sure changes appear, brute force it by calling display()
    -- on every change, if a frame is known.
    -- Removed; causes blank menu and log full of "invalid table" errors.
    --if menu_data.frame ~= nil then
    --    menu_data.frame:display()
    --end
end


-- Init once everything is ready.
Init()

