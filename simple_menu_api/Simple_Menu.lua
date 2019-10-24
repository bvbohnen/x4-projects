--[[
Lua side of the simple menu api.
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

-------------------------------------------------------------------------------
-- Global config customization.
-- A lot of ui config is in widget_fullscreen.lua, where its 'config'
-- table is global, allowing editing of various values.

-- Rename the global config, to not interfere with local.
local global_config = config
if global_config == nil then
    error("Failed to find global config from widget_fullscreen.lua")
end

-------------------------------------------------------------------------------
-- Local data tables.

local debugger = {
    -- Send chat messages on player actions to widgets.
    actions_to_chat = false,
    -- Print all commands run.
    announce_commands = false,
    -- Generic filter on messages.
    verbose = false,
}

-- User registered menus to show in options.
-- Keys are the menu_ids of the submenus. Entries are subtables with the
-- submenu properties (id, menu_id, name, private, etc.).
local custom_menu_specs = {
}

-- The table holding the standalone menu details.
-- Egosoft code will process this to add extra properties and methods.
-- This is reused for all standalone user menus, but not for options menus.
local menu = {
    -- Flag, true when the menu is known to be open.
    -- May false positive depending on how the menu was closed?
    is_open = false,

    -- Name of the menu used in registration. Should be unique.
    name = "SimpleMenu",
    -- How often the menu refreshes?
    updateInterval = 0.1,
    
    -- Table holding user settings passed from md to Create_Menu.
    -- TODO: absorb width/height/etc. into this.
    user_settings = nil,
    
    -- Defaults for settings the user didn't specify.
    -- Use "nil" for optional entries that default nil.
    defaults = {
        width   = 400,
        height  = "nil",
        offsetX = "nil",
        offsetY = "nil", -- TODO: nil?
    },
    
    -- The main frame, named to match ego code.
    -- TODO: naming probably not important.
    infoFrame = nil,
}

-- Proxy for the gameoptions menu, linked further below.
-- This should be used when in options mode.
local gameoptions_menu = nil

-- Custom data of the current menu (standalone or gameoptions).
-- These get linked appropriately depending on which menu type is active.
local menu_data = {
    -- Number of columns in the table, not including back arrow.
    columns = nil,
    
    -- The gui frame being displayed.
    -- frame:display() needs to be called after changes to make updates visible.
    frame = nil,
    -- The table widget, which is the sole occupant of the frame.
    -- (Not called 'table' because that is reserved in lua.)
    ftable = nil,    
    -- Single row table holding the title.
    title_table = nil,
    -- List of rows in the table, in order, added by user.
    -- Does not include header rows.
    user_rows = {},
    
    -- Mode will be a string, either "options" or "standalone", based on
    -- the active menu type.
    mode = nil,
    
    -- Flag, if incoming commands (other than creating/closing tables)
    -- need to be delayed. True for standalone menus, false for options
    -- menus.
    delay_commands = false,
    -- Queue for the above delays.
    queued_events = {}
}


-- Generic config, mimicking ego code.
-- Copied from ego code; may not all be used.
local config = {
    optionsLayer = 3,
    topLevelLayer = 4,

    backarrow = "table_arrow_inv_left",
    backarrowOffsetX = 3,

    sliderCellValueColor = { r = 71, g = 136, b = 184, a = 100 },
    greySliderCellValueColor = { r = 55, g = 55, b = 55, a = 100 },

    font = "Zekton outlined",
    fontBold = "Zekton bold outlined",

    headerFontSize = 13,
    infoFontSize = 9,
    standardFontSize = 10,

    headerTextHeight = 34,
    subHeaderTextHeight = 22,
    standardTextHeight = 19,
    infoTextHeight = 16,

    headerTextOffsetX = 5,
    standardTextOffsetX = 5,
    infoTextOffsetX = 5,

    vrIntroDelay = 32,
    vrIntroFadeOutTime = 2,
}
-- Copied for table setup; may not all be used.
config.table = {
    x = 45,
    y = 45,
    width = 710,
    widthWithExtraInfo = 370,
    height = 600,
    arrowColumnWidth = 20,
    infoColumnWidth = 330,
}
-- Copied from ego menu for fonts.
config.headerTextProperties = {
    font = config.fontBold,
    fontsize = config.headerFontSize,
    x = config.headerTextOffsetX,
    y = 6,
    minRowHeight = config.headerTextHeight,
    titleColor = Helper.defaultSimpleBackgroundColor,
}
config.infoTextProperties = {
    font = config.font,
    fontsize = config.infoFontSize,
    x = config.infoTextOffsetX,
    y = 2,
    wordwrap = true,
    minRowHeight = config.infoTextHeight,
    titleColor = Helper.defaultSimpleBackgroundColor,
}
config.standardTextProperties = {
    font = config.font,
    fontsize = config.standardFontSize,
    x = config.standardTextOffsetX,
    y = 2,
}


-- Clean out stored references after menu closes, to release memory.
function menu.cleanup()
    menu.is_open = false
    menu.infoFrame = nil
    -- Reset menu_data as well. This is somewhat redundant with reset
    -- on opening a new menu, but should let garbage collection run
    -- sooner when the current menu closed properly.
    menu_data_reset()
end

-- Reset any menu data to a clean state.
-- For safety, call this when opening a new menu, protecting against cases
-- where a prior attempted menu errored out with leftover queued commands
-- or similar.
function menu_data_reset()
    menu_data.frame = nil
    menu_data.ftable = nil
    menu_data.title_table = nil
    menu_data.user_rows = {}
    menu_data.queued_events = {}
    menu_data.mode = nil
end

-- Forward function declarations.
local Handle_Open_Menu
local Handle_Add_Row
local Handle_Make_Label


local function init()

    -- MD triggered events.
    RegisterEvent("Simple_Menu.Process_Command", Handle_Process_Command)
    RegisterEvent("Simple_Menu.Register_Options_Menu", Handle_Register_Options_Menu)
    
    -- Register menu; uses its name.
    Menus = Menus or {}
    table.insert(Menus, menu)
    if Helper then
        Helper.registerMenu(menu)
    end
    
    -- Signal to md that a reload event occurred.
    Raise_Signal("reloaded")
    
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
-- String processing, mostly for unpacking args sent from md.

-- Split a string on the first separator.
-- Note: works on the MD passed arrays of characters.
-- Returns two substrings, left and right of the sep.
function Split_String(this_string, separator)

    -- Get the position of the separator.
    local position = string.find(this_string, separator)
    if position == nil then
        error("Bad separator")
    end

    -- Split into pre- and post- separator strings.
    -- TODO: should start point be at 1?  0 seems to work fine.
    local left  = string.sub(this_string, 0, position -1)
    local right = string.sub(this_string, position +1)
    
    return left, right
end

-- Split a string as many times as possible.
-- Returns a list of substrings.
function Split_String_Multi(this_string, separator)
    substrings = {}
    
    -- Early return for empty string.
    if this_string == "" then
        return substrings
    end
    
    -- Use Split_String to iteratively break apart the args in a loop.
    local remainder = this_string
    local left, right
    
    -- Loop until Split_String fails to find the separator.
    local success = true
    while success do
    
        -- pcall will error and set sucess=false if no separators remaining.
        success, left, right = pcall(Split_String, remainder, separator)
        
        -- On success, the next substring is in left.
        -- On failure, the final substring is still in remainder.
        local substring
        if success then
            substring = left
            remainder = right
        else
            substring = remainder
        end
        
        -- Add to the running list.
        table.insert(substrings, substring)
    end
    return substrings
end


-- Take an arg string and convert to a table.
function Tabulate_Args(arg_string)
    local args = {}    
    -- Start with a full split on semicolons.
    local named_args = Split_String_Multi(arg_string, ";")
    -- Loop over each named arg.
    for i = 1, #named_args do
        -- Split the named arg on comma.
        local key, value = Split_String(named_args[i], ",")
        -- Keys have a prefixed $ due to md dumbness; remove it here.
        key = string.sub(key, 2, -1)
        args[key] = value
    end
    return args    
end

--[[ 
Handle validation of arguments, filling in defaults.
'args' is a table with the named user provided arguments.
'arg_specs' is a list of subtables with fields:
  n : string, name
  d : optional default
  t : string type, only needed for casting (eg. if not string).
If a name is missing from user args, the default is added to 'args'.
 If the default is the "nil" string, nothing is added.
 If the default is nil, it is treated as non-optional.
Type is "str" or "int"; the latter will get converted to a number.
If the original arg is a string "nil" or "null", it will be converted
 to nil, prior to checking if optional and filling a default.
 
TODO: maybe support dynamic code execution for complex args that want
 to use lua data (eg. Helper.viewWidth for window size adjustment sliders),
 using loadstring(). This is probably a bit niche, though.
]]
function Validate_Args(args, arg_specs)
    -- Loop over the arg_specs list.
    for i = 1, #arg_specs do 
        local name    = arg_specs[i].n
        local default = arg_specs[i].d
        local arttype = arg_specs[i].t
        
        -- Convert "none" and "nil" to nil; eg. treat arg as not given.
        if args[name] == "nil" or args[name] == "none" then
            args[name] = nil
        end
        
        -- In lua, if a name is missing from args its lookup will be nil.
        if args[name] == nil then
            -- Error if no default available.
            if default == nil then
                -- Treat as non-recoverable, with hard error instead of DebugError.
                error("Args missing non-optional field: "..name)
            -- Do nothing if default is explicitly nil; this leaves the arg
            -- as nil for later uses.
            elseif default == "nil" then
            else
                -- Use the default.
                args[name] = default
            end
        else
            -- Number casting.
            -- TODO: maybe round ints, but for now floats are fine.
            if arttype == "int" then
                args[name] = tonumber(args[name])
            end
        end        
    end
end


-------------------------------------------------------------------------------
-- MD/lua event handling.


-- Handle command events coming in.
-- Menu creation and closing will be processed immediately, while
-- other events are delayed until a menu is created by the backend.
function Handle_Process_Command(_, param)
    -- Unpack the param into a table of args.
    local args = Tabulate_Args(param)
    
    if args.command == "Create_Menu" then
        Process_Command(args)
    elseif args.command == "Close_Menu" then
        Process_Command(args)
    elseif menu_data.delay_commands == false then
        Process_Command(args)
    else
        table.insert(menu_data.queued_events, args)
    end
end


-- Handle registration of user options menus.
function Handle_Register_Options_Menu(_, param)
    -- Unpack the param into a table of args.
    local args = Tabulate_Args(param)
    
    -- Validate all needed args are present.
    Validate_Args(args, {
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


-- Signalling results from lua to md.
-- Takes the row,col of the activated widget, and an optional new value
-- for that widget.
-- TODO: think about this more.
function Raise_Signal(name, value)
    AddUITriggeredEvent("Simple_Menu", name, value)
end

-------------------------------------------------------------------------------
-- General event processing.

-- Process all of the delayed events, in order.
function Process_Delayed_Commands()
    -- Loop until the list is empty; each iteration removes one event.
    while #menu_data.queued_events ~= 0 do
        -- Process the next event.
        local args = table.remove(menu_data.queued_events, 1)
        Process_Command(args)
    end
end

-- Generic handler for all signals.
-- They could also be split into separate functions, but this feels
-- a little cleaner.
function Process_Command(args)
    
    if debugger.announce_commands then
        DebugError("Processing command: "..args.command)
    end
    
    -- Create a new menu; does not display.
    -- TODO: does the shell of the menu display anyway?
    if args.command == "Create_Menu" then
        -- Close any currently open menu, which will also clear out old
        -- data (eg. don't want to append to old rows).
        Close_Menu()
        
        -- Clear old menu_data to be safe.
        menu_data_reset()
        -- Delay following commands since the menu isn't set up immediately.
        menu_data.delay_commands = true
        
        -- Ensure needed args are present, and fill any defaults.
        Validate_Args(args, {
            {n="title", d=""}, 
            {n="columns", t='int'},
            {n="width"   , t='int', d = menu.defaults.width},
            {n="height"  , t='int', d = menu.defaults.height},
            {n="offsetY" , t='int', d = menu.defaults.offsetY},
            {n="offsetX" , t='int', d = menu.defaults.offsetX},
        })        
        -- Store the args into the menu, to be used when onShowMenu gets
        -- its delayed call.
        menu.user_settings = args
                        
        -- OpenMenu is an exe side function.
        -- TODO: what are the args?
        -- Will automatically call onShowMenu(), but after some delay during
        -- which other md signals are processed.
        OpenMenu("SimpleMenu", nil, nil, true)
        -- TODO: try this form, that is more common:
        -- OpenMenu("SimpleMenu", { 0, 0 }, nil)
        
        -- TODO: should this flag be set here, or at onShowMenu?
        menu.is_open = true
    
    -- Close the menu if open.
    elseif args.command == "Close_Menu" then
        Close_Menu()
        
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
        Validate_Args(args, {
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
        
        -- Add a generic selectable row to be handled like normal menus.
        -- Last arg is the column count; the line will be set to span all
        -- columns after the first (implicitly skipping the backarrow column).
        gameoptions_menu.displayOption(menu_data.ftable, {
            id      = args.id,
            name    = args.text,
            submenu = args.id,
        }, menu_data.columns + 1)
    
    
    -- Various widget makers begin with 'Make'.
    elseif string.sub(args.command, 1, #"Make") == "Make" then
    
        -- Handle common args to all options.
        Validate_Args(args, {
            {n="col", t='int'},
            -- TODO: colspan, font
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
        
    
        if args.command == "Make_Label" then
            Validate_Args(args, {
                {n="text"},
                {n="mouseover", d=""}
            })
            
            -- Set up a text box.
            -- TODO: maybe support colspan.
            -- TODO: a good font setting
            row[col]:createText(args.text, config.standardTextProperties)
            -- Set any default properties.
            -- TODO: merge these into the createText call.
            row[col].properties.wordwrap = true
            -- Mouseover is optional.
            if args.mouseover ~= "" then
                row[col].properties.mouseOverText = args.mouseover
            end
        
        
        -- Simple clickable buttons.
        elseif args.command == "Make_Button" then
            Validate_Args(args, {
                {n="text", d=""}
            })
            row[col]:createButton():setText(args.text, { halign = "center" })
            
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
                Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = args.col
                    })
            end
            
        
        -- Editable text boxes.
        elseif args.command == "Make_EditBox" then
            Validate_Args(args, {
                {n="text", d=""}
            })
            row[col]:createEditBox():setText(args.text, config.standardTextProperties)
            
            -- Capture changed text.
            row[col].handlers.onTextChanged = function(_, text) 
                if debugger.actions_to_chat then
                    CallEventScripts("directChatMessageReceived", 
                    "Menu;Text on ("..row_index..","..args.col..") changed to: "..text)
                end
                
                Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = args.col,
                    ["text"] = text,
                    })
                end
                
        
        -- Sliders for picking a value in a range.
        elseif args.command == "Make_Slider" then
            Validate_Args(args, {
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
                
                Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = args.col,
                    ["value"] = value,
                    })
                end
                
        
        -- Dropdown menu of options.
        elseif args.command == "Make_Dropdown" then
            Validate_Args(args, {
                {n="options"},
                {n="start"  , d="nil", t='int'},
            })
            
            -- The options will be passed as a comma separated list; split
            -- them apart here.
            local option_names = Split_String_Multi(args.options, ',')
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
                
                Raise_Signal("Event", {
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

function Close_Menu()
    if menu.is_open == true then
        -- Reuses the ui close function.
        menu.onCloseElement("close", true)
    end
end

-------------------------------------------------------------------------------
-- Menu methods.
-- It is unclear on which of these may be implicitly called by the
-- gui backend, so naming is generally left as-is.

-- This is called automatically when a menu opens.
-- At this point, the menu table has a "param" subtable member.
function menu.onShowMenu()
    -- Bounce over to the frame maker.
    menu.createInfoFrame()
end

-- Set up a gui frame.
function menu.createInfoFrame()
    -- TODO: revisit if needed.
    -- Presumably this allows for assigning menu subframes to layer numbers,
    -- and this command can clear a specific layer that holds dynamic data
    -- while leaving static layers (bordering and such) untouched so they
    -- are only built once.
    -- In this case, however, nearly the entire menu is dynamic and rebuilt
    -- every time.
    --Helper.clearDataForRefresh(menu, menu.infoLayer)
        
    -- Set frame properties using a table to be passed as an arg.
    -- Note: width and X offset are known here; height and Y offset are
    -- computed later based on contents.
    local frameProperties = {
        -- TODO: don't override this; will get close/back buttons by default,
        -- and so don't need a back arrow.
        --standardButtons = {},
        
        -- Calculate horizontal sizing/position.
        -- Scale width and pad enough for borders.
        width = Helper.scaleX(menu.user_settings.width) + 2 * Helper.borderSize,
        layer = config.optionsLayer,
        backgroundID = "solid",
        backgroundColor = Helper.color.semitransparent,
        startAnimation = false,
    }
    
    -- Create the frame object; returns its handle to be saved.
    menu.infoFrame = Helper.createFrameHandle(menu, frameProperties)

    -- Create the table as part of the frame.
    -- This function is further below, and handles populating sub-widgets.
    local ftable = menu.createTable(menu.infoFrame)
    
    -- Copy some links and settings to the generic menu data, for use
    -- by commands.
    menu_data.ftable = ftable
    menu_data.columns = menu.user_settings.columns
    menu_data.frame = frame
    menu_data.mode = "standalone"

    -- Process all of the delayed commands, which depended on the above
    -- table being initialized.
    Process_Delayed_Commands()
    
    -- Apply vertical sizing and offset.
    menu.Set_Vertical_Size(menu)
    
    -- Apply frame offsets.
    -- These have to be handled after frame size is known.
    menu.Set_Frame_Offset(menu)
   
    -- Enable display of the frame.
    -- Note: this may also need to be called on the fly if later changes
    -- are made to the menu.
    -- TODO: maybe scrap this and rely on user calling Disply_Menu.
    menu.infoFrame:display()
    
end


-- Set up the main table for standalone menus.
-- TODO: consider merging this with the options menu code, though there are
-- a lot of little differences that might make it not worth the effort.
function menu.createTable(frame)

    -- Do not include frame borders in this width.
    local table_width = Helper.scaleX(menu.user_settings.width)

    -- Create a separate table, with one row/column, for the title.
    -- This needs to be separate so that the main table can scroll.
    local title_table = frame:addTable(1, { 
        -- Non-interactive.
        tabOrder = 0, 
        -- Offset x/y by the frame border.
        x = Helper.borderSize, 
        y = Helper.borderSize, 
        width = table_width, 
        -- Tabbing skips this table.
        skipTabChange = true 
        })
    -- Unselectable (first arg false).
    local row = title_table:addRow(false, { fixed = true, bgColor = Helper.color.transparent })
    row[1]:createText(menu.user_settings.title, config.headerTextProperties)
    menu_data.title_table = title_table
    
    
    -- Set up the main table.
    local ftable = frame:addTable(menu.user_settings.columns, {
        -- There is a header property, but its code is bugged in
        -- widget_fullscreen, using an undefined 'tableoffsety' in
        -- widgetSystem.setUpTable, spamming the log with errors.
        -- header = menu.user_settings.title,
        
        -- 1 sets the table as interactive.
        tabOrder = 1, 
        -- Sets cells to have a colored background.
        borderEnabled = true, 
        width = table_width,
        
        -- Offset x by the frame border, y by title height plus border.
        x = Helper.borderSize,
        y = title_table.properties.y + title_table:getVisibleHeight() + Helper.borderSize,
        
        -- Makes the table the interactive widget of the frame.
        defaultInteractiveObject = true 
    })
        
    -- Removed; no longer put a back button with title on first ftable row.
    ---- Narrow the first column, else the button is super wide.
    ---- TODO: it is still kinda oddly sized.
    ---- TODO: make button optional; not really meaningful for standalone
    ---- menus besides being an obvious way to close it.
    --ftable:setColWidth(1, config.table.arrowColumnWidth, false)
    --
    ---- TODO: change title bar handling:
    ----  a) remove back button; standard window buttons are cleaner.
    ----  b) split title bar into a separate table or widget, so that the main table can scroll.
    ----  c) make title bar optional.
    --
    ---- First row holds title.
    ---- Note: first arg needs to be '{}' instead of 'true' to avoid a ui
    ---- crash when adding a button to the first row (with log error about that
    ---- not being allowed).
    ---- TODO: make unfixed?
    --local row = ftable:addRow({}, { fixed = true, bgColor = Helper.color.transparent })
    ---- Left side will be a back button.
    ---- Sizing/fonts largely copied from ego code.
    --row[1]:createButton({ height = config.headerTextHeight }):setIcon(config.backarrow, { x = config.backarrowOffsetX })
    --row[1].handlers.onClick = function () return menu.onCloseElement("back", true) end
    ---- Make the title itself, in a header font.
    --row[2]:setColSpan(menu.user_settings.columns):createText(menu.user_settings.title, config.headerTextProperties)
        
    return ftable
end


-- Set the standalone menu height and Y offset, considering user
-- specification and contents.
function menu.Set_Vertical_Size(menu)
    -- Set height and align the frame.
    -- These are conditional on user_settings and frame contents, so do
    -- it last.
    --[[
    Scaling notes:
    
    Since height and offsetY may both be unspecified, the initial height
    setting will use a default offsetY of 0, then if there is room leftover
    the offsetY will be scaled.
    
    Borders will be added on top of user requested width/height.
    Therefore, the frame has borders, table does not.
    Initial calc will be for frame size, limited to screen borders.
    Table will follow from frame with border adjustment.
    Size of the table area will be scaled by scaleX/Y commands.
    ]]
    local table_height
    local frame_height
    local frame_offsetY
    
    -- Set initial y offset, to know how much room to reserve.
    -- In negative cases, it is offset from bottom of screen, so want
    -- the abs() value.
    if menu.user_settings.offsetY then
        frame_offsetY = math.abs(Helper.scaleY(menu.user_settings.offsetY))
    else
        -- Start at 0, and adjust further after height known.
        frame_offsetY = 0
    end
    
    -- Set initial height for the table, without borders, with scaling.
    if menu.user_settings.height then
        table_height = Helper.scaleY(menu.user_settings.height)
    else
        -- Size to fit contents.
        table_height = menu_data.ftable:getVisibleHeight()
    end
                
    -- Size the frame, capping to screen.
    frame_height = math.min(
        -- Max height to fit on screen with required offset.
        Helper.viewHeight - frame_offsetY, 
        
        -- Fit the table, its y offset (which covers the title), and borders.
        table_height + menu_data.ftable.properties.y + 2 * Helper.borderSize
        )
        
    -- Set the final table height, same as frame without borders.
    table_height = frame_height - 2 * Helper.borderSize
            
    -- Update the frame and table.
    menu.infoFrame.properties.height = frame_height
    menu_data.ftable.properties.height = table_height
end


-- Offset the frame based on user request, or default centering.
-- Treats negative offsets as being from the opposite edge of the screen.
function menu.Set_Frame_Offset(menu)
    
    local frame_x    
    if menu.user_settings.offsetX then
        -- Start with scaling, whether positive or negative.
        frame_x = Helper.scaleX(menu.user_settings.offsetX)
        -- Check negatives.
        if frame_x < 0 then
            -- Adjust to be from the edge.
            frame_x = Helper.viewWidth - menu.infoFrame.properties.width + frame_x
        end
    else
        -- Center.
        frame_x = (Helper.viewWidth - menu.infoFrame.properties.width) / 2
    end
    
    -- Do the same for Y.
    local frame_y
    if menu.user_settings.offsetY then
        frame_y = Helper.scaleY(menu.user_settings.offsetY)
        if frame_y < 0 then
            frame_y = Helper.viewHeight - menu.infoFrame.properties.height + frame_y
        end
    else
        frame_y = (Helper.viewHeight - menu.infoFrame.properties.height) / 2
    end
    
    -- Update the frame.
    menu.infoFrame.properties.x = frame_x
    menu.infoFrame.properties.y = frame_y
end


-- Function called when the 'close' button pressed.
function menu.onCloseElement(dueToClose, allowAutoMenu)
    Helper.closeMenu(menu, dueToClose, allowAutoMenu)
    menu.cleanup()
    -- Signal md.
    Raise_Signal("onCloseElement", dueToClose)
end

-- Unused function.
function menu.viewCreated(layer, ...)
end

-- Guessing this just refreshes the frame in some way.
-- Unclear on how it knows what to do to update.
function menu.onUpdate()
    menu.infoFrame:update()
end

-- Unused function.
function menu.onRowChanged(row, rowdata, uitable)
end

-- Unused function.
function menu.onSelectElement(uitable, modified, row)
end


-------------------------------------------------------------------------------
-- Interface into the ego options menu.
-- Goal is to add a new option, leading to a submenu with a list of all mods
-- that have registered their menu definition cues with this api, from which
-- the player can pick a specific mod and edit its settings.
-- This solves the question of how mod users will make their menus easily
-- accessible to the player (without relying on the key capture api or similar).

--[[
Development notes:

menu.submenuHandler(optionParameter)
    This function picks which submenu to open, based on what the player clicked
    from the main menu.  optionParameter is a string, eg. "extensions".
    This can be monkeypatched to support Simple Menu menus.
    Requires the simple menu option be in the list first.
    
    Perhaps useful: this will raise a ui event for md listeners:
    AddUITriggeredEvent(menu.name, "menu_" .. optionParameter)
    
    The top level menu appears to be opened by calling this function 
    with "main" as the parameter.
    There are many special case function calls, but a generic catchall at
    the end handles "main" by calling a generic menu builder:
        menu.displayOptions(optionParameter)
        
menu.displayOptions(optionParameter)
    Reads generic specification info from config.optionDefinitions to build
    a menu. The config table is private, so specs cannot be directly
    modified.
    
    Rows are filled out near the end just before displaying:
        
        -- options
        for optionIdx, option in ipairs(options) do
            menu.displayOption(ftable, option)
        end

        ftable:setTopRow(menu.preselectTopRow)
        menu.preselectTopRow = nil
        menu.preselectOption = nil

        frame:display()
        
    A monkeypatch could potentially call this function first to build the
    submenu, then call menu.displayOption to fill in a custom row.
    Hopefully this won't look odd to display() before the last row is
    added in.
    This approach would need a way to access the ftable from the frame from
    the menu, which is unclear on how to do, since the menu table doesn't
    store the frame or ftable explicitly.
    
    Alternatively, this function could be copied in full, with custom menus
    using the copied code, and original menus reverting to calling the
    original function (to be somewhat stable across patches).
    
    
menu.displayOption(ftable, option, numCols)
    Displays a single option in the main menu (or other menus) to open
    a submenu.
    "option" is a table defining the string to display and the
    name of the submenu.
    "numCols" is optional, and presumably for multi-col situations
    (eg. if other parts of the table are 2 columns, maybe the
    submenu options will have a 2-wide span.
        
    
Accessing frame/ftable from menu:
    Frames are added by Helper.
    gameoptions/menu.createOptionsFrame() adds the frame, 
    and makes a link in menu.optionsFrame.
    
    So, menu.optionsFrame should be sufficient to obtain the frame.
    
    From the frame, tables are added using frame:addTable. The prototype
    for this is found in helper/widgetPrototypes.frame:addTable().
    Here, the table is added to a list in frame.content.
    If the frame has multiple content entries, the table will need to be
    identified.  It is not given an "id" by gameoptions, but there should
    be just one table, and the content.type field will be "table".
    
    So, loop over frame.content for frame.content[i].type == "table" to
    find the desired table.
    
    
After having trouble getting submenus to be selected. Thoughts:

    menu.displayOption
        Called on main menu for first submenu; works correctly.
        Used in first submenu to access user submenu, does nothing on click.
    
    menu.onSelectElement(uitable, modified, row)
        Gets called on selecting the submenu item.
        Correctly called for user submenu, giving row=1, but the uitable
        does not match menu.optionTable, leading to early return.
        
    menu.viewCreated(layer, ...)
        Called from Helper.viewCreated.
        Sets menu.optionTable if the layer is config.optionsLayer.
        Different ... arg counts based on menu.currentOption, but expect
        only one arg for the general case, presumably a table.
        
    Helper.viewCreated(menu, layer, frames)
        Called from Helper.displayFrame.
        Passes children of menu.frames[layer] to menu.viewCreated.
        Implies there should only be one child of the optionsLayer for
        the menu.currentOption to get set correctly.
        
    Likely problem: first pass of the intermediate submenu patterned
    off of the 'extensions' menu, but that unpacks to three tables
    with special handling in menu.viewCreated.
    
    Solutions:
    a) Monkey patch menu.viewCreated, but eh.
    b) Only use one table.
    c) Put the table with submenu options first (assuming ordering is kept).
    
    Later observation: the title needs to be in a separate table to allow
    the main data table to be scrollable.  Monkeypatching viewCreated may
    be the only reliable way to handle this.
        
]]

-- Hook into the gameoptions menu.
function Init_Gameoptions_Link()
    -- Stop if something went wrong.
    if Menus == nil then
        error("Menus global not yet initialized")
    end
    
    -- Search the ego menu list. When this lua loads, they should all
    -- be filled in.
    for i, ego_menu in ipairs(Menus) do
        if ego_menu.name == "OptionsMenu" then
            gameoptions_menu = ego_menu
        end
    end
    
    -- Stop if something went wrong.
    if gameoptions_menu == nil then
        error("Failed to find egosoft's OptionsMenu")
    end
    
    -- Patch displayOptions.
    local original_displayOptions = gameoptions_menu.displayOptions
    gameoptions_menu.displayOptions = function (optionParameter)
    
        -- Start with the original function.
        original_displayOptions(optionParameter)
        
        -- If this is the main menu, add an extra option row.
        if optionParameter == "main" then
        
            -- Look up the frame with the table.
            -- This should be in layer 3, matching config.optionsLayer.
            local frame = gameoptions_menu.optionsFrame
            if frame == nil then
                error("Failed to find gameoptions menu main frame")
            end
            
            -- Look up the table in the frame.
            -- There is probably just the one content entry, but to be safe
            -- search content for a table.
            local ftable
            for i=1,#frame.content do
                if frame.content[i].type == "table" then
                    ftable = frame.content[i]
                end
            end
            if ftable == nil then
                error("Failed to find gameoptions menu main ftable")
            end
        
            -- Add the option.
            -- Note: this arg is column count, which defaults to 4;
            -- seems to work okay with default.
            gameoptions_menu.displayOption(ftable, {
                -- TODO: put this id/name in a global table somewhere.
                id = "simple_menu_extension_options",
                name = "Extension Options",
                submenu = "simple_menu_extension_options",
                -- TODO: maybe give a display function that turns off this
                -- entry if there are no registered user mod menus.
                -- This needs to be nil or a function.
                display = nil,
            })
            
            -- Display needs to be called again to get an updated frame drawn.
            frame:display()
        end
    end
    
    -- Helper function to determine if optionParameter refers to a custom menu.
    local Is_Custom_Menu = function (optionParameter)
        if optionParameter == "simple_menu_extension_options" or custom_menu_specs[optionParameter] ~= nil then
            return true
        end
        return false
    end
    
    -- Patch submenuHandler to catch new submenus.
    local original_submenuHandler = gameoptions_menu.submenuHandler
    gameoptions_menu.submenuHandler = function (optionParameter)
    
        -- Look for custom menus.
        if Is_Custom_Menu(optionParameter) then
            if debugger.verbose then
                DebugError("Simple_Menu_API opening submenu: "..optionParameter)
            end
            
            -- Copy a couple preliminary lines over.
            gameoptions_menu.userQuestion = nil
            AddUITriggeredEvent(gameoptions_menu.name, "menu_" .. optionParameter)
            
            if optionParameter == "simple_menu_extension_options" then
                -- Call the display function.
                Display_Extension_Options()
            else
                -- Handle integrating with user code to built the menu.
                Display_Custom_Menu(custom_menu_specs[optionParameter])
            end
        else
            -- Use the original function.
            original_submenuHandler(optionParameter)
        end
    end
    
    
    -- Patch viewCreated to properly register tables.
    local original_viewCreated = gameoptions_menu.viewCreated
    gameoptions_menu.viewCreated = function (layer, ...)
        -- Check if this is handling a custom menu.
        if Is_Custom_Menu(gameoptions_menu.currentOption) then
            if debugger.verbose then
                DebugError("Simple_Menu_API viewCreated for submenu: "..gameoptions_menu.currentOption)
            end
            -- Repeat the layer check, to be safe.
            if layer == config.optionsLayer then
                -- Will have two tables.
                gameoptions_menu.titleTable, gameoptions_menu.optionTable = ...
            end
        else
            -- Use the original function.
            original_viewCreated(layer, ...)
        end
    end
       
    
    ---- Patch menu.onSelectElement(uitable, modified, row) purely for
    ---- debug help.
    --local original_onSelectElement = gameoptions_menu.onSelectElement
    --gameoptions_menu.onSelectElement = function (uitable, modified, row)
    --    DebugError("onSelectElement triggered")
    --    
    --    row = row or Helper.currentTableRow[uitable]
    --    DebugError("onSelectElement row: "..row)
    --    if uitable == gameoptions_menu.optionTable then
    --        DebugError("onSelectElement uitable matches menu.optionTable")
    --        local option = gameoptions_menu.rowDataMap[uitable][row]
    --        DebugError("onSelectElement type(option): "..type(option))
    --    end
    --    
    --    original_onSelectElement(uitable, modified, row)
    --end
    
    -- TODO: clear some private data on menu closing.
    -- May require another monkey patch.
end
Init_Gameoptions_Link()


-- Helper function to build a shell of a menu, with back button, title,
-- and a table for adding content to, all sized appropriately.
-- 'properties' is a table with [id, title, columns].
-- Column count will be padded by 1 for the left side under-arrow column.
-- Returns the frame and ftable for custom data, with this extra padded column.
function Make_Menu_Shell(menu_spec)
    -- Convenience renaming.
    local menu = gameoptions_menu
    
    -- Remove data from the prior menu.
    Helper.clearDataForRefresh(menu, config.optionsLayer)
    menu.selectedOption = nil

    menu.currentOption = menu_spec.id

    local frame = menu.createOptionsFrame()
        
    -- Create a separate table, with one row for the title.
    -- This needs to be separate so that the main table can scroll.
    -- 2 columns, button and label.
    local title_table = frame:addTable(2, { 
        -- Unclear what this does, but setting 0 gets a scrollability error.
        tabOrder = 2,
        x = menu.table.x, 
        y = menu.table.y, 
        width = menu.table.width,
        -- Tabbing skips this table.
        skipTabChange = true 
        })
    -- Note: col widths apparently need to be set before rows are added.
    title_table:setColWidth(1, menu.table.arrowColumnWidth, false)
    
    -- Title/back button row.
    -- Must be selectable for back button to work.
    local row = title_table:addRow(true, { fixed = true, bgColor = Helper.color.transparent })
    
    -- Unclear what this does, but background span the whole thing.
    row[1]:setBackgroundColSpan(2)
    row[1]:createButton({ height = config.headerTextHeight }):setIcon(config.backarrow, { x = config.backarrowOffsetX })
    row[1].handlers.onClick = function () return menu.onCloseElement("back") end
    row[2]:createText(menu_spec.title, config.headerTextProperties)
    -- Record it, in case it is ever useful to know.
    menu_data.title_table = title_table
        
        
    -- Set up the main table.
    -- Add one column to those requested, for the arrow padding.
    local ftable = frame:addTable(menu_spec.columns + 1, { 
        -- 1 sets the table as interactive.
        tabOrder = 1, 
        
        x = menu.table.x, 
        -- Adjust the y position down, to make room for the title.
        y = title_table.properties.y + title_table:getVisibleHeight() + Helper.borderSize,
        
        width = menu.table.width, 
        maxVisibleHeight = menu.table.height,
        
        -- Makes the table the interactive widget of the frame.
        -- TODO: maybe not needed; not used in gameoptions example.
        defaultInteractiveObject = true 
        })
    -- Size the first column under the back arrow.
    ftable:setColWidth(1, menu.table.arrowColumnWidth, false)
                
    return frame, ftable
end


-- Builds the menu to display when showing the extension options submenu.
-- This will in turn list each user registered mod options menu.
-- Patterned off of code in gameoptions, specifically menu.displayExtensions().
function Display_Extension_Options()
    
    -- Clean out old menu_data.
    menu_data_reset()
    
    -- Set up the shell menu, get the fillable table.
    local frame, ftable = Make_Menu_Shell({
        id = "simple_menu_extension_options", 
        -- TODO: readtext
        title = "Extension Options", 
        -- Set to 3, so total is 4, which matches main menu.
        columns = 3 })
    
    -- Fill in all listings.
    -- Note: lua is horrible about getting the size of a table; set a flag
    -- to indicate if there were any registered menus.
    -- (The # operator only works on contiguous lists.)
    local menu_found = false
    for menu_id, spec in pairs(custom_menu_specs) do
        --DebugError("spec '"..spec.id.."' private: "..spec.private)
        -- Only display non-private menus.
        if spec.private == 0 then
            menu_found = true
            -- Add a generic selectable row to be handled like normal menus.
            gameoptions_menu.displayOption(ftable, {
                id      = spec.id,
                name    = spec.title,
                submenu = spec.id,
            })
        end
    end
    
    -- If there are no menus, note this.
    if not menu_found then
        local row = ftable:addRow(false, { bgColor = Helper.color.transparent })
        row[2]:setColSpan(3):createText("No menus registered", config.warningTextProperties)
    end
    
    frame:display()
end


-- Set up a user's option menu.
function Display_Custom_Menu(menu_spec)

    -- Clean out old menu_data.
    menu_data_reset()
    
    -- Set up the shell menu, get the fillable table.
    local frame, ftable = Make_Menu_Shell(menu_spec)
    
    -- Update local menu data for user functions.
    menu_data.frame = frame
    menu_data.ftable = ftable
    menu_data.columns = menu_spec.columns    
    menu_data.mode = "options"
    -- No delay on commands; the menu is ready right away.
    menu_data.delay_commands = false
    
    -- Signal md api so it can call the user cue which fills the menu.
    Raise_Signal("Display_Custom_Menu", menu_spec.id)
    
    -- TODO: any other special functionality needed.
    -- TODO: maybe remove this and rely on user calling Display_Menu.
    frame:display()
end


-- Run main init once everything is set up.
init()
