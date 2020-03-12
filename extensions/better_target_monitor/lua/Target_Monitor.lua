
------------------------------------------------------------------------------
--[[
    The high level of the monitor is handled in monitors.lua.
    Specific details on what text is displayed are handled in targetmonitor.lua.

    The GetTargetMonitorDetails function handles selection of which text
    to show on which rows. By wrappint it, text can be modified.

    Note: the display only has room for 7 rows, so some things may need
    to be pruned or otherwise mucked with. There is a lot of vertical
    space, so maybe some sort of compression. The left side is often
    just labels, so perhaps use it for data instead.

    The GetTargetMonitorDetails call returns a table with:
    [text]             : List holding the text data
        [left]         : Table for left side of display
            [text]     : String
            [color]    : color table ({ r = 127, g = 195, b = 255 })
            [font]     : font string ("Zekton")
            [fontsize] : int, 22
        [right]        : Table for right side of display, as above.
    [other stuff]

    The text is processed to not go over 700 width, and strings
    truncated to fit without overlapping each other, with the left
    side text getting priority (right side omitted if out of room).
    In practice, only half the room appears to be used, if that.

    Ships use up all 7 lines:
    - info unlock % (or pilot name for player ships)
    - command
    - action
    - hull (%)
    - shield (%)
    - storage (x/y)
    - crew (#)

    Note: many of the terms are initially given as keywords between $,
    eg. $bla$. These are parsed later by GetLiveData, also a global function.
    If adding new keywords, can wrap GetLiveData to handle them.


TODO:
    Faction colors:
        Use this to look up the color of a faction in general:
            GetFactionData(faction, "color")
        If wanting to insert this into a text string, can use:
            Helper.convertColorToText(color_table)
]]

-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef uint64_t UniverseID;
    typedef struct {
        const char* name;
        float hull;
        float shield;
        int speed;
        bool hasShield;
    } ComponentDetails;
    typedef struct {
        const float x;
        const float y;
        const float z;
        const float yaw;
        const float pitch;
        const float roll;
    } UIPosRot;
    typedef struct {
        const char* factionID;
        const char* factionName;
        const char* factionIcon;
    } FactionDetails;
    const char* GetLocalizedText(const uint32_t pageid, uint32_t textid, const char*const defaultvalue);
    const char* GetCompSlotPlayerActionTriggeredConnection(UniverseID componentid, const char* connectionname);
    ComponentDetails GetComponentDetails(const UniverseID componentid, const char*const connectionname);
    UIPosRot GetPlayerTargetOffset(void);
    UniverseID GetPlayerID(void);
    UniverseID GetPlayerOccupiedShipID(void);
    UIPosRot GetObjectPositionInSector(UniverseID objectid);
    const char* GetMacroClass(const char* macroname);
    FactionDetails GetOwnerDetails(UniverseID componentid);
    float GetTextWidth(const char*const text, const char*const fontname, const float fontsize);
]]

-- TODO: maybe remove dependency on the existing lib, if wanting to
-- support this without simple meny api installed.
--local Lib = require("extensions.simple_menu_api.lua.Library")

-- Table of locals.
local L = {
    -- Control settings. Generally these can be changed through the menu.
    settings = {
        -- TODO: user config values, eg. which rows to show, coloring, etc.
        enabled = true,

        -- The layout to use.
        -- UI will initially treat this as on/off, 0 or 1, but keep it
        -- an integer for possible future development of other layouts.
        layout = 1,

        -- If colors are added to hull/shield values.
        hull_shield_colors = true,
        -- If the title bar should be colored by faction.
        faction_color = true,
        -- If hull and shield are bold.
        hull_shield_bold = true,
        -- If the colors in general should be lightened (eg. white).
        -- TODO: customizing the coloring.
        brighten_text = true,
    },
    
    -- How far away player can be from a target and be considered to
    -- have arrived; eg. 1000 for 1 km.
    -- TODO: make ship size specific.
    arrival_tolerance = 1000,

    -- When brightening colors, how much to reduce the range from the color
    -- current value to max 255.
    -- Eg. 0.6 will take a 120 color to 120+(255-120)*0.6 = 201
    faction_color_brightening_factor = 0.5,   

    -- Default font/color, originally matching the ego menu.
    orig_defaults = {
        headercolor = { r = 127, g = 195, b = 255 },
        headerfont = "Zekton",
        headerfontsize = 22,

        textcolor = { r = 127, g = 195, b = 255 },
        textfont = "Zekton",
        textfontsize = 22,

        boldfont = "Zekton Bold",
    },
    -- Customized defaults, to be used for new items and overwrite ego stuff.
    new_defaults = {
        headercolor = { r = 255, g = 255, b = 255 },
        headerfont = "Zekton Bold",
        headerfontsize = 22,

        textcolor = { r = 255, g = 255, b = 255 },
        textfont = "Zekton Bold",
        textfontsize = 22,

        boldfont = "Zekton Bold",
    },

    -- Optional special colors for certain terms.
    colors = {
        -- yellow
        hull   = { r = 200, g = 200, b = 0 },
        -- blue
        shield = { r = 90, g = 146, b = 186 },
    },

    -- Table holding row/column display specifications.
    specs = {},

    -- Temp storage of MD transmitted setting fields.
    md_field = nil,

    -- Copy of targetdata from targetmonitor GetTargetMonitorDetails.
    targetdata = nil,

    -- Note: objects at a far distance, eg. borderline low-attention, get
    -- very janky speed values (rapidly fluctuating, even every frame
    -- while paused), causing distracting menu flutter for ETA calculations
    -- and similar.  Can fix it somewhat with a smoothing filter on the
    -- speed and distance values, and maybe eta.
    filters = {
        -- Objects created later.
        speed = nil,
        distance = nil,
        eta = nil,
        rel_speed = nil,
    },

    -- Stored values for calculating relative speeds.
    last_component64 = nil,
    last_distance    = nil,
    last_update_time = nil,

    -- Note: next two are not currently used.
    -- Copy of messageID sent to SetSofttarget.
    last_softtarget_messageID = nil,
    -- Table, keyed by messageID, holding the distances from GetTargetElementInfo.
    target_element_distances = nil,

}

