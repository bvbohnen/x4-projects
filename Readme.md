# X4 Time API

This api provides additional real-time timing functions to mission director scripts. These timers will continue to run while the game is paused.

This is based on the lua function GetCurRealTime(), which measures the seconds since X4 booted up, advancing while X4 is active (eg. not while minimized). This time appears to advance once each frame, so this api will only be useful for inter-frame timing needs.

Warning: when a game is saved and reloaded, all active timers will be destroyed and any pending alarms will not go off.

General commands are sent using raise_lua_event of the form "Time.command".
Since multiple users may be accessing the timer during the same period,
each command will take an "id" unique string parameter.
Responses (if any) are captured in screen "Time" with control "id".
Return values will be in "event.param3".

Commands:

* getRealTime (id)
  - Returns the current real time in seconds, as alongfloat.
  - Note: this is the number of seconds since the gamewasloaded, counting
    only time while the game has been active (eg. ignoretime while
    minimized).
  - Capture the time using event_ui_triggered.
* startTimer (id)
  - Starts a timer instance under "id".
  - If the timer didn't exist, it is created.
* stopTimer (id)
  - Stops a timer instance.
* getTimer (id)
  - Returns the current time of the timer.
  - Accumulated between all Start/Stop periods, and sincthe last Start.
  - Capture the time using event_ui_triggered.
* resetTimer (id)
  - Resets a timer to 0.
  - If the timer was started, it will keep running.
* printTimer (id)
  - Prints the time on the timer to the debug log.
* tic (id)
  - Starts a fresh timer at time 0.
  - Intended as a convenient 1-shot timing solution.
* toc (id)
  - Stops the timer associated with tic, returns the timmeasured,
    and prints the time to the debug log.
* setAlarm (id:delay)
  - Sets an alarm to fire after a certain delay,inseconds.
  - Arguments are a concantenated string, colonseparated.
  - Detect the alarm using event_ui_triggered.
  - Returns the realtime the alarm was set for,forconvenience in
    creating clocks or similar.
  - Note: precision based on game framerate.


* Example: get real time.
  ```xml
  <cue name="Test" instantiate="true">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>
      <raise_lua_event name="'Time.getRealTime'"  param="'my_test'"/>
    </actions>
  </cue>
  <cue name="Capture" instantiate="true">
    <conditions>
      <event_ui_triggered screen="'Time'" control="'my_test'" />
    </conditions>
    <actions>
      <set_value name="$realtime" exact="event.param3"/>
    </actions>
  </cue>
  ```
  
- Example: set an alarm.
  ```xml
  <cue name="Delay_5s" instantiate="true">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>
      <raise_lua_event name="'Time.setAlarm'"  param="'my_alarm:5'" />
    </actions>
  </cue>  
  <cue name="Wakeup" instantiate="true">
    <conditions>
      <event_ui_triggered screen="'Time'" control="'my_alarm'" />
    </conditions>
    <actions>
      <.../>
    </actions>
  </cue>
  ```

