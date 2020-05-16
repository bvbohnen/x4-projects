--[[
This module adds real time support accessible from md.

The motivating use is for md scripts that want to have some delay
between cue calls, but for that delay to run while the game is paused.
The normal MD timing is paused in such cases, since it operates
on game time.

Makes use of the GetCurRealTime() function, available globally, which
appears to return a time in seconds that the game has been active since
loading. (Tabbed-out time not included.)

Note: preliminary testing suggests GetCurRealTime may only update once
each frame, and won't be suitable for in-frame code performance testing.

To allow for proper in-frame timing for performance measurements or
similar, a python pipe server is provided using a proper performance
counter.

TODO: maybe find a more reliable way to detect frame change when paused.
]]

--[[ @doc-functions

Other lua modules may require() this module to access these api functions:

* Register_NewFrame_Callback(function)
  - Sets the function to be called on every frame.
  - Detects frame changes through two methods:
    - onUpdate events (sometimes have gaps)
    - MD signals (when not paused)
  - Some frames may be missed while the game is paused.
  - Callback function is given the current engine time.
* Unregister_NewFrame_Callback(function)
  - Remove a per-frame callback function that was registered.
* Set_Alarm(id, time, function)
  - Sets a single-fire alarm to trigger after the given time elapses.
  - Callback function is called with args: (id, alarm_time), where the
    alarm_time is the original scheduled time of the alarm, which will
    generally be sometime earlier than the current time (due to frame
    boundaries).
* Set_Frame_Alarm(id, frames, function)
  - As above, but measures time in frame switches.

An MD ui event is raised on every frame, which MD cues may listen to.
This differs from a cue firing every 1ms in that this works when paused.
The event.param3 will be the current engine time. Example:
`<event_ui_triggered screen="'Time'" control="'Frame_Advanced'" />`


MD commands are sent using raise_lua_event of the form "Time.<command>",
and responses (if any) are captured in screen "Time" with control "id".
Return values will be in "event.param3".
Note: since multiple users may be accessing the timer during the same period,
each command will take an id unique string parameter.

Commands:
- getEngineTime (id)
  - Returns the current engine operation time in seconds, as a long float.
  - Note: this is the number of seconds since x4 was loaded, counting
    only time while the game has been active (eg. ignores time while
    minimized).
  - Capture the time using event_ui_triggered.
- getSystemTime (id)
  - Returns the system time reported by python through a pipe.
  - Pipe communication will add some delay.
  - Can be used to measure real time passed, even when x4 is minimized.
  - Capture the time using event_ui_triggered.
- startTimer (id)
  - Starts a timer instance under id.
  - If the timer didn't exist, it is created.
- stopTimer (id)
  - Stops a timer instance.
- getTimer (id)
  - Returns the current time of the timer.
  - Accumulated between all Start/Stop periods, and since the last Start.
  - Capture the time using event_ui_triggered.
- resetTimer (id)
  - Resets a timer to 0.
  - If the timer was started, it will keep running.
- printTimer (id)
  - Prints the time on the timer to the debug log.
- tic (id)
  - Starts a fresh timer at time 0.
  - Intended as a convenient 1-shot timing solution.
- toc (id)
  - Stops the timer associated with tic, returns the time measured,
    and prints the time to the debug log.
- setAlarm (id:delay)
  - Sets an alarm to fire after a certain delay, in seconds.
  - Arguments are a concantenated string, colon separated.
  - Detect the alarm using event_ui_triggered.
  - Returns the realtime the alarm was set for, for convenience in
    creating clocks or similar.
  - Note: precision based on game framerate.


- Example: get engine time.
  ```xml
  <cue name="Test" instantiate="true">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>
      <raise_lua_event name="'Time.getEngineTime'" param="'my_test'"/>
    </actions>
    <cues>
      <cue name="Capture" instantiate="true">
        <conditions>
          <event_ui_triggered screen="'Time'" control="'my_test'" />
        </conditions>
        <actions>
          <set_value name="$time" exact="event.param3"/>
        </actions>
      </cue>
    </cues>
  </cue>  
  ```
  
- Example: set an alarm.
  ```xml
  <cue name="Delay_5s" instantiate="true">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>
      <raise_lua_event name="'Time.setAlarm'"  param="'my_alarm:5'"/>
    </actions>
    <cues>
      <cue name="Wakeup" instantiate="true">
        <conditions>
          <event_ui_triggered screen="'Time'" control="'my_alarm'" />
        </conditions>
        <actions>
          <.../>
        </actions>
      </cue>
    </cues>
  </cue>  
  ```
]]

