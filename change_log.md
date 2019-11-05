
Change Log

* 0.7
  - Initial version of key_capture_api MD file and related python server code,
    for capturing key/combo presses and linking them to cues.
* 0.8
  - Update to use load the server dynamically through python host.
* 0.9
  - Made use of Pipe_Server_Lib to simplify MD code.
  - Added requirement that keys be re-registered when it reloads.
* 0.91
  - Removed ack-based flow control.
* 0.10
  - Key listener thread will completely stop when X4 loses focus.
* 0.11
  - Integrated into the ego input selection menu.
  - Switched from direct key/cue pairings to setting up shortcut definitions that can set keys through md or player menu input.


