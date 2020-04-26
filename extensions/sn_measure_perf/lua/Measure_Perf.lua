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

Note: since md cues can call libs, if lib measurements are wanted,
then some extra care is needed to keep the md/lib measurements separated.
TODO: think about this.

Operation:
- AI or MD script raises a lua signal with the above message.
- Multiple such messages are expected to be signalled before lua processing,
  eg. normally at least two (start/end of a code block).
- Lua parses the message into parts: file_name, event_name, time (deformatted).
- Lua sums up events seen.
- Last and current event, if the same file_name, form a path.
- Path name: {file_name},{start event_name},{end event_name}
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
local Lib = require("extensions.sn_mod_support_apis.lua_interface").Library


-- Table of local functions and data.
local L = {
    debug = true,

    -- Table of prior seen events, keyed by section_name, with data subtable.
    -- Eg. a given cue will show up separately from a lib it calls, so this
    -- can hold both the cue entry and the lib entry.
    -- Subtables include section_name (redundant), location, path_bound, time.
    -- This will not record "exit" path_bounds, as those will clear entries
    -- instead.
    prior_events = {},

    -- Table, keyed by script and event name, with the number of occurrences.
    event_counts = {},

    -- Table, keyed by script name and pairs of event names, with a subtable
    -- of summed time spent on the path.
    path_times = {},

    -- Point at which the timer rolls over.
    -- Based on the exe edit limiting the fundamental timer to 32-bits.
    rollover = math.pow(2, 32),
    }
    

function Init()
    -- Sampler of current fps; gets called roughly once a second.
    RegisterEvent("Measure_Perf.Get_Sample", L.Get_Sample)

    -- Returns all recorded data.
    RegisterEvent("Measure_Perf.Get_Script_Info", L.Get_Script_Info)

    -- Recorder for captured timestamped events, with timestamps in a
    -- "year,day,hour,minute,second"
    -- format, where a "second" is actually 100 ns.
    RegisterEvent("Measure_Perf.Record_Event", L.Record_Event)
end

-- Simple sampler, returning framerate and gametime.
function L.Get_Sample()
    AddUITriggeredEvent("Measure_Perf", "Sample", {
        gametime     = GetCurTime(),
        fps          = C.GetFPS().fps,
    })
end

function L.Get_Script_Info()
    -- Collect the data into a big string for python side processing.
    -- TODO

    Lib.Print_Table(L.event_counts, "event_counts")
    Lib.Print_Table(L.path_times, "path_times")

    AddUITriggeredEvent("Measure_Perf", "Script_Info", {
        gametime     = GetCurTime(),
        fps          = C.GetFPS().fps,
        event_counts = L.event_counts,
        path_times   = L.path_times,
    })
    -- Clear old info (for now).
    L.event_counts = {}
    L.path_times = {}
    -- Can probably keep the prior_event.
end

-- TODO: maybe manually count frames elapsed per second, for aid in
-- precisely saying how much script compute time was taken per frame.

-- Event recorder.
function L.Record_Event(_, message)

    -- Print the first few for debugging.
    local print_this = false
    if L.debug then
        if L.messages_printed == nil then L.messages_printed = 0 end
        if L.messages_printed < 10 then
            print_this = true
            L.messages_printed = L.messages_printed + 1
        end
    end

    if print_this then
        DebugError("Perf Message: "..tostring(message))
    end

    -- Break up message on commas.
    local section_name, location, path_bound, time_string = unpack(Lib.Split_String_Multi(message, ","))

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

    -- Check if there is a prior recorded event matching this section_name,
    -- eg. an md cue entry for this exit.
    -- This should not be an entry.
    if L.prior_events.section_name ~= nil and path_bound ~= "entry" then

        -- Path will be the section_name, start location, end location,
        -- comma separated.
        local path = section_name .. "," .. L.prior_events.section_name.location .. "," .. location

        -- Get the time delta.
        -- This may have rolled over, so put in a little extra care.
        local time_delta
        local prior_time = L.prior_events.section_name.time
        if time >= prior_time then
            time_delta = time - prior_time
        else
            -- Can add in the rollover as implicitly part of this time.
            time_delta = time + L.rollover - prior_time
        end
        
        if print_this then
            DebugError("Path "..path.." Time delta: "..tostring(time_delta))
        end

        -- Sum with the prior timer.
        if L.path_times[path] == nil then
            L.path_times[path] = 0            
        end
        L.path_times[path] = L.path_times[path] + time_delta
    end

    -- Record this as the prior event for the next event.
    -- If this was a path exit, clear the prior_event.
    if path_bound ~= "exit" then
        L.prior_events.section_name = {
            section_name = section_name,
            location = location,
            path_bound = path_bound,
            time = time,
            }
    else
        L.prior_events.section_name = nil
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
    local num_years = tonumber(year_str)
    -- Account for leap years from 1970 to ~3000, starting in 1972.
    local num_days = tonumber(day_str) + num_years * 365 + math.floor((num_years - 1968) / 4)
    local num_hours = tonumber(hour_str) + num_days * 24
    local num_mins = tonumber(minute_str) + num_hours * 60
    local num_secs = tonumber(second_str) + num_mins * 60

    -- Note: source timer was a 64-bit counter truncated to 32-bits, so
    -- the above math should always fit safely in a lua double.
    return num_secs
