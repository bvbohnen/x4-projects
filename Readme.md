# X4 Hotkey API

Adds support for capturing key presses in X4, to implement custom hotkeys.
An external Python server is used for the key capture and combo recognition, and interfaces with X4 using named pipes.


### Requirements

* Named Pipe API extension
  - https://github.com/bvbohnen/x4-named-pipes-api
  - Server should be running.
* Optionally, if using the python pipe server, the pywin32 and pynput packages.
  - Not needed when using the prebuilt server executable.


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

Note: the windows backend confuses numpad enter and numpad / with their non-numpad counterparts.  If one of these keys is used, both the numpad and normal key will trigger the hotkey callback.

See "API Functions.md" for full details.


  