local T = {
    hull      = ReadText(1001, 1),
    shield    = ReadText(1001, 2),
    speed     = ReadText(1001, 8051),
    distance  = ReadText(20223, 51),
    crew      = ReadText(1001, 8057),
    type      = ReadText(1001, 6400),
    eta       = ReadText(1001, 2923),
    
    -- Borrowed from targetsystem.lua
    units = {
        ["km"]   = ffi.string(C.GetLocalizedText(1001, 108, "km")),
        ["m"]    = ffi.string(C.GetLocalizedText(1001, 107, "m")),
        ["m/s"]  = ffi.string(C.GetLocalizedText(1001, 113, "m/s")),
        ["s"]    = ffi.string(C.GetLocalizedText(1001, 100, "s")),
        ["h"]    = ffi.string(C.GetLocalizedText(1001, 102, "h")),
        ["min"]  = ffi.string(C.GetLocalizedText(1001, 103, "min")),
    },
    
    purpose_names = {
        fight = ReadText(20213, 300),
        trade = ReadText(20213, 200),
        mine  = ReadText(20213, 500),
        build = ReadText(20213, 400),
        misc  = ReadText(1001, 2664),
    },
    
    size_names = {
        ship_xl = ReadText(20111, 5041),
        ship_l  = ReadText(20111, 5031),
        ship_m  = ReadText(20111, 5021),
        ship_s  = ReadText(20111, 5011),
        ship_xs = ReadText(20111, 5001),
    },
    
    type_names = {
    },    

    x3_class_names = {
        fight = {
            ship_xl = "M2",
            ship_l  = "M7",
            ship_m  = "M6",
            ship_s  = "M4",
            ship_xs = "M5",
        },
        trade = {
            ship_xl = "TL",
            ship_l  = "TL",
            ship_m  = "TS",
            ship_s  = "TS",
            ship_xs = "TS",
        },
        mine = {
            ship_xl = "TL",
            ship_l  = "TL",
            ship_m  = "TS",
            ship_s  = "TS",
            ship_xs = "TS",
        },
        build = {
            ship_xl = "TL",
            ship_l  = "TL",
            ship_m  = "TS",
            ship_s  = "TS",
            ship_xs = "TS",
        },
        misc = {
            ship_xl = "CV",
            ship_l  = "CV",
            ship_m  = "CV",
            ship_s  = "CV",
            ship_xs = "CV",
        },
    },
}

------------------------------------------------------------------------------
-- Support object for data smoothing.

local Filter = {}

function Filter.New ()
  return {
    -- List of samples.
    -- This will fill up on first pass, then has static size afterwards
    -- and just overwrites old samples.
    samples = {},
    -- Index of the next location to store. (1-based indexing.)
    next = 1,
    -- Max depth.
    -- Assuming speed flutter alternates every frame, make this even
    -- to balance the flutter.
    depth = 4,
    -- Running sum of values.
    sum = 0,
    -- Current smoothed value. Note: float.
    current = nil,
    }
end

-- Add a new sample, and return the current smoothed value.
-- Stores returned value in "current".
function Filter.Smooth(filter, sample)

    -- If at max depth, overwrite oldest.
    if #filter.samples == filter.depth then
        -- Subtract the to-be-replaced point.
        filter.sum = filter.sum - filter.samples[filter.next]
    end

    -- Add the new sample.
    filter.sum = filter.sum + sample
    filter.samples[filter.next] = sample

    -- Increment next, with rollover.
    -- Note: 1-based indexing, so next goes from 1 to depth then rolls over.
    filter.next = filter.next + 1
    if filter.next > filter.depth then
        filter.next = 1
    end

    -- TODO: this summation might not be entirely stable over time,
    -- so every so many samples recompute the total sum.

    -- Calculate the average.
    filter.current = filter.sum / #filter.samples
    return filter.current
end

-- Clear samples.
function Filter.Clear(filter)
    filter.samples = {}
    filter.next    = 1
    filter.sum     = 0
    filter.current = nil
end

------------------------------------------------------------------------------
-- Setup functions, or helpers.

function L.Init_TargetMonitor()
    if GetTargetMonitorDetails == nil then
        error("GetTargetMonitorDetails global not yet initialized")
    end
        
    -- MD hooks.
    RegisterEvent("Target_Monitor.Set_Field", L.Handle_Event)
    RegisterEvent("Target_Monitor.Set_Value", L.Handle_Event)

    L.Init_Specs()

    L.Patch_GetTargetMonitorDetails()
    L.Patch_GetLiveData()

    -- Init some extra units.
    T.units["km/s"] = T.units["km"].."/"..T.units["s"]

    -- Init data objects.
    L.filters.speed     = Filter.New()
    L.filters.distance  = Filter.New()
    L.filters.eta       = Filter.New()
    L.filters.rel_speed = Filter.New()

    -- Unused; this approach to distance capture didn't work out
    -- (patches never trigger).
    --L.Patch_GetTargetElementInfo()
    --L.Patch_SetSofttarget()
end

