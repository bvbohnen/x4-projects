
------------------------------------------------------------------------------
--[[
    The high level of the monitor is handled in monitors.lua.
    Specific details on what text is displayed are handled in targetmonitor.lua.

    The GetTargetMonitorDetails function handles selection of which text
    to show on which rows. By wrapping it, text can be modified.

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
    UniverseID GetPlayerObjectID(void);
    UniverseID GetPlayerOccupiedShipID(void);    
    UIPosRot GetObjectPositionInSector(UniverseID objectid);
    const char* GetMacroClass(const char* macroname);
    FactionDetails GetOwnerDetails(UniverseID componentid);
    float GetTextWidth(const char*const text, const char*const fontname, const float fontsize);
]]

-- Inherited lua stuff from support apis.
local Lib = require("extensions.sn_mod_support_apis.lua_interface").Library
local Time = Lib.Time

-- Table of locals.
local L = {
    -- Cap on how many debug errors will be printed.
    debug_errors_remaining = 50,

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

        -- If the roughly equivelent x3 class type should be shown
        -- after the ship type.
        show_x3_class = true,
    },
    
    -- How far away player can be from a target and be considered to
    -- have arrived; eg. 1000 for 1 km.
    -- TODO: make ship size specific.
    arrival_tolerance = 1000,

    -- When brightening colors, what the target total r+g+b value.
    -- Up to 255*3 = 765
    -- TODO: play around with this concept; 600 is good for paranid purple,
    -- but too much for red xenon; how to fix? Should red be treated
    -- differently?
    faction_color_target_brightness = 200*3,
    -- Storage of color channels, to avoid rebuilding regularly.
    color_channels = {"r","g","b"},

    -- Default font/color, originally matching the ego menu.
    orig_defaults = {
        headercolor = Color["text_notification_header"],
        headerfont = "Zekton",
        headerfontsize = 22,

        textcolor = Color["text_notification_text"],
        textfont = "Zekton",
        textfontsize = 22,

        boldfont = "Zekton Bold",
    },
    -- Customized defaults, to be used for new items and overwrite ego stuff.
    new_defaults = {
        headercolor = Color["text_normal"],
        headerfont = "Zekton Bold",
        headerfontsize = 22,

        textcolor = Color["text_normal"],
        textfont = "Zekton Bold",
        textfontsize = 22,

        boldfont = "Zekton Bold",
    },

    -- Optional special colors for certain terms.
    -- Note: these are passed to Helper.convertColorToText which expects
    -- alpha in 0-100 (and converts it to 0-255 internally).
    colors = {
        -- yellow
        hull   = { r = 200, g = 200, b = 0, a = 100},
        -- blue
        shield = { r = 108, g = 175, b = 223, a = 100},
    },

    -- Table holding row/column display specifications.
    specs = {},

    -- Temp storage of MD transmitted setting fields.
    md_field = nil,

    -- Copy of targetdata from targetmonitor GetTargetMonitorDetails.
    targetdata = nil,

    -- Note: objects at a far distance, eg. borderline low-attention, get
    --  very janky speed values (rapidly fluctuating, even every frame
    --  while paused), causing distracting menu flutter for ETA calculations
    --  and similar.  Can fix it somewhat with a smoothing filter on the
    --  speed and distance values, and maybe eta.
    -- Note: speed will filter across realtime, since it can jitter per
    --  frame even during a pause, but distance will filter across game time,
    --  and will not update during a pause.
    filter_speed = nil,
    filter_distance = nil,

    -- Stored values for calculating relative speeds.
    last_component64 = nil,
    --last_distance    = nil,
    last_update_time = nil,

    -- Note: next two are not currently used.
    -- Copy of messageID sent to SetSofttarget.
    last_softtarget_messageID = nil,
    -- Table, keyed by messageID, holding the distances from GetTargetElementInfo.
    target_element_distances = nil,

    -- Link to T table below, for returning to require statements.
    text = nil,
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
        -- Favor type checks.
        battleship = {
            ship_xl = "M0",
        },
        carrier = {
            ship_xl = "M1",
        },
        builder = {
            ship_xl = "TL",
        },
        resupplier = {
            ship_xl = "TL",
        },
        destroyer = {
            -- Only xl destroyer is the K
            ship_xl = "M2+",
            ship_l  = "M2",
        },
        corvette = {
            ship_m = "M6",
        },
        frigate = {
            ship_m = "M7",
        },
        gunboat = {
            ship_m = "M6",
        },
        scavenger = {
            ship_m = "M6",
        },

        -- Make the M heavyfighter also m3+.
        -- Le Leon comment: Reason: The only M-class heavy fighters, ive 
        -- seen are the Khaak ships. Both are not M6 corvettes. One is a old
        -- M4, the other is the old M3. Their firepower is same as fighter/ 
        -- heavy fighter of S-class.
        heavyfighter = {
            ship_m = "M3+",
            ship_s = "M3+",
        },
        fighter = {
            -- Includes Nova.
            ship_s = "M3",
        },
        interceptor = {
            ship_s = "M4",
        },
        scout = {
            ship_s = "M5",
        },
        smalldrone = {
            ship_s = "DR",
        },
        lasertower = {
            ship_s = "OL",
        },
        personalvehicle = {
            ship_s = "CV",
            ship_xs = "CV",
        },
        -- Fallback defaults using purpose.
        auxiliary = {
            ship_xl = "TL",
        },
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
-- Link for export.
L.text = T

