
###  Functions

 

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
  - Callback function is called with args: (id, alarm_time), where the alarm_time is the original scheduled time of the alarm, which will generally be sometime earlier than the current time (due to frame boundaries).

An MD ui event is raised on every frame, which MD cues may listen to. The event.param3 will be the current engine time. Example: `<event_ui_triggered screen="'Time'" control="'Frame_Advanced'" />`


MD commands are sent using raise_lua_event of the form "Time.<command>", and responses (if any) are captured in screen "Time" with control "id". Return values will be in "event.param3". Note: since multiple users may be accessing the timer during the same period, each command will take an id unique string parameter.

Commands:
- getEngineTime (id)
  - Returns the current engine operation time in seconds, as a long float.
  - Note: this is the number of seconds since x4 was loaded, counting only time while the game has been active (eg. ignores time while minimized).
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
  - Stops the timer associated with tic, returns the time measured, and prints the time to the debug log.
- setAlarm (id:delay)
  - Sets an alarm to fire after a certain delay, in seconds.
  - Arguments are a concantenated string, colon separated.
  - Detect the alarm using event_ui_triggered.
  - Returns the realtime the alarm was set for, for convenience in creating clocks or similar.
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