-- Capture settings updates.
function L.Handle_Event(signal, value)
    --DebugError("Signal: "..tostring(signal).." : "..tostring(value))

    -- To change settings, a pair of calls will come in, giving field
    -- and then value.
    if signal == "Target_Monitor.Set_Field" then
        L.md_field = value

    elseif signal == "Target_Monitor.Set_Value" then

        -- The field name should exist, and have a current value.
        if L.md_field ~= nil and L.settings[L.md_field] ~= nil then

            -- Lua is stupid and treats 0 as true; fix it here.
            if type(L.settings[L.md_field]) == "boolean" then
                if value == 0 then value = false else value = true end
            end

            L.settings[L.md_field] = value
            -- Re-init specs, in case they depend on a changed setting.
            L.Init_Specs()
        else

            DebugError("Unrecognized target monitor setting: "..tostring(L.md_field))
        end
    end
end

------------------------------------------------------------------------------
-- Generic text support functions.

-- Given a color table, brightens and returns it. Alpha is unchanged.
function L.Brighten_Color(color, color_brightening_factor)
    if color == nil then return nil end
    local new_color = {}
    for key, value in pairs(color) do
        if key == "r" or key == "g" or key == "b" then
            -- Adjust based on distance from 255.
            new_color[key] = value + math.floor((255 - value) * color_brightening_factor)
            -- Safety limits.
            if new_color[key] > 255 then new_color[key] = 255 end
            if new_color[key] < 0   then new_color[key] = 0 end
        else
            new_color[key] = color
        end
    end
    return new_color
end

-- Given two strings, pad the shorter one with spaces until the strings roughly
-- match in length.  Suffixes by default, unless "prefix" is true.
-- Assumes standard font size.
-- Pricision is limited to space width.
-- TODO: switch to Helper.standardFontMono instead of this logic, and just
-- simply space to same string length.
function L.Match_String_Length(A, B, font, prefix)
    -- Assume both inputs will have a space suffixed or prefixed outside
    -- this function; double space was observed to be significantly larger
    -- than 2x single space.
    -- Result: improves accuracy.
    if prefix then
        A = " "..A
        B = " "..B
    else
        A = A.." "
        B = B.." "
    end

    -- Scale the font size based on ui scaling, in case that helps.
    -- In practice, seems to make things worse?
    --local fontsize = Helper.scaleFont(font, L.orig_defaults.textfontsize)
    -- Supposition: GetTextWidth might treat spaces as some fixed-fontsize
    -- instead of scaled properly with fontsize as other characters are.
    -- In such a case, can experiment with fontsize here to estimate what
    -- the GetTextWidth function is using.
    -- (In testing, small fontsizes under-estimate, larger over-estimate.)
    local fontsize = 18

    -- Get the initial text widths.
    local a_width     = C.GetTextWidth(A, font, fontsize)
    local b_width     = C.GetTextWidth(B, font, fontsize)

    -- Determine the shorter string.
    local new_short
    local current_width
    local target_width
    if a_width < b_width then
        new_short       = A
        current_width   = a_width
        target_width    = b_width
    else
        new_short       = B
        current_width   = b_width
        target_width    = a_width
    end

    -- Pad the shortest string with spaces until reaching the target width.
    -- Buffer the prior test point for selection later.
    local debug_spaces_added = 0
    local prior_width    = current_width
    local prior_short    = new_short
    while current_width < target_width do
        -- Save earlier results.
        prior_width    = current_width
        prior_short    = new_short
        -- Add a space.
        if prefix then 
            new_short = " "..new_short 
        else 
            new_short = new_short.." "
        end
        -- Update width.
        current_width = C.GetTextWidth(new_short, font, L.orig_defaults.textfontsize)
        debug_spaces_added = debug_spaces_added + 1
    end

    -- Switch back to the prior width if it was a closer match.
    if math.abs(prior_width - target_width) < math.abs(current_width - target_width) then
        new_short = prior_short
        current_width = prior_width
        debug_spaces_added = debug_spaces_added - 1
    end
    
    --[[
    Lib.Print_Table({
        A = A,
        B = B,
        a_width = a_width,
        b_width = b_width,
        new_short = new_short,
        new_width = current_width,
        spaces = debug_spaces_added,
    }, "Match_String_Length")
    ]]

    -- Match up this short string with the right arg and return.
    if a_width < b_width then
        return new_short, B
    else
        return A, new_short
    end

    -- Removed, the below overshoots for some reason.
    --[[
    -- Get the space width when it is inserted between two characters, just
    -- in case this differs from a space alone.
    -- TODO: overshooting by too much.
    local space_width = ( C.GetTextWidth("a ", font, L.orig_defaults.textfontsize)
                        - C.GetTextWidth("a",  font, L.orig_defaults.textfontsize))

    -- Calculate spaces needed.
    local difference = a_width - b_width
    if difference < 0 then difference = 0 - difference end
    -- Always floor for now, to avoid overshoot.
    local spaces = math.floor((difference / space_width))

    if prefix then
        if a_width < b_width then
            return string.rep(" ", spaces) .. A, B
        else
            return A, string.rep(" ", spaces) .. B
        end
    else
        if a_width < b_width then
            return A .. string.rep(" ", spaces), B
        else
            return A, B .. string.rep(" ", spaces)
        end
    end
    ]]
end

------------------------------------------------------------------------------
-- Various stubs of row or column specs (tables of text, color, etc.),
-- to be used in later building the actual rows.

