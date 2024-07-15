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

TODO:
- Check/enforce the widget/row/char limits defined in widget_fullscreen.lua.
]]


-- Import config and widget_properties tables.
local Tables = require("extensions.sn_mod_support_apis.lua.simple_menu.Tables")
local widget_properties = Tables.widget_properties
local widget_defaults   = Tables.widget_defaults
--local config            = Tables.config
local menu_data         = Tables.menu_data
local debugger          = Tables.debugger

-- Import library functions for strings and tables.
local Lib = require("extensions.sn_mod_support_apis.lua.simple_menu.Library")

-- Import the user options menu handler.
local Options_Menu = require("extensions.sn_mod_support_apis.lua.simple_menu.Options_Menu")

-- Import the standalone menu handler.
local Standalone_Menu = require("extensions.sn_mod_support_apis.lua.simple_menu.Standalone_Menu")


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
    void SetButtonIconID(const int buttonid, const char* iconid);
    void SetButtonIcon2ID(const int buttonid, const char* iconid);
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
    void SetSliderCellValue(const int slidercellid, double value);
    void SetStatusBarCurrentValue(const int statusbarid, float value);
    void SetStatusBarMaxValue(const int statusbarid, float value);
    void SetStatusBarStartValue(const int statusbarid, float value);    
]]
--[[
TODO:
    void SetCheckBoxChecked2(const int checkboxid, bool checked, bool update);
    void SetCheckBoxColor(const int checkboxid, Color color);
]]


-- Note on forward declarations: any functions (or other locals) refernced
-- in code need to be declared local before that code point.
-- This is a lexical scoping issue for locals, not a runtime timing issue.
-- These functions need to not be specified as local when declared later,
-- because lua.
-- Since this is a headache to manage, a local table will be used to capture
-- all misc functions, so that lookups are purely a runtime issue.
local L = {}


local function Init()

    -- MD triggered events.
    RegisterEvent("Simple_Menu.Process_Command", L.Handle_Process_Command)
    
    -- Signal to md that a reload event occurred.
    Lib.Raise_Signal("reloaded")
    
    -- Cache the player component id.
    L.player_id = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    
    --Lib.Print_Table(_G, "_G")
    --Lib.Print_Table(Color, "Color")
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
    args removed, since SetNPCBlackboard will only write a table (not list).
    
    So, this function will store the list of args locally, and overwrite
    the blackboard with nil, deleting the var. MD will recreate a list when
    needed to pass more args.

    Note: "none" entries in md convert to lua nil, and hence will not
    show up in the args table.
]]
function L.Get_Next_Args()

    -- If the list of queued args is empty, grab more from md.
    if #menu_data.queued_args == 0 then
    
        -- Args are attached to the player component object.
        local args_list = GetNPCBlackboard(L.player_id, "$simple_menu_args")
        
        -- Loop over it and move entries to the queue.
        for i, v in ipairs(args_list) do
            table.insert(menu_data.queued_args, v)
        end
        
        -- Clear the md var by writing nil.
        SetNPCBlackboard(L.player_id, "$simple_menu_args", nil)
    end
    
    -- Pop the first table entry.
    local args = table.remove(menu_data.queued_args, 1)
    
    -- Debug printout of passed args; kinda messy.
    -- Note: printouts will fail when v is a table; todo: maybe revisit and
    -- cleanup properly.
    --DebugError("Args received:")
    --for k,v in pairs(args) do
    --    DebugError(""..k.." type = "..type(v))
    --    if type(v) ~= "userdata" then
    --        DebugError(""..k.." = "..v)
    --    end
    --end

    -- Support the user giving strings matching Helper or Color consts,
    -- replacing them here.
    Lib.Replace_Helper_Args(args)
    Lib.Replace_Color_Args(args)

    return args
end


-- Handle command events coming in.
-- Param unused currently.
function L.Handle_Process_Command(_, param)
    local args = L.Get_Next_Args()
    
    if menu_data.delay_commands == false
    -- These commands are never delayed.
    or args.command == "Create_Menu"
    or args.command == "Close_Menu"
    or args.command == "Register_Options_Menu" then
        L.Process_Command(args)
    else
        table.insert(menu_data.queued_events, args)
    end
end


-------------------------------------------------------------------------------
-- General event processing.

-- Process all of the delayed events, in order.
function L.Process_Delayed_Commands()
    -- Loop until the list is empty; each iteration removes one event.
    while #menu_data.queued_events ~= 0 do
        -- Process the next event.
        local args = table.remove(menu_data.queued_events, 1)
        L.Process_Command(args)
    end