-- Print an error to the log, or suppress if too many printed.
local function Print_Error(text)
    if L.debug_errors_remaining > 0 and text ~= nil then
        DebugError(text)
        L.debug_errors_remaining = L.debug_errors_remaining - 1
        if L.debug_errors_remaining == 0 then
            DebugError("Maximum better_target_monitor error prints reached; suppressing further errors.")
        end
    end
end

------------------------------------------------------------------------------
-- Support object for data smoothing.
-- TODO: move to the mod support apis, maybe.

local Depth_Filter = {}

function Depth_Filter.New ()
  return {
    -- List of samples.
    -- This will fill up on first pass, then has static size afterwards
    -- and just overwrites old samples.
    samples = {},
    -- Index of the next location to store. (1-based indexing.)
    next = 1,
    -- Depth of the list. Grows dynamically.
    depth = 4,
    -- Running sum of values.
    sum = 0,
    -- Current smoothed value. Note: float.
    current = nil,
    }
end

-- Add a new sample, and return the current smoothed value.
-- Stores returned value in "current".
function Depth_Filter.Smooth(filter, sample)

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

-- Change the depth of a filter, if signifcantly different.
function Depth_Filter.Change_Depth(filter, new_depth)
    -- To prevent excess changes when an object is around a depth
    -- boundary, only update if the depth changed by a couple steps,
    -- where one step is 2 (hence 4 for two steps).
    if math.abs(new_depth - filter.depth) < 4 then
        return
    end
    -- Safety against 0, negative, or just too large.
    new_depth = math.floor(new_depth)
    if new_depth <= 0 or new_depth > 100 then
        Print_Error("Change_Depth rejecting "..tostring(new_depth))
        return
    end

    -- Build a new list, using existing oldest to newest points.
    local new_samples = {}

    -- There needs to be at least one point for the following to make sense.
    if #filter.samples > 0 then
        -- Points from the latter part of the filter, oldest to end.
        -- If next == 1, then this gets everything.
        for i = filter.next, #filter.samples do
            -- TODO: if speed is important, t[#t+1] is 2x faster than table.insert
            table.insert(new_samples, filter.samples[i])
        end
        -- Points from start of the filter, midway to newest.
        -- Only if next != 1
        if filter.next ~= 1 then
            for i = 1, filter.next - 1 do
                table.insert(new_samples, filter.samples[i])
            end
        end
    end

    -- If the new_depth is shorter than the known samples, take away
    -- the oldest ones.
    local samples_to_remove = #new_samples - new_depth
    if samples_to_remove > 0 then
        local pruned_samples = {}
        for i = samples_to_remove + 1, #new_samples do
            table.insert(pruned_samples, new_samples[i])
        end
        new_samples = pruned_samples
    end

    -- Swap the filter state.
    filter.depth = new_depth
    filter.samples = new_samples
    -- Set the .next to the correct point.
    filter.next = #new_samples + 1
    if filter.next > filter.depth then
        filter.next = 1
    end

    -- Compte a new current value.
    Depth_Filter.Refresh_Sum(filter)
end

-- Recompute the current sum and average.
function Depth_Filter.Refresh_Sum(filter)
    local sum = 0
    for i, value in ipairs(filter.samples) do
        sum = sum + value
    end
    filter.sum = sum
    -- Reset current to nil if no samples.
    if #filter.samples > 0 then
        filter.current = filter.sum / #filter.samples
    else
        filter.current = nil
    end
end

-- Clear samples.
function Depth_Filter.Clear(filter)
    filter.samples = {}
    filter.next    = 1
    filter.sum     = 0
    filter.current = nil
end

------------------------------------------------------------------------------
-- Alternate filter, time based instead of depth based.
-- This will be the new default.
local Filter = {}

-- Make a new filter, set for "use_realtime" to base on realtime timeout,
-- eg. for cases where jitter is observed in paused games, else uses gametime.
function Filter.New (use_realtime, default_update_period)
    local data = {
        use_realtime = use_realtime,
        default_update_period = default_update_period,
    }
    Filter.Clear(data)
    return data
end

-- Init/clear the filter.
function Filter.Clear(filter)

    -- List of samples, where each is a sublist of [real_timestamp, game_timestamp, value].
    -- This will grow dynamically as needed, but will not shrink.
    -- Invalidated entries may be present with a nil timestamp, but all
    -- entries will contain the sublists to be overwritten as needed.
    filter.samples = {}

    -- Index of the newest entry.
    -- New samples will be stored after this (or at index 1 if this is
    -- the last array index and index 1 is free).
    -- Init to 0; logic works out for first insertion.
    filter.newest = 0
    -- Index of the oldest entry that is still valid, or if all are invalid,
    -- then the index of the next entry expected to be added.
    -- Anything older will have been invalidated (nil timestamp).
    -- Init to 1; logic works out for first insertion.
    filter.oldest = 1

    -- Number of currently valid samples.
    filter.valid_samples = 0

    -- Time after which samples are dropped, in seconds (may be float).
    -- (Speed will use this by default for now.)
    filter.timeout = 0.2
    -- Running sum of values.
    filter.sum = 0

    -- How frequently the resulting values are output to users.
    -- This is used to regulate the ui update rate, since it doesn't need
    -- to change every frame.
    -- Can go with 1/10th of a second for now.
    -- TODO: maybe tune based on distance.
    filter.summary_period = filter.default_update_period
    -- Time of the last summary update.
    filter.last_summary_time = 0

    -- Summary values, not updated every frame.
    -- Current average value. Note: float.
    filter.current = nil
    -- The average delta from newest to oldest, or nil.
    filter.delta = nil
end


-- Add a new sample, and return the current average value.
-- Stores returned value in "current".
function Filter.Update(filter, sample)
    -- Convenience renaming.
    local samples = filter.samples

    -- Select the current time, from gametime or realtime.
    local time
    if filter.use_realtime then
        time = GetCurRealTime()
    else
        time = GetCurTime()
    end

    -- Note how far back the filter should go; older entries should be dropped.
    local cutoff_time = time - filter.timeout

    -- Update invalidations, starting from the oldest entry.
    -- Can only do this as long as at least one valid sample remains.
    -- Update: when testing 2x job counts and the game performed at 5fps,
    -- the refresh rate on the monitor dropped to where all samples were
    -- timing out regularly. As a workaround, always keep a couple samples
    -- regardless of timeout.
    while filter.valid_samples > 2 do
        -- Check the oldest timestamp.
        if samples[filter.oldest][1] < cutoff_time then

            -- Too old, invalidate and move to the next sample.
            samples[filter.oldest][1] = nil
            filter.sum = filter.sum - samples[filter.oldest][2]
            filter.valid_samples = filter.valid_samples - 1

            -- Inc with rollover.
            filter.oldest = filter.oldest + 1
            if filter.oldest > #samples then
                filter.oldest = 1
            end
        else
            -- Oldest is still valid, so stop looking.
            break
        end
    end
    
    -- Set up the location for the new value.
    local insert_index
    -- Can reuse the newest+1 entry if it is present but invalid.
    -- If newest is at the end of the array, try the first array location.
    local post_newest = filter.newest + 1
    if post_newest > #samples then
        post_newest = 1
    end
    if samples[post_newest] and not samples[post_newest][1] then
        insert_index = post_newest
    -- Otherwise, if the newest is at the end of the array, can append
    -- the new value to grow the array, or if the newest is in the middle,
    -- can insert a location. Either way works the same.
    else
        insert_index = filter.newest + 1
        -- Make a spot.
        table.insert(samples, insert_index, nil)
        -- Adjust the oldest index, if after this spot.
        -- (The oldest could be before, if everything after this spot
        -- has been invalidated, or this is at the end of the list.)
        if filter.oldest >= insert_index then
            filter.oldest = filter.oldest + 1
        end
    end

    -- Store the new value.
    samples[insert_index] = {time, sample}
    filter.sum = filter.sum + sample
    filter.valid_samples = filter.valid_samples + 1
    filter.newest = insert_index
    -- If this is the only valid sample, set it as oldest.
    if filter.valid_samples == 1 then
        filter.oldest = insert_index
    end

    -- Update the summary, if needed.
    -- Based on real time.
    local now = GetCurRealTime()
    if now > filter.last_summary_time + filter.summary_period then
        filter.last_summary_time = now

        -- Calculate the average.
        -- TODO: this summation might not be entirely stable over time,
        -- so every so many samples recompute the total sum.
        -- (This gets reset anyway when the player changes targets.)
        filter.current = filter.sum / filter.valid_samples

        -- Calculate the delta.
        local old_sample = filter.samples[filter.oldest]
        local new_sample = filter.samples[filter.newest]

        -- Check for not having samples, or time not changing.
        if filter.valid_samples == 0 or old_sample[1] == new_sample[1] then
            filter.delta = nil
        else
            local time_delta  = new_sample[1] - old_sample[1]
            local value_delta = new_sample[2] - old_sample[2]
            filter.delta = value_delta / time_delta
        end
    end
end


-- Change the timeout for the filter.
-- Sample updates occur after the next Update call.
function Filter.Change_Timeout(filter, new_timeout)
    -- Safety against 0, negative, or just too large.
    if new_timeout <= 0 or new_timeout > 100 then
        Print_Error("Filter.Change_Timeout rejecting "..tostring(new_timeout))
        return
    end
    filter.timeout = new_timeout
end

-- Change how often the summary 'current' and 'delta' values recompute.
function Filter.Change_Summary_Period(filter, new_period)
    filter.summary_period = new_period
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

    -- Init filters.
    -- Speed is realtime, distance is gametime.
    -- Speed can update fast; distance will update slower to reduce jitter.
    -- TODO: maybe go back to a depth filter for speed, if good enough.
    L.filter_speed      = Filter.New(true, 0.03)
    L.filter_distance   = Filter.New(false, 0.1)
    
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

            Print_Error("Unrecognized target monitor setting: "..tostring(L.md_field))
        end
    end
end

------------------------------------------------------------------------------
-- Generic text support functions.

-- Given a color table, brightens and returns it. Alpha is unchanged.
-- TODO: maybe rethink this whole algorithm; complicated and doesn't work
-- well on red vs purple. Maybe something more color specific would
-- be better.
function L.Brighten_Color(color, target_brightness)
    if color == nil then return color end

    -- Determine the total brightness of the existing color.
    local orig_brightness = color.r + color.g + color.b
    -- If target already met, return unchanged.
    if orig_brightness >= target_brightness  then
        return color
    end

    -- Determine the desired amount of upscaling to reach the
    -- target brightness. Should be >1.
    local target_ratio = target_brightness / orig_brightness

    -- Determine the maximum amount the color can be brightened while
    -- maintaining the color balance.
    -- This depends on whichever channel is closest to 255.
    local max_ratio
    for i, channel in ipairs(L.color_channels) do
        -- Eg. if color is 128, then the ratio is ~2.
        local this_ratio = 255 / color[channel]
        -- Keep the smallest ratio.
        if max_ratio == nil or this_ratio < max_ratio then
            max_ratio = this_ratio
        end
    end

    -- Use the smaller ratio.
    if max_ratio < target_ratio then
        target_ratio = max_ratio
    end

    -- Apply this ratio to all channels.  Keep original alpha (maybe nil).
    local new_color = {a = color.a}
    for i, channel in ipairs(L.color_channels) do
        -- Round to an integer.
        new_color[channel] = math.floor(color[channel] * target_ratio + 0.5)
        -- Safety limits.
        if new_color[channel] > 255 then new_color[channel] = 255 end
        if new_color[channel] < 0   then new_color[channel] = 0 end
    end


    -- The above may not have hit the brightness target, eg. an original
    -- channel with a 0 value would still be 0.
    -- Fall back on generically lightening channels uniformly.
    -- This shouldn't need more than 3 loops.
    for loops=1,3 do

        -- Compute amount still needed.
        local new_brightness = new_color.r + new_color.g + new_color.b
        local remaining_amount = target_brightness - new_brightness

        -- Figure out how many channels are not saturated, 1-3.
        local unsaturated_channels = 0
        for i, channel in ipairs(L.color_channels) do
            if new_color[channel] < 255 then
                unsaturated_channels = unsaturated_channels + 1
            end
        end

        -- Distribute remaining_amount to unsaturated channels.
        local amount_per_channel = remaining_amount / unsaturated_channels
        for i, channel in ipairs(L.color_channels) do
            if new_color[channel] < 255 then
                new_color[channel] = new_color[channel] + amount_per_channel
                -- Saturate.
                if new_color[channel] > 255 then new_color[channel] = 255 end
            end
        end
    end

    -- Removed; old algorithm made already-readable colors too light.
    --local new_color = {}
    --for key, value in pairs(color) do
    --    if key == "r" or key == "g" or key == "b" then
    --        -- Adjust based on distance from 255.
    --        new_color[key] = value + math.floor((255 - value) * color_brightening_factor)
    --        -- Safety limits.
    --        if new_color[key] > 255 then new_color[key] = 255 end
    --        if new_color[key] < 0   then new_color[key] = 0 end
    --    else
    --        new_color[key] = color
    --    end
    --end
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
    -- Note: unused in favor of distance_delta.
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

        -- Some rows have no entry on the right; isolate the text or nil.
        local right_text
        if row.right ~= nil then
            right_text = row.right.text
        end

        -- Check all cases, defaulting to unknown.
        if right_text == "$hullpercent$%" then
            orig.hull = row

        elseif right_text == "$shieldpercent$%" then
            orig.shield = row

        elseif right_text == "$aicommand$" then
            orig.command_0 = row

        elseif right_text == "$aicommandaction$" then
            orig.command_1 = row

        elseif right_text == "$crew$" then
            orig.crew = row
            -- Storage always preceeds crew, though its format isn't
            -- always the same, so fill here.
            orig.storage = text_rows[i -1]

        elseif right_text == "$revealpercent$%" then
            orig.reveal = row

        elseif right_text == "$commander$" then
            orig.commander = row

        elseif right_text == "$buildingprogress$%" then
            orig.building = row
        else
            table.insert(orig.unknowns, row)
        end
    end
    return orig
end

-- Clean up a row list by removing nil entries, as well as any rows
-- past the 7th.
-- TODO: maybe remove empty rows (left/right are empty).
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
-- Also may update the targetdata table with some annotation,
-- eg. if the target has a speed value.
function L.Get_New_Rows(targetdata, original_rows, row_specs, col_specs)
    -- Convenience renaming.
    local component = targetdata.component

    -- Convenience renaming.
    local orig  = original_rows
    local rows = row_specs
    local cols = col_specs

    local has_shields = GetComponentData(component, "shieldmax") ~= 0
    -- Term for shields or blank if unshielded.
    local col_left_shield_blank = has_shields and cols.left.shield or ""
    
    -- Some of these objects don't work with the sector position lookup
    -- function.  Pending tweaks, adjust their distance/eta to be
    -- hidden.
    -- TODO: maybe support some of these by checking for their container.
    -- TODO: at least some object can still give errors, not included here,
    -- though it hasn't been reproduceable yet (just observed errors in log).
    if     IsComponentClass(component, "turret")
    or     IsComponentClass(component, "weapon")
    or     IsComponentClass(component, "shieldgenerator")
    or     IsComponentClass(component, "engine")
    or     IsComponentClass(component, "module")
    -- Note" "highway" covers the generated nodes along a zone highway,
    -- as well as the gates of super highways and entry/exit points of
    -- zone highways.
    -- TODO: distinguish these.
    or     IsComponentClass(component, "highway") 
    or     IsComponentClass(component, "zone")
    or     IsComponentClass(component, "signalleak")
    or     IsComponentClass(component, "dockingbay")
    or     IsComponentConstruction(component)
    then
        cols_distance_delta = ""
        cols_right_eta      = ""
    else
        cols_distance_delta = cols.distance_delta
        cols_right_eta      = cols.right.eta
    end

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
            Make_Row(col_left_shield_blank, cols_distance_delta),
            Make_Row(cols.left.hull,        cols.speed),
            -- Pack in crew on the left, eta right.
            Make_Row(cols.left.crew,        cols_right_eta),
            -- TODO: pack in crew, maybe storage (though that is trickier
            -- to put together, and may be too long).
            -- Continue with normal stuff.
            orig.command_0,
            orig.command_1,
            orig.storage,
            --orig.crew,
            orig.building,
        }
        targetdata.has_speed = true
    
    -- TODO: for this other stuff, also include a type field like ships,
    -- eg. 'station', 'gate', etc., since the standard ui doesn't indicate
    -- this in any way beyond the object name, which doesn't work for gates
    -- which instead display a target sector.
    elseif IsComponentClass(component, "station") then
        new_rows = {
            orig.reveal,
            Make_Row(col_left_shield_blank, cols_distance_delta),
            Make_Row(cols.left.hull,        ""),
            Make_Row("",                    cols_right_eta),
            orig.command_0,
            orig.command_1,
            orig.building,
        }
        
    -- Some mines can move, so include speed.
    elseif IsComponentClass(component, "mine")
    then
        new_rows = {
            Make_Row(col_left_shield_blank, cols_distance_delta),
            Make_Row(cols.left.hull,        cols.speed),
            Make_Row("",                    cols_right_eta),
        }
        targetdata.has_speed = true

    -- Objects that can't move.
    elseif IsComponentClass(component, "asteroid")
    or     IsComponentClass(component, "collectable")
    or     IsComponentClass(component, "crate")
    or     IsComponentClass(component, "lockbox")
    or     IsComponentClass(component, "navbeacon")
    or     IsComponentClass(component, "resourceprobe")
    or     IsComponentClass(component, "satellite")
    -- Ship subsystems treated as speedless for now; todo: support speed
    -- based on parent ship.
    or     IsComponentClass(component, "turret")
    or     IsComponentClass(component, "shieldgenerator")
    or     IsComponentClass(component, "engine")
    or     IsComponentClass(component, "module")
    or     IsComponentConstruction(component)
    then
        new_rows = {
            Make_Row(col_left_shield_blank, cols_distance_delta),
            Make_Row(cols.left.hull,        ""),
            Make_Row("",                    cols_right_eta),
        }
                
    -- Static objects without hull/shield.
    elseif IsComponentClass(component, "gate")
    -- Note: entry/exit gates never seem to be matched, just highway.
    or     IsComponentClass(component, "highwayentrygate")
    or     IsComponentClass(component, "highwayexitgate")
    or     IsComponentClass(component, "highway")
    or     IsComponentClass(component, "zone")
    or     IsComponentClass(component, "signalleak")
    or     IsComponentClass(component, "dockingbay")
    -- Data vaults have no special class; they are just "object"; try
    -- this as a catch-all.
    or     IsComponentClass(component, "object")
    -- Wrecks
    or not IsComponentOperational(component)
    then
        --if IsComponentClass(component, "highwayentrygate") then
        --    DebugError("is highwayentrygate")
        --end
        --if IsComponentClass(component, "highwayexitgate") then
        --    DebugError("is highwayexitgate")
        --end
        --if IsComponentClass(component, "highway") then
        --    DebugError("is highway")
        --end
        new_rows = {
            Make_Row("",               cols_distance_delta),
            Make_Row("",               cols_right_eta),
        }
        
        
    -- TODO: npcs are entities (eg. with skill popup);
    -- anything interesting to add?
    --elseif IsComponentClass(component, "entity")
        
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
-- Patching the primary function that lays out the ui rows.

