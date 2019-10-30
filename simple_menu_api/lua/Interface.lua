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
    void SetBoxText(const int boxtextid, const char* text);
    void SetBoxTextBoxColor(const int boxtextid, Color color);
    void SetBoxTextColor(const int boxtextid, Color color);
    void SetButtonActive(const int buttonid, bool active);
    void SetButtonHighlightColor(const int buttonid, Color color);
    void SetButtonTextColor(const int buttonid, Color color);
    void SetButtonText2(const int buttonid, const char* text);
    void SetButtonText2Color(const int buttonid, Color color);
    void SetCheckBoxChecked(const int checkboxid, bool checked);
    void SetDropDownCurOption(const int dropdownid, const char* id);
    void SetEditBoxText(const int editboxid, const char* text);
    void SetFlowChartEdgeColor(const int flowchartedgeid, Color color);
    void SetFlowChartNodeCaptionText(const int flowchartnodeid, const char* text);
    void SetFlowChartNodeCaptionTextColor(const int flowchartnodeid, Color color);
    void SetFlowChartNodeCurValue(const int flowchartnodeid, double value);
    void SetFlowchartNodeExpanded(const int flowchartnodeid, const int frameid, bool expandedabove);
    void SetFlowChartNodeMaxValue(const int flowchartnodeid, double value);
    void SetFlowChartNodeOutlineColor(const int flowchartnodeid, Color color);
    void SetFlowChartNodeSlider1Value(const int flowchartnodeid, double value);
    void SetFlowChartNodeSlider2Value(const int flowchartnodeid, double value);
    void SetFlowChartNodeSliderStep(const int flowchartnodeid, double step);
    void SetFlowChartNodeStatusBgIcon(const int flowchartnodeid, const char* iconid);
    void SetFlowChartNodeStatusIcon(const int flowchartnodeid, const char* iconid);
    void SetFlowChartNodeStatusText(const int flowchartnodeid, const char* text);
    void SetFlowChartNodeStatusColor(const int flowchartnodeid, Color color);
    void SetIcon(const int widgeticonid, const char* iconid);
    void SetIconColor(const int widgeticonid, Color color);
    void SetIconText(const int widgeticonid, const char* text);
    void SetIconText2(const int widgeticonid, const char* text);
    void SetShieldHullBarHullPercent(const int shieldhullbarid, float hullpercent);
    void SetShieldHullBarShieldPercent(const int shieldhullbarid, float shieldpercent);
    void SetSliderCellMaxSelectValue(const int slidercellid, double value);
    void SetSliderCellMaxValue(const int slidercellid, double value);
    void SetStatusBarCurrentValue(const int statusbarid, float value);
    void SetStatusBarMaxValue(const int statusbarid, float value);
    void SetStatusBarStartValue(const int statusbarid, float value);    
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
        Lib.Print_Table(args, "Args")
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
        -- First arg is rowdata; must not be nil/false for the row to
        -- be selectable. TODO: hook up any callbacks, which echo rowdata.
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
            -- Default to first column if not given.
            {n="col", t='int', d=1},
        })
        
        -- Rename the column for convenience.
        -- Add any adjustment.
        local col = args.col + menu_data.col_adjust
        
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
            -- Fix bools.
            Lib.Fix_Bool_Args(properties, widget_defaults["text"])
            -- Set up a text box.
            row[col]:createText(args.text, properties)
        
        
        -- Simple clickable buttons.
        elseif args.command == "Make_Button" then
        
            local properties = Lib.Filter_Table(args, widget_properties["button"])
            -- Custom defaults; center text.
            Lib.Fill_Defaults(properties, {text = {halign = "center"}})
        
            -- Get general defaults for subtables.
            Lib.Fill_Defaults(properties, widget_defaults["button"])
            -- Fix bools.
            Lib.Fix_Bool_Args(properties, widget_defaults["button"])
            -- Make the widget.
            row[col]:createButton(properties)

            -- Event handlers.
            loc.Widget_Event_Script_Factory(row[col], "onClick", 
                row_index, args.col, {})
            loc.Widget_Event_Script_Factory(row[col], "onRightClick", 
                row_index, args.col, {})
                        

        elseif args.command == "Make_CheckBox" then
        
            local properties = Lib.Filter_Table(args, widget_properties["checkbox"])        
            -- Get general defaults for subtables.
            Lib.Fill_Defaults(properties, widget_defaults["checkbox"])
            -- Fix bools.
            Lib.Fix_Bool_Args(properties, widget_defaults["checkbox"])
            -- Make the widget.
            row[col]:createCheckBox(properties.checked, properties)

            -- Event handlers.
            -- Note: event gets true/false for "checked", but they return
            -- to md as 0/1.
            loc.Widget_Event_Script_Factory(row[col], "onClick", 
                row_index, args.col, {"checked"})
        

        -- Editable text boxes.
        elseif args.command == "Make_EditBox" then
        
            local properties = Lib.Filter_Table(args, widget_properties["editbox"])
            -- Standard formatting.
            Lib.Fill_Defaults(properties, {text = config.standardTextProperties})
            -- Get general defaults.
            Lib.Fill_Defaults(properties, widget_defaults["editbox"])
            -- Fix bools.
            Lib.Fix_Bool_Args(properties, widget_defaults["editbox"])
                    
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
            -- Fix bools.
            Lib.Fix_Bool_Args(properties, widget_defaults["slidercell"])
            
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
            -- Fix bools.
            Lib.Fix_Bool_Args(properties, widget_defaults["dropdown"])

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
        

    -- Handle widget update requests.
    elseif args.command == "Update_Widget" then
        -- Hand off to another function, since code is potentially long.
        loc.Update_Widget(args)

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
-- TODO: make use of Helper.set<name>Script functions, which can
--  wrap the callback function with a ui event and sound.
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