end
-- This will attach to the standalone menu, which calls it when it
-- sets up the delayed frame.
Standalone_Menu.Process_Delayed_Commands = L.Process_Delayed_Commands


-- Wrapper on the actual process command function, for error catching.
function L.Process_Command(args)
    local success, message = pcall(L._Process_Command, args)
    if not success then
        DebugError(string.format(
            'Simple Menu API: command "%s" produced error: %s', 
            tostring(args.command),
            tostring(message)))
    end
end

-- Generic handler for all signals.
-- They could also be split into separate functions, but this feels
-- a little cleaner.
function L._Process_Command(args)
    
    if debugger.announce_commands then
        DebugError("Processing command: "..args.command)
        Lib.Print_Table(args, "Args")
    end

    -- Check the command names, roughly in most to least frequent order.
    
    -- Handle widget update requests.
    -- Check this early, since when in use, it may be used at a high rate.
    if args.command == "Update_Widget" then
        -- Hand off to another function, since code is potentially long.
        L.Update_Widget(args)

    elseif args.command == "Refresh_Menu" then
        -- Just skip for now if in wrong mode.
        if menu_data.mode ~= "options" then
            error("Refresh_Menu only supported for options menus")
        end
        Options_Menu.Refresh(args)


    elseif args.command == "Make_Widget" then
        -- Hand off to the widget maker local function.
        L.Make_Widget(args)    

    -- Add a new row.
    elseif args.command == "Add_Row" then
        -- Filter for row properties, defaults, fix bools.
        local properties = Lib.Filter_Table(args, widget_properties["row"])
        Lib.Fill_Defaults(properties, menu_data.custom_widget_defaults["row"])
        Lib.Fill_Complex_Defaults(properties, widget_defaults["row"])
        Lib.Fix_Bool_Args(properties, widget_defaults["row"])

        -- This also supports a custom "selectable" flag, which wasn't fixed
        -- by bool handling above.
        Lib.Validate_Args(args, {
            {n="selectable", t="boolean", d=true},
        })

        -- Add one generic row.
        -- First arg is rowdata; must not be nil/false for the row to
        --  be selectable.
        -- TODO: set up row event callbacks; maybe use rowdata, given
        --  to callbacks, to specify details (eg. row index) to avoid
        --  having to look it up.
        local new_row = menu_data.ftable:addRow(args.selectable, properties)
        -- Store in user row table for each reference.
        table.insert(menu_data.user_rows, new_row)
        

    -- Adjust table aspects.
    elseif args.command == "Call_Table_Method" then
        -- Supported table methods and their order of call args.
        local table_method_args = {
            ["setColWidth"]                 = {"col", "width", "scaling"},
            ["setColWidthMin"]              = {"col", "width", "weight", "scaling"},
            ["setColWidthPercent"]          = {"col", "width"},
            ["setColWidthMinPercent"]       = {"col", "width", "weight"},
            ["setDefaultColSpan"]           = {"col", "colspan"},
            ["setDefaultBackgroundColSpan"] = {"col", "bgcolspan"},
        }

        -- Generic defaults for col adjustments, regardless of if the
        -- method uses it.  No particular field differs between calls.
        local generic_defaults = {scaling = true, weight = 1}
        Lib.Fill_Defaults(args, generic_defaults)
        Lib.Fix_Bool_Args(args, generic_defaults)

        -- Pack the method args. Always start with table itself, since
        -- these methods are called like functions.
        local method_args = {menu_data.ftable}
        for i, field in ipairs(table_method_args[args.method]) do

            -- Error check; should have been given by user or defaults.
            if not args[field] then
                error(table.format("Adjust_Table method '%s' missing field '%s'", args.method, field))
            end

            -- If this is the "col", do an adjustment.
            if field == "col" then
                value = args.col + menu_data.col_adjust
            else
                value = args[field]
            end
        
            table.insert(method_args, value)
        end

        -- Call the method.
        menu_data.ftable[args.method](table.unpack(method_args))
        
        
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
        if menu_data.mode ~= "options" then
            error("Add_Submenu_Link only supported for options menus")
        end
        -- TODO: make text optional, and just use the title of the submenu
        -- by default.
        
        -- Hand off to the options menu.
        Options_Menu.Add_Submenu_Link(args)
        
    
    -- Create a new menu; does not display immediately.
    elseif args.command == "Create_Menu" then
        -- Hand off to the standalone menu.
        Standalone_Menu.Open(args)
    
    -- Close the menu if open.
    elseif args.command == "Close_Menu" then
        -- Hand off to the standalone menu.
        Standalone_Menu.Close()
        
    elseif args.command == "Register_Options_Menu" then
        -- Validate all needed args are present.
        Lib.Validate_Args(args, {
            {n="id"},
            {n="title"}, 
            {n="columns", t='int'},
            {n="private", t='boolean', d=false},
        })
        -- Hand off.
        Options_Menu.Register_Options_Menu(args)
        
    else
        -- If here, the command wasn't recognized.
        error("Simple_Menu.Process_Command: unknown command: "..args.command)
    end
    
