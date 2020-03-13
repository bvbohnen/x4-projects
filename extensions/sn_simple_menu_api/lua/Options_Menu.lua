
--[[ 
Interface into the ego options menu.

Goal is to add a new option, leading to a submenu with a list of all mods
that have registered their menu definition cues with this api, from which
the player can pick a specific mod and edit its settings.

This solves the question of how mod users will make their menus easily
accessible to the player (without relying on the hotkey api or similar).

TODO: hooks to modify stock menu parameters of interest.
    - menu.valueGameUIScale, menu.callbackGameUIScaleReset()
      for higher scaling (above 1.5)
    - menu.valueGfxAA to unlock higher ssaa (probably not useful)

]]


-- Import config and widget_properties tables.
local Tables = require("extensions.sn_simple_menu_api.lua.Tables")
local widget_properties = Tables.widget_properties
local widget_defaults   = Tables.widget_defaults
local config            = Tables.config
local menu_data         = Tables.menu_data
local debugger          = Tables.debugger
local custom_menu_specs = Tables.custom_menu_specs


-- Import library functions for strings and tables.
local Lib = require("extensions.sn_simple_menu_api.lua.Library")

-- Container for local functions that will be exported.
local menu = {}

-- Custom defaults, generally patterned off code in gameoptions.
menu.custom_widget_defaults = {
    ["table"] = {        
        -- 1 sets the table as interactive.
        tabOrder = 1,
        -- Turn on wraparound.
        wraparound = true,
        },

    ["text"] = config.standardTextProperties,
    ["boxtext"] = config.standardTextProperties,

    -- Center button labels.  Note: a lot of options put this back to left
    -- aligned, so maybe this isn't the best default.
    --["button"] = {text = {halign = "center"}},

    ["exitbox"] = {text = config.standardTextProperties},
    
    -- Blank row backgrounds. Extra handy for the backarrow column.
    ["row"] = { bgColor = Helper.color.transparent },
    
    -- Defaults that match what ego does with setDefaultCellProperties.
    -- Ego's approach updates metatables, but doesn't work when the user
    -- wants to provide one fields of a complex subtable (by experience).
    ["button"] = {
        height = config.standardTextHeight,
        text = { 
            x = config.standardTextOffsetX, 
            fontsize = config.standardFontSize },
        },

    ["dropdown"] = {
        height = config.standardTextHeight,
        text = { 
            x = config.standardTextOffsetX, 
            fontsize = config.standardFontSize },
        },

    ["slidercell"] = {
        height = config.standardTextHeight,
        text = { 
            x = config.standardTextOffsetX, 
            fontsize = config.standardFontSize },

        -- Changes color to match the options menu default.
        valueColor = config.sliderCellValueColor,
        -- Options menu hides maxes, from example looked at.
        hideMaxValue = true,
        },

}


-- Proxy for the gameoptions menu, linked further below.
-- This should be used when in options mode.
local gameoptions_menu = nil

