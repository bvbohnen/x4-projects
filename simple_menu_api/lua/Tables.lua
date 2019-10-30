--[[
Container for data tables, shared by other active modules.
]]

local tables = {}

tables.debugger = {
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
tables.custom_menu_specs = {
}

-- Custom data of the current menu (standalone or gameoptions).
-- These get linked appropriately depending on which menu type is active.
tables.menu_data = {
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

    -- Adjustment to apply to user supplied column numbers, to get
    -- the real col.
    -- Expected to be 1 for options, 0 for standalone.
    col_adjust = nil,
    
    -- Flag, if incoming commands (other than creating/closing tables)
    -- need to be delayed. True for standalone menus, false for options
    -- menus.
    delay_commands = false,
    -- Queue for the above delays.
    queued_events = {},
    
    -- Queue of arg tables sent from md, consumed as commands are processed.
    queued_args = {},
}

-- Reset any menu data to a clean state.
-- For safety, call this when opening a new menu, protecting against cases
-- where a prior attempted menu errored out with leftover queued commands
-- or similar.
function tables.menu_data:reset()
    self.frame = nil
    self.ftable = nil
    self.title_table = nil
    self.user_rows = {}
    self.queued_events = {}
    self.mode = nil
end


-- General config, copied from ego code; may not all be used.
tables.config = {
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

-- Convenience renaming.
local config = tables.config

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


-- Tables that will hold just the property names of the widgets,
-- used for filtering user args.
-- Autofilled based on default's keys.
tables.widget_properties = {}


-- Default properties for each widget.
-- Note: cell inherits from widget, various standalone widgets from cell.
-- These are largely copied from helper.lua defaultWidgetProperties,
--  which is local.
-- While bothersome, this needs to specify which properties are bools,
-- since md->lua is janky and makes md bools into lua 0/1, causing problems.
-- Library code will do proper bool conversion based on these contents.
tables.widget_defaults = {
    ["widget"] = {		
        scaling = true,											
        width = 0,												
        height = 0,												
        x = 0,													
        y = 0,													
        mouseOverText = ""										
    },
    ["frame"] = {
        layer = 3,												
        exclusiveInteractions = false,							
        backgroundID = "",										
        backgroundColor = Helper.color.white,					
        overlayID = "",											
        overlayColor = Helper.color.white,						
        standardButtons = Helper.standardButtons_CloseBack,		
        standardButtonX = 0,									
        standardButtonY = 0,									
        showBrackets = false,									
        autoFrameHeight = false,								
        closeOnUnhandledClick = false,							
        playerControls = false,									
        startAnimation = true,									
        enableDefaultInteractions = true,						
        useMiniWidgetSystem = false,							
        _basetype = "widget"
    },
    ["rendertarget"] = {
        alpha = 100,											
        _basetype = "widget"
    },
    ["table"] = {
        header = "",											
        tabOrder = 0,											
        skipTabChange = false,									
        defaultInteractiveObject = false,						
        borderEnabled = true,									
        maxVisibleHeight = 0,									
        reserveScrollBar = true,								
        wraparound = false,										
        highlightMode = "on",									
        multiSelect = false,									
        backgroundID = "",										
        backgroundColor = Helper.color.white,					
        prevTable = 0,											
        nextTable = 0,											
        _basetype = "widget"
    },
    ["row"] = {
        scaling = true,											
        fixed = false,											
        borderBelow = true,										
        bgColor = Helper.defaultSimpleBackgroundColor,			
        multiSelected = false									
    },
    
    ["cell"] = {
        cellBGColor = Helper.defaultSimpleBackgroundColor,		
        uiTriggerID = propertyDefaultValue,						
        _basetype = "widget"
    },
    ["text"] = {
        text = "",												
        halign = Helper.standardHalignment,						
        color = Helper.standardColor,							
        titleColor = propertyDefaultValue,						
        font = Helper.standardFont,								
        fontsize = Helper.standardFontSize,						
        wordwrap = false,										
        x = Helper.standardTextOffsetx,							
        y = Helper.standardTextOffsety,							
        minRowHeight = Helper.standardTextHeight,				
        _basetype = "cell"
    },
    ["icon"] = {
        icon = "",												
        color = Helper.standardColor,							
        _basetype = "cell"
    },
    ["button"] = {
        active = true,											
        bgColor = Helper.defaultButtonBackgroundColor,			
        highlightColor = Helper.defaultButtonHighlightColor,	
        height = Helper.standardButtonHeight,					
        _basetype = "cell"
    },
    ["editbox"] = {
        bgColor = Helper.defaultEditBoxBackgroundColor,			
        closeMenuOnBack = false,								
        defaultText = "",
        textHidden = false,										
        encrypted = false,										
        _basetype = "cell"
    },
    ["shieldhullbar"] = {
        shield = 0,
        hull = 0,
        _basetype = "cell"
    },
    ["graph"] = {		
        graphdesc = propertyDefaultValue,
        _basetype = "cell"
    },
    ["slidercell"] = {
        bgColor = Helper.defaultSliderCellBackgroundColor,			
        valueColor = Helper.defaultSliderCellValueColor,			
        posValueColor = Helper.defaultSliderCellPositiveValueColor,	
        negValueColor = Helper.defaultSliderCellNegativeValueColor,	
        min = 0,													
        minSelect = propertyDefaultValue,							
        max = 0,													
        maxSelect = propertyDefaultValue,							
        start = 0,													
        step = 1,													
        infiniteValue = 0,											
        suffix = "",												
        exceedMaxValue = false,										
        hideMaxValue = false,										
        rightToLeft = false,										
        fromCenter = false,											
        readOnly = false,											
        useInfiniteValue = false,									
        useTimeFormat = false,										
        _basetype = "cell"
    },
    ["dropdown"] = {
        options = {},
        startOption = "",
        active = true,
        bgColor = Helper.defaultButtonBackgroundColor,
        highlightColor = Helper.defaultButtonHighlightColor,
        optionColor = Helper.color.black,
        optionWidth = 0,
        optionHeight = 0,
        allowMouseOverInteraction = false,
        textOverride = "",
        text2Override = "",
        _basetype = "cell"
    },
    ["checkbox"] = {
        checked = false,
        bgColor = Helper.defaultCheckBoxBackgroundColor,
        active = true,
        _basetype = "cell"
    },
    ["statusbar"] = {
        current = 0,
        start = 0,
        max = 0,
        valueColor = Helper.defaultStatusBarValueColor,
        posChangeColor = Helper.defaultStatusBarPosChangeColor,
        negChangeColor = Helper.defaultStatusBarNegChangeColor,
        markerColor = Helper.defaultStatusBarMarkerColor,
        _basetype = "cell"
    },
    ["boxtext"] = {
        text = "",												
        halign = Helper.standardHalignment,						
        color = Helper.standardColor,							
        boxColor = Helper.defaultBoxTextBoxColor,				
        font = Helper.standardFont,								
        fontsize = Helper.standardFontSize,						
        wordwrap = false,										
        textX = Helper.standardTextOffsetx,						
        textY = Helper.standardTextOffsety,						
        minRowHeight = Helper.standardTextHeight,				
        _basetype = "cell"
    },
    
    ["flowchart"] = {
        tabOrder = 0,											
        skipTabChange = false,									
        defaultInteractiveObject = false,						
        borderHeight = 0,										
        borderColor = Helper.color.transparent,					
        maxVisibleHeight = 0,									
        minRowHeight = 0,										
        minColWidth = 0,										
        edgeWidth = 1,											
        firstVisibleRow = 1,									
        firstVisibleCol = 1,									
        selectedRow = 1,										
        selectedCol = 1,										
        _basetype = "widget"
    },
    ["flowchartcell"] = {
        _basetype = "widget"
    },
    ["flowchartnode"] = {
        height = Helper.standardFlowchartNodeHeight,			
        shape = "rectangle",									
        expandedFrameLayer = 0,									
        expandedTableNumColumns = 0,							
        value = 0,												
        max = 0,												
        slider1 = -1,											
        slider2 = -1,											
        step = 0,												
        connectorSize = Helper.standardFlowchartConnectorSize,	
        statusColor = propertyDefaultValue,						
        statusBgIconID = "",									
        statusBgIconRotating = false,							
        bgColor = Helper.defaultFlowchartBackgroundColor,		
        outlineColor = Helper.defaultFlowchartOutlineColor,		
        valueColor = Helper.defaultFlowchartValueColor,			
        slider1Color = Helper.defaultFlowchartSlider1Color,		
        slider2Color = Helper.defaultFlowchartSlider2Color,		
        diff1Color = Helper.defaultFlowchartDiff1Color,			
        diff2Color = Helper.defaultFlowchartDiff2Color,			
        slider1MouseOverText = "",								
        slider2MouseOverText = "",								
        _basetype = "flowchartcell"
    },
    ["flowchartjunction"] = {
        
        
        junctionXOff = -1,										
        junctionSize = Helper.standardFlowchartConnectorSize,	
        _basetype = "flowchartcell"
    },
    ["flowchartedge"] = {
        color = Helper.standardColor,							
        sourceSlotColor = propertyDefaultValue,					
        sourceSlotSecondary = false,							
        destSlotColor = propertyDefaultValue,					
        destSlotSecondary = false,								
        _basetype = "widget"
    },
}

-- For any widget field that is a subtable, need to know the defaults.
--[[
    Note: the Helper backend doesn't understand how to apply defaults for
    complex widget properties, eg. nested tables.
    For example, if a user wants to change button text through text.text,
    the backend will see the rest of the textproperties as empty and give
    an error on nil fontsize.
    So, these custom widget defaults will need to copy/paste over the ego
    defaults for any nested tables, so that a local function can fill them
    appropriately.
]]
local complexCell_defaults = {
    textproperty = {
        text = "",
        x = 0,
        y = 0,
        halign = Helper.standardHalignment,
        color = Helper.standardColor,
        font = Helper.standardFont,
        fontsize = Helper.standardFontSize,
        scaling = true,
    },
    iconproperty = {
        icon = "",
        swapicon = "",
        width = 0,
        height = 0,
        x = 0,
        y = 0,
        color = Helper.standardColor,
        scaling = true,
    },
    hotkeyproperty = {
        hotkey = "",
        displayIcon = false,
        x = 0,
        y = 0,
    },
}
-- Copied from Helper, fields in each widget that are a subtable/complex.
local complexCellProperties = {
    ["icon"] = {
        text =			"textproperty",
        text2 =			"textproperty"
    },
    ["button"] = {
        text =			"textproperty",
        text2 =			"textproperty",
        icon =			"iconproperty",
        icon2 =			"iconproperty",
        hotkey =		"hotkeyproperty"
    },
    ["editbox"] = {
        text =			"textproperty",
        hotkey =		"hotkeyproperty"
    },
    ["slidercell"] = {
        text =			"textproperty"
    },
    ["dropdown"] = {
        text =			"textproperty",
        text2 =			"textproperty",
        icon =			"iconproperty",
        hotkey =		"hotkeyproperty"
    },
    ["flowchartnode"] = {
        text =			"textproperty",
        statustext =	"textproperty",
        statusicon =	"iconproperty",
    },
}


local function Widget_Init()

    -- Fill out complex defaults.
    for name, subtable in pairs(complexCellProperties) do
        -- Work through the fields.
        for k, v in pairs(subtable) do
            -- Shwllow copy the default table.
            -- (Lua has no easy way to do this, so do it ugly.)
            tables.widget_defaults[name][k] = {}
            for k2, v2 in pairs(complexCell_defaults[v]) do
                tables.widget_defaults[name][k][k2] = v2
            end
        end
    end

    -- Fill out inheritances, recursively as needed.
    local function Fill_Inheritances(prop_list)
        -- Check for a parent.
        if prop_list._basetype then
            local parent = tables.widget_defaults[prop_list._basetype]
            -- If the parent still has a basetype, it needs to be visited first.
            if parent._basetype then
                Fill_Inheritances(parent)
            end
            -- Loop over the list part of the parent.
            for i, field in ipairs(parent) do
                table.insert(prop_list, field)
            end
            -- Clear out the link; no longer needed.
            prop_list._basetype = nil
        end
    end
    -- Kick it off for all widgets.
    -- Note: tables don't retain order, which is why the recursive function
    -- is used to be robust against whatever visitation ordering is used.
    for widget, prop_list in pairs(tables.widget_defaults) do
        Fill_Inheritances(prop_list)
    end

    -- Fill in the property list.
    for widget_name, subtable in pairs(tables.widget_defaults) do
        tables.widget_properties[widget_name] = {}
        for k,v in pairs(subtable) do
            table.insert(tables.widget_properties[widget_name], k)
        end
    end
    
end
Widget_Init()

-- Export tables.
return tables