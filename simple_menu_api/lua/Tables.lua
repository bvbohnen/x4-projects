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

-- Custom defaults.
-- These should be applied before the generic widget default filler
-- tables, found further below.
-- TODO: in the current setup, defaults set further below are likely to
-- get entered into this table; consider if this should be prevented.
config.standardButtonProperties = {
    text = {
        halign = "center",
    },
}


-- Widget property names.
-- These are defined in helper.lua defaultWidgetProperties, but it is local,
-- so names are redefined here.
-- Note: cell inherits from widget, various standalone widgets from cell.
tables.widget_properties = {
    widget = {
        "scaling",
        "width",
        "height",
        "x",
        "y",
        "mouseOverText",
    },
    cell = {
        "cellBGColor",
        "uiTriggerID",
        _basetype = "widget",
    },
    text = {
        "text",
        "halign",
        "color",
        "titleColor",
        "font",
        "fontsize",
        "wordwrap",
        "minRowHeight",
        _basetype = "cell",
    },    
    button = {
        "active",
        "bgColor",
        "highlightColor",
        "height",
        "text",
        "text2",
        "icon",
        "icon2",
        "hotkey",
        _basetype = "cell"
    },
    editbox = {
        "bgColor",
        "closeMenuOnBack",
        "defaultText",
        "textHidden",
        "encrypted",
        "text",
        "hotkey",
        _basetype = "cell"
    },
    icon = {
        "icon",
        "color",
        "text",
        "text2",
        _basetype = "cell"
    },
    shieldhullbar = {
        "shield",
        "hull",
        _basetype = "cell"
    },
    slidercell = {
        "bgColor",
        "valueColor",
        "posValueColor",
        "negValueColor",
        "min",
        "minSelect",
        "max",
        "maxSelect",
        "start",
        "step",
        "infiniteValue",
        "suffix",
        "exceedMaxValue",
        "hideMaxValue",
        "rightToLeft",
        "fromCenter",
        "readOnly",
        "useInfiniteValue",
        "useTimeFormat",
        "text",
        _basetype = "cell"
    },
    dropdown = {
        "options",
        "startOption",
        "active",
        "bgColor",
        "highlightColor",
        "optionColor",
        "optionWidth",
        "optionHeight",
        "allowMouseOverInteraction",
        "textOverride",
        "text2Override",
        "text",
        "text2",
        "icon",
        "hotkey",
        _basetype = "cell"
    },
    checkbox = {
        "checked",
        "bgColor",
        "active",
        _basetype = "cell"
    },
    -- TODO: others
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

-- Table, keyed by widget name, holding necessary default subtable values.
-- Filled in below.
tables.widget_defaults = {}

local function Init()

    -- Fill out defaults.
    for name, subtable in pairs(complexCellProperties) do
        -- Init an entry.
        tables.widget_defaults[name] = {}
        -- Work through the fields.
        for k, v in pairs(subtable) do
            -- Set a reference to the default table.
            tables.widget_defaults[name][k] = complexCell_defaults[v]
        end
    end

    -- Fill out inheritances, recursively as needed.
    local function Fill_Inheritances(prop_list)
        -- Check for a parent.
        if prop_list._basetype then
            local parent = tables.widget_properties[prop_list._basetype]
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
    for widget, prop_list in pairs(tables.widget_properties) do
        Fill_Inheritances(prop_list)
    end
end
Init()

-- Export tables.
return tables