--[[
Lua side of the simple menu api.
Interfaces with MD script commands which will populate the menu and
capture callbacks.

Much of this was initially patterned after menu_userquestion.lua, a relative
short egosoft lua file, with various bits of gameoptions.lua copied in.

TODO: look at gameoptions around line 2341 for different widget types
and how ego makes them somewhat generic and string based.
Maybe emulate this format.
]]


-------------------------------------------------------------------------------
-- Local data tables.

-- User registered menus to show in options.
-- Keys are the menu_ids of the submenus. Entries are subtables with the
-- submenu properties (id, menu_id, name, maybe other stuff).
local custom_menu_specs = {
}

-- The table holding the menu details to be fed to egosoft code.
-- This is reused for all user menus.
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
    
    -- Width of the menu. TODO: dynamically rescale.
    width = 400,
    -- Height of menu. Maybe optional, presumably scales up with content.
    -- TODO: does width scale too?
    height = nil,
    -- ? Does this just offset the table down from the top border?
    offsetY = 300,
    -- ? Maybe a ui layer to resolve overlap? but no overlap expected.
    layer = 3,
    
    -- Number of columns in the table.
    num_columns = nil,    
    -- String title of the table.
    title = nil,
    
    -- The main frame, named to match ego code.
    infoFrame = nil,
    -- The table widget, which is the sole occupant of the frame.
    -- (Not called 'table' because that is reserved in lua.)
    ftable = nil,
    -- List of rows in the table, in order, added by user.
    -- Does not include header rows.
    user_rows = {}
}

-- Proxy for the gameoptions menu, linked further below.
-- This should be used when in options mode.
local gameoptions_menu = nil

-- Custom data of the current menu (standalone or gameoptions).
-- These get linked appropriately depending on which menu type is active.
local private = {
    -- Number of columns in the table, not including back arrow.
    num_columns = nil,
    
    -- The gui frame being displayed.
    -- frame:display() needs to be called after changes to make updates visible.
    frame = nil,
    -- The table widget, which is the sole occupant of the frame.
    -- (Not called 'table' because that is reserved in lua.)
    ftable = nil,
    -- List of rows in the table, in order, added by user.
    -- Does not include header rows.
    user_rows = {},
    
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
    private.frame = nil
    private.ftable = nil
    private.user_rows = {}
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
]]
function Validate_Args(args, arg_specs)
    -- Loop over the arg_specs list.
    for i = 1, #arg_specs do 
        local name    = arg_specs[i].n
        local default = arg_specs[i].d
        local arttype = arg_specs[i].t
        
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
        end
        
        -- Number casting.
        -- TODO: maybe round ints, but for now floats are fine.
        if arttype == "int" then
            args[name] = tonumber(args[name])
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
    elseif private.delay_commands == false then
        Process_Command(args)
    else
        table.insert(private.queued_events, args)
    end
end


-- Handle registration of user options menus.
function Handle_Register_Options_Menu(_, param)
    -- Unpack the param into a table of args.
    local args = Tabulate_Args(param)
    
    -- Validate all needed args are present.
    Validate_Args(args, {
        {n="id", t='int'},
        {n="title"}, 
        {n="columns", t='int'}
    })
    
    -- Fill in a menu_id string, since using raw small integers isn't
    -- very comfortable.
    args.menu_id = "custom_menu_"..args.id
    
    -- Record to the global table.
    custom_menu_specs[args.menu_id] = args
    
    DebugError("Registered submenu: "..args.title)
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
    while #private.queued_events ~= 0 do
        -- Process the next event.
        local args = table.remove(private.queued_events, 1)
        Process_Command(args)
    end
end

