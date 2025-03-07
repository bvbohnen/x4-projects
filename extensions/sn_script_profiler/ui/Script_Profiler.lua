Lua_Loader.define("extensions.sn_script_profiler.lua.Script_Profiler",function(require)
--[[
Lua side of performance profiling.

AI/MD timestamped events will be sent here for processing.

Event message format:
    {section_name},{location_name},{path_bound},{formatted_time}
Where:
    section_name includes the file name and cue/lib name (if relevant).
    location_name is some descriptive term, likely including line number.
    path_bound is one of "entry","mid","exit".
    formatted_time has the format: {year}-{day}-{hour}-{minute}-{second}

Events represent specific points in the code being visited by scripts.
Lua code will track two aspects of events:
- Number of times each event is seen.
- Time delay between each pair of events in the same file.

Note: md cues can call libs or other cues (instantly) before returning, so
this will be set up to track both the calling cue's start/end points as
well as the callee points.

Operation:
- AI or MD script raises a lua signal with the above message.
- Multiple such messages are expected to be signalled before lua processing,
  eg. normally at least two (start/end of a code block).
- Lua parses the message into parts: section_name, event_name, time (deformatted).
- Lua sums up events seen.
- Last and current event, if the same section_name, form a path.
- Path name: {section_name},{start event_name},{end event_name}
- Time delta computed for the path on this visit.
- Overall path metrics will include: total time, min time, max time.

A special MD performance script will signal to lua when it wants the
measurements back. This will cause lua to clear measurements for
the next time period.

TODO: think about extra safety against a missed path "exit", which may
lead to the prior_message appearing valid to a later message when it
should have been invalidated.

]]

local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef struct {
        double fps;
        double moveTime;
        double renderTime;
        double gpuTime;
    } FPSDetails;
    FPSDetails GetFPS();
]]

-- Inherited lua stuff from support apis.
local Lib   = require("extensions.sn_mod_support_apis.lua_interface").Library
local Pipes = require("extensions.sn_mod_support_apis.lua_interface").Pipes

-- Table of local functions and data.
local L = {
    debug = true,

    -- Table of prior seen events, keyed by section_name, with data subtable.
    -- Eg. a given cue will show up separately from a lib it calls, so this
    -- can hold both the cue entry and the lib entry.
    -- Subtables include section_name (redundant), location, path_bound, time,
    -- engine_time, message.
    -- This will not record "exit" path_bounds, as those will clear entries
    -- instead.
    prior_events = {},

    -- Table, keyed by script and event name, with the number of occurrences.
    event_counts = {},

    -- Table, keyed by script name and pairs of event names, with a subtable
    -- holding: 'sum' (across all visits), 'min', 'max', 'count' (visits).
    path_times = {},

    -- Game time when paths started gathering, since last reset or clear.
    path_gather_start_time = nil,

    -- Point at which the timer rolls over.
    -- Based on the exe edit limiting the fundamental timer to 32-bits.
    rollover = math.pow(2, 32),
    rollover_halved = math.pow(2, 31),
    }
    

function Init()
    -- Transmits all recorded data.
    RegisterEvent("Script_Profiler.Send_Script_Info", L.Send_Script_Info)

    -- Recorder for captured timestamped events, with timestamps in a
    -- "year,day,hour,minute,second"
    -- format, where a "second" is actually 100 ns.
    RegisterEvent("Script_Profiler.Record_Event", L.Record_Event)
    
    L.path_gather_start_time = GetCurTime()
end

