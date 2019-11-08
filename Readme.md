# X4 Key Capture API

Adds support for capturing key presses in X4, to implement custom hotkeys.
An external Python server is used for the key capture and combo recognition, and interfaces with X4 using named pipes.


### Requirements

* Named Pipe API extension
  - https://github.com/bvbohnen/x4-named-pipes-api
* Simple Menu API
  - https://github.com/bvbohnen/x4-simple-menu-api
* Optionally, Python 3.6+ with the pywin32 and pynput packages.
  - The named pipe host server needs to be running alongside X4.
  - Python not needed if using the standalone server executable.


### Usage

Extensions may define custom hotkeys by registering a new shortcut with the api. Shortcuts will appear in the standard options controls menu for the player. Each shortcut may specify in which contexts it will be valid: when flying, when walking, or in menus.

Example shortcut registration:
  ```xml
  <signal_cue_instantly 
    cue="md.Key_Capture.Register_Shortcut" 
    param="table[
      $id = 'kc_target_follow', 
      $cue = Target_Follow,
      $name = 'Follow Target', 
      $description = 'Turns on autopilot to follow the target'
    ]"/>
  ```

Optionally, a key or key combination may be directly assigned to the shortcut from md script. When done this way, a wider variety of combinations are supported than possible through the standard options menu.

See "API Functions.md" for full details.


  