-- Fill in a table with defaults for a text field in the target monitor.
-- Uses old defaults initially; new defaults replace it later along
-- with original row specs.
-- Accepts plain text (to be given defaults), or existing table (unchanged).
local function Make_Spec(text, font)
    if type(text) ~= "table" then
        return {
            text     = text or "",
            color    = L.orig_defaults.textcolor,
            font     = font or L.orig_defaults.textfont,
            fontsize = L.orig_defaults.textfontsize,
        }
    else
        return text
    end
end

-- Make a row (pair of tables) for the target monitor.
local function Make_Row(left, right, font)
    return {
        left  = Make_Spec(left , font),
        right = Make_Spec(right, font),
    }
end
    
function L.Init_Specs()

    -- Start building pieces of rows, to be assembled later.
    -- Can use half-row specs (take up one side), categorized
    -- as left/right or uncategorized.
    local cols = {right = {}, left = {}}
    -- Or full row specs (take up both sides).
    local rows = {}
    L.specs.cols = cols
    L.specs.rows = rows
    
    -- Pre-encode some colorings here.
    local hull_code   = "$hullpercent$%"
    local shield_code = "$shieldpercent$%"
    if L.settings.hull_shield_colors then
        -- TODO: how to limit the coloring to not spread to any following text?
        hull_code   = Helper.convertColorToText(L.colors.hull)   .. hull_code
        shield_code = Helper.convertColorToText(L.colors.shield) .. shield_code
    end

    -- Pre-select any special fonts.
    local hullshield_font = L.orig_defaults.textfont
    if L.settings.hull_shield_bold then
        hullshield_font = L.orig_defaults.boldfont
    end

    -- Pre-pad shield and hull strings so they match in length.
    -- Do this for left and right versions.
    -- Right side will prefix spaces (so they align on the right).
    local str_hull_r, str_shield_r = L.Match_String_Length(T.hull, T.shield, hullshield_font, true)
    -- Left side will suffix spaces (so they align on the left).
    local str_hull_l, str_shield_l = L.Match_String_Length(T.hull, T.shield, hullshield_font, false)

    -- Right display, half row each.
    -- TODO: fancy functions to equalize shield/hull string lengths.
    -- X% Hull
    cols.right.hull   = Make_Spec(hull_code.."   "..str_hull_r, hullshield_font)
    -- X% Shield
    cols.right.shield = Make_Spec(shield_code.." "..str_shield_r, hullshield_font)
            
    -- Left display, half row each.
    -- Hull X%
    cols.left.hull   = Make_Spec(str_hull_l.."   "..hull_code, hullshield_font)
    -- Shield X%
    cols.left.shield = Make_Spec(str_shield_l.." "..shield_code, hullshield_font)
            
    -- Single row shield/hull.
    rows.shield_hull = Make_Row(T.hull.." / "..T.shield,
                                shield_code.." / "..hull_code,
                                hullshield_font)
    -- Classic style shield and hull one row each.
    rows.hull   = Make_Row(T.hull,   hull_code, hullshield_font)
    rows.shield = Make_Row(T.shield, shield_code, hullshield_font)

    -- Distance row and col
    rows.distance = Make_Row(T.distance, "$distance$")
    cols.distance = Make_Spec("$distance$")

    -- Ship type.
    -- This can be wide, potentially, but not expected to be
    -- super wide (still likely half column).
    -- TODO: maybe x3 style name as an alternative split?
    rows.type = Make_Row(T.type, "$type$")
    cols.type = Make_Spec("$type$")

    -- Crew, for boarding.
    rows.crew = Make_Row(T.crew, "$crew$")
    cols.left.crew  = Make_Spec(T.crew.." $crew$")
    cols.right.crew = Make_Spec("$crew$ "..T.crew)

    -- Commander, just col version.
    cols.commander  = Make_Spec("$commander$")
    -- Reveal %; ideally would have some label, but hard to find a good
    -- one that is short.  TODO: maybe try "information" though long.
    cols.reveal  = Make_Spec("$revealpercent$%")
    
    -- Speed row
    rows.speed = Make_Row(T.speed, "$speed$")
    -- Speed col, no label (suffix m/s should be clear enough.)
    cols.speed = Make_Spec("$speed$")
            
    -- Relative speed.
    -- Try out delta for clarifying the label.
    -- TODO: delta doesn't display.
    rows.rel_speed = Make_Row("▲"..T.speed, "$rel_speed$")
    cols.rel_speed = Make_Spec("▲".."$rel_speed$")

    -- Alternatively, combine distance and relspeed, eg. "1km + 10m/s".
    -- This will encode a compressed relative speed so that high speeds
    -- don't take as much space. The speed will always have a + if positive.
    rows.distance_delta = Make_Row(T.distance, "$distance$ $rel_speed_suffix$")
    cols.distance_delta = Make_Spec("$distance$ $rel_speed_suffix$")
            
    -- ETA
    rows.eta = Make_Row(T.eta, "$eta$")
    -- Need label to know what this is.
    cols.left.eta = Make_Spec(T.eta.." $eta$")
    cols.right.eta = Make_Spec("$eta$ "..T.eta)

    
    -- TODO: other stuff.
end

------------------------------------------------------------------------------
-- Helper function to categorize existing text rows.
-- Each key corresponds to one row, except "unknowns" which is a list
-- with all unhandled rows.
function L.Categorize_Original_Rows(text_rows)
    local orig = {unknowns = {}}
    for i, row in ipairs(text_rows) do

        if row.right == nil then
            -- Skip.

        elseif row.right.text == "$hullpercent$%" then
            orig.hull = row

        elseif row.right.text == "$shieldpercent$%" then
            orig.shield = row

        elseif row.right.text == "$aicommand$" then
            orig.command_0 = row

        elseif row.right.text == "$aicommandaction$" then
            orig.command_1 = row

        elseif row.right.text == "$crew$" then
            orig.crew = row
            -- Storage always preceeds crew, though its format isn't
            -- always the same, so fill here.
            orig.storage = text_rows[i -1]

        elseif row.right.text == "$revealpercent$%" then
            orig.reveal = row

        elseif row.right.text == "$commander$" then
            orig.commander = row

        elseif row.right.text == "$buildingprogress$%" then
            orig.building = row
        else
            table.insert(orig.unknowns, row)
        end
    end
    return orig