-- Function which will update an existing widget.
-- Split off for code organization.
function loc.Update_Widget(args)
    -- Adjust the column number as needed.
    args.col = args.col + menu_data.col_adjust

    -- Look up the requested widget.
    -- TODO: safety against not existing, though it should unless
    -- there was a creation error.
    local cell = menu_data.user_rows[args.row][args.col]
    
    -- Which fields update will depend on widget type.
    -- Follow a similar approach as helper widgetPrototypes.frame:update
    -- initially.
    --[[
        There are two general ways to approach this:

        a) Copy the stock update function, edit it for swapping in a value
           from args instead of doing a function call.

           Drawback: there is some quirkiness to button text changes,
           and a lot of quirkiness to flowcharts, and its just generally
           a lot of lines. However, if flowcharts dropped and buttons
           don't bother truncating when there's too much text, it goes
           back to being relatively simple.

        b) Create a temp function which will return the new value, and
           attach it to the widget. Let the normal update call implement
           the change.
           This function can be set to delete itself when done, since it
           receives the cell object as the first arg, and so can delink itself
           and replace with its value on the first call.

           Drawback: factory function a little tricky, but not too bad.
           Performance will be somewhat worse, since the stock update
           function checks all function capable widgets.

           Result: attempted, but one hiccup: the menu needs widgets with
           update functions included in its menu.frame.functionCells list.

        Going with (a) for flexibility.

    ]]

    -- Filter out cases where the cell has no id.
    -- Helper comments for addRow suggests id will be autofilled when
    -- the widget is visible.
    -- TODO: remove this; can rely on the standard update() to check.
    if not cell.id then
        DebugError("Failed to update widget due to nil id, on row,col: ("..args.row..","..args.col..")")
        return
    end
    
    --DebugError("Updating cell type: "..cell.type)


    -- Fix bools.
    Lib.Fix_Bool_Args(args, widget_defaults[cell.type])

    Lib.Print_Table(args)
    if args.text then
        Lib.Print_Table(args.text)
    end

    if cell.type == "text" then
        if args.text then
            -- Ego code may have a bug when it uses cell.id here.
            SetText(cell.id, args.text)
        end
        if args.color then
            -- Ego code may have a bug when it uses cell.id here.
            SetTextColor(cell.id, args.color.r, args.color.g, args.color.b, args.color.a)
        end

    elseif cell.type == "boxtext" then                    
        if args.text then
            C.SetBoxText(cell.id, args.text)
        end
        if args.color then
            C.SetBoxTextColor(cell.id, Helper.ffiColor(args.color))
        end
        if args.boxColor then
            C.SetBoxTextBoxColor(cell.id, Helper.ffiColor(args.boxColor))
        end
        
    elseif cell.type == "editbox" then
        if args.defaultText then
            C.SetEditBoxText(cell.id, args.defaultText)
        end
        
    -- Sliders don't appear fleshed out; just can change max side.
    elseif cell.type == "slider" then
        if args.max then
            C.SetSliderCellMaxValue(cell.id, args.max)
        end
        if args.maxSelect then
            C.SetSliderCellMaxSelectValue(cell.id, args.maxSelect)
        end
        
    elseif cell.type == "button" then
        -- Unpack text properties 1.
        local textprop = args.text
        if textprop then
            if textprop.text then
                -- Ignore font cuttoff for now; rely on user to not go over.
                SetButtonText(cell.id, textprop.text)
            end
            if textprop.color then
                C.SetButtonTextColor(cell.id, Helper.ffiColor(textprop.color))
            end
        end
        -- Unpack text properties 2.
        local textprop2 = args.text2
        if textprop2 then
            if textprop2.text then
                C.SetButtonText2(cell.id, textprop2.text)
            end
            if textprop2.color then
                -- Note: ego code has bug here and reuses SetButtonTextColor.
                C.SetButtonText2Color(cell.id, Helper.ffiColor(textprop2.color))
            end
        end

        if args.active then
            C.SetButtonActive(cell.id, args.active)
        end        
        if args.bgColor then
            -- Ego code may have a bug when it uses cell.id here.
            SetButtonColor(cell.id, args.bgColor.r, args.bgColor.g, args.bgColor.b, args.bgColor.a)
        end        
        if args.highlightColor then
            C.SetButtonHighlightColor(cell.id, Helper.ffiColor(args.highlightColor))
        end
        
    elseif cell.type == "shieldhullbar" then
        if args.shield then
            C.SetShieldHullBarShieldPercent(cell.id, args.shield)
        end
        if args.hull then
            C.SetShieldHullBarHullPercent(cell.id, args.hull)
        end
        
    elseif cell.type == "statusbar" then
        if args.current then
            C.SetStatusBarCurrentValue(cell.id, args.current)
        end
        if args.start then
            C.SetStatusBarStartValue(cell.id, args.start)
        end
        if args.max then
            C.SetStatusBarMaxValue(cell.id, args.max)
        end
        
    elseif cell.type == "icon" then
        local textprop = args.text
        if textprop then
            if textprop.text then
                C.SetIconText(cell.id, textprop.text)
            end
        end
        local textprop2 = args.text2
        if textprop2 then
            if textprop2.text then
                C.SetIconText2(cell.id, textprop2.text)
            end
        end
        if args.color then
            C.SetIconColor(cell.id, Helper.ffiColor(args.color))
        end
        if args.icon then
            C.SetIcon(cell.id, args.icon)
        end

    elseif cell.type == "dropdown" then
        if args.startOption then
            C.SetDropDownCurOption(cell.id, args.startOption)
        end

    elseif cell.type == "checkbox" then
        if args.checked then
            C.SetCheckBoxChecked(cell.id, args.checked)
        end

    end

    -- Removed, favoring direct handling.
    ---- Specify the fields updateable for each widget, and hand off
    ---- to the function factory.
    --if cell.type == "text" then
    --    loc.Setup_Update_Function(cell, args, {'text'})
    --    loc.Setup_Update_Function(cell, args, {'color'})
    --    
    --elseif cell.type == "boxtext" then
    --    loc.Setup_Update_Function(cell, args, {'text'})
    --    loc.Setup_Update_Function(cell, args, {'color'})
    --    loc.Setup_Update_Function(cell, args, {'boxColor'})
    --    
    --elseif cell.type == "button" then
    --    loc.Setup_Update_Function(cell, args, {'text','text'})
    --    loc.Setup_Update_Function(cell, args, {'text','color'})
    --    loc.Setup_Update_Function(cell, args, {'text2','text'})
    --    loc.Setup_Update_Function(cell, args, {'text2','color'})
    --    loc.Setup_Update_Function(cell, args, {'active'})
    --    loc.Setup_Update_Function(cell, args, {'bgColor'})
    --    loc.Setup_Update_Function(cell, args, {'highlightColor'})
    --    
    --elseif cell.type == "shieldhullbar" then
    --    loc.Setup_Update_Function(cell, args, {'shield'})
    --    loc.Setup_Update_Function(cell, args, {'hull'})
    --
    --elseif cell.type == "statusbar" then
    --    loc.Setup_Update_Function(cell, args, {'current'})
    --    loc.Setup_Update_Function(cell, args, {'start'})
    --    loc.Setup_Update_Function(cell, args, {'max'})
    --
    --elseif cell.type == "icon" then
    --    loc.Setup_Update_Function(cell, args, {'text','text'})
    --    loc.Setup_Update_Function(cell, args, {'text2','text'})
    --    loc.Setup_Update_Function(cell, args, {'color'})
    --    loc.Setup_Update_Function(cell, args, {'icon'})
    --    
    --elseif cell.type == "dropdown" then
    --    loc.Setup_Update_Function(cell, args, {'startOption'})
    --
    --elseif cell.type == "checkbox" then
    --    loc.Setup_Update_Function(cell, args, {'checked'})
    --end
    --
    ---- Force call the frame update function.
    --menu_data.frame:update()