end


Init()


--[[
    Testing an idea:
    If opened conversations from md call to lua immediately, and not in
    a delay until after the cue completes, then they can be used to do
    direct lua function calls. Which would in turn allow for getting
    a high performance counter (with dll plugin) back to the script level.

    MD will use open_menu on the "CallLua" menu. Register it here.

    Test results:
        md open_menu appears to simply raise a lua event.
        When in lua a menu is registerd, Helper will attach a custom
        showMenuCallback function, and register this function to be
        called on the "show<menu_name>" event.
        As such, md open_menu is seemingly equivelent to raising a lua event.

        open_menu: dead end.

    Other things to try:
        uipositionlookup
            Returns conversation highlighted option, 1-6.
            Quick glance finds nothing for this in lua.
        add_player_choice
            ?


    NotifyOnX
        Lua global functions, which are used in low level ui contracts
        that also listen to a similarly named event.
        In testing, such contracts need a NotifyX for their event
        registration to work and get callbacks, but these still have
        a delay on the callback.
        Testing with opening/closing a converstation, listening to
        the conversationFinished event with NotifyOnConversationFinished.

    Results:
        All attempts below failed to trigger until after the md actions
        completed.

]]
--local Lib = require("extensions.sn_mod_support_apis.lua.simple_menu.Library")

--[[
local menu = {
    -- Name of the menu used in registration. Should be unique.
    name = "CallLua",
    -- How often the menu refreshes?
    updateInterval = 0.1,
    -- The main frame, named to match ego code.
    infoFrame = nil,
}

local function Menu_Init()
    -- Register menu; uses its name.
    Menus = Menus or {}
    table.insert(Menus, menu)
    if Helper then
        Helper.registerMenu(menu)
    end
end
Menu_Init()

-- TODO: how to avoid closing existing menus?
function menu.onShowMenu()
    DebugError("CallLua onShowMenu triggered")

    ----Lib.Print_Table(args, "menu_open_args")
    --local player_id = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    --
    ---- Look at what md sent.
    --local arg = GetNPCBlackboard(player_id, "$call_lua_arg")
    --DebugError("CallLua onShowMenu got arg: "..tostring(arg))
    --SetNPCBlackboard(player_id, "$call_lua_arg", nil)
    --
    --
    ---- Write something to the blackboard.
    --SetNPCBlackboard(player_id, "$call_lua_response", 'lua_hello')
    ---- Do nothing further (eg. no frame display).

    -- System thinks this menu is now open; force close it.
    Helper.closeMenu(menu, "close")
end
]]

-- Try out NotifyOnStartDialog.
--[[
local function startDialog(data, time)
    DebugError("Caught startDialog")
end

local function conversationFinished(data, time)
    DebugError("Caught conversationFinished")
end

local function Test_Init()
    DebugError("Creating contract and registering events.")
    local scene           = getElement("Scene")
    local contract        = getElement("UIContract", scene)
    registerForEvent("startDialog", contract, startDialog)
    registerForEvent("conversationFinished", contract, conversationFinished)
    NotifyOnStartDialog(contract)
    NotifyOnConversationFinished(contract)
end
Test_Init()
]]



return