-- Send collacted data straight to the pipe.
function L.Send_Script_Info()

    -- Transmit the time elapsed since paths started gathering.
    -- TODO: if server restarted, somehow this transmits to the new server,
    -- then causes it to shut down and restart. why??
    Pipes.Schedule_Write("x4_script_profile", nil, string.format(
        "update;path_metrics_timespan:%f;", GetCurTime() - L.path_gather_start_time))
    
    -- Collect the data into a big string for python side processing.
    -- To maybe speed this up, put substrings into a bit list, then
    -- use table.concat to join them.
    -- General format: command;key:value;key:value;...
    for i, field in ipairs({"event_counts", "path_times"}) do
        -- Skip transmit if nothing was recorded.
        local send = false
        local str_table = {field..";"}
        for key, value in pairs(L[field]) do
            -- path_times need more work to break out sum/min/max/count;
            -- do those with comma separation.
            if field == "path_times" then
                value = string.format("%d,%d,%d,%d", value.sum, value.min, value.max, value.count)
            end
            table.insert(str_table, key..":"..value..";")
            send = true
        end
        if send then
            local message = table.concat(str_table)
            DebugError("Sending "..field..", items: "..#str_table..", size: "..string.len(message))
            -- No callback for now.
            Pipes.Schedule_Write("x4_script_profile", nil, message)
        end
        -- Clear old info (for now).
        L[field] = {}
    end

    -- Reset the timer.
    L.path_gather_start_time = GetCurTime()

    --Lib.Print_Table(L.event_counts, "event_counts")
    --Lib.Print_Table(L.path_times, "path_times")

    --AddUITriggeredEvent("Script_Profiler", "Script_Info", {
    --    gametime     = GetCurTime(),
    --    fps          = C.GetFPS().fps,
    --    event_counts = L.event_counts,
    --    path_times   = L.path_times,
    --})

end

-- TODO: maybe manually count frames elapsed per second, for aid in
-- precisely saying how much script compute time was taken per frame.

-- Event recorder.
function L.Record_Event(_, message)

    -- Break up message on commas.
    local section_name, location, path_bound, time_string = unpack(Lib.Split_String_Multi(message, ","))

    -- Print the first few for debugging.
    local print_this = false
    if L.debug then
        if L.messages_printed == nil then L.messages_printed = 0 end
        -- Normally md runs first; quick hack: look for "a" to check ai.
        if L.messages_printed < 10 then-- and string.sub(section_name, 1, 1) == "a" then
            print_this = true
            L.messages_printed = L.messages_printed + 1
        end
    end

    if print_this then
        DebugError("Perf Message: "..tostring(message))
    end

    -- Add to event counter. Events named after section and location.
    local event_name = section_name .. "," .. location
    if L.event_counts[event_name] == nil then
        L.event_counts[event_name] = 1
    else
        L.event_counts[event_name] = L.event_counts[event_name] + 1
    end

    -- Convert the time string to a time.
    local time = L.Deformat_Time(time_string)
    
    if print_this then
        DebugError("Deformatted time: "..tostring(time))
    end

    -- Track the frame time.
    local engine_time = GetCurRealTime()
    --if print_this then
    --    DebugError("engine_time: "..tostring(engine_time))
    --end
    -- Convenience renaming.
    local prior_event = L.prior_events[section_name]

    -- Error check: there should be no prior recorded event left over
    -- from an earlier frame.
    if prior_event ~= nil and prior_event.engine_time ~= engine_time then
        DebugError("Error: Leftover non-exit event from earlier frame: "..tostring(prior_event.message))
        -- Clear it for safety, to avoid accidental cross-frame matching.
        L.prior_events[section_name] = nil
        prior_event = nil
    end

    -- TODO: maybe a way to detect if a prior event was from a different
    -- ai script instance (eg. another pilot).

    -- Error check: if not entry, then there should be a prior event (entry
    -- or mid, but don't need to check it).
    if path_bound ~= "entry" and prior_event == nil then
        DebugError("Error: Non-entry event with no prior event match: "..tostring(message))
    end

    -- Error check: if this is entry, there shouldn't be a prior unclosed entry.
    if path_bound == "entry" and prior_event ~= nil and prior_event.path_bound == "entry" then
        DebugError("Error: Entry event with unclosed prior entry, this: "..tostring(message).."   prior: "..tostring(prior_event.message))
    end

    -- Check if there is a prior recorded event matching this section_name,
    -- eg. an md cue entry for this exit.
    if path_bound ~= "entry" and prior_event ~= nil then
    
        -- Path will be the section_name, start location, end location,
        -- comma separated.
        local path = section_name .. "," .. prior_event.location .. "," .. location

        -- Get the time delta.
        -- This may have rolled over, so put in a little extra care.
        local time_delta
        local prior_time = prior_event.time
        if time >= prior_time then
            time_delta = time - prior_time
        -- The numbers should diverge wildly at this point; if not,
        -- something went wrong somewhere.
        -- This check looks for the numbers being with half a rollover still.
        else if time + L.rollover_halved >= prior_time then
            DebugError(string.format("Bad time delta; prior %d, new %d (%s)", prior_time, time, time_string))
            -- Ignore this contribution.
            time_delta = nil
        else
            -- Can add in the rollover as implicitly part of this time.
            time_delta = time + L.rollover - prior_time
            end
        end

        if time_delta ~= nil then        
            if print_this then
                DebugError("Path "..path.." Time delta: "..tostring(time_delta))
            end

            -- Update the table of metrics.
            metrics = L.path_times[path]
            if metrics == nil then
                L.path_times[path] = {
                    sum   = time_delta, 
                    min   = time_delta, 
                    max   = time_delta, 
                    count = 1,
                }
            else
                metrics.count = metrics.count + 1
                metrics.sum   = metrics.sum + time_delta
                if time_delta < metrics.min then
                    metrics.min = time_delta
                end
                if time_delta > metrics.max then
                    metrics.max = time_delta
                end
            end
        end
    end

    -- Record this as the prior event for the next event.
    -- If this was a path exit, clear the prior_event.
    if path_bound ~= "exit" then
        L.prior_events[section_name] = {
            message = message,
            section_name = section_name,
            location = location,
            path_bound = path_bound,
            time = time,
            engine_time = engine_time,
            }
    else
        L.prior_events[section_name] = nil
    end
end

-- Convert a formatted time string to a time number.
-- Returns number of elapsed time units (which depends on timer scaling).
-- Nominally, these will return 100ns units.
function L.Deformat_Time(time_string)
    -- Format: {year}-{day}-{hour}-{minute}-{second}
    local year_str, day_str, hour_str, minute_str, second_str = unpack(Lib.Split_String_Multi(time_string, "-"))

    -- These aren't really seconds, but 100 ns units, though don't
    -- worry about that at the moment.
    -- Combine the terms.
    local year = tonumber(year_str)
    -- Recenter the year count around 1970; not necessary, but limits
    -- counters a little bit for safety and debug readability.
    local num_years = year - 1970
    
    -- Leap years start in 1972. This means the first leap has passed
    -- in 1973 (since want to know an extra day was missed).
    -- Can offset by +1, divide by 4, so first leap is at (3+1).
    local leap_years = math.floor((num_years + 1) / 4)
    -- Every 100 years is a skipped leap, except every 400 years which
    -- retain the leap.
    -- Only check this past 2000, to avoid dealing with negatives.
    if year > 2000 then
        -- Start by removing the 100 entries. First occurrence at 2001,
        -- so offset +(100-31)=69.
        leap_years = leap_years - math.floor((num_years + 69) / 100)
        -- Undo every 400, first occurrence also at 2001, so offset +369.
        leap_years = leap_years + math.floor((num_years + 369) / 400)
    end

    -- Day counts are 1-366; adjust back by 1 to recenter.
    local num_days = tonumber(day_str) - 1
    -- Add standard 365 days/year, plus leap years.
    num_days = num_days + num_years * 365 + leap_years

    -- Hours are 0-23 format, so no extra adjustment.
    local num_hours = tonumber(hour_str) + num_days * 24
    local num_mins = tonumber(minute_str) + num_hours * 60
    local num_secs = tonumber(second_str) + num_mins * 60

    -- Note: source timer was a 64-bit counter truncated to 32-bits, so
    -- the above math should always fit safely in a lua double.
    return num_secs
end


return nil,Init
)