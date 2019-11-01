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
]]

--[[ @doc-functions

General commands are sent using raise_lua_event of the form "Time.<command>",
and responses (if any) are captured in screen "Time" with control "<id>".
Return values will be in "event.param3".

Note: since multiple users may be accessing the timer during the same period,
each command will take an <id> unique string parameter.

Commands:
  - getRealTime (<id>)
    - Returns the current real time in seconds, as a long float.
    - Note: this is the number of seconds since the game was loaded, counting
      only time while the game has been active (eg. ignores time while
      minimized).
    - Capture the time using event_ui_triggered.
  - startTimer (<id>)
    - Starts a timer instance under <id>.
    - If the timer didn't exist, it is created.
  - stopTimer (<id>)
    - Stops a timer instance.
  - getTimer (<id>)
    - Returns the current time of the timer.
    - Accumulated between all Start/Stop periods, and since the last Start.
    - Capture the time using event_ui_triggered.
  - resetTimer (<id>)
    - Resets a timer to 0.
    - If the timer was started, it will keep running.
  - printTimer (<id>)
    - Prints the time on the timer to the debug log.
  - tic (<id>)
    - Starts a fresh timer at time 0.
    - Intended as a convenient 1-shot timing solution.
  - toc (<id>)
    - Stops the timer associated with tic, returns the time measured,
      and prints the time to the debug log.
  - setAlarm (<id>:<delay>)
    - Sets an alarm to fire after a certain delay, in seconds.
    - Arguments are a concantenated string, colon separated.
    - Detect the alarm using event_ui_triggered.
    - Returns the realtime the alarm was set for, for convenience in
      creating clocks or similar.
    - Note: precision based on game framerate.


- Full example: get real time.
  ```xml
  <cue name="Test" instantiate="true">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>
      <raise_lua_event name="'Time.getRealTime'" param="'my_test'"/>
    </actions>
    <cues>
      <cue name="Capture" instantiate="true">
        <conditions>
          <event_ui_triggered screen="'Time'" control="'my_test'" />
        </conditions>
        <actions>
          <set_value name="$realtime" exact="event.param3"/>
        </actions>
      </cue>
    </cues>
  </cue>  
  ```
  
  - Full example: set an alarm.
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

-- Table of local functions and data.
local loc = {
    debug = false,
    -- Flag, if true then alarms are being checked every cycle.
    checking_alarms = false,
    }

-- Table of timers, keyed by id.
-- Subtables have the fields: {last_start, total, running}
loc.timers = {}

-- Table of alarms scheduled. Values are the realtime the alarm
-- will go off.
loc.alarms = {}

function Init()
    -- Set up all unique events.
    RegisterEvent("Time.getRealTime", loc.Get_RealTime)
    RegisterEvent("Time.startTimer" , loc.Start_Timer)
    RegisterEvent("Time.stopTimer"  , loc.Stop_Timer)
    RegisterEvent("Time.getTimer"   , loc.Get_Timer)
    RegisterEvent("Time.resetTimer" , loc.Reset_Timer)
    RegisterEvent("Time.printTimer" , loc.Print_Timer)
    RegisterEvent("Time.tic"        , loc.Tic)
    RegisterEvent("Time.toc"        , loc.Toc)
    RegisterEvent("Time.setAlarm"   , loc.Set_Alarm)
end


-- Raise an event for md to capture.
function loc.Raise_Signal(name, return_value)
    AddUITriggeredEvent("Time", name, return_value)
end

function loc.Get_RealTime(_, id)
    local now = GetCurRealTime()
    loc.Raise_Signal(id, now)
end

-- Make a timer if it doesn't exists.
function loc.Make_Timer(id)
    if not loc.timers[id] then
        loc.timers[id] = {
            start = 0,
            total = 0,
            running = false,
            }
    end
end

-- Update a timer by accumulating any time since its last_check.
-- Sets the new last_check to now.
-- If the timer is not running, will just update last_check.
function loc.Update_Timer(id)
    local now = GetCurRealTime()
    if loc.timers[id].running then
        loc.timers[id].total = loc.timers[id].total + now - loc.timers[id].last_check
    end
    loc.timers[id].last_check = now
end

function loc.Start_Timer(_, id)
    loc.Make_Timer(id)
    -- Update it, since it may already be running, and needs to initialize
    -- its last_check anyway.
    loc.Update_Timer(id)
    loc.timers[id].running = true
end

function loc.Stop_Timer(_, id)
    loc.Make_Timer(id)
    -- Update it, to capture any time up to this stop.
    loc.Update_Timer(id)
    loc.timers[id].running = false
end

function loc.Get_Timer(_, id)
    loc.Make_Timer(id)
    -- Make sure it is up to date if still running.
    loc.Update_Timer(id)
    loc.Raise_Signal(id, loc.timers[id].total)
end

function loc.Reset_Timer(_, id)
    loc.Make_Timer(id)
    -- Update it, mostly to reset the last_check.
    loc.Update_Timer(id)
    -- Now reset the total.
    loc.timers[id].total = 0
end

function loc.Print_Timer(_, id)
    loc.Make_Timer(id)
    loc.Update_Timer(id)
    -- Put the time in the log.
    DebugError(string.format(
        "Timer id '%s' current total: %f seconds", 
        id, loc.timers[id].total))
end

function loc.Tic(_, id)
    -- Use the timer system, giving a probably unique name.
    local name = "TicToc_"..id
    -- Reset it, which also makes it if needed.
    loc.Reset_Timer(_, name)
    -- Start it off.
    loc.Start_Timer(_, name)
    -- TODO: maybe optimize the above to not double-update.
end


function loc.Toc(_, id)
    -- Use the timer system, giving a probably unique name.
    local name = "TicToc_"..id

    -- Safety in case toc called without tic.
    loc.Make_Timer(name)
    -- Get it updated.
    loc.Update_Timer(name)

    -- Print it; don't really need to stop it.
    -- Put the time in the log.
    DebugError(string.format(
        "Toc id '%s': %f seconds", 
        id, loc.timers[name].total))

    -- Also report it to user.
    loc.Raise_Signal(id, loc.timers[name].total)
end


function loc.Set_Alarm(_, id_time)
    if debug then
        DebugError("Time.Set_Alarm got: "..tostring(id_time))
    end

    -- Split the input to separate id and time.
    local id, time = loc.Split_String(id_time)

    -- Time should be a number; may have decimal.
    time = tonumber(time)

    -- Schedule the alarm.
    loc.alarms[id] = GetCurRealTime() + time

    -- Start polling if not already.
    if not loc.checking_alarms then
        SetScript("onUpdate", loc.Poll_For_Alarm)
        loc.checking_alarms = true
        if debug then
            DebugError("Time.Set_Alarm started polling")
        end
    end    
end


function loc.Poll_For_Alarm()
    local now = GetCurRealTime()

    -- List of ids who's alarms fired this check.
    local ids_to_remove = {}
    -- Flag to indicate there is an alarm that didn't fire yet.
    local alarms_still_pending = false

    -- Check all alarms.
    for id, time in pairs(loc.alarms) do

        if now >= time then

            -- Time reached.
            -- Send back the id and the time that was scheduled, not the
            -- current time, so that alarms can be chained to make clocks.
            loc.Raise_Signal(id, time)

            -- Note this id for list removal.
            table.insert(ids_to_remove, id)

        else
            -- Note the alarm didn't fire.
            alarms_still_pending = true
        end
    end

    -- Remove any alarms that fired.
    for i, id in ipairs(ids_to_remove) do
        loc.alarms[id] = nil
    end

    -- If no alarms remaining, stop polling.
    if not alarms_still_pending then
        RemoveScript("onUpdate", loc.Poll_For_Alarm)
        loc.checking_alarms = false
        if debug then
            DebugError("Time.Set_Alarm stopped polling")
        end
    end
end


-- Split a string on the first colon.
-- Note: works on the MD passed arrays of characters.
-- Returns two substrings.
-- TODO: a good way to share string helper code across extensions.
function loc.Split_String(this_string)
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


Init()