-- Table of data/functions to export to other lua modules on require.
local E = {}

-- Table of local functions and data.
local L = {
    debug = false,
    -- Flag, if true then alarms are being checked every cycle.
    checking_alarms = false,

    -- Last frame update engine time.
    last_frame_time = 0,
    -- Lua functions registered to be called every frame.
    frame_callbacks = {},
    
    -- Table of timers, keyed by id.
    -- Subtables have the fields: {last_start, total, running}
    timers = {},

    -- Table of alarms scheduled. Values are the realtime the alarm
    -- will go off. Keyed by id.
    alarms = {},
    -- As above, but holding 2-element lists with 
    -- {realtime when alarm set up, pending frames until alarm}.
    frame_alarms = {},

    -- Table of lua callbacks per id, for alarms.
    -- These are used for the lua interface alarms, which use callback
    -- functions instead of signals.
    -- Key ids should match those in "alarms" or "frame_alarms" above.
    alarm_callbacks = {},
    }


function Init()
    -- Set up all unique events.
    RegisterEvent("Time.getEngineTime", L.Get_EngineTime)
    RegisterEvent("Time.startTimer"   , L.Start_Timer)
    RegisterEvent("Time.stopTimer"    , L.Stop_Timer)
    RegisterEvent("Time.getTimer"     , L.Get_Timer)
    RegisterEvent("Time.resetTimer"   , L.Reset_Timer)
    RegisterEvent("Time.printTimer"   , L.Print_Timer)
    RegisterEvent("Time.setAlarm"     , L.Set_Alarm)

    -- Misc
    RegisterEvent("Time.MD_New_Frame" , L.New_Frame_Detector)
    
    -- Init loading frame time.
    L.last_frame_time = GetCurRealTime()
    -- Start listening to onUpdate events.
    -- TODO: switch to a more direct hook-in with the widget contract stuff,
    -- if it would be more reliable.
    -- eg. registerForEvent("frameupdate", private.contract, L.New_Frame_Detector)
    SetScript("onUpdate", L.New_Frame_Detector)
end

-- Raise an event for md to capture.
function L.Raise_Signal(name, return_value)
    AddUITriggeredEvent("Time", name, return_value)
end

function L.Get_EngineTime(_, id)
    local now = GetCurRealTime()
    L.Raise_Signal(id, now)
end

------------------------------------------------------------------------------
-- Timer stuff.

-- Make a timer if it doesn't exists.
function L.Make_Timer(id)
    if not L.timers[id] then
        L.timers[id] = {
            start = 0,
            total = 0,
            running = false,
            }
    end
end

-- Update a timer by accumulating any time since its last_check.
-- Sets the new last_check to now.
-- If the timer is not running, will just update last_check.
function L.Update_Timer(id)
    local now = GetCurRealTime()
    if L.timers[id].running then
        L.timers[id].total = L.timers[id].total + now - L.timers[id].last_check
    end
    L.timers[id].last_check = now
end

function L.Start_Timer(_, id)
    L.Make_Timer(id)
    -- Update it, since it may already be running, and needs to initialize
    -- its last_check anyway.
    L.Update_Timer(id)
    L.timers[id].running = true
end

function L.Stop_Timer(_, id)
    L.Make_Timer(id)
    -- Update it, to capture any time up to this stop.
    L.Update_Timer(id)
    L.timers[id].running = false
end

function L.Get_Timer(_, id)
    L.Make_Timer(id)
    -- Make sure it is up to date if still running.
    L.Update_Timer(id)
    L.Raise_Signal(id, L.timers[id].total)
end

function L.Reset_Timer(_, id)
    L.Make_Timer(id)
    -- Update it, mostly to reset the last_check.
    L.Update_Timer(id)
    -- Now reset the total.
    L.timers[id].total = 0
