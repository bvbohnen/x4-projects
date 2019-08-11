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

  

### Key Capture API Cues

* Register_Key
  
  User function to register a key with a cue. If this is the first cue registered, it will start the key listening loop. This should be re-sent each time Reloaded is signalled.
      
  Param  : Table with the following items:
   - key  : String specifying the key/combo to capture.
   - cue  : Callback, the cue to call when the key is pressed.
        
  Returns: Callback cue will be given the key pressed in event.param.
      
  Usage example:
  
      <cue name="Register_Keys" instantiate="true">
        <conditions>
          <event_cue_signalled cue="md.Key_Capture.Reloaded" />
        </conditions>
        <actions>
          <signal_cue_instantly 
            cue="md.Key_Capture.Register_Key" 
            param="table[$key='shift w', $cue=OnKeyPress]"/>
        </actions>
      </cue>
  
    
* Unregister_Key
  
  User function to unregister a key/cue. Params are the same as for Register_Key. If this was the only cue registered (across all keys), the key listerner loop will stop itself.
      
  Note: in development, untested.
      
  Usage example:
  
      <signal_cue_instantly 
        cue="md.Key_Capture.Unregister_Key" 
        param="table[$key='w', $cue=OnKeyPress]">
  
    