--[[
    Methods specific to the standalone menu.
]]

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

-- Custom defaults, generally patterened off code in gameoptions.
menu.custom_widget_defaults = {
    -- Don't use text overrides like the options menu; user may want
    -- the smaller default fonts.
    
    ["table"] = {        
        -- 1 sets the table as interactive.
        tabOrder = 1, 
        -- Turn on wraparound.
        wraparound = true,
        },

    -- Center button labels.
    ["button"] = {text = {halign = "center"}},

    -- Blank row backgrounds.
    ["row"] = { bgColor = Helper.color.transparent },
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
    -- TODO: try to avoid GoToSlide errors by putting a 1-frame delay
    --  here if a menu was opened and needed closing; maybe the backend
    --  just can't start a new menu on the same frame as closing an old one.
    menu.Close()
            
    -- Delay following commands since the menu isn't set up immediately.
    menu_data.delay_commands = true

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


-- TODO: this doesn't work completely, and debuglog gets a bunch of
-- "GotoSlide" error messages if opening a new menu while one is
-- already open, which don't occur if manually closing a menu before
-- reopening.
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
-- TODO: integrate into onCloseElement.
function menu.cleanup()
    menu.is_open = false
    menu.infoFrame = nil
    menu.user_settings = nil

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
    -- Signal md api with a general event for a menu opening.
    Lib.Raise_Signal("Event", {type='menu', event='onOpen'})

    -- Bounce over to the frame maker.
    menu.create()
end

-- Set up the menu.
function menu.create()
    -- Safety data clear, to get rid of any prior frame data.
    Helper.clearDataForRefresh(menu, config.optionsLayer)
    
    -- TODO: is this useful?
    --Helper.clearFrame(menu, config.optionsLayer)

    -- Handle frame creation.
    menu.createFrame()

    -- Create the table as part of the frame.
    -- This function is further below, and handles populating sub-widgets.
    local ftable = menu.createTable(menu.infoFrame)
    
    -- Copy some links and settings to the generic menu data, for use
    -- by commands.
    -- TODO: do this smarter; eg. use these directly at initial assignments.
    menu_data.ftable = ftable
    menu_data.columns = menu.user_settings.columns
    menu_data.frame = menu.infoFrame
    menu_data.mode = "standalone"
    menu_data.custom_widget_defaults = menu.custom_widget_defaults
    menu_data.col_adjust = 0

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
    --[[
        Notes on creating a standalone frame (non-menu):
        
        The helper frame:display() function does some table assembly, and
        ends up calling CreateFrame (global function). It then registers
        that frame with viewhelper's global View object. It also closes
        other menus.

        The standalone chatwindow does not use helper.lua, and instead
        uses CreateFrame directly and registers with View.

        Note: commands in chatwindow and widget_fullscreen suggest the
        layers are limited to 1-6, with menus having to share layers.
        The chat window is on 6, with notes about moving it to 2 to
        join something debug related.
        If creating standalone frames, layer selection may be tricky,
        but can try to match 6 (presumably that will put it on top).

        For a standalone frame, instead of using frame:display(), copy
        that function's contents but modify it to no longer close 
        any open menus, and maybe do that same with the callbacks used
        by CreateFrame for when a frame is shown or removed (also
        may be a lot of copy/paste).
    ]]
        
    -- Stop delaying commands now that menu is ready.
    menu_data.delay_commands = false
end


-- Create a main frame.
-- Sticks it in menu.infoFrame.
function menu.createFrame()
    -- Extract any supported frame properties from the user args.
    local properties
    if menu.user_settings.frame then
        properties = Lib.Filter_Table(menu.user_settings.frame, widget_properties["frame"])
    else
        properties = {}
    end

    -- Fix any bools that md gave as ints.
    Lib.Fix_Bool_Args(properties, widget_defaults["frame"])

    -- Apply local defaults.
    Lib.Fill_Defaults(properties, {
        layer = config.optionsLayer,
        backgroundID = "solid",
        backgroundColor = Helper.color.semitransparent,
        startAnimation = false,
        })
        
    Lib.Table_Update(properties, {
        -- Manually handle width scaling.
        -- Note: width and X offset are known here; height and Y offset are
        -- computed later based on contents.
        -- Calculate horizontal sizing/position.
        -- Scale width and pad enough for borders.
        width = Helper.scaleX(menu.user_settings.width) + 2 * Helper.borderSize,
    })
        
    -- Create the frame object; returns its handle to be saved.
    menu.infoFrame = Helper.createFrameHandle(menu, properties)
end


-- Set up the main table for standalone menus.
-- TODO: consider merging this with the options menu code, though there are
-- a lot of little differences that might make it not worth the effort.
function menu.createTable(frame)

    -- TODO: make title optional.
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
    -- Extract any supported table properties from the user args.
    local properties
    if menu.user_settings.table then
        properties = Lib.Filter_Table(menu.user_settings.table, widget_properties["table"])
    else
        properties = {}
    end

    -- Fix any bools that md gave as ints.
    Lib.Fix_Bool_Args(properties, widget_defaults["table"])

    -- Apply local defaults.
    Lib.Fill_Defaults(properties, menu.custom_widget_defaults["table"])

    -- Apply local overrides.
    Lib.Table_Update(properties, {
        width = table_width,
        
        -- Offset x by the frame border, y by title height plus border.
        x = Helper.borderSize,
        y = title_table.properties.y + title_table:getVisibleHeight() + Helper.borderSize,        
        })

    -- Make the actual table.
    local ftable = frame:addTable(menu.user_settings.columns, properties)
        
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


------------------------------------------------------------------------------
-- Menu event handlers, signalled by backend.
-- Note: table row/col/element events are handled in Interface, which
-- plugs its own functions into the local menu.

-- Function called when the menu is closed for any reason.
-- dueToClose is one of ["close", "back", "minimize"].
function menu.onCloseElement(dueToClose, allowAutoMenu)
    -- Note: allowAutoMenu appears to lead to code that opens a new menu
    -- automatically if the player is in a ship, either dockedmenu or
    -- toplevelmenu.  Can ignore.
    -- TODO: support for "back", which will cause Helper to try to open
    -- another menu possibly stored in menu.param2 somehow.
    Helper.closeMenu(menu, dueToClose)
    menu.cleanup()

    -- Signal md. Use similar format to widget events.
    -- Custom field will be "reason" for the closure.
    Lib.Raise_Signal("Event", {
        type = 'menu',
        event = 'onCloseElement',
        reason = dueToClose,
        })
end

-- This appears to be called when the first frame is added to the menu.
-- No use currently.
--function menu.viewCreated(layer, ...)
--end

-- This is a general update function called with some regularity.
-- Currently not expected to have much effect, though may be useful if
-- every supplying functions as some widget args, which will be used
-- to trigger updates.
function menu.onUpdate()
    menu.infoFrame:update()
end



Init()

return menu