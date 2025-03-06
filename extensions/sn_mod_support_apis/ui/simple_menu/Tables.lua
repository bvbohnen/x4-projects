Lua_Loader.define("extensions.sn_mod_support_apis.lua.simple_menu.Tables",function(require)
--[[
Container for data tables, shared by other active modules.
]]

-- Import library functions, to help with table setup.
local Lib = require("extensions.sn_mod_support_apis.lua.simple_menu.Library")

local T = {}

T.debugger = {
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
T.custom_menu_specs = {
}

-- Custom data of the current menu (standalone or gameoptions).
-- These get linked appropriately depending on which menu type is active.
T.menu_data = {
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

    -- Table of default widget properties to apply on top of the generic
    -- ones below.
    -- This will generally be set initially when setting menu mode, and
    -- possibly updated based on user commands.
    custom_widget_defaults = nil
}

-- Reset any menu data to a clean state.
-- For safety, call this when opening a new menu, protecting against cases
-- where a prior attempted menu errored out with leftover queued commands
-- or similar.
function T.menu_data:reset()
    self.frame = nil
    self.ftable = nil
    self.title_table = nil
    self.user_rows = {}
    self.queued_events = {}
    self.mode = nil
end


-- General config, copied from ego code (gameoptions.lua).
-- Commenting out unused fields for clarity.
T.config = {
	--contextLayer = 2,
	optionsLayer = 4,
	--topLevelLayer = 5,
    
	backarrow = "table_arrow_inv_left",
	backarrowOffsetX = 3,
    
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
    
	--idleTime = 10,
    --
	--saveReloadInterval = 60,
    --
	--hubFadeOutTime = 2,
	--hubFadeOutHoldDuration = 0.1,
    --
	--numRecommendedGamestarts = 2,
    --
	--minGamestartInfoRows = 8,
}

-- Convenience renaming.
local config = T.config

--config.table = {
--    x = 45,
--    y = 45,
--    width = 710,
--	widthExtraWide = 1130,
--	widthWithExtraInfo = 370,
--	height = 980,
--	arrowColumnWidth = 20,
--	infoColumnWidth = 330,
--}
---- Copied from ego menu for fonts.
config.headerTextProperties = {
    font = config.fontBold,
    fontsize = config.headerFontSize,
    x = config.headerTextOffsetX,
    y = 6,
    minRowHeight = config.headerTextHeight,
    titleColor = Color["row_title"],
}
config.subHeaderTextProperties = {
    font = config.fontBold,
    fontsize = config.standardFontSize,
    x = config.standardTextOffsetX,
    y = 2,
    minRowHeight = config.subHeaderTextHeight,
    halign = "center",
    titleColor = Color["row_title"],
}
config.infoTextProperties = {
    font = config.font,
    fontsize = config.infoFontSize,
    x = config.infoTextOffsetX,
    y = 2,
    wordwrap = true,
    minRowHeight = config.infoTextHeight,
    titleColor = Color["row_title"],
}
config.standardTextProperties = {
    font = config.font,
    fontsize = config.standardFontSize,
    x = config.standardTextOffsetX,
    y = 2,
}
-- Custom subheader punched up a bit (used by hotkey api).
-- Basically Header with center alignment.
config.subHeaderTextProperties_2 = {
    font = config.fontBold,
    fontsize = config.headerFontSize,
    x = config.headerTextOffsetX,
    y = 6,
    minRowHeight = config.headerTextHeight,
    halign = "center",
    titleColor = Color["row_title"],
}


-- Tables that will hold just the property names of the widgets,
-- used for filtering user args.
-- Autofilled based on default's keys.
T.widget_properties = {}


-- TODO: split between stock defaults and applied defaults, since applying
-- stock defaults to widgets can override some stuff with widgets inheriting
-- from row properties.


-- Default properties for each widget, from helper.
--[[
    Note: cell inherits from widget, various standalone widgets from cell.
    These are largely copied from helper.lua defaultWidgetProperties,
    which is local.
    While bothersome, this needs to specify which properties are bools,
    since md->lua is janky and makes md bools into lua 0/1, causing problems.
    Library code will do proper bool conversion based on these contents.
    
    Helper.lua defines some table fields that don't have intentional
    defaults. It uses this term to represent them, and gives them a
    'false' bool value, though they don't represent bools.
    Some helper logic uses checks against this to know if a term wasn't
    given, eg. for slider minSelect.
    In the local menus, typing of bools is important for handling md
    transfers.
    So, the approach used here will be:
        - Still use propertyDefaultValue, but set to "nil".
        - Never apply top level defaults to property tables; let the backend
          fill them in.
]]
local propertyDefaultValue = "nil"

-- Note: to remove api support for a property, comment it out.
T.widget_defaults = {
    ["widget"] = {
        scaling = true,
        width = 0,
        height = 0,
        x = 0,
        y = 0,
        mouseOverText = ""
    },
    ["frame"] = {
        -- Layer is fixed.
        --layer = 4,
        -- No notable effect with only one table to use.
        --exclusiveInteractions = false,

        -- Removed in 7.0:
        --backgroundID = "",
        --backgroundColor = Color.text_normal,
        --overlayID = "",
        ---- Bugged; overlay icon uses backgroundColor instead.
        ---- Can leave for now; may get fixed.
        --overlayColor = Color.text_normal,

        standardButtons = Helper.standardButtons_CloseBack,
        standardButtonX = 0,
        standardButtonY = 0,
        showBrackets = false,
        -- TODO: toy around with this.
        -- For now, height computed manually, but this might do the same thing.
        --autoFrameHeight = false,
        closeOnUnhandledClick = false,
        playerControls = false,
        -- Does this do anything?  No animations noticed. Not really
        -- used in stock menus.
        -- Disable for now.
        --startAnimation = true,
        enableDefaultInteractions = true,
        -- Disallow miniwidgets; they appear to be limited to 2 rows
        -- in widget_fullscreen.
        --useMiniWidgetSystem = false,
        keepHUDVisible = false,
        keepCrosshairVisible = false,
        showTickerPermanently = false,
        -- Don't allow fiddling with widget level stuff.
        --_basetype = "widget"
    },
    ["rendertarget"] = {
        alpha = 100,
        clear = true,
        startnoise = false,
        _basetype = "widget"
    },
    ["table"] = {
        -- There is a header property, but its code is bugged in
        -- widget_fullscreen, using an undefined 'tableoffsety' in
        -- widgetSystem.setUpTable, spamming the log with errors.
        -- header = "",

        -- This is actually flipped to 1 in the custom menu defaults.
        -- Remove; user probably never needs to set to 0.
        --tabOrder = 0,

        -- Remove; only one table, so there is no tab support for moving
        -- between tables anyway.
        --skipTabChange = false,

        -- Removed; no apparent affect, the single table is always
        -- selected.
        --defaultInteractiveObject = false,

        -- Allow this to change; if false cells move closer together,
        -- though player cannot click to select other rows.
        borderEnabled = true,
        -- No height limit; stretch to menu/frame size.
        --maxVisibleHeight = 0,
        -- This had no clear affect on menu layout.
        reserveScrollBar = true,
        -- Set true in custom defaults.
        wraparound = false,
        highlightMode = "on",
        multiSelect = false,
        backgroundID = "",
        backgroundColor = Color.table_background_default,
        -- Unused; just one table.
        --prevTable = 0,
        --nextTable = 0,
        -- Don't allow fiddling with widget level stuff.
        --_basetype = "widget"
    },
    ["row"] = {
        scaling = true,
        fixed = false,
        borderBelow = true,
        interactive = true,
        bgColor = Color.row_background,
        multiSelected = false
    },
    
    ["cell"] = {
        cellBGColor = Color.row_background,
        uiTriggerID = propertyDefaultValue,
        _basetype = "widget"
    },
    ["text"] = {
        text = "",
        halign = Helper.standardHalignment,
        color = Color.text_normal,
        glowfactor = Color.text_normal.glow,
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
        color = Color.icon_normal,
        glowfactor = Color.icon_normal.glow,
        _basetype = "cell"
    },
    ["button"] = {
        active = true,
        bgColor = Color.button_background_default,
        highlightColor = Color.button_highlight_default,
        height = Helper.standardButtonHeight,
        _basetype = "cell"
    },
    ["editbox"] = {
        bgColor = Color.editbox_background_default,
        closeMenuOnBack = false,
        defaultText = "",
        description = "",
        textHidden = false,
        encrypted = false,
        selectTextOnActivation = true,
        active = true,
        restoreInteractiveObject = false,
        maxChars = 50,
        _basetype = "cell"
    },
    ["shieldhullbar"] = {
        shield = 0,
        hull = 0,
        glowfactor = Color.icon_normal.glow,
        _basetype = "cell"
    },
    ["graph"] = {		
        graphdesc = propertyDefaultValue,
        bgColor = Color.graph_background,
        _basetype = "cell"
    },
    ["slidercell"] = {
        bgColor = Color.slider_background_default,
        inactiveBGColor = Color.slider_background_inactive,
        valueColor = Color.slider_value,
        posValueColor = Color.slider_diff_pos,
        negValueColor = Color.slider_diff_neg,
        min = 0,
        minSelect = propertyDefaultValue,
        max = 0,
        maxSelect = propertyDefaultValue,
        start = 0,
        step = 1,
        accuracyOverride = propertyDefaultValue,
        infiniteValue = 0,
        suffix = "",
        exceedMaxValue = false,
        hideMaxValue = false,
        rightToLeft = false,
        fromCenter = false,
        readOnly = false,
        forceArrows = false,
        useInfiniteValue = false,
        useTimeFormat = false,
        _basetype = "cell"
    },
    ["dropdown"] = {
        options = {},
        startOption = "",
        active = true,
        bgColor = Color.dropdown_background_default,
        highlightColor = Color.dropdown_highlight_default,
        optionColor = Color.dropdown_background_options,
        optionWidth = 0,
        optionHeight = 0,
        allowMouseOverInteraction = false,
        textOverride = "",
        text2Override = "",
        _basetype = "cell"
    },
    ["checkbox"] = {
        checked = false,
        bgColor = Color.checkbox_background_default,
        active = true,
        symbol = "circle",
        glowfactor = Color.icon_normal.glow,
        _basetype = "cell"
    },
    ["statusbar"] = {
        current = 0,
        start = 0,
        max = 0,
        valueColor = Color.statusbar_value_default,
        posChangeColor = Color.statusbar_diff_pos_default,
        negChangeColor = Color.statusbar_diff_neg_default,
        markerColor = Color.statusbar_marker_default,
        titleColor = propertyDefaultValue,
        _basetype = "cell"
    },
    ["boxtext"] = {
        text = "",
        halign = Helper.standardHalignment,
        color = Color.text_normal,
        boxColor = Color.boxtext_box_default,
        font = Helper.standardFont,
        fontsize = Helper.standardFontSize,
        wordwrap = false,
        textX = Helper.standardTextOffsetx,
        textY = Helper.standardTextOffsety,
        minRowHeight = Helper.standardTextHeight,
        glowfactor = Color.text_normal.glow,
        _basetype = "cell"
    },
    
    ["flowchart"] = {
        tabOrder = 0,
        skipTabChange = false,
        defaultInteractiveObject = false,
        borderHeight = 0,
        borderColor = Color.flowchart_border_default,
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
        expandedFrameNumTables = 1,
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
        bgColor = Color.flowchart_node_background,
        outlineColor = Color.flowchart_node_default,
        valueColor = Color.flowchart_value_default,
        slider1Color = Color.flowchart_slider_value1,
        slider2Color = Color.flowchart_slider_value2,
        diff1Color = Color.flowchart_slider_diff1,
        diff2Color = Color.flowchart_slider_diff2,
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
        color = Color.flowchart_edge_default,
        sourceSlotColor = propertyDefaultValue,
        sourceSlotRank = 1,
        destSlotColor = propertyDefaultValue,
        destSlotRank = 1,
        _basetype = "widget"
    },
}

-- For any widget field that is a subtable, need to know the defaults.
--[[
    Note: the Helper backend doesn't understand how to apply defaults for
    complex widget properties, eg. nested T.
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
        color = Color.text_normal,
        glowfactor = Color.text_normal.glow,
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
        color = Color.icon_normal,
        glowfactor = Color.icon_normal.glow,
        scaling = true,
    },
    hotkeyproperty = {
        hotkey = "",
        displayIcon = false,
        x = 0,
        y = 0,
    },
	frametextureproperty = {
		icon = "",
		color = Color["frame_background_default"],
		width = 0,
		height = 0,
		rotationRate = 0,
		rotationStart = 0,
		rotationDuration = 0,
		rotationInterval = 0,
		initialScaleFactor = 1,
		scaleDuration = 0,
		glowfactor = Color["frame_background_default"].glow,
	},
}
-- Copied from Helper, fields in each widget that are a subtable/complex.
local complexCellProperties = {
	["frame"] = {
		background =	"frametextureproperty",
		background2 =	"frametextureproperty",
		overlay =		"frametextureproperty",
	},
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
    for widget, subtable in pairs(complexCellProperties) do
        -- Work through the fields.
        for field, propname in pairs(subtable) do
            -- Shwllow copy the default table.
            -- (Lua has no easy way to do this, so do it ugly.)
            T.widget_defaults[widget][field] = {}
            for subfield, default in pairs(complexCell_defaults[propname]) do
                T.widget_defaults[widget][field][subfield] = default
            end
        end
    end

    -- Fill out inheritances, recursively as needed.
    local function Fill_Inheritances(itable)
        -- Check for a parent.
        if itable._basetype then
            local parent = T.widget_defaults[itable._basetype]
            -- If the parent still has a basetype, it needs to be visited first.
            if parent._basetype then
                Fill_Inheritances(parent)
            end
            -- Copy over the parent fields.
            for field, default in pairs(parent) do
                itable[field] = default
            end
            -- Clear out the link; no longer needed.
            itable._basetype = nil
        end
    end
    -- Kick it off for all widgets.
    -- Note: tables don't retain order, which is why the recursive function
    -- is used to be robust against whatever visitation ordering is used.
    for widget, subtable in pairs(T.widget_defaults) do
        Fill_Inheritances(subtable)
    end

    -- Apply custom defaults.
    -- TODO: rethink this; favor dynamic defaults.
    --Lib.Table_Update(T.widget_defaults, widget_default_overrides)

    -- Fill in the property list.
    for widget_name, subtable in pairs(T.widget_defaults) do
        T.widget_properties[widget_name] = {}
        for k,v in pairs(subtable) do
            table.insert(T.widget_properties[widget_name], k)
        end
    end
    
end

-- Export tables.
return T,Widget_Init
end)