-- All logic for modifying the target monitor specification table.
-- Edits in-place.
function L.Process_Monitor_Spec(component, templateConnectionName, full_spec)
    local component64 = ConvertIDTo64Bit(component)

    -- To look up speed in GetLiveData, might need to save some info
    -- from the GetTargetMonitorDetails call (unless there is another
    -- way to rebuild it).
    -- (Need to do this before fast exit checks.)
    L.targetdata = { }
    L.targetdata.component = component
    L.targetdata.component64 = component64
    L.targetdata.templateConnectionName = templateConnectionName
    L.targetdata.triggeredConnectionName = (
        templateConnectionName ~= "" 
        and ffi.string(C.GetCompSlotPlayerActionTriggeredConnection(
            component64, templateConnectionName)) 
        or "")
    L.targetdata.has_speed = false
    L.targetdata.distance_error = false
        
    -- Hand off to helper functions based on object type.
    local orig = L.Categorize_Original_Rows(full_spec.text)    
    local new_rows = L.Get_New_Rows(L.targetdata, orig, L.specs.rows, L.specs.cols)
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
        -- (This seems to be a C type, string, empty if no faction,
        -- so check for empty string.)
        local factionID_str = ffi.string(faction_details.factionID)
        if factionID_str and factionID_str ~= "" then
            local faction_color = GetFactionData(factionID_str, "color")
            if faction_color then
                full_spec.header.color = L.Brighten_Color(faction_color, L.faction_color_target_brightness)
            end
        end
    end
