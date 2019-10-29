--[[
    Methods specific to the standalone menu.
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
    defaults = {
        columns = 5,
        width   = 400,
    },
    
    -- The main frame, named to match ego code.
    -- TODO: naming probably not important.
    infoFrame = nil,

    -- Function to call when a menu is ready to process commands.
    -- The Interface will link this to its matching function.
    Process_Delayed_Commands = nil,
}

local function Init()
    -- Register menu; uses its name.
    Menus = Menus or {}
    table.insert(Menus, menu)
    if Helper then
        Helper.registerMenu(menu)
    end
end


function menu.Open(args)
    -- Close any currently open menu, which will also clear out old
    -- data (eg. don't want to append to old rows).
    menu.Close()
            
    -- Delay following commands since the menu isn't set up immediately.
    menu_data.delay_commands = true

    -- TODO: validate args for column count; for now use a default.

    -- Fill in default args.
    Lib.Fill_Defaults(args, menu.defaults)

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
end


function menu.Close()
    -- Clear old menu_data to be safe.
    menu_data:reset()

    if menu.is_open == true then
        -- Reuses the ui close function.
        menu.onCloseElement("close", true)
        menu.is_open = false
    end
end


-- Clean out stored references after menu closes, to release memory.
-- Unclear on if this is called automatically ever.
function menu.cleanup()
    menu.is_open = false
    menu.infoFrame = nil
    -- Reset menu_data as well. This is somewhat redundant with reset
    -- on opening a new menu, but should let garbage collection run
    -- sooner when the current menu closed properly.
    menu_data:reset()
end


-- It is unclear on which of these may be implicitly called by the
-- gui backend, so naming is generally left as-is.
-- These are implicitly local since menu is local.

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
    menu.Process_Delayed_Commands()
    
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
    -- Unselectable (first arg nil/false).
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
    Lib.Raise_Signal("onCloseElement", dueToClose)
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


Init()

return menu