end

-- Clean up a row list by removing nil entries, as well as any rows
-- past the 7th.
function L.Sanitize_Rows(row_list)
    -- Since tables cannot be nicely traversed with nil entries,
    -- sort the table keys first.
    local keys = {}
    for key in pairs(row_list) do
        table.insert(keys, key)
    end
    table.sort(keys)
    local final = {}
    for i, key in ipairs(keys) do
        if #final < 7 then
            table.insert(final, row_list[key])
        end
    end
    return final
end

------------------------------------------------------------------------------
-- Logic for changing what rows are displayed.

-- Make this somewhat patchable, to easily scale out different possible
-- layouts (eg. user monkey patching).
-- Returns a list of row data, or nil if an unsupported object type.
function L.Get_New_Rows(component, original_rows, row_specs, col_specs)

    -- Convenience renaming.
    local orig  = original_rows
    local rows = row_specs
    local cols = col_specs

    local has_shields = GetComponentData(component, "shieldmax") ~= 0
    -- Term for shields or blank if unshielded.
    local col_left_shield_blank = has_shields and cols.left.shield or ""

    local new_rows = nil

    -- Note: currently just layout 0 (no change) and 1 (as follows).
    if L.settings.layout == 0 then
        -- Do nothing.

    elseif IsComponentClass(component, "ship")
    then
        new_rows = {
            -- TODO: does this get too busy with player ship commanders?
            Make_Row(cols.type, orig.reveal and cols.reveal or cols.commander),
            -- Shield/hull in top left, distance/speed top right.
            Make_Row(col_left_shield_blank, cols.distance_delta),
            Make_Row(cols.left.hull,        cols.speed),
            -- Pack in crew on the left, eta right.
            Make_Row(cols.left.crew,        cols.right.eta),
            -- TODO: pack in crew, maybe storage (though that is trickier
            -- to put together, and may be too long).
            -- Continue with normal stuff.
            orig.command_0,
            orig.command_1,
            orig.storage,
            --orig.crew,
            orig.building,
        }
    
    elseif IsComponentClass(component, "station") then
        new_rows = {
            orig.reveal,
            Make_Row(col_left_shield_blank, cols.distance_delta),
            Make_Row(cols.left.hull,        cols.speed),
            Make_Row("",                    cols.right.eta),
            orig.command_0,
            orig.command_1,
            orig.building,
        }
        
    elseif IsComponentClass(component, "mine")
    then
        new_rows = {
            Make_Row(col_left_shield_blank, cols.distance_delta),
            Make_Row(cols.left.hull,        cols.speed),
            Make_Row("",                    cols.right.eta),
        }

    -- TODO: maybe split off objects that can't move to hide speed.
    -- TODO: check if object has shields, and maybe hide shield readout if not.
    elseif IsComponentClass(component, "collectable")
    or     IsComponentClass(component, "crate")
    or     IsComponentClass(component, "lockbox")
    or     IsComponentClass(component, "navbeacon")
    or     IsComponentClass(component, "resourceprobe")    
    or     IsComponentClass(component, "satellite")
    then
        new_rows = {
            Make_Row(col_left_shield_blank, cols.distance_delta),
            Make_Row(cols.left.hull,        ""),
            Make_Row("",                    cols.right.eta),
        }
                
    -- Static objects without hull/shield.
    elseif IsComponentClass(component, "asteroid")
    or     IsComponentClass(component, "gate")
    then
        new_rows = {
            Make_Row("",               cols.distance_delta),
            Make_Row("",               cols.right.eta),
        }
        
        
    end

    if new_rows ~= nil then
        -- Append all unknown original rows.
        for i, unknown in ipairs(orig.unknowns) do
            table.insert(new_rows, unknown)
        end
    end

    return new_rows
end