end


function L.Patch_GetTargetMonitorDetails()
    local ego_GetTargetMonitorDetails = GetTargetMonitorDetails
    GetTargetMonitorDetails = function(component, templateConnectionName)

        -- Get the standard table data.
        local full_spec = ego_GetTargetMonitorDetails(component, templateConnectionName)
        
        -- Quick exit when disabled or something went wrong.
        if (not L.settings.enabled) or (full_spec == nil) or (full_spec.text == nil) then
            return full_spec
        end

        local success, error = pcall(L.Process_Monitor_Spec, 
            component, templateConnectionName, full_spec)
        if success == false then
            Print_Error(error)
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
    GetLiveData = function(placeholder, component, templateConnectionName)

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
                --L.last_distance    = nil
                L.last_update_time = nil

                Filter.Clear(L.filter_speed)
                Filter.Clear(L.filter_distance)
                --for key, filter in pairs(L.filters) do
                --    Filter.Clear(filter)
                --end
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

        return ego_GetLiveData(placeholder, component, templateConnectionName)
    end
end



------------------------------------------------------------------------------
-- Get target ship's speed.
-- Run it through the smoothing filter before returning.

function L.Get_Speed(targetdata)
    local componentDetails = C.GetComponentDetails(
                                    targetdata.component64, 
                                    targetdata.triggeredConnectionName)
    -- Get speed, with smoothing, since per-frame jitter has been observed.
    Filter.Update(L.filter_speed, componentDetails.speed)
    return math.floor(L.filter_speed.current).." "..T.units["m/s"]
