
### Key Capture API Cues

* Reloaded
  
  Dummy cue used for signalling that the api reloaded. Users that are registering shortcuts should listen to this cue being signalled.
    
* Register_Shortcut
  
  User function to register a shortcut. These shortcuts will be displayed in the api options menu for use assignment of a hotkey. This should be re-sent each time Reloaded is signalled.
      
  Param : Table with the following items:
  * id
    - String, unique identifier of this shortcut.
    - Saved keys will map to ids; other fields may be changed.
  * cue
    - The callback cue for when the shortcut is triggered.
  * name = id
    - String, name to use for the key in the menu.
    - If not given, defaults to the id.
  * description = ""
    - String, mouseover text use for the key in the menu.
  * contexts
    - Table holding the player contexts where the shortcut is valid.
    - If not given, defaults to "table{$flying = true}".
    - Fields:
      * flying
        - Bool, if the shortcut is valid while the player is piloting a ship.
      * walking
        - Bool, if the shortcut is valid while the player is on foot.
      * menu
        - Bool, if the shortcut is valid while the player is in any menu.
      * menu_names
        - List of names of menus where the shortcut is valid.
        - 'menu' is ignored if this is given.
        
  Keypress events will return a table with these fields:
  * id
    - Matching id of the shortcut. May be useful if one callback cue handles multiple shortcuts.
  * context
    - String, the player context when this shortcut was triggered.
    - Either one of ["flying", "walking", "menu"], or the name of the open menu matching an entry in menu_names.
      
  Usage example:
    ```xml
  
      <cue name="Register_Shortcut" instantiate="true">
        <conditions>
          <event_cue_signalled cue="md.Key_Capture.Reloaded" />
        </conditions>
        <actions>
          <signal_cue_instantly 
            cue="md.Key_Capture.Register_Key" 
            param="table[
              $id   = 'my_key',
              $cue  = OnKeyPress,
              $name = 'Test Key',
              $description = 'This key is just testing',
              $contexts = table[ $flying = true, $walking = true ],
              ]"/>
        </actions>
      </cue>
  
    ```
    
* Register_Key
  
  Function to register a key with a shortcut. If this is the first key registered, it will start the key listening loop. This is used by the menu system to set up player custom keys, but may also be called by a user to directly assign a key to a shortcut. Keys added by direct user calls will not be visible in the menu, and have fewer restrictions than the menu enforces. This should be re-sent each time Reloaded is signalled.
      
  Param  : Table with the following items:
    - key  : String specifying the key/combo to capture.
    - id   : String, id of the matching shortcut sent to Register_Shortcut.
        
  Usage example:
  
      <cue name="Register_Keys" instantiate="true">
        <conditions>
          <event_cue_signalled cue="md.Key_Capture.Reloaded" />
        </conditions>
        <actions>
          <signal_cue_instantly 
            cue="md.Key_Capture.Register_Key" 
            param="table[$key='shift w', $id='my_registered_key']"/>
        </actions>
      </cue>
  
      
  Key syntax:
  - Keys may be given singular or as a combination.
  - Combinations are space separated.
  - A combo is triggered when the last key is pressed while all prior keys are held.
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
  
    
* Unregister_Key
  
  Function to unregister a key from a shortcut. Params are the same as for Register_Key. If this was the only cue registered (across all keys), the key listerner loop will stop itself.
      
  Note: in development, untested.
      
  Usage example:
  
      <signal_cue_instantly 
        cue="md.Key_Capture.Unregister_Key" 
        param="table[$key='w', $id='my_registered_key']">
  
    