-- Hook into the gameoptions menu.
local function Init_Gameoptions_Link()
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
    
    
        -- Record the last selected row.
        -- The ego function overwrites this, so need to presave
        -- to if wanting to restore it later.
        local preselectTopRow = gameoptions_menu.preselectTopRow
        local preselectOption = gameoptions_menu.preselectOption
        --DebugError(tostring(preselectTopRow))
        --DebugError(tostring(preselectOption))
        
        -- Intercept the frame creation to suppress its frame:display
        -- temporarily.
        -- See the hotkey api for further comments on why.
        local ego_createOptionsFrame = gameoptions_menu.createOptionsFrame
        -- Store the frame and its display function.
        local frame
        local frame_display
        gameoptions_menu.createOptionsFrame = function(...)
            -- Build the frame.
            frame = ego_createOptionsFrame(...)
            -- Record its display function.
            frame_display = frame.display
            -- Replace it with a dummy.
            frame.display = function() return end
            -- Return the edited frame to displayControls.
            return frame
            end

        
        -- Call the standard function.
        original_displayOptions(optionParameter)
        
        -- Reconnect the createOptionsFrame function, to avoid impacting
        -- other menu pages.
        gameoptions_menu.createOptionsFrame = ego_createOptionsFrame

        -- If this is the main menu, add an extra option row.
        if optionParameter == "main" then
        
            -- -Removed; frame captured above.
            ---- Look up the frame with the table.
            ---- This should be in layer 3, matching config.optionsLayer.
            --local frame = gameoptions_menu.optionsFrame
            --if frame == nil then
            --    error("Failed to find gameoptions menu main frame")
            --end
            
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

            -- The above was appended to the menu rows. For cleanliness,
            -- reposition the entry to be by Extensions.
            -- TODO: this changes the default menu option from Exit to
            --  custom options; how to restore back to exit?
            -- Do a search for the extensions row index, and target one after.
            local last_index = #ftable.rows
            local target_index = last_index
            for i = 1, last_index do
                if ftable.rows[i].rowdata and ftable.rows[i].rowdata.id == "extensions" then
                    target_index = i + 1
                    break
                end
            end

            -- Pick out the new options row and move it.
            local custom_row = table.remove(ftable.rows, last_index)
            table.insert(ftable.rows, target_index, custom_row)
            -- Rows are annotated with their index; fix those annotations here.
            for i = target_index, last_index do
                ftable.rows[i].index = i
            end

            -- Fix the row selection.
            -- The preselectOption should match the id of the desired row.
            for i = 1, #ftable.rows do
                if ftable.rows[i].rowdata and ftable.rows[i].rowdata.id == preselectOption then
                    ftable:setSelectedRow(ftable.rows[i].index)
                    break
                end
            end


            -- Do an adjustment here
            local menu_selected_row = ftable.selectedrow

            -- Call preselectTopRow again, since the ego code originally
            -- called this just after it added all table rows.
            -- (In pracice, this might not matter much if it just deals with
            -- scroll bar position, as the main menu isn't big enough to
            -- scroll.)
            ftable:setTopRow(preselectTopRow)

            -- Default to selecting row 1 if no preselectOption is available.
            -- (May not have much effect if preselectOption is reliable.)
            if preselectOption == nil then
                ftable:setSelectedRow(1)
            end
            
            -- -Removed; display done smarter now.
            -- Display needs to be called again to get an updated frame drawn.
            -- Clear scripts for safety, though got no warnings when
            -- skipping this, likely due to main menu just looking for row
            -- selection and having no active widgets.
            -- TODO: replace this with the new method that suppresses the
            -- original frame:display temporarily.
            --Helper.removeAllWidgetScripts(menu, config.optionsLayer)
            --frame:display()
        end
        
        -- Re-attach the original frame display, and call it.
        frame.display = frame_display
        frame:display()
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
            
            -- This field is normally updated in the next function called
            -- by submenuHandler, but doing it here for convenience.
            gameoptions_menu.currentOption = optionParameter

            if optionParameter == "simple_menu_extension_options" then
                -- Call the display function.
                menu.Display_Extension_Options()
            else
                -- Handle integrating with user code to built the menu.
                menu.Display_Custom_Menu(custom_menu_specs[optionParameter])
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
                -- Note: optionTable gets used by calls to refresh().
                gameoptions_menu.titleTable, gameoptions_menu.optionTable = ...
            end
        else
            -- Use the original function.
            original_viewCreated(layer, ...)
        end
    end

    -- Patch some event handlers to call the local handlers as well.
    for i, name in ipairs({
            "onRowChanged", 
            "onColChanged", 
            "onSelectElement", 
            }) do
        -- The interface module will hook up its own functions to the local
        -- menu table.  Set the gameoptions_menu to conditionally call those
        -- in the local table if they exist.
        local orig_func = gameoptions_menu[name]
        gameoptions_menu[name] = function(...)
            -- This fires on all events for any options menu.
            -- Check if this is handling a custom menu.
            -- Can ignore if it is the main index; it has no special
            -- callback handling.
            if custom_menu_specs[gameoptions_menu.currentOption] ~= nil then
                if menu[name] then
                    menu[name](...)
                end
            end
            -- Always call the original, since it still has functionality
            -- when in player menus (eg. selecting submenus).
            if orig_func then
                orig_func(...)
            end
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

-- Run the above immediately.
Init_Gameoptions_Link()

-- Register a custom options submenu provided by user.
function menu.Register_Options_Menu(args)
    -- Verify the id appears unique, at least among registered submenus.
    if custom_menu_specs[args.id] then
        error("Submenu id conflicts with prior registered id: "..args.id)
    end
    
    -- Record to the global table.
    custom_menu_specs[args.id] = args
    
    if debugger.verbose then
        DebugError("Registered submenu: "..args.id)
    end
