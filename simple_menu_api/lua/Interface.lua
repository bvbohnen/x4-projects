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
        -- TODO: finish moving away from Validate_Args usage.
        Lib.Validate_Args(args, {
            -- Default to first column if not given.
            {n="col", t='int', d=1},
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
            -- Custom defaults.
            Lib.Fill_Defaults(properties, config.standardTextProperties)
            -- Get general defaults for subtables.
            Lib.Fill_Defaults(properties, widget_defaults["text"])
            -- Set up a text box.
            row[col]:createText(args.text, properties)
        
        
        -- Simple clickable buttons.
        elseif args.command == "Make_Button" then

            local properties = Lib.Filter_Table(args, widget_properties["button"])
            -- Custom defaults; center text.
            Lib.Fill_Defaults(properties, {text = {halign = "center"}})
        
            -- Get general defaults for subtables.
            Lib.Fill_Defaults(properties, widget_defaults["button"])
            -- Make the widget.
            row[col]:createButton(properties)

            -- Event handlers.
            loc.Widget_Event_Script_Factory(row[col], "onClick", row_index, args.col, {})
            loc.Widget_Event_Script_Factory(row[col], "onRightClick", row_index, args.col, {})
                        
        
        -- Editable text boxes.
        elseif args.command == "Make_EditBox" then

            local properties = Lib.Filter_Table(args, widget_properties["editbox"])
            -- Standard formatting.
            Lib.Fill_Defaults(properties, {text = config.standardTextProperties})
            -- Get general defaults.
            Lib.Fill_Defaults(properties, widget_defaults["editbox"])
                    
            row[col]:createEditBox(properties)
            
            -- Event handlers.
            loc.Widget_Event_Script_Factory(row[col], "onTextChanged", 
                row_index, args.col, {"text"})

            -- TODO: only way to deactivate without confirmation is to
            -- hit escape, but that also clears all box text at the same time.
            -- Maybe interpose a handler function that tracks and restores
            -- the text from the last confirmation in this case.
            loc.Widget_Event_Script_Factory(row[col], "onEditBoxDeactivated", 
                row_index, args.col, {"text", "textchanged", "wasconfirmed"})
                                
        
        -- Sliders for picking a value in a range.
        elseif args.command == "Make_Slider" then
        
            local properties = Lib.Filter_Table(args, widget_properties["slidercell"])

            -- Standard formatting.
            Lib.Fill_Defaults(properties, {
                -- Changes color to match the options menu default.
                valueColor = config.sliderCellValueColor,
                -- Options menu hides maxes, from example looked at.
                hideMaxValue = true,
                })
            -- Get general defaults.
            Lib.Fill_Defaults(properties, widget_defaults["slidercell"])
            
            row[col]:createSliderCell(properties)
            
            -- Event handlers.
            -- Swapping ego's "newvalue" to "value".
            loc.Widget_Event_Script_Factory(row[col], "onSliderCellChanged", 
                row_index, args.col, {"value"})
            loc.Widget_Event_Script_Factory(row[col], "onSliderCellActivated", 
                row_index, args.col, {})
            -- Removing onSliderCellDeactivated. In practice it is buggy:
            --  no return values unless the player uses the editbox, and
            --  even then returns the wrong valuechanged (true) if the player
            --  escapes out of an edit (resets the value so valuechanged
            --  should be false, as onSliderCellConfirm returns).
            --loc.Widget_Event_Script_Factory(row[col], "onSliderCellDeactivated", 
            --    row_index, args.col, {"value", "valuechanged"})
            loc.Widget_Event_Script_Factory(row[col], "onRightClick", 
                row_index, args.col, {"row", "col", "posx", "posy"})
            loc.Widget_Event_Script_Factory(row[col], "onSliderCellConfirm", 
                row_index, args.col, {"value", "valuechanged"})
                                
        
        -- Dropdown menu of options.
        elseif args.command == "Make_Dropdown" then
            
            local properties = Lib.Filter_Table(args, widget_properties["dropdown"])
            -- Standard formatting. Nothing for now.
            --Lib.Fill_Defaults(properties, {})
            -- Get general defaults.
            Lib.Fill_Defaults(properties, widget_defaults["dropdown"])

            -- TODO: an optional, simpler way to lay out options, like
            -- in the original imagining with a comma separated string.

            ---- The options will be passed as a comma separated list; split
            ---- them apart here.
            --local option_names = Lib.Split_String_Multi(args.options, ',')
            ---- It seems the widget treats each option as a subtable with
            ---- the following fields; fill them all in.
            --local options = {}
            --for i = 1, #option_names do
            --    table.insert(options, {
            --        -- Set the id to match the index.
            --        id = i,
            --        text = option_names[i], 
            --        -- Don't use any icon (ego code set this "" instead of nil).
            --        icon = "", 
            --        -- Unclear what this would do.
            --        displayremoveoption = false 
            --        })
            --end

            -- Fill default ids in options.
            for i, option in ipairs(args.options) do
                if not option.id then
                    option.id = i
                end
                -- Default icon needs to be "" not nil.
                if not option.icon then
                    option.icon = ""
                end
                -- Also set default text string for safety.
                -- (nil might be okay, but not tested)
                if not option.text then
                    option.text = ""
                end
                -- Undocumented flag causes errors if missing, so include.
                -- (Makes options removeable with an 'x' button.)
                option.displayremoveoption = false
            end
                        
            row[col]:createDropDown(args.options, properties)
                
            -- Event handlers.
            -- Swapping ego's "value" to "id".
            loc.Widget_Event_Script_Factory(row[col], "onDropDownActivated", 
                row_index, args.col, {})
            loc.Widget_Event_Script_Factory(row[col], "onDropDownConfirmed", 
                row_index, args.col, {"id"})
            loc.Widget_Event_Script_Factory(row[col], "onDropDownRemoved", 
                row_index, args.col, {"id"})
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


-- Factory for creating handler functions for widget events.
-- Automatically attaches to the widget's matching event.
-- Args:
--  Widget: widget to attach the handler to.
--  Event: name of the event, eg. "onClick".
--  Row/col: widget coordinates.
--  Params: List of names of values returned by the event, excepting the
--   widget.  Eg. {"text", "textchanged", "wasconfirmed"}.
function loc.Widget_Event_Script_Factory(widget, event, row, col, params)

    -- Handlers are set up in the "handlers" widget subtable.
    -- Note: lua variable args are handled with "..." in the function args.
    widget.handlers[event] = function(event_widget, ...)

        -- Renamed the variable args, since ... cannot be indexed, and
        -- is kinda dumb anyhow. Packing needs to put table brackets on it.
        local vargs = {...}

        -- Put together a table to return to MD.
        local ret_table = {
            type = widget.type,
            event = event,
            row = row,
            col = col,
        }
        -- Add the params, in order; count should match.
        for i, field in ipairs(params) do
            -- In the unusual case of getting row/col, avoid overwrite
            -- just in case there is a difference.
            if not ret_table[field] then
                ret_table[field] = vargs[i]
            end
        end
        
        -- Debug messaging.
        if debugger.actions_to_chat then
            local message = "" .. widget.type .." "..event.." on ("..row..","..col.."): ("
            -- Add all params to it, if any; unnamed for now.
            if vargs then
                for i, result in ipairs(vargs) do
                    message = message .. " " .. tostring(result)
                end
            end
            message = message .. ")"
            CallEventScripts("directChatMessageReceived", "Menu;"..message)
        end

        -- Signal the lua.
        Lib.Raise_Signal("Event", ret_table)
    end
end


-- Init once everything is ready.
Init()