end


-------------------------------------------------------------------------------
-- Widget creation/update functions.


-- Make a widget in some cell.
function L.Make_Widget(args)
    -- Handle common args to all options.
    -- TODO: remove this; shouldn't be needed since md sets default col.
    Lib.Validate_Args(args, {
        -- Default to first column if not given.
        {n="col", t='int', d=1},
    })
        
    -- Rename the column for convenience.
    -- Add any adjustment.
    local col = args.col + menu_data.col_adjust
        
    -- Error if no rows present yet.
    if #menu_data.user_rows == 0 then
        error("Simple_Menu.Make_Widget: no user rows for Make command")
    end
    -- Set the last row index, and pick out the row object.
    local row_index = #menu_data.user_rows
    local row = menu_data.user_rows[row_index]

    -- Make sure the col is in range.
    if not row[col] then
        error("Simple_Menu.Make_Widget: column out of range")
    end
        
    -- Filter for widget properties.
    --  Note: the widget creator does some property name validation,
    --  printing harmless debugerror messages on mismatch.
    --  Filtering will reduce debug spam.
    local properties = Lib.Filter_Table(args, widget_properties[args.type])
    
    -- Fill in custom defaults.
    Lib.Fill_Defaults(properties, menu_data.custom_widget_defaults[args.type])

    -- Fill in subtable defaults, needed for subtables which the ego
    --  backend can't autofill with defaults (unless it replaces the
    --  entire table).
    -- Do not touch top level args, since it can cause confusion with
    --  some that are optional and the backend sets as 'false' (confusing
    --  the following bool fix).
    Lib.Fill_Complex_Defaults(properties, widget_defaults[args.type])

    -- Fix bools, which are 0/1 coming out of md.
    Lib.Fix_Bool_Args(properties, widget_defaults[args.type])


    -- Handle generic colSpan argument.
    if args.colSpan then
        row[col]:setColSpan(args.colSpan)
    end

    -- Go through the possible widgets.
    -- Start with simpler ones that have no callbacks.
    if args.type == "text" then
        row[col]:createText(args.text, properties)
        
    elseif args.type == "boxtext" then
        row[col]:createBoxText(args.text, properties)
        
    elseif args.type == "icon" then
        row[col]:createIcon(args.icon, properties)
        
    elseif args.type == "statusbar" then
        row[col]:createStatusBar(properties)
        

    elseif args.type == "button" then
        row[col]:createButton(properties)

        -- Event handlers.
        L.Widget_Event_Script_Factory(row[col], "onClick", 
            row_index, args.col, {})
        L.Widget_Event_Script_Factory(row[col], "onRightClick", 
            row_index, args.col, {})
                        

    elseif args.type == "checkbox" then
        row[col]:createCheckBox(properties.checked, properties)

        -- Event handlers.
        -- Note: event gets true/false for "checked", but they return
        -- to md as 0/1.
        L.Widget_Event_Script_Factory(row[col], "onClick", 
            row_index, args.col, {"checked"})
        

    -- Editable text boxes.
    elseif args.type == "editbox" then
        row[col]:createEditBox(properties)
            
        -- Event handlers.
        L.Widget_Event_Script_Factory(row[col], "onTextChanged", 
            row_index, args.col, {"text"})

        -- TODO: only way to deactivate without confirmation is to
        -- hit escape, but that also clears all box text at the same time.
        -- Maybe interpose a handler function that tracks and restores
        -- the text from the last confirmation in this case.
        L.Widget_Event_Script_Factory(row[col], "onEditBoxDeactivated", 
            row_index, args.col, {"text", "textchanged", "wasconfirmed"})
                                
        
    -- Sliders for picking a value in a range.
    elseif args.type == "slidercell" then        
        row[col]:createSliderCell(properties)
            
        -- Event handlers.
        -- Swapping ego's "newvalue" to "value".
        L.Widget_Event_Script_Factory(row[col], "onSliderCellChanged", 
            row_index, args.col, {"value"})
        L.Widget_Event_Script_Factory(row[col], "onSliderCellActivated", 
            row_index, args.col, {})
        -- Removing onSliderCellDeactivated. In practice it is buggy:
        --  no return values unless the player uses the editbox, and
        --  even then returns the wrong valuechanged (true) if the player
        --  escapes out of an edit (resets the value so valuechanged
        --  should be false, as onSliderCellConfirm returns).
        --L.Widget_Event_Script_Factory(row[col], "onSliderCellDeactivated", 
        --    row_index, args.col, {"value", "valuechanged"})
        L.Widget_Event_Script_Factory(row[col], "onRightClick", 
            row_index, args.col, {"row", "col", "posx", "posy"})
        L.Widget_Event_Script_Factory(row[col], "onSliderCellConfirm", 
            row_index, args.col, {"value", "valuechanged"})
                                
        
    -- Dropdown menu of options.
    elseif args.type == "dropdown" then

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
            -- Always overwrite the option's id field; this is required
            -- to be the index when the ego callback returns it (as a string).
            option.id = i

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
        -- Swapping ego's "value" to "option_id".
        -- Note: ego's backend converts the id to a string; special handling
        -- will be used to convert them to numbers at callback.
        L.Widget_Event_Script_Factory(row[col], "onDropDownActivated", 
            row_index, args.col, {})
        L.Widget_Event_Script_Factory(row[col], "onDropDownConfirmed", 
            row_index, args.col, {"option_index"}, {["option_index"] = "number"})
        L.Widget_Event_Script_Factory(row[col], "onDropDownRemoved", 
            row_index, args.col, {"option_index"}, {["option_index"] = "number"})


    elseif args.type == "shieldhullbar" then
        -- This could be using a fixed shield/hull percentage, or be
        -- linked to an object target.
        -- The builder function to call depends on which mode is used.
        if args.object then
            row[col]:createObjectShieldHullBar(args.object, properties)
        else
            -- TODO: Ensure the shield/hull values in 0-100 range.
            row[col]:createShieldHullBar(args.shield, args.hull, properties)
        end

    else
        -- Shouldn't be here.
        error("Widget type not recognized: "..tostring(args.type))
    end        
