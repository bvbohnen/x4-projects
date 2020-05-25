# X4 Mod Support APIs

This is a collection of APIs developed to ease mod creation in a variety of ways. Components include:

* Lua Loader API
  - Support for loading lua files
* Simple Menu API
  - Create custom menus
* Interact Menu API
  - Add new context menu commands
* Named Pipes API
  - Inter-process two-way communication
* Hotkey API
  - Create new hotkeys
* Time API
  - Real-time delays


### Contributors
* Le Leon - German translation


# X4 LUA Loader API
This extension implements a generic method of loading custom lua files into X4, working around a bug in the intended method of loading lua code.

### How to use

In an MD script, add a cue that follows this template code:
```xml
<cue name="Load_Lua_Files" instantiate="true">
  <conditions>
  <event_ui_triggered screen="'Lua_Loader'" control="'Ready'" />
  </conditions>
  <actions>
  <raise_lua_event 
    name="'Lua_Loader.Load'" 
    param="'extensions.your_ext_name.your_lua_file_name'"/>
  </actions>
</cue>
```
The cue name may be anything. Replace "your_ext_name.your_lua_file_name" with the appropriate path to your lua file, without file extension. The lua file needs to be loose, not packed in a cat/dat. The file extension may be ".lua" or ".txt", where the latter may be needed if distributing through steam workshop. If editing the lua code, it can be updated in-game using "/reloadui" in the chat window.

When a loading is complete, a message is printed to the debuglog, and a ui signal is raised. The signal "control" field will be "Loaded " followed by the original param file path. This can be used to set up loading dependencies, so that one lua file only loads after a prior one.

Example dependency condition code:
```xml
<conditions>
  <event_ui_triggered screen="'Lua_Loader'" 
    control="'Loaded extensions.other_ext_name.other_lua_file_name'" />
</conditions>
```
### How it works

A small lua program is provided with two functions: to signal when it is loaded, and to receive file paths from MD scripts. These files are loaded using lua's "require". This api's lua file is itself loaded into x4 by replacing ui/addons/ego_debug/ui.xml file.

### Summary of the problem

The intended method of adding lua files is to place a ui.xml file in the extension's primary folder, which in turn specifies the lua files to load into the game. As of X4 2.5, lua files loaded this way are provided some basic X4 functions (eg. DebugError), but their globals table is not initialized. Without this table, the lua code cannot access the various UI functions exported by other X4 lua files, lacks FFI support, and lacks a way to communicate with the mission director. Even basic lua functions are unavailable.

A workaround is to load in custom lua files alongside the egosoft lua. This is done by editing one of a handful of ui.xml files in the ui/addons folders, adding the path to the custom lua file. These ui.xml files cannot be diff patched. The lua file must be given an xpl extension, and this xpl and the ui.xml must be packed in a "subst" cat/dat.

Since there are a limited number of such ui.xml files, there is a high likelyhood of conflicts in mods importing lua files this way. Additionally, when editing code, this method of lua inclusion will generally require a restart of X4 to load any changes properly due to the "subst" packing.

### Prior work

