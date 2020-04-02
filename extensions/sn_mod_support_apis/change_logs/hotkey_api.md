
Change Log

* 0.7
  - Initial version of key_capture_api MD file and related python server code,
    for capturing key/combo presses and linking them to cues.
* 0.8
  - Update to use load the server dynamically through python host.
* 0.9
  - Made use of Pipe_Server_Lib to simplify MD code.
  - Added requirement that keys be re-registered when it reloads.
* 0.9.1
  - Removed ack-based flow control.
* 0.10
  - Key listener thread will completely stop when X4 loses focus.
* 0.11
  - Integrated into the ego input selection menu.
  - Switched from direct key/cue pairings to setting up action definitions that can set keys through md or player menu input.
* 0.12
  - Added support for action contexts (flying, walking, menus, or specific menu) where is is valid.
* 0.13
  - Improved general keycode support, particularly for numpad keys.
* 0.14
  - Replaced $cue with $onPress, $onRelease, $onRepeat key events.
  - Callbacks receive a more detailed table with capture event properties.
* 0.15
  - Added Eject_Illegal_Wares action.
  - Sorted actions in the menu, and support grouping by category names.
* 0.16
  - Changed the contexts are to be a list instead of table.
* 1.0
  - General release.
  - Renamed to Hotkey_API.
  - "Shorcuts" renamed to "actions".
* 1.0.1
  - Ignore UserQuestionMenu context, due to difficulty detecting its closure.
* 1.1
  - Added keys to fast-drop satellites.
* 1.2
  - Moved custom hotkeys to SirNukes' Hotkey Collection.
  - Fixed menu not showing in new games that don't yet have hotkeys set up.
  - Fixed problem with key remap and deletion remembering the old key.