end

-- Add a generic selectable row to be handled like normal menus.
function menu.Add_Submenu_Link(args)
    -- Last arg is the column count; the line will be set to span all
    -- columns after the first (implicitly skipping the backarrow column).
    gameoptions_menu.displayOption(menu_data.ftable, {
        id      = args.id,
        name    = args.text,
        submenu = args.id,
    }, menu_data.columns + 1)
end

-- Refresh the menu by clearing its contents and rebuilding it, but
-- with no change in options menu depth.
function menu.Refresh()
    -- Store the selected row/col.
    -- (Ego code does something slightly different, with rowdata.)
    -- The Helper functions require the integer table id, which was
    -- recorded into optionTable.
    menu_data.currentTableRow = Helper.currentTableRow[gameoptions_menu.optionTable]
    menu_data.currentTableCol = Helper.currentTableCol[gameoptions_menu.optionTable]
    -- Use the existing refresh method.
    gameoptions_menu.refresh()
end


-- Helper function to build a shell of a menu, with back button, title,
-- and a table for adding content to, all sized appropriately.
-- 'properties' is a table with [id, title, columns].
-- Column count will be padded by 1 for the left side under-arrow column.
-- Returns the frame and ftable for custom data, with this extra padded column.
function menu.Make_Menu_Shell(menu_spec)
    -- Convenience renaming. TODO: maybe switch back; originally this was
    -- to reuse/tweak ego code.
    local custom_menu = menu
    local menu = gameoptions_menu
    
    -- Remove data from the prior menu.
    Helper.clearDataForRefresh(menu, config.optionsLayer)
    menu.selectedOption = nil

    menu.currentOption = menu_spec.id
    
    -- Note: this does not support generic user args for frame setup;
    -- it will match the options menu default behavior.
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
    -- Extract any supported table properties from the user args.
    local properties
    if menu_spec.table then
        properties = Lib.Filter_Table(menu_spec.table, widget_properties["table"])
    else
        properties = {}
    end
    -- Fix any bools that md gave as ints.
    Lib.Fix_Bool_Args(properties, widget_defaults["table"])

    -- Fill local defaults.
    Lib.Fill_Defaults(properties, custom_menu.custom_widget_defaults["table"])
            
    -- Apply local overrides.
    Lib.Table_Update(properties, {
        x = menu.table.x, 
        -- Adjust the y position down, to make room for the title.
        y = title_table.properties.y + title_table:getVisibleHeight() + Helper.borderSize,
        
        width = menu.table.width, 
        maxVisibleHeight = menu.table.height,     
        })

    -- Add one column to those requested, for the arrow padding.
    local ftable = frame:addTable(menu_spec.columns + 1, properties)

    -- Size the first column under the back arrow.
    ftable:setColWidth(1, menu.table.arrowColumnWidth, false)

    -- Note: don't set cell defaults the way ego does it, since it gets
    -- confusing with their defaults being metatables, but not being
    -- robust with regard to complex properties (where a user cannot
    -- just given one field of the subtable, and needs all filled in).

    return frame, ftable
end