------------------------------------------------------------------------------
-- Older functions, mostly replaced.
--[[
function L.Modify_Ship_Rows(full_spec)
    local text_rows = full_spec.text

    -- Look through the data to identify lines of interest.
    local orig = Categorize_Original_Rows(text_rows)

    -- Build the new table.
    -- Can try different styles here.
    local style = 3
    
    local cols = L.specs.cols
    local rows = L.specs.rows

    local new_rows
    if style == 1 then
        -- Labels on left still.
        -- Put new info up top.
        new_rows = {
            rows.type,
            rows.shield_hull,
            rows.distance,
            rows.speed,
            orig.command_0,
            orig.command_1,
            orig.storage,
            orig.crew,
            orig.commander or orig.reveal,
            orig.building,
        }
    elseif style == 2 then
        -- Make use of columns to pack in more info, or organize it.
        new_rows = {
            -- Type on left, info % or commander on right.
            Make_Row(cols.type, orig.reveal and cols.reveal or cols.commander),
            -- Shield/hull still take up 2 columns, but orient on the top
            -- left for easier visual parsing.
            -- On right, put distance and speed.
            Make_Row(cols.left.shield, cols.distance),
            Make_Row(cols.left.hull, cols.speed),
            -- TODO: pack in crew, maybe storage (though that is trickier
            -- to put together, and may be too long).
            -- Continue with normal stuff.
            orig.command_0,
            orig.command_1,
            orig.storage,
            orig.crew,
            orig.building,
        }
    elseif style == 3 then
        -- Similar to 2, but include relative speed and eta.
        -- TODO: compress storage.
        new_rows = {
            Make_Row(cols.type, orig.reveal and cols.reveal or cols.commander),
            -- Shield/hull in top left, distance/speed top right.
            Make_Row(cols.left.shield, cols.distance_delta),
            Make_Row(cols.left.hull, cols.speed),
            -- Pack in crew on the left, eta right.
            Make_Row(cols.left.crew, cols.right.eta),
            -- TODO: pack in crew, maybe storage (though that is trickier
            -- to put together, and may be too long).
            -- Continue with normal stuff.
            orig.command_0,
            orig.command_1,
            orig.storage,
            --orig.crew,
            orig.building,
        }
    else
        -- No change.
        new_rows = text_rows
    end

    -- Store the new row list.
    full_spec.text = L.Sanitize_Rows(new_rows)
end

-- Logic for changing what rows are displayed for mines.
function L.Modify_Mine_Rows(full_spec)
    -- This just has one row for hull, maybe a second for shield.
    local orig = Categorize_Original_Rows(full_spec.text)
    
    -- Build the new table.
    -- Can try different styles here.
    local style = 2
    
    local cols = L.specs.cols
    local rows = L.specs.rows

    local new_rows
    if style == 1 then
        -- Labels on left still.
        -- TODO: maybe prune out shield if unshielded.
        new_rows = {
            rows.shield,
            rows.hull,
            rows.distance,
            rows.speed,
        }
    elseif style == 2 then
        -- Make use of columns to pack in more info, or organize it.
        new_rows = {
            Make_Row(cols.left.shield, cols.distance),
            Make_Row(cols.left.hull, cols.speed),
        }
    else
        -- No change.
        new_rows = text_rows
    end
    
    -- Store the new row list.
    full_spec.text = L.Sanitize_Rows(new_rows)
end
]]


------------------------------------------------------------------------------
-- Patching the primary function that lays out the ui rows.

function L.Patch_GetTargetMonitorDetails()
    local ego_GetTargetMonitorDetails = GetTargetMonitorDetails
    GetTargetMonitorDetails = function(component, templateConnectionName)
        local component64 = ConvertIDTo64Bit(component)

        -- Get the standard table data.
        local full_spec = ego_GetTargetMonitorDetails(component, templateConnectionName)
        
        -- To look up speed in GetLiveData, might need to save some info
        -- from the GetTargetMonitorDetails call (unless there is another
        -- way to rebuild it).
        -- (Need to do this before fast exit checks.)
        L.targetdata = { }
        L.targetdata.component = component
        L.targetdata.component64 = component64
        L.targetdata.templateConnectionName = templateConnectionName
        L.targetdata.triggeredConnectionName = templateConnectionName ~= "" and ffi.string(C.GetCompSlotPlayerActionTriggeredConnection(component64, templateConnectionName)) or ""
        
        -- Quick exit when disabled or something went wrong.
        if (not L.settings.enabled) or (full_spec == nil) then
            return full_spec
        end

        -- Hand off to helper functions based on object type.
        local orig = L.Categorize_Original_Rows(full_spec.text)    
        local new_rows = L.Get_New_Rows(component, orig, L.specs.rows, L.specs.cols)
        if new_rows ~= nil then
            full_spec.text = L.Sanitize_Rows(new_rows)
        end
    
        -- Change the default fonts.
        -- TODO: maybe play around with colors dynamically.
        -- TODO: detect if a custom color was used, and skip if so.
        -- TODO: apply brightening, particularly if not replacing colors.
        if L.settings.brighten_text then
            for i, row in ipairs(full_spec.text) do
                for side, spec in pairs(row) do
                    spec.color    = L.new_defaults.textcolor
                    spec.fontsize = L.new_defaults.textfontsize
                    -- Skip this one for now, so bold fonts pass through.
                    --spec.font     = L.new_defaults.textfont
                end
            end
            full_spec.header.color     = L.new_defaults.headercolor
            full_spec.header.fontsize  = L.new_defaults.headerfontsize
            full_spec.header.font      = L.new_defaults.headerfont
        end

        -- Color the title based on target faction.
        if L.settings.faction_color then
            local faction_details = C.GetOwnerDetails(component64)
            -- Sometimes no faction id available; skip to avoid log spam.
            if faction_details.factionID then
                local faction_color = GetFactionData(ffi.string(faction_details.factionID), "color")
                if faction_color then
                    full_spec.header.color = L.Brighten_Color(faction_color, L.faction_color_brightening_factor)
                end
            end
        end
        
        -- Return it all for display.
        return full_spec
    end
end
    
------------------------------------------------------------------------------
-- Patching the function for live updating strings from changing data.