end

------------------------------------------------------------------------------

-- -Removed; didn't help prevent errors (they are deeper than pcall sees).
---- Wrapper function on C.GetObjectPositionInSector, since it may
---- be sometimes triggering errors (perhaps GetPlayerObjectID isn't
---- always valid?).
---- Returns nil on error.
--local function GetObjectPositionInSector(object)
--    local success, result = pcall(C.GetObjectPositionInSector, object)
--    if success then
--        return result
--    else
--        -- Something went wrong. Maybe bad player object?
--        -- TODO: try to catch this sometime; leave printout disabled
--        -- for now to avoid spamming log.
--        -- Result: the problem is some other file; this trigger is
--        -- never hit.
--        --Print_Error("C.GetObjectPositionInSector error: "..tostring(result))
--        return nil
--    end
--end

-- Returns a string for target's distance, and updates internal
-- values used in relative speed and ETA.
function L.Get_Distance(targetdata)

    -- Only sample a new distance when the game time has advanced.
    -- Also skip if there was a GetObjectPositionInSector error on a
    -- prior update, since in practice that function will just keep
    -- getting errors for this target.
    local now = GetCurTime()
    if targetdata.distance_error == false and now ~= L.last_update_time then
        L.last_update_time = now
    
        --local playertarget = ConvertIDTo64Bit(GetPlayerTarget())
        -- Or maybe this, gives x/y/z of player target:
        -- C.GetPlayerTargetOffset()
        -- Note: GetPlayerTargetOffset has been observed (rarely) to return bad z
        -- data for a superhighway when it was selected with no prior target; z data
        -- was correct if there was a prior target. No ideas on why.
        --local t_off = C.GetPlayerTargetOffset()
        --local t_off = C.GetObjectPositionInSector(ConvertIDTo64Bit(GetPlayerTarget()))

        -- Work off the player target object instead; more reliable in testing.
        -- Buffer into an ffi object like menu_interactmenu does.
        -- Note: Some targets fail at this, eg. signal leaks; is there a good way
        -- to detect such failures here? For now, just prune it above when
        -- selecting the rows to display.
        local t_off = ffi.new("UIPosRot")
        t_off = C.GetObjectPositionInSector(targetdata.component64)
    
        --if t_off then
        --    DebugError("x "..t_off.x .." y "..t_off.y .." z "..t_off.z)
        --end

        -- This gets pos of an object; try to get player ship or player.
        -- Need to use player directly, so this works when outside a ship.
        local p_off = ffi.new("UIPosRot")
        p_off = C.GetObjectPositionInSector(C.GetPlayerObjectID())

        if t_off and p_off then
            local distance = ((t_off.x - p_off.x)^2
                            + (t_off.y - p_off.y)^2
                            + (t_off.z - p_off.z)^2 ) ^ 0.5
            -- Note: distances seem fairly smooth floats, and should be reliable.
            --DebugError("distance: "..tostring(distance))

            -- Note: don't round this number yet; at high framerates and slow
            -- speeds the differences between samples can easily be well below
            -- the decimal point.

            -- Update filter timeout based on this distance.
            -- Further objects need more filtering. Unclear on good timeouts,
            -- but can fiddle with this until happy.
            -- Shorter range should be more responsive.
            local distance_km = distance / 1000
            local filter_timeout
            local summary_period
            -- Just hand set based on distance cuttoffs for now, to easily tune.
            -- Also adjust the ui update rate, slower for distance objects
            -- that are more prone to jitter.
            -- Unmoving objects will use a shorter timeout regardless of distance,
            -- to quickly reflect player speed changes.
            if not targetdata.has_speed then
                filter_timeout = 0.1
                summary_period = 0.03
            elseif distance_km > 90 then
                filter_timeout = 3.0
                summary_period = 0.15
            elseif distance_km > 70 then
                filter_timeout = 2.0
                summary_period = 0.10
            elseif distance_km > 50 then
                filter_timeout = 1.0
                summary_period = 0.08
            elseif distance_km > 30 then
                filter_timeout = 0.4
                summary_period = 0.05
            else
                filter_timeout = 0.2
                summary_period = 0.03
            end
            Filter.Change_Timeout(L.filter_distance, filter_timeout)
            Filter.Change_Summary_Period(L.filter_distance, summary_period)
            
            
            -- Save it in the filter.
            Filter.Update(L.filter_distance, distance)

        else
            -- Clear out data that eta uses; it should also be unknown.
            Filter.Clear(L.filter_distance)
            -- To avoid the log getting spammed with errors, flag this
            -- target to fail future distance checks.
            targetdata.distance_error = true
        end
    end

    -- Grab the current value, if any.
    local distance = L.filter_distance.current
    if distance then        
        -- Suffix it.
        return L.Value_To_Rounded_Text(distance, T.units["m"], T.units["km"], false)
    end

    return "..."