-- Builds the menu to display when showing the extension options submenu.
-- This will in turn list each user registered mod options menu.
-- Patterned off of code in gameoptions, specifically menu.displayExtensions().
-- TODO: replace this with a standard md-declared menu for code reuse
-- and to enable more features (eg. row select callbacks).
function menu.Display_Extension_Options()
    
    -- Clean out old menu_data.
    menu_data:reset()
    
    -- Set up the shell menu, get the fillable table.
    local num_cols = 2
    local frame, ftable = menu.Make_Menu_Shell({
        id = "simple_menu_extension_options", 
        -- TODO: readtext
        title = "Extension Options", 
        -- Set to 2, to sync with the extra options that will get
        -- appended after the submenu list.
        columns = num_cols })

    -- Sort the submenus by title.
    -- Do this by building a new table of them keyed by their titles,
    -- then use lua sort.
    local title_menu_specs = {}
    for menu_id, spec in pairs(custom_menu_specs) do
        title_menu_specs[spec.title] = spec
    end
    -- Sort it.
    table.sort(title_menu_specs)
        
    -- Fill in all listings.
    -- Note: lua is horrible about getting the size of a table; set a flag
    -- to indicate if there were any registered menus.
    -- (The # operator only works on contiguous lists.)
    local menu_found = false
    for title, spec in pairs(title_menu_specs) do
        --DebugError("spec '"..spec.id.."' private: "..spec.private)
        -- Only display non-private menus.
        if not spec.private then
            menu_found = true
            -- Add a generic selectable row to be handled like normal menus.
            gameoptions_menu.displayOption(ftable, {
                id      = spec.id,
                name    = spec.title,
                submenu = spec.id,
            }, num_cols + 1)
        end
    end
    
    -- Merge the simple options into this layer, if available.
    local menu_spec = custom_menu_specs["simple_menu_options"]
    if menu_spec ~= nil then
        menu.Display_Custom_Menu_PostShell(menu_spec, frame, ftable)
    else
        -- If there are no menus, note this.
        if not menu_found then
            local row = ftable:addRow(false, { bgColor = Helper.color.transparent })
            row[2]:setColSpan(num_cols):createText("No menus registered", config.warningTextProperties)
        end
        frame:display()
    end
end


-- Set up a user's option menu.
function menu.Display_Custom_Menu(menu_spec)

    -- Clean out old menu_data.
    menu_data:reset()
    
    -- Set up the shell menu, get the fillable table.
    local frame, ftable = menu.Make_Menu_Shell(menu_spec)

    -- Hand off to the rest of the logic for filling.
    menu.Display_Custom_Menu_PostShell(menu_spec, frame, ftable)
end

-- Shared logic between the top level menu and custom submenus.
function menu.Display_Custom_Menu_PostShell(menu_spec, frame, ftable)
    -- Update local menu data for user functions.
    menu_data.frame = frame
    menu_data.ftable = ftable
    menu_data.columns = menu_spec.columns    
    menu_data.mode = "options"
    menu_data.custom_widget_defaults = menu.custom_widget_defaults
    menu_data.col_adjust = 1
    -- No delay on commands; the menu is ready right away.
    menu_data.delay_commands = false
    
    -- Signal md api with a general event for a menu opening; this is to
    -- match standalone menu behavior, and switches the menu page (does
    -- not call the user onOpen cue).
    Lib.Raise_Signal("Event", {type='menu', event='onOpen'})
    
    -- Signal md api so it can call the user cue which fills the menu.
    Lib.Raise_Signal("Display_Custom_Menu", menu_spec.id)
    
    -- To allow users to make widgets without having to say when to
    -- display the menu, an automated 1-frame delayed display() can
    -- be used.
    SetScript("onUpdate", menu.Handle_Delayed_Display)
    -- Record the start time of the delay, otherwise the onUpdate may
    -- happen in this frame before widgets are set up.
    menu.opened_time = GetCurRealTime()
end

function menu.Handle_Delayed_Display()
    -- Make sure a frame has passed.
    if menu.opened_time == GetCurRealTime() then return end

    --DebugError("Handle_Delayed_Display called")

    -- Stop listening to updates.
    RemoveScript("onUpdate", menu.Handle_Delayed_Display)

    -- In testing, a user that sets up the options menu onOpen event to
    -- create a standalone menu caused some confusion here.
    -- This case can be detected by the ftable having been cleared when
    -- the options menu was force closed. (Why this works is unclear;
    -- perhaps the log error was due to something else?)
    if not menu_data.ftable then return end
        
    -- A couple options menu cleanup steps, related to support
    -- for going back a level and reselecting the prior row.
    -- Guess: this sets the vertical scroll point when scrolled down.
    -- In testing, preselectTopRow is nil and scrolling is still retained,
    -- so unclear what this is doing.
    menu_data.ftable:setTopRow(gameoptions_menu.preselectTopRow)
    gameoptions_menu.preselectTopRow = nil
    -- TODO: maybe do something with this, from ego code holding rowdata.
    gameoptions_menu.preselectOption = nil

    -- For refreshes, restore the row/col selection.
    -- (Ego code defaults to 0 for these calls.)
    -- DebugError("currentTableRow: "..tostring(currentTableRow))
    -- DebugError("currentTableCol: "..tostring(currentTableCol))
    if menu_data.currentTableRow then
        menu_data.ftable:setSelectedRow(menu_data.currentTableRow)
        menu_data.currentTableRow = nil
    end
    if menu_data.currentTableCol then
        menu_data.ftable:setSelectedCol(menu_data.currentTableCol)
        menu_data.currentTableCol = nil
    end
        
    
    -- Do the final display call.
    menu_data.frame:display()
end


return menu




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