function L.Patch_GetLiveData()
    -- Wrap the live keyword replacement function.
    local ego_GetLiveData = GetLiveData
    GetLiveData = function(placeholder, component)

        local targetdata = L.targetdata

        -- Note: in some cases a /reloadui will still keep the current
        -- object targetted, in which case targetdata isn't known.
        -- Check for that case here.
        if targetdata then
            -- Update component, just to be safe, though the connection name
            -- will be the one stored before.
            targetdata.component64 = ConvertIDTo64Bit(component)
        
            -- If the target changed, clear old cached data.
            if L.last_component64 ~= targetdata.component64 then
                -- Record fresh values.
                L.last_component64 = targetdata.component64
                L.last_distance    = nil
                L.last_update_time = nil

                Filter.Clear(L.filters.speed)
                Filter.Clear(L.filters.rel_speed)
                Filter.Clear(L.filters.distance)
                Filter.Clear(L.filters.eta)
            end

            if placeholder == "speed" then
                return L.Get_Speed(targetdata)
            elseif placeholder == "type" then
                return L.getShipTypeText(targetdata)
            elseif placeholder == "distance" then
                return L.Get_Distance(targetdata)
            elseif placeholder == "rel_speed" then
                return L.Get_Relative_Speed(targetdata, false)
            elseif placeholder == "rel_speed_suffix" then
                return L.Get_Relative_Speed(targetdata, true)
            elseif placeholder == "eta" then
                return L.Get_ETA(targetdata)
            -- TODO: maybe intercept shield/hull readouts and recolor when
            -- the percentages get lower (eg. green-yellow-red), though thought
            -- is needed on how this interracts with general coloring (blue/yellow).
            end
        end

        return ego_GetLiveData(placeholder, component)
    end
end



------------------------------------------------------------------------------
-- Get target ship's speed.
-- Run it through the smoothing filter before returning.

function L.Get_Speed(targetdata)
    local componentDetails = C.GetComponentDetails(
                                    targetdata.component64, 
                                    targetdata.triggeredConnectionName)
    -- Get speed, with smoothing.
    local speed = Filter.Smooth(L.filters.speed, componentDetails.speed)
    return math.floor(speed).." "..T.units["m/s"]
end

------------------------------------------------------------------------------

-- Returns a string for target's distance, and updates internal
-- values used in relative speed and ETA.
function L.Get_Distance(targetdata)

    -- Removed code; didn't work out.
    ---- Look up the recorded distance for the current target.
    --if (L.target_element_distances 
    --and L.last_softtarget_messageID) then
    --
    --    local distance = L.target_element_distances[
    --                        L.last_softtarget_messageID]
    --    -- Suffix it.
    --    return L.getDistanceText(distance)
    --end

    --local playertarget = ConvertIDTo64Bit(GetPlayerTarget())
    -- Or maybe this, gives x/y/z of player target:
    -- C.GetPlayerTargetOffset()
    local t_off = C.GetPlayerTargetOffset()
    --if t_off then
    --    DebugError("x "..t_off.x .." y "..t_off.y .." z "..t_off.z)
    --end

    -- This gets pos of an object; try to get player ship or player.
    --local player = C.GetPlayerID()
    local player_ship = C.GetPlayerOccupiedShipID()
                
    -- Note: player id didn't work out with following call.
    -- UIPosRot GetObjectPositionInSector(UniverseID objectid);
    local p_off = C.GetObjectPositionInSector(player_ship)
    --if p_off then
    --    DebugError("x "..p_off.x .." y "..p_off.y .." z "..p_off.z)
    --end

    if t_off and p_off then
        local distance = ((t_off.x - p_off.x)^2
                        + (t_off.y - p_off.y)^2
                        + (t_off.z - p_off.z)^2 ) ^ 0.5

        -- Round it, else a fighter in orbit of a big ship with 0 relative
        -- speed will tend to have its sign alternating +/- due to
        -- imprecision.
        distance = math.floor(distance + 0.5)

        -- Hand off to the update function for deltas.
        L.Update_Relative_Speed(targetdata, distance)

        -- Smooth it (after the above handoff, to not mess with time
        -- increments; eta smooths on its own).
        distance = Filter.Smooth(L.filters.distance, distance)

        -- Suffix it.
        return L.Value_To_Rounded_Text(distance, T.units["m"], T.units["km"])
    end

    return "Much Far"
end