end

function L.Print_Timer(_, id)
    L.Make_Timer(id)
    L.Update_Timer(id)
    -- Put the time in the log.
    DebugError(string.format(
        "Timer id '%s' current total: %f seconds", 
        id, L.timers[id].total))
end

------------------------------------------------------------------------------
-- Versions of tic/toc that were using x4 time.
-- Replacing with python server high precision timing.
-- These have an _old suffix for now.

function L.Tic_old(_, id)
    -- Use the timer system, giving a probably unique name.
    local name = "TicToc_"..id
    -- Reset it, which also makes it if needed.
    L.Reset_Timer(_, name)
    -- Start it off.
    L.Start_Timer(_, name)
    -- TODO: maybe optimize the above to not double-update.
end


function L.Toc_old(_, id)
    -- Use the timer system, giving a probably unique name.
    local name = "TicToc_"..id

    -- Safety in case toc called without tic.
    L.Make_Timer(name)
    -- Get it updated.
    L.Update_Timer(name)

    -- Print it; don't really need to stop it.
    -- Put the time in the log.
    DebugError(string.format(
        "Toc id '%s': %f seconds", 
        id, L.timers[name].total))

    -- Also report it to user.
    L.Raise_Signal(id, L.timers[name].total)
end

------------------------------------------------------------------------------
-- Alarm related functions.

-- Start the alarm poller, if not started yet.
function L.Start_Alarm_Polling()
    if not L.checking_alarms then
        E.Register_NewFrame_Callback(L.Poll_For_Alarm)
        L.checking_alarms = true
        if L.debug then
            DebugError("Time.Set_Alarm started polling")
        end
    end    
end


-- Set up a new time based alarm, from md.
function L.Set_Alarm(_, id_time)
    if L.debug then
        DebugError("Time.Set_Alarm got: "..tostring(id_time))
    end

    -- Split the input to separate id and time.
    local id, time = L.Split_String(id_time)

    -- Time should be a number; may have decimal.
    time = tonumber(time)

    -- Schedule the alarm.
    L.alarms[id] = GetCurRealTime() + time

    -- Start polling if not already.
    L.Start_Alarm_Polling()
end


-- Lua callable, with lua callback, time based alarm.
function E.Set_Alarm(id, time, callback)
    -- Schedule the alarm.
    L.alarms[id] = GetCurRealTime() + time
    -- Record the callback.
    L.alarm_callbacks[id] = callback
    
    -- Start polling if not already.
    L.Start_Alarm_Polling()
end


-- Lua callable, alarm based on frame count.
function E.Set_Frame_Alarm(id, frames, callback)

    -- Schedule the alarm for some frames in the future.
    -- Note: New_Frame_Detector may have already run this frame, or may have
    -- yet to run, or may get skipped this frame entirely (if not started
    -- yes). If it is going to still run this frame, then the below timer
    -- will need to have an extra +1 offset. While it can be determined
    -- if it already ran, it cannot be determined if it will run.
    -- The solution: record the current real time, and frames remaining;
    -- the polling loop will count down frames, but only once the original
    -- time has passed (eg. not on the same frame as registered).
    L.frame_alarms[id] = {GetCurRealTime(), frames}

    -- Record the callback.
    L.alarm_callbacks[id] = callback    
    -- Start polling if not already.
    L.Start_Alarm_Polling()
end


