# X4 Key Capture API

Adds support for capturing key presses in X4, to implement custom hotkeys.
An external Python server is used for the key capture and combo recognition, and interfaces with X4 using named pipes.


### Requirements

* Named Pipe API extension
* Python 3.6+ with the pywin32 and pynput packages.
  - The named pipe host server needs to be running alongside X4.


### Key syntax
 - Keys may be given singular or as a combination.
 - Combinations are space separated.
 - A combo is triggered when the last key is pressed while all prior keys
   are held.
   - Examples:
   - "shift ctrl k" : 'shift' and 'ctrl' held when 'k' pressed.
   - "space 5" : 'space' held when '5' pressed
 - Shift, alt, ctrl act as modifiers.
 - Alphanumeric keys use their standard character.
 - Special keys use their names from pynput:
   - alt
   - alt_gr
   - alt_l
   - alt_r
   - backspace
   - caps_lock
   - cmd
   - cmd_l
   - cmd_r
   - ctrl
   - ctrl_l
   - ctrl_r
   - delete
   - down
   - end
   - enter
   - esc
   - f1 - f20
   - home
   - insert
   - left
   - menu
   - num_lock
   - page_down
   - page_up
   - pause
   - print_screen
   - right
   - scroll_lock
   - shift
   - shift_l
   - shift_r
   - space
   - tab
   - up

  