-- Update values for the change in distance.
function L.Update_Relative_Speed(targetdata, new_distance)
    -- TODO: is C.GetCurrentGameTime() better?
    local now = GetCurTime()

    -- Stored values could be clear due to target change or first call
    -- after loading.
    -- Can compute if a distance is known, and the time has changed
    -- (eg. don't try to compute during a pause).
    if L.last_distance ~= nil and L.last_update_time ~= now then
        local time_delta = now - L.last_update_time
        -- Orient so closing is negative.
        local distance_delta = new_distance - L.last_distance
        -- Smooth the relative speed, in case distance is janky.
        Filter.Smooth(L.filters.rel_speed, distance_delta / time_delta)
    end

    -- Store values for next iteration.
    L.last_distance    = new_distance
    L.last_update_time = now
end

-- Returns a string for the current distance delta.
-- Ideally called after the delta was updated.
-- "suffix" is bool, true if this is a suffix to distance (always include
--  sign, and round if large).
function L.Get_Relative_Speed(targetdata, suffix)
    local rel_speed = L.filters.rel_speed.current

    -- Skip if unknown.
    if rel_speed == nil then 
        return "+...".." "..T.units["m/s"]
    end

    -- Convert to rounded text.
    -- To avoid distance lines getting too long, maybe compress it to km/s.
    local ret_str
    if suffix then
        ret_str = L.Value_To_Rounded_Text(rel_speed, T.units["m/s"], T.units["km/s"])
    else 
        ret_str = tostring(math.floor(rel_speed + 0.5)).." "..T.units["m/s"]
    end

    -- Prefix with + if needed.
    if suffix and rel_speed >= 0 then
        ret_str = "+"..ret_str
    end
    return ret_str
end

-- Returns a string for the ETA.
-- Ideally runs after Get_Distance.
function L.Get_ETA(targetdata)
    -- Skip if distance and/or relative speed unknown.
    if (L.filters.rel_speed.current == nil
    or  L.filters.distance.current  == nil) then 
        return "--" 
    end

    -- Based on relative speed and distance.
    -- Discount the arrival_tolerance from the distance; may already be
    -- considered arrived if close.
    -- TODO: tune this based on ship sizing.
    local remaining_distance = L.filters.distance.current - L.arrival_tolerance
    if remaining_distance <= 0 then
        return "--"
    end
    -- Relative speed is negative for closing, so flip the sign.
    local eta = 0 - (remaining_distance / L.filters.rel_speed.current)

    -- TODO: filter if needed, though distance and rel_speed filters
    -- should hopefully cover things.

    -- If negative or 0, then infinite.
    -- Also cuttoff large values (else being stopped will display some
    -- crazy high number).  1 million seconds ~= 300 hours.
    if eta <= 0 or eta > 1000000 then
        return "∞"
    end

    -- Encode as a string.
    return ConvertTimeString(eta, "%h:%M:%S")
end

-- Encode a value as text, rounding off below the decimal, and if over
-- 1000 then encoding as "X.Y ", and adding corresponding kilo suffix.
function L.Value_To_Rounded_Text(value, units, kilounits)
    local ret_str
    if value >= 1000 then
        -- Round off two digits, and then divide by 10 to alight units to k.
        local value = math.floor((value + 50) / 100) / 10
        if math.fmod(value, 1) == 0 then
            value = tostring(value)..".0"
        end
        return value.." "..kilounits
    else
        return math.floor(value + 0.5).." "..units
    end
end

------------------------------------------------------------------------------
-- Get target ship's classification and size.

-- Returns a text string with the ship primary role and size.
function L.getShipTypeText(targetdata)

    -- Note: GetComponentData can be used for most of these fields, but
    -- equivelent is GetMacroData after extracting the component "macro"
    -- field.

    -- Grab some values.
    local purpose, shiptype, shiptypename = GetComponentData(
            targetdata.component, 
            "primarypurpose", 
            -- Basic type from xml.
            "shiptype", 
            -- Type already converted to handy text.
            "shiptypename")

    -- Direct macro class lookup (for size) doesn't work, at least not
    -- by this name.
    --local macroclass = GetComponentData(targetdata.component, "macroclass")
    -- Need macro for size lookup.
    local macro = GetComponentData(targetdata.component, "macro")
    local macroclass = ffi.string(C.GetMacroClass(macro))

    -- Encode ship purpose, eg. Fight.
    local purpose_name = T.purpose_names[purpose]
    if purpose_name == nil then
        purpose_name = "?"
    end
    
    -- Encode ship size, eg. M.
    local size_name = T.size_names[macroclass]
    if size_name == nil then
        size_name = ""
    end

    -- Estimate the x3 style encoding.
    local x3_class = L.Get_X3_Class(macroclass, purpose, shiptype)

    -- Note: some ships don't have a type (unclear on if the shiptypename
    -- will have already cleaned up this case), eg. boarding pods.
    -- TODO: maybe clean up if boarding pods give odd results.
    
    -- Pick what to return.  Go with type and size for now.
    return tostring(shiptypename).." "..tostring(size_name).." ("..x3_class..")"
end

-- Return a string for the X3 style class name.
function L.Get_X3_Class(macroclass, purpose, shiptype)
    -- This will require a bit of work to lay out different cases, but
    -- should be doable.
    -- Start with defaults.
    local purpose_group = T.x3_class_names[purpose]
    if purpose_group == nil then return "" end
    local name = purpose_group[macroclass]
    if name == nil then return "" end
    return name
end

------------------------------------------------------------------------------
L.Init_TargetMonitor()


--[[

Distance lookup:
    This one is harder.  targetsystem does a call to GetTargetElementInfo
    (external lua function) giving it messageID and posID for a list
    of targetelements.
    'messageID' is an int, and appears to be related to the target
    selection subsystem signalling somehow (is fed into C functions).

    Potentially distance can be freshly computed here, but perhaps
    the GetTargetElementInfo call can be wrapped and listened to
    to pick out the distance of the current target, assuming the
    target can be properly identified (out of the list of targets).

    It appears targetelement.softtarget is the flag for the current
    player target, though is there a way to get at that field, when
    the GetTargetElementInfo call only take messageID and posID?

    SetSofttarget is a global function which is called with a
    "TargetMessageID", which appears to match the messageID that
    is sent to GetTargetElementInfo.

    Piecing these two together should succesfully find the target distance.

    Result: neither function gets called. Perhaps targetsystem.lua is
    not patchable (lowered to c++, or something; it is in ui/core instead
    of the addons folder).
]]
--[[
function L.Patch_GetTargetElementInfo()
    -- Wrap the target info lookup, to use for distance checks.
    local ego_GetTargetElementInfo = GetTargetElementInfo
    GetTargetElementInfo = function(targetElementQuery)
        DebugError("GetTargetElementInfo called")
        local result = ego_GetTargetElementInfo(targetElementQuery)

        -- Repack into a table.
        local table = {}
        for i, info in ipairs(result) do
            local target_info = targetElementQuery[i]
            table[target_info.messageID] = info.distance
        end
        L.target_element_distances = table

        return result
    end
end

function L.Patch_SetSofttarget()
    -- Wrap SetSofttarget to capture the last succesful messageID.
    local ego_SetSofttarget = SetSofttarget
    SetSofttarget = function(newTargetMessageID, ...)
        DebugError("SetSofttarget called")
        local success, wasalreadyset = ego_SetSofttarget(newTargetMessageID, ...)
        if success then
            L.last_softtarget_messageID = newTargetMessageID
        end
        return success, wasalreadyset
    end
end
]]
return L