An initial workaround was provided by morbideth (https://forum.egosoft.com/viewtopic.php?t=411630). However, this was presented alongside a much more complicated right-click-menu mod, leading to confusion among modders as to how to use the workaround, how reliable it is, and if they had permission to use it.

This new api has a new, somewhat simpler implementation; supports txt files; and is available under the MIT license.



# X4 Simple Menu API

This extension adds support for generating menus using mission director scripts in X4. A lua backend handles the details of interfacing with the x4 ui system.

Two types of menus are supported: options menus that are integrated with the standard x4 options, and standalone menus which will display immediately.

Additionally, a simplified interface is provided for adding options to an extension. These options are simple buttons and sliders that display in the main Extension Options menu.

### Usage

* Basic extension options
  - Call Register_Option with a name, default value, widget type, and callback.
  - Callback will receive the new value whenever the player changes the option.

* Standalone menu
  - Call Create_Menu to open a new menu, closing any others.
  - Fill the menu with rows and widgets, specifying callback cues.
  - Callback cues will be signalled on player input.
  - Access through a trigger condition of your choice.

* Options menu
  - Call Register_Options_Menu to register your menu with the backend.
  - Create a cue which will make the rows and widgets as above.
  - Set the above cue as the onOpen callback target during registration.
  - Access through the "Extension Options" page of the main menu.

### Examples

* Simple Option with setup and callback, enabling debug logging:
  ```xml
  <cue name="Reset_On_Reload" instantiate="true">
    <conditions>
      <event_cue_signalled cue="md.Simple_Menu_Options.Reloaded"/>
    </conditions>
    <actions>
      <signal_cue_instantly
        cue="md.Simple_Menu_Options.Register_Option"
        param = "table[
          $id         = 'debug_menu_api',
          $name       = 'Enable menu api debug logs',
          $mouseover  = 'Prints extra api status info to the debug log',
          $default    = 0,
          $type       = 'button',
          $callback   = OnChange,
          ]"/>
    </actions>
  </cue>
  <cue name="OnChange" instantiate="true">
    <conditions>
      <event_cue_signalled />
    </conditions>
    <actions>
      <set_value name="md.My_Extension.Globals.$DebugChance"
                  exact ="if (event.param.$value) then 100 else 0"/>
    </actions>
  </cue>
  ```

* Standalone menu:
  ```xml
  <cue name="Open_Menu" instantiate="true" namespace="this">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>
      <signal_cue_instantly
        cue = "md.Simple_Menu_API.Create_Menu"
        param = "table[
          $columns = 1, 
          $title   = 'My Menu',
          $width   = 500,
          ]"/>
      <signal_cue_instantly cue="md.Simple_Menu_API.Add_Row"/>
      <signal_cue_instantly
        cue = "md.Simple_Menu_API.Make_Text"
        param = "table[$col=1, $text='Hello world']"/>
    </actions>
  </cue>
  ```
* Options menu:
  ```xml
  <cue name="Register_Options_Menu" instantiate="true" namespace="this">
    <conditions>
      <event_cue_signalled cue="md.Simple_Menu_API.Reloaded"/>
    </conditions>
    <actions>
      <signal_cue_instantly
        cue="md.Simple_Menu_API.Register_Options_Menu"
        param = "table[
          $id = 'my_unique_menu',
          $columns = 1, 
          $title = 'My Options',
          $onOpen = Build_Options_Menu
          ]"/>
    </actions>
  </cue>

  <cue name="Build_Options_Menu" instantiate="true" namespace="this">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>            
      <signal_cue_instantly cue="md.Simple_Menu_API.Add_Row"/>
      <signal_cue_instantly
        cue="md.Simple_Menu_API.Make_Text"
        param = "table[$col=1, $text='Hello world']"/>
    </actions>
  </cue>
  ```

# X4 Interact Menu API
This extension implements a generic mission-director level api for adding custom interact menu actions (eg. the right-click menu).  A lua backend interfaces with the egosoft menu code; api users may work purely with mission director scripts.

When a menu is first opened, information is gathered from lua and passed to the md.Interact_Menu_API.Get_Actions cue. Users may listen to this cue, check the menu parameters, and on wanted conditions add a new action using Add_Action, which defines a callback cue if the player selects the action.

### Example Usage

This code adds a generic "Follow" action to any target.
```xml
<cue name="Add_Interact_Actions" instantiate="true">
  <conditions>
    <event_cue_signalled cue="md.Interact_Menu_API.Get_Actions" />
  </conditions>
  <actions>
    <set_value name="$target" exact="event.param.$object"/>
    <do_if value="event.param.$showPlayerInteractions and $target.isclass.{class.destructible} ">
      <signal_cue_instantly
        cue="md.Interact_Menu_API.Add_Action"
        param = "table[
          $id         = 'target_follow',
          $section    = 'interaction',
          $text       = 'Follow',
          $mouseover  = '%s %s'.[Text.$Follow, $target.name],
          $icon       = 'order_follow',
          $mouseover_icon = 'order_follow',
          $callback   = Target_Follow,
          ]"/>
    </do_if>
  </actions>
</cue>
<cue name="Target_Follow" instantiate="true" namespace="this">
  <conditions>
    <event_cue_signalled/>
    <check_value value="player.occupiedship"/>
  </conditions>
  <actions>
    <start_player_autopilot destination="event.param.$object"/>
  </actions>
</cue>
```

# X4 Named Pipes API

Adds support for Windows named pipes to X4 Foundations.
Named pipes are OS level psuedo-files which support inter-process communication.
Pipes avoid the overhead of disk access from normal files (eg. debug logs), and are bidirectional.
X4 will act as a client, with one or more an external applications serving the pipes.

There are three components to this API:
 * A low level lua plugin and corresponding dll for pipe access.
 * An MD wrapper that interfaces between the lua and MD pipe users.
 * A default, optional Python external pipe host server.

### Requirements

* Windows
  - Currently, pipes are only set for Windows, not Linux.
* The X4_Python_Pipe_Server (exe or python source code version).
  - Run this pipe server alongside X4.
* Optionally, Python 3.6+ with the pywin32 package if running from source.
  - Only needed if not using the standalone exe.
  - An executable is provided as an alternative.
  - The pywin32 package is part of the Anaconda distribution of python by default.

### Components

* MD Pipe API

  This api is found in Named_Pipes.xml, and allows MD code to read or write pipes.

* MD Server API

  This api is found in Pipe_Server_Host, and allows MD code to register a python module with the host server.
  The host (if running) will dynamically import the custom module.
  Such modules may be distributed with extensions.

* Lua Pipe API

  The lower level support for X4 to use named pipes is located in Named_Pipes.lua.
  Basic pipe usage can ignore this level in favor of the MD api.
  Advanced usage may want to use this api directly.

* Winpipe dll API

  The pipes themselves are accessed through a dll which wraps key Windows functions.
  This dll is limited to only what is needed: opening a pipe client, reading/writing/closing it, and error checking.
  If desired, the dll may be compiled freshly from source on github.

# X4 Hotkey API

Adds support for capturing key presses in X4, to implement custom hotkeys.
An external Python server is used for the key capture and combo recognition, and interfaces with X4 using named pipes.


### Requirements

* If running the python pipe server from source, the pywin32 and pynput packages.
  - Not needed when using the server exe (which includes these packages).


### Usage

Extensions may define custom hotkeys by registering a new action with the api. Actions will appear in the standard options controls menu for the player. Each action may specify in which contexts it will be valid: when flying, when walking, in any menu, or in specifically named menus.

Example action registration:
  ```xml
  <signal_cue_instantly 
    cue="md.Hotkey_API.Register_Action" 
    param="table[
      $id = 'kc_target_follow', 
      $cue = Target_Follow,
      $name = 'Follow Target', 
      $description = 'Turns on autopilot to follow the target'
    ]"/>
  ```

Optionally, a key or key combination may be directly assigned to the action from md script. When done this way, a wider variety of combinations are supported than possible through the standard options menu.

Example direct key mapping:
  ```xml
  <cue name="Register_Keys" instantiate="true">
    <conditions>
      <event_cue_signalled cue="md.Hotkey_API.Reloaded" />
    </conditions>
    <actions>
      <signal_cue_instantly 
        cue="md.Hotkey_API.Register_Key" 
        param="table[$key='shift a', $id='kc_target_follow']"/>
    </actions>
  </cue>
  ```

Limitations:
* The windows backend confuses numpad enter and numpad / with their non-numpad counterparts.  If one of these keys is used, both the numpad and normal key will trigger the hotkey callback.
* Currently only supports keyboard inputs, not mouse or joystick.
  

# X4 Time API

This api provides additional timing functions to mission director scripts and lua modules. These timers will continue to run while the game is paused.

Timing is done using two sources:
* The lua function GetCurRealTime(), which measures the seconds since X4 booted up, advancing each frame while X4 is active (eg. not while minimized).
* Optionally, the python 'time' module, accessed through the Named Pipes API, which can track time changes while the game is paused and minimized.

Example uses:
- In-menu delays, eg. a blinking cursor.
- Timing for communication through a pipe with an external process.
- Code profiling.

### Usage

General commands are sent using raise_lua_event of the form "Time.command".
Since multiple users may be accessing the timer during the same period,
each command will take an [id] unique string parameter.
Responses (if any) are captured using event_ui_triggered with screen "Time" and control [id].
Return values will be in "event.param3".

Note: the X4 engine processes MD scripts earlier in a frame than lua scripts. Any responses from lua back to md will have a 1 frame delay.

Warning: when a game is saved and reloaded, all active timers will be destroyed and any pending alarms will not go off.

Standard Commands:

- getEngineTime ([id])
  - Returns the current engine operation time in seconds, as a long float.
  - Note: this is the number of seconds since x4 was loaded, counting
    only time while the game has been active (eg. ignores time while
    minimized).
  - Capture the time using event_ui_triggered.
- startTimer ([id])
  - Starts a timer instance under id.
  - If the timer didn't exist, it is created.
- stopTimer ([id])
  - Stops a timer instance.
- getTimer ([id])
  - Returns the current time of the timer.
  - Accumulated between all Start/Stop periods, and since the last Start.
  - Capture the time using event_ui_triggered.
- resetTimer ([id])
  - Resets a timer to 0.
  - If the timer was started, it will keep running.
- printTimer ([id])
  - Prints the time on the timer to the debug log.
- setAlarm ([id]:[delay])
  - Sets an alarm to fire after a certain delay, in seconds.
  - Arguments are a concantenated string, colon separated.
  - Detect the alarm using event_ui_triggered.
  - Returns the realtime the alarm was set for, for convenience in
    creating clocks or similar.
  - Note: precision based on game framerate.

External timer commands (requires a running named pipes host server):

- getSystemTime ([id])
  - Returns the system time reported by python through a pipe.
  - Pipe communication will add some delay.
  - Can be used to measure real time passed, even when x4 is minimized.
- tic ([id])
  - Starts a fresh timer at time 0.
  - Intended as a convenient 1-shot timing solution.
- toc ([id])
  - Stops the timer associated with tic, returns the time measured,
    and prints the time to the debug log.

Additional lua commands are documented in the time interface.lua file.

* Example: get engine time.
  ```xml
  <cue name="Test" instantiate="true">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>
      <raise_lua_event name="'Time.getEngineTime'"  param="'my_test'"/>
    </actions>
  </cue>
  <cue name="Capture" instantiate="true">
    <conditions>
      <event_ui_triggered screen="'Time'" control="'my_test'" />
    </conditions>
    <actions>
      <set_value name="$time" exact="event.param3"/>
    </actions>
  </cue>
  ```
  
- Example: set an alarm (works while paused).
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