end


-- Returns a string for the current distance delta.
-- Ideally called after the delta was updated.
-- "suffix" is bool, true if this is a suffix to distance (always include
--  sign, and round if large).
function L.Get_Relative_Speed(targetdata, suffix)

    -- Calculate based on the total change in distance and change in time
    -- in the distance filter.
    local rel_speed = L.filter_distance.delta

    -- Skip if unknown.
    if rel_speed == nil then 
        return "+...".." "..T.units["m/s"]
    end
    
    -- Note: a small ship next to a large one, with 0 relative speed, will
    -- alternate slightly positive and slightly negative.
    -- Try to clean that up here, to avoid the printed sign bouncing
    -- back and forth.
    rel_speed = math.floor(rel_speed + 0.5)

    -- To avoid distance lines getting too long, compress it to km/s if large.
    local ret_str
    if suffix then
        ret_str = L.Value_To_Rounded_Text(rel_speed, T.units["m/s"], T.units["km/s"], true)
    else 
        ret_str = tostring(math.floor(value + 0.5)).." "..T.units["m/s"]
    end

    return ret_str
end

-- Returns a string for the ETA.
-- Ideally runs after Get_Distance.
-- TODO: maybe limit update rate to every half second, to reduce jankiness
-- in some situations.
function L.Get_ETA(targetdata)
    -- Get the current distance, and change rate (rel speed).
    local distance  = L.filter_distance.current
    local rel_speed = L.filter_distance.delta

    -- Skip if distance and/or relative speed unknown.
    if distance  == nil or rel_speed == nil then 
        return "--" 
    end

    -- Based on relative speed and distance.
    -- Discount the arrival_tolerance from the distance; may already be
    -- considered arrived if close.
    -- TODO: tune this based on ship sizing.
    local remaining_distance = distance - L.arrival_tolerance
    if remaining_distance <= 0 then
        return "--"
    end
    -- Relative speed is negative for closing, so flip the sign.
    local eta = 0 - (remaining_distance / rel_speed)

    -- When in seta, time is sped up 5x.
    -- Account for that here.  TODO: maybe make optional.
    if GetPlayerActivity() == "seta" then
        eta = eta / 5
    end

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
function L.Value_To_Rounded_Text(value, units, kilounits, force_sign)
    local ret_str

    -- Maybe force a + sign.
    local fmt_pre
    if force_sign then
        fmt_pre = "%+"
    else
        fmt_pre = "%"
    end

    if value >= 1000 then
        return string.format(fmt_pre..".1f %s", value/1000, kilounits)
    else
        return string.format(fmt_pre..".0f %s", value, units)
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
    --local macro = GetComponentData(targetdata.component, "macro")
    --local macroclass = ffi.string(C.GetMacroClass(macro))
    -- The above 2 lines work fine, but can be done in one line.
    local macroclass = ffi.string(C.GetComponentClass(targetdata.component64))

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
    
    -- Note: some ships don't have a type (unclear on if the shiptypename
    -- will have already cleaned up this case), eg. boarding pods.
    -- TODO: maybe clean up if boarding pods give odd results.
    
    -- Pick what to return.  Go with type and size for now.
    local ret_string = tostring(shiptypename).." "..tostring(size_name)

    -- Maybe append the x3 class.
    if L.settings.show_x3_class then
        local x3_class = L.Get_X3_Class(macroclass, purpose, shiptype)
        if x3_class then
            ret_string = ret_string.." ("..x3_class..")"
        end
    end

    return ret_string
end

-- Return a string for the X3 style class name.
-- If no match found, returns nil.
function L.Get_X3_Class(macroclass, purpose, shiptype)

    -- This will require a bit of work to lay out different cases, but
    -- should be doable.
    -- Look up by ship type first, then purpose.
    local size_table
    local x3_class
    
    -- Clumsy to do this double lookup, but should work okay.
    size_table = T.x3_class_names[shiptype]
    if size_table then 
        x3_class = size_table[macroclass] 
    end

    if not x3_class then
        size_table = T.x3_class_names[purpose]
        if size_table then 
            x3_class = size_table[macroclass] 
        end
    end
    
    return x3_class
end

------------------------------------------------------------------------------


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


Register_Require_With_Init(
    "extensions.sn_better_target_monitor.ui.Target_Monitor", 
    L, L.Init_TargetMonitor)
-- For possible backward compatability.
Register_Require_Response(
    "extensions.sn_better_target_monitor.lua_interface", L)

return L