-- Generic handler for all signals.
-- They could also be split into separate functions, but this feels
-- a little cleaner.
function Process_Command(args)
    
    DebugError("Processing command: "..args.command)
    
    -- Create a new menu; does not display.
    -- TODO: does the shell of the menu display anyway?
    if args.command == "Create_Menu" then
        -- Close any currently open menu, which will also clear out old
        -- data (eg. don't want to append to old rows).
        Close_Menu()
        
        -- Clear old menu_data to be safe.
        -- TODO: standalone function for this.
        private.ftable = nil
        private.user_rows = {}
        -- Delay following commands since the menu isn't set up immediately.
        private.delay_commands = true
        
        -- Ensure needed args are present, and fill any defaults.
        Validate_Args(args, {
            {n="title", d=""}, 
            {n="columns", t='int'}
        })
        
        -- Make sure column count is a number.
        args.num_columns = tonumber(args.columns)
        -- Store the args into the menu, to be used when onShowMenu gets
        -- its delayed call.
        menu.user_settings = args
        -- TODO: remove these; old storage method.
        menu.title = args.title
        menu.num_columns = tonumber(args.columns)
        
        
        -- This function appears to be exe side.
        -- TODO: what are the args?  copying from gameoptions.lua.
        -- Will automatically call onShowMenu(), presumably.
        -- By experience, onShowMenu is called after a delay, so other
        -- md signals may be processed before then.
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
        private.frame:display()
        
    -- Add a new row.
    elseif args.command == "Add_Row" then
        -- Add one generic row.
        local new_row = private.ftable:addRow({}, { fixed = true, bgColor = Helper.color.transparent })
        -- Store in user row table for each reference.
        table.insert(private.user_rows, new_row)
    
    
    -- Various widget makers begin with 'Make'.
    elseif string.sub(args.command, 1, #"Make") == "Make" then
    
        -- Handle common args to all options.
        Validate_Args(args, {
            {n="col", t='int'},
        })
        
        -- These share some setup code.
        -- Notably, they generally require a column, and operate on the most
        -- recent row.
        -- Make sure column count is a number, and adjust right by
        -- 1 to account for the backarrow column.
        local col, user_col
        if args.col ~= nil then
            user_col = tonumber(args.col)
            col = user_col + 1
        end
        
        -- Error if no rows present yet.
        if #private.user_rows == 0 then
            error("Simple_Menu.Make_Label: no user rows for Make command")
        end
        -- Set the last row index, and pick out the row object.
        local row_index = #private.user_rows
        local row = private.user_rows[row_index]
        
    
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
                CallEventScripts("directChatMessageReceived", 
                    "Menu;Button clicked on ("..row_index..","..user_col..")")
                    
                -- Return a table of results.
                -- Note: this should not prefix with '$' like the md, but
                -- the conversion to md will add such prefixes automatically.
                -- Note: this row/col does not include title row or arrow
                -- column.
                Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = user_col
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
                CallEventScripts("directChatMessageReceived", 
                    "Menu;Text on ("..row_index..","..user_col..") changed to: "..text)
                Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = user_col,
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
                {n="start"     , t='int'},
                {n="step"      , t='int'},
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
                CallEventScripts("directChatMessageReceived", 
                    "Menu;Slider on ("..row_index..","..user_col..") changed to: "..value)
                Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = user_col,
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
                CallEventScripts("directChatMessageReceived", 
                    "Menu;Dropdown on ("..row_index..","..user_col..") changed to: "..option_id)
                Raise_Signal("Event", {
                    ["row"] = row_index,
                    ["col"] = user_col,
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
    --if private.frame ~= nil then
    --    private.frame:display()
    --end
end

function Close_Menu()
    if menu.is_open == true then
        -- Reuses the ui close function.
        menu.onCloseElement("back", true)
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
    -- Note: Helper.scaleX/Y will multiply by the ui scaling factor.
    -- TODO: work on scaling options.
    local frameProperties = {
        standardButtons = {},
        -- Scale width and pad enough for borders.
        width = Helper.scaleX(menu.width) + 2 * Helper.borderSize,

        -- Center the frame along x.
        x = (Helper.viewWidth - Helper.scaleX(menu.width)) / 2,
        -- Move the frame down some amount.
        -- TODO: redo centering to account for final expected row/col sizing.
        y = Helper.scaleY(menu.offsetY),

        layer = menu.layer,
        backgroundID = "solid",
        backgroundColor = Helper.color.semitransparent,
        startAnimation = false,
    }
    -- Create the frame object; returns its handle to be saved.
    menu.infoFrame = Helper.createFrameHandle(menu, frameProperties)

    -- Want to fill the frame with a simple table to be populated.
    -- Set (widget) table properties using a (lua) table.
    local tableProperties = {
        width = Helper.scaleX(menu.width),
        x = Helper.borderSize,
        y = Helper.borderSize,
    }
    -- Create the table as part of the frame.
    -- This function is further below, and handles populating sub-widgets.
    menu.createTable(menu.infoFrame, tableProperties)

    -- Process all of the delayed commands, which depended on the above
    -- table being initialized.
    Process_Delayed_Commands()

    -- Is this resizing the frame to fit the table?
    -- TODO: replace this with general resizing for contents, or put
    -- the burdon on the user.
    menu.infoFrame.properties.height = private.ftable.properties.y + private.ftable:getVisibleHeight() + Helper.borderSize

    -- Enable display of the frame.
    -- Note: this may also need to be called on the fly if later changes
    -- are made to the menu.
    -- TODO: maybe scrap this and rely on user calling Disply_Menu.
    menu.infoFrame:display()
    
end


-- Set up the main table.
function menu.createTable(frame, tableProperties)

    -- Add the table.
    -- This will add an extra column on the left for the back arrow, similar
    -- to ego menus.
    local ftable = frame:addTable(
        menu.num_columns + 1, { 
        tabOrder = 1, 
        borderEnabled = true, 
        width = tableProperties.width, 
        x = tableProperties.x, 
        y = tableProperties.y, 
        defaultInteractiveObject = true })
        
    private.ftable = ftable
    private.num_columns = menu.num_columns
    private.frame = frame

    -- Narrow the first column, else the button is super wide.
    -- TODO: it is still kinda oddly sized.
    -- TODO: make button optional; not really meaningful for standalone
    -- menus besides being an obvious way to close it.
    ftable:setColWidth(1, config.table.arrowColumnWidth, false)
    
    -- First row holds title.
    -- Note: first arg needs to be '{}' instead of 'true' to avoid a ui
    -- crash when adding a button to the first row (with log error about that
    -- not being allowed).
    local row = ftable:addRow({}, { fixed = true, bgColor = Helper.color.transparent })
    -- Left side will be a back button.
    -- Sizing/fonts largely copied from ego code.
    row[1]:createButton({ height = config.headerTextHeight }):setIcon(config.backarrow, { x = config.backarrowOffsetX })
    row[1].handlers.onClick = function () return menu.onCloseElement("back", true) end
    -- Make the title itself, in a header font.
    row[2]:setColSpan(menu.num_columns):createText(menu.title, config.headerTextProperties)
        
end

-- Function called when the 'close' button pressed.
function menu.onCloseElement(dueToClose, allowAutoMenu)
    Helper.closeMenu(menu, dueToClose, allowAutoMenu)
    menu.cleanup()
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
    
    -- Patch submenuHandler to catch new submenus.
    local original_submenuHandler = gameoptions_menu.submenuHandler
    gameoptions_menu.submenuHandler = function (optionParameter)
        DebugError("submenuHandler opening submenu: "..optionParameter)
        
        -- Look for custom menus.
        if optionParameter == "simple_menu_extension_options" or custom_menu_specs[optionParameter] ~= nil then
            DebugError("Simple_Menu_API opening submenu: "..optionParameter)
            
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

    -- Note: due to behavior of menu.viewCreated and other code, this
    -- will only use a single table for everything.
    -- Add one column to those requested, for the arrow padding.
    local ftable = frame:addTable(menu_spec.columns + 1, { 
        tabOrder = 1, 
        x = menu.table.x, 
        y = menu.table.y, 
        width = menu.table.width, 
        maxVisibleHeight = menu.table.height })
    -- Note: col widths apparently need to be set before rows are added.
    ftable:setColWidth(1, menu.table.arrowColumnWidth, false)
    
    -- Title/back button row.
    local row = ftable:addRow(true, { fixed = true, bgColor = Helper.color.transparent })
    -- Unclear what this does, but background span the whole thing.
    row[1]:setBackgroundColSpan(menu_spec.columns + 1)
    row[1]:createButton({ height = config.headerTextHeight }):setIcon(config.backarrow, { x = config.backarrowOffsetX })
    row[1].handlers.onClick = function () return menu.onCloseElement("back") end
    row[2]:setColSpan(menu_spec.columns):createText(menu_spec.title, config.headerTextProperties)
        
    DebugError("Frame setup")
    
    return frame, ftable
end


-- Builds the menu to display when showing the extension options submenu.
-- This will in turn list each user registered mod options menu.
-- Patterned off of code in gameoptions, specifically menu.displayExtensions().
function Display_Extension_Options()
    DebugError("Making extension options menu")
    
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
        menu_found = true
        -- Add a generic selectable row to be handled like normal menus.
        gameoptions_menu.displayOption(ftable, {
            id      = spec.menu_id,
            name    = spec.title,
            submenu = spec.menu_id,
        })
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
    DebugError("Making custom menu")
    
    -- Set up the shell menu, get the fillable table.
    local frame, ftable = Make_Menu_Shell(menu_spec)
    
    -- Update local menu data for user functions.
    private.frame = frame
    private.ftable = ftable
    private.user_rows = {}
    private.num_columns = menu_spec.columns
    -- No delay on commands; the menu is ready right away.
    private.delay_commands = false
    
    -- Testing a couple faked md commands, to see if they draw correctly.
    -- Handle_Process_Command("", "$command,Add_Row")
    -- Handle_Process_Command("", "$col,1;$command,Make_Label;$mouseover,Type of widget being tested;$text,Type")
    -- Handle_Process_Command("", "$col,2;$command,Make_Label;$mouseover,Interractable widget;$text,Widget")
        
    DebugError("Signalling MD")
    
    -- Signal md api so it can call the user cue which fills the menu.
    -- This will use the integer id, so md can treat it as a list index.
    Raise_Signal("Display_Custom_Menu", menu_spec.id)
    
    -- TODO: any other special functionality needed.
    -- TODO: maybe remove this and rely on user calling Display_Menu.
    frame:display()
end


-- Run main init once everything is set up.
init()
