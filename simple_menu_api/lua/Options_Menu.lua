
--[[ 
Interface into the ego options menu.

Goal is to add a new option, leading to a submenu with a list of all mods
that have registered their menu definition cues with this api, from which
the player can pick a specific mod and edit its settings.

This solves the question of how mod users will make their menus easily
accessible to the player (without relying on the key capture api or similar).

TODO: hooks to modify stock menu parameters of interest.
    - menu.valueGameUIScale, menu.callbackGameUIScaleReset()
      for higher scaling (above 1.5)
    - menu.valueGfxAA to unlock higher ssaa (probably not useful)

TODO: set up player facing option to remove some menu animation delays.
]]

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

-- Import config and widget_properties tables.
local Tables = require("extensions.simple_menu_api.lua.Tables")
local widget_properties = Tables.widget_properties
local config            = Tables.config
local menu_data         = Tables.menu_data
local debugger          = Tables.debugger
local custom_menu_specs = Tables.custom_menu_specs


-- Import library functions for strings and tables.
local Lib = require("extensions.simple_menu_api.lua.Library")

-- Container for local functions that will be exported.
local menu = {}


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

-- Run the above immediately.
Init_Gameoptions_Link()


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


-- Helper function to build a shell of a menu, with back button, title,
-- and a table for adding content to, all sized appropriately.
-- 'properties' is a table with [id, title, columns].
-- Column count will be padded by 1 for the left side under-arrow column.
-- Returns the frame and ftable for custom data, with this extra padded column.
function menu.Make_Menu_Shell(menu_spec)
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

    -- Set widget defaults that match gameoptions.
    ftable:setDefaultCellProperties("button",                    { height = config.standardTextHeight })
    ftable:setDefaultComplexCellProperties("button", "text",     { x = config.standardTextOffsetX, fontsize = config.standardFontSize })
    ftable:setDefaultCellProperties("dropdown",                  { height = config.standardTextHeight })
    ftable:setDefaultComplexCellProperties("dropdown", "text",   { x = config.standardTextOffsetX, fontsize = config.standardFontSize })
    ftable:setDefaultCellProperties("slidercell",                { height = config.standardTextHeight })
    ftable:setDefaultComplexCellProperties("slidercell", "text", { x = config.standardTextOffsetX, fontsize = config.standardFontSize })
                
    return frame, ftable
end


-- Builds the menu to display when showing the extension options submenu.
-- This will in turn list each user registered mod options menu.
-- Patterned off of code in gameoptions, specifically menu.displayExtensions().
function menu.Display_Extension_Options()
    
    -- Clean out old menu_data.
    menu_data:reset()
    
    -- Set up the shell menu, get the fillable table.
    local frame, ftable = menu.Make_Menu_Shell({
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
function menu.Display_Custom_Menu(menu_spec)

    -- Clean out old menu_data.
    menu_data:reset()
    
    -- Set up the shell menu, get the fillable table.
    local frame, ftable = menu.Make_Menu_Shell(menu_spec)
    
    -- Update local menu data for user functions.
    menu_data.frame = frame
    menu_data.ftable = ftable
    menu_data.columns = menu_spec.columns    
    menu_data.mode = "options"
    menu_data.col_adjust = 1
    -- No delay on commands; the menu is ready right away.
    menu_data.delay_commands = false
    
    -- Signal md api so it can call the user cue which fills the menu.
    Lib.Raise_Signal("Display_Custom_Menu", menu_spec.id)
    
    -- TODO: any other special functionality needed.
    -- TODO: maybe remove this and rely on user calling Display_Menu.
    frame:display()
end


return menu