end

-- Removed; not used (though runs fine).
---- Factory function to create a temp update function and attach
---- it to a widget. Temp function will destroy itself after first call.
--function loc.Setup_Update_Function(cell, args, fields)
--
--    -- Get the new value. If nil, no matching value present in args.
--    local new_val = Lib.Multilevel_Table_Lookup(args, fields)
--
--    if new_val == nil then
--        return
--    end
--    
--    -- Slice the fields to split off the last one.
--    local field_slice = Lib.Slice_List(fields, 1, #fields -1)
--    local last_field = fields[#fields]
--    -- Look up the table holding the value being changed.
--    local val_table = Lib.Multilevel_Table_Lookup(cell.properties, field_slice)
--    
--    DebugError("Updating cell "..last_field
--                .." from '"..tostring(val_table[last_field])
--                .."' to '" ..tostring(new_val).."'")
--
--    -- Temp func will be given the cell by frame:update().
--    -- In practice, the func should have a copy of the above locals, so
--    -- shouldn't need to do anything with cell directly.
--    local temp_function = function(cell)
--        -- This just needs to return the new_val, but will also remove
--        -- itself from the cell (replacing with new_val) as well to
--        -- act as a 1-shot.
--        -- Use the last field for the table key, assign new_val.
--        val_table[last_field] = new_val        
--        DebugError("Updated cell "..last_field.." to "..tostring(new_val))
--        return new_val        
--    end
--
--    -- Attach this function to the cell.
--    val_table[last_field] = temp_function
--end


-- Init once everything is ready.
Init()