end


-- Factory for creating handler functions for widget events.
-- Automatically attaches to the widget's matching event.
-- Args:
--  Widget: widget to attach the handler to.
--  Event: name of the event, eg. "onClick".
--  Row/col: widget coordinates.
--  Params: List of names of values returned by the event, excepting the
--   widget.  Eg. {"text", "textchanged", "wasconfirmed"}.
--  Conversions: table of params (keyed by name) holding their conversion
--   types, if any. Added to convert dropdown option strings to numbers.
-- TODO: make use of Helper.set<name>Script functions, which can
--  wrap the callback function with a ui event and sound.
function L.Widget_Event_Script_Factory(widget, event, row, col, params, conversions)

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
                value = vargs[i]
                -- Deal with any type conversions.
                if conversions and conversions[field] then
                    if conversions[field] == "number" then
                        value = tonumber(value)
                    end
                end
                ret_table[field] = value
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
function L.Update_Widget(args)
    -- Adjust the column number as needed.
    args.col = args.col + menu_data.col_adjust

    -- Look up the requested widget.
    -- TODO: safety against not existing, though it should unless
    -- there was a creation error.
    local cell = menu_data.user_rows[args.row][args.col]
    

    -- Filter out cases where the cell has no id.
    -- Helper comments for addRow suggests id will be autofilled when
    -- the widget is visible.
    -- Something similar is done in the helper update() function.
    if not cell or not cell.id then
        error(string.format(
            "Failed to update widget due to nil id, on row,col: (%d,%d)", 
            args.row, args.col))
    end
        
    -- Fix bools.
    Lib.Fix_Bool_Args(args, widget_defaults[cell.type])

    -- Note: below updates depend generally on C functions available.
    -- Any more general update would require closing and reopening the
    -- menu entirely. (Just a frame:display() refresh leads to other
    -- bugs with unregistered widgets/scripts/etc in the ego backend.)

    -- Handle each cell type individually.
    if cell.type == "text" then
        if args.text then
            -- Ego code may have a bug when it uses cell.id here.
            SetText(cell.id, args.text)
        end
        if args.color then
            SetTextColor(cell.id, args.color.r, args.color.g, args.color.b, args.color.a)
        end
        -- TODO: maybe glowfactor

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
    -- TODO: SetSliderCellMaxFactor (what is this?)
    elseif cell.type == "slider" then
        if args.value then
            C.SetSliderCellValue(cell.id, args.value)        
        end
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
        -- TODO: add support for changing icon id, added in 3.0beta7.
        -- C.SetButtonIconID (cell.id, args.icon)
        -- C.SetButtonIcon2ID(cell.id, args.icon)
        
    elseif cell.type == "shieldhullbar" then
        if args.shield then
            C.SetShieldHullBarShieldPercent(cell.id, args.shield)
        end
        if args.hull then
            C.SetShieldHullBarHullPercent(cell.id, args.hull)
        end
        if args.object then
            -- TODO: rewrap the shield/hull functions of the widget.
            -- Need to mimic code in createObjectShieldHullBar.
            local object64 = ConvertStringTo64Bit(tostring(args.object))
            shield = function() return IsComponentOperational(object64) and GetComponentData(object64, "shieldpercent") or 0 end
            hull   = function() return IsComponentOperational(object64) and GetComponentData(object64, "hullpercent") or 0 end
            -- TODO: is this the right way to update the cell?
            cell.properties.shield = shield
            cell.properties.hull   = hull
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

