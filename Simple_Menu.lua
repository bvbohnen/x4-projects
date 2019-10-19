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

-- The table holding the menu details to be fed to egosoft code.
local menu = {
    -- Flag, true when the menu is known to be open.
    -- May false positive depending on how the menu was closed?
    is_open = false,

    -- Name of the menu used in registration. Should be unique.
    name = "SimpleMenu",
    -- How often the menu refreshes?
    updateInterval = 0.1,
    
    -- Width of the menu. TODO: dynamically rescale.
    width = 400,
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


-- Misc private data.
local private = {
    -- Since menus are created after a delay, md signalled events that
    -- fill out the menu will be queued up until the menu is ready.
    queued_events = {}
}

-- Clean out stored references after menu closes, to release memory.
function menu.cleanup()
    menu.is_open = false
    menu.infoFrame = nil
    menu.ftable = nil
    menu.user_rows = {}
end

-- Forward function declarations.
local Handle_Open_Menu
local Handle_Add_Row
local Handle_Make_Label


local function init()

    -- MD triggered events.
    RegisterEvent("Simple_Menu.Process_Command", Handle_Process_Command)
    
    -- Register menu; uses its name.
    Menus = Menus or {}
    table.insert(Menus, menu)
    if Helper then
        Helper.registerMenu(menu)
    end
end


-------------------------------------------------------------------------------
-- MD to lua event handling.

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

-- Handle validation of arguments, filling in defaults.
-- 'args' is a table with the named user provided arguments.
-- 'arg_specs' is a list of sublists of [name, default].
-- If a name is missing from user args, the default is added to 'args'.
--  If the default is the "nil" string, nothing is added.
--  If the default is nil in this case, it is treated as non-optional and an
--  error is thrown.
function Validate_Args(args, arg_specs)
    -- Loop over the arg_specs list.
    for i = 1, #arg_specs do 
        local name    = arg_specs[i][1]
        local default = arg_specs[i][2]
        
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
    end
end


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
    else
        table.insert(private.queued_events, args)
    end
end

-- Signalling results from lua to md.
-- Takes the row,col of the activated widget, and an optional new value
-- for that widget.
-- TODO: think about this more.
function Raise_Signal(name, row, col, value)
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
    
    -- Create a new menu; does not display.
    -- TODO: does the shell of the menu display anyway?
    if args.command == "Create_Menu" then
        -- Close any currently open menu, which will also clear out old
        -- data (eg. don't want to append to old rows).
        Close_Menu()
        
        -- Ensure needed args are present, and fill any defaults.
        Validate_Args(args, {
            {"title", ""}, 
            {"columns"}
        })
        
        -- Store the args into the menu, to be used when onShowMenu gets
        -- its delayed call.
        menu.title = args.title
        -- Make sure column count is a number.
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
    
    elseif args.command == "Add_Row" then
        -- Add one generic row.
        local new_row = menu.ftable:addRow({}, { fixed = true, bgColor = Helper.color.transparent })
        -- Store in user row table for each reference.
        table.insert(menu.user_rows, new_row)
    
    
    -- Various widget makers begin with 'Make'.
    elseif string.sub(args.command, 1, #"Make") == "Make" then
    
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
        if #menu.user_rows == 0 then
            error("Simple_Menu.Make_Label: no user rows for Make command")
        end
        -- Set the last row index, and pick out the row object.
        local row_index = #menu.user_rows
        local row = menu.user_rows[row_index]
    
        if args.command == "Make_Label" then
            Validate_Args(args, {
                {"col"}, 
                {"text"},
                {"mouseover",""}
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
                {"col"}, 
                {"text"}
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
                AddUITriggeredEvent("Simple_Menu", "Event", {
                    ["row"] = row_index,
                    ["col"] = user_col
                    })
            end
            
        
        -- Editable text boxes.
        elseif args.command == "Make_EditBox" then
            Validate_Args(args, {
                {"col"}, 
                {"text",""}
            })
            row[col]:createEditBox():setText(args.text, config.standardTextProperties)
            
            -- Capture changed text.
            row[col].handlers.onTextChanged = function(_, text) 
                CallEventScripts("directChatMessageReceived", 
                    "Menu;Text on ("..row_index..","..user_col..") changed to: "..text)
                AddUITriggeredEvent("Simple_Menu", "Event", {
                    ["row"] = row_index,
                    ["col"] = user_col,
                    ["text"] = text,
                    })
                end
                
        
        -- Sliders for picking a value in a range.
        elseif args.command == "Make_Slider" then
            Validate_Args(args, {
                {"col"}, 
                {"min"},
                {"minSelect","nil"},
                {"max"},
                {"maxSelect","nil"},
                {"start"},
                {"step"},
                {"suffix",""}
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
                AddUITriggeredEvent("Simple_Menu", "Event", {
                    ["row"] = row_index,
                    ["col"] = user_col,
                    ["value"] = value,
                    })
                end
                
        
        -- Dropdown menu of options.
        elseif args.command == "Make_Dropdown" then
            Validate_Args(args, {
                {"col"}, 
                {"options"},
                {"start","nil"},
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
                AddUITriggeredEvent("Simple_Menu", "Event", {
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
    -- Set table properties using a table.
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
    menu.infoFrame.properties.height = menu.ftable.properties.y + menu.ftable:getVisibleHeight() + Helper.borderSize

    -- Enable display of the frame.
    menu.infoFrame:display()
end


-- Set up the main table.
function menu.createTable(frame, tableProperties)

    -- Add the table.
    -- This will add an extra column on the left for the back arrow, similar
    -- to ego menus.
    menu.ftable = frame:addTable(
        menu.num_columns + 1, { 
        tabOrder = 1, 
        borderEnabled = true, 
        width = tableProperties.width, 
        x = tableProperties.x, 
        y = tableProperties.y, 
        defaultInteractiveObject = true })

    -- Narrow the first column, else the button is super wide.
    menu.ftable:setColWidth(1, config.table.arrowColumnWidth, false)
    
    -- First row holds title.
    -- Note: first arg needs to be '{}' instead of 'true' to avoid a ui
    -- crash when adding a button to the first row (with log error about that
    -- not being allowed).
    local row = menu.ftable:addRow({}, { fixed = true, bgColor = Helper.color.transparent })
    -- Left side will be a back button.
    -- Sizing/fonts largely copied from ego code.
    row[1]:createButton({ height = config.headerTextHeight }):setIcon(config.backarrow, { x = config.backarrowOffsetX })
    row[1].handlers.onClick = function () return menu.onCloseElement("back", true) end
    -- Make the title itself, in a header font.
    row[2]:setColSpan(menu.num_columns):createText(menu.title, config.headerTextProperties)
        
    -- Add a blank line, across all columns.
    -- TODO: is this what creates the horizontal line?  Probably not.
    -- local row = menu.ftable:addRow(true, { fixed = true, bgColor = Helper.color.transparent })
    -- row[1]:setColSpan(menu.num_columns):createText("")

    -- Final row will have a couple buttons.
    -- First button confirms; second closes.
    -- local row = menu.ftable:addRow(true, { fixed = true, bgColor = Helper.color.transparent })
    -- row[2]:createButton():setText(ReadText(1001, 2821), { halign = "center" })
    -- row[2].handlers.onClick = menu.confirm
    -- row[4]:createButton():setText(ReadText(1001, 64), { halign = "center" })
    -- row[4].handlers.onClick = function () return menu.onCloseElement("back", true) end

    return
end

-- Confirm button was pushed.
function menu.confirm()
    -- Just close for now.
    menu.onCloseElement("close")
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

-- Run init once everything is set up.
init()