-- Alarm polling, called once each frame while alarms are active,
-- possibly skipping the first frame the first alarm was scheduled.
function L.Poll_For_Alarm()
    local now = GetCurRealTime()

    -- List of ids who's alarms fired this check.
    local ids_to_remove = {}
    -- Flag to indicate there is an alarm that didn't fire yet.
    local alarms_still_pending = false

    -- Check all alarms for triggers.
    for id, time in pairs(L.alarms) do

        if now >= time then
            -- Time reached.
            -- Send back the id and the time that was scheduled, not the
            -- current time, so that alarms can be chained to make clocks.
            -- Use a lua callback if known, else an MD signal.
            if L.alarm_callbacks[id] ~= nil then
                pcall(L.alarm_callbacks[id], id, time)
            else
                L.Raise_Signal(id, time)
            end

            -- Note this id for list removal.
            table.insert(ids_to_remove, id)

        else
            -- Note the alarm didn't fire.
            alarms_still_pending = true
        end
    end
    -- Remove any alarms that fired.
    for i, id in ipairs(ids_to_remove) do
        L.alarms[id] = nil
    end

    -- Check all frame alarms.
    ids_to_remove = {}
    for id, alarm_data in pairs(L.frame_alarms) do

        -- Unpack the alarm data.
        local alarm_start_time, pending_frames = unpack(alarm_data)

        -- If time has advanced since the alarm was set up, count down
        -- a frame.
        if alarm_start_time ~= now then

            -- If this was the last frame, trigger the alarm.
            if pending_frames == 1 then
                -- Frame reached.
                -- Send back the id only; frame count doesn't make sense.
                -- Use a lua callback if known, else an MD signal.
                if L.alarm_callbacks[id] ~= nil then
                    pcall(L.alarm_callbacks[id], id)
                else
                    L.Raise_Signal(id)
                end

                -- Note this id for list removal.
                table.insert(ids_to_remove, id)
            else
                -- Otherwise count down the frames.
                alarm_data[2] = alarm_data[2] - 1
                -- Note the alarm didn't fire.
                alarms_still_pending = true
            end
        else
            -- Note the alarm didn't fire.
            alarms_still_pending = true
        end
    end
    -- Remove any alarms that fired.
    for i, id in ipairs(ids_to_remove) do
        L.frame_alarms[id] = nil
    end


    -- If no alarms remaining, stop polling.
    if not alarms_still_pending then
        --RemoveScript("onUpdate", L.Poll_For_Alarm)
        E.Unregister_NewFrame_Callback(L.Poll_For_Alarm)
        L.checking_alarms = false
        if L.debug then
            DebugError("Time.Set_Alarm stopped polling")
        end
    end
end

-- Split a string on the first colon.
-- Note: works on the MD passed arrays of characters.
-- Returns two substrings.
-- TODO: reuse the shared lib function.
function L.Split_String(this_string)
    -- Get the position of the separator.
    local position = string.find(this_string, ":")
    if position == nil then
        error("Bad separator in: "..tostring(this_string))
    end
    -- Split into pre- and post- separator strings.
    local left  = string.sub(this_string, 0, position -1)
    local right = string.sub(this_string, position +1)    
    return left, right
end


------------------------------------------------------------------------------
-- Every-frame triggers.
--[[
    The "onUpdate" script events normally seem to fire every frame, but
    sometimes can drop out for stretches of time.
    To help with this problem, MD will signal every unpaused frame as well,
    to generate a unified Frame_Advanced detector here.
]]

function L.New_Frame_Detector()
    local now = GetCurRealTime()
    -- Skip if this frame already handled.
    if L.last_frame_time == now then return end

    -- Update recorded time.
    L.last_frame_time = now

    -- Signal MD listeners, returning time for convenience.
    L.Raise_Signal("Frame_Advanced", now)

    -- Handle any callback functions.
    for i, callback in ipairs(L.frame_callbacks) do
        success, message = pcall(callback, now)
        if not success then
            DebugError("Frame Callback function error: "..tostring(message))
        end
    end
end

-- Lua api function for users to register a callback function.
function E.Register_NewFrame_Callback(callback)
    if type(callback) ~= "function" then
        DebugError("Register_Frame_Callback got a non-function: "..type(callback))
        return
    end
    -- Ignore if already registered.
    for index, value in ipairs(L.frame_callbacks) do
        if value == callback then
            return
        end
    end
    table.insert(L.frame_callbacks, callback)
end

-- Lua api function to remove a frame callback.
function E.Unregister_NewFrame_Callback(callback)
    if type(callback) ~= "function" then
        DebugError("Register_Frame_Callback got a non-function: "..type(callback))
        return
    end
    -- Search for it and remove.
    for index, value in ipairs(L.frame_callbacks) do
        if value == callback then
            -- This will edit the table directly, so don't keep looping.
            table.remove(L.frame_callbacks, index)
            break
        end
    end
end


Init()

return E