end

-------------------------------------------------------------------------------
-- Generic shared menu event support.
-- These will not cover onClose or similar events that are unique to
--  a menu type, just the generic table/widget related events.
-- Note: for the options menu, these will catch all events, not just those
--  on customized submenus.

-- TODO: make some generic function for fill out the following deub
-- messages and lua events, for code reuse. Currently just three of
-- them, so okay to be redundant.

-- Called when player selects a row (click or arrow key).
-- row: int
-- rowdata: echo of what was fed to addSelectRow() calls.
-- uitable: int, ui id of the table; this constantly increments across
--  all menu elements for all menus (eg. it will often be a big number).
-- modified, input, source: ???
-- Generic options menu uses this to stop playing cutscenes or simliar,
--  presumably for when played changes encyclopedia entry?
function L.onRowChanged(row, rowdata, uitable, modified, input, source)
    -- Debug messaging.
    if debugger.actions_to_chat then
        CallEventScripts("directChatMessageReceived", 
            string.format("Menu;table onRowChanged to row: (%s)", 
            tostring(row)))
    end
    -- Safety against bad row args.
    if not row then return end
    
    -- Signal md. Use similar format to widget events.
    Lib.Raise_Signal("Event", {
        type = "menu",
        event = "onRowChanged",
        row = row,
        modified = modified,
        input = input,
        source = source,
        })
end

-- Called when player selects a column (click or arrow key, as well
--  as by changing row to a row with a widget).
-- row: the most recently selected row recorded by onRowChanged.
-- col: int
-- uitable: table with the row/col
function L.onColChanged(row, col, uitable)
    -- Debug messaging.
    if debugger.actions_to_chat then
        CallEventScripts("directChatMessageReceived",
            string.format("Menu;table onColChanged to row,col: (%s, %s)", 
            tostring(row), tostring(col)))
    end
    
    -- On first opening, the menu appears to throw out nil/nil garbage;
    -- ignore it.
    if (not row) or (not col) then return end

    -- Signal md. Use similar format to widget events.
    Lib.Raise_Signal("Event", {
        type = "menu",
        event = "onColChanged",
        row = row,
        -- Adjust the col index going back to remove backarrow col.
        col = col - menu_data.col_adjust,
        })
end

-- Called when player selects an element?
-- Maybe only informs of the row, like onRowChanged?
-- Generic options menu uses this for opening submenus.
function L.onSelectElement(uitable, modified, row, isdblclick, input)    
    -- Debug messaging.
    if debugger.actions_to_chat then
        CallEventScripts("directChatMessageReceived", 
            string.format("Menu;table onSelectElement to row: (%s)", 
            tostring(row)))
    end
    -- Safety against bad row args.
    if not row then return end

    -- Signal md. Use similar format to widget events.
    Lib.Raise_Signal("Event", {
        type = "menu",
        event = "onSelectElement",
        row = row,
        modified = modified,
        isdblclick = isdblclick,
        input = input,
        })
end

-- This appears (based on looking at menu_map.lua) that this activates
-- when a different table is selected. 
-- element: int?  (referred to as an id)
-- Not useful for the custom menus since 1 table.
--function L.onInteractiveElementChanged(element)
--    -- Debug messaging.
--    if debugger.actions_to_chat then
--        CallEventScripts("directChatMessageReceived", 
--            string.format("Menu;table onInteractiveElementChanged to element type: %s", 
--            element.type))
--    end
--end

-- Attach these to the standalone/options menu tables.
Options_Menu.onRowChanged = L.onRowChanged
Options_Menu.onColChanged = L.onColChanged
Options_Menu.onSelectElement = L.onSelectElement

Standalone_Menu.onRowChanged = L.onRowChanged
Standalone_Menu.onColChanged = L.onColChanged
Standalone_Menu.onSelectElement = L.onSelectElement



-- Init once everything is ready.
Init()

