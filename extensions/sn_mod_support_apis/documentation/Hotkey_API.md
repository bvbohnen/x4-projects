
### Hotkey API Cues

* **Reloaded**
  
  Dummy cue used for signalling that the api reloaded. Users that are registering actions should listen to this cue being signalled.
    
* **Register_Action**
  
  Function to register an action. These actions will be displayed in the api options menu for user assignment of a hotkey. This should be re-sent each time Reloaded is signalled.
      
  Param : Table with the following items:
  * id
    - String, unique identifier of this action.
    - Saved keys will map to ids; other fields may be changed.
  * name = id
    - String, name to use for the key in the menu.
    - If not given, defaults to the id.
  * description = ""
    - String, mouseover text use for the key in the menu.
  * category = null
    - String, optional category heading to use in the menu.
    - Hotkeys are displayed by sorted categories first, then sorted names.
  * onPress = null
    - Callback cue when the combo final key is pressed.
  * onRelease = null
    - Callback cue when the combo final key is released.
  * onRepeat = null
    - Callback cue when the combo final key is repeated while held.
    - Repeat delay and rate depend on OS settings.
  * echo
    - Anything; this will be passed to the callback cue.
  * contexts
    - List of strings, names of player contexts where the action is valid.
    - If not given, defaults to "['flying']".
    - Valid contexts:
      * 'flying'
        - While the player is piloting a ship.
      * 'walking'
        - While the player is on foot.
      * 'menus'
        - While the player is in any menu.
        - The OptionsMenu will be protected, with actions always disabled.
      * ...
        - Other entries are names of individual menus, as registered by the egosoft backend.
                  
  Keypress events will return a table with these fields:
  * key
    - String, identifier of the key combination matched.
  * id
    - Matching id of the action. May be useful if one callback cue handles multiple actions.
  * context
    - String, the player context when this action was triggered.
    - Either one of ["flying", "walking", "menu"], or the name of the open menu matching an entry in menu_names.
  * event
    - String, name of the event that occured.
    - One of ["onPress", "onRelease", "onRepeat"].
  * echo
    - Copy of what was given to the action registration, or null.
      
  Usage example:
    ```xml
    <cue name="Register_Action" instantiate="true">
      <conditions>
        <event_cue_signalled cue="md.Hotkey_API.Reloaded" />
      </conditions>
      <actions>
        <signal_cue_instantly 
          cue = "md.Hotkey_API.Register_Key" 
          param="table[
            $id          = 'my_key',
            $onPress     = OnKeyPress,
            $name        = 'Test Key',
            $description = 'This key is just testing',
            $contexts    = ['flying','walking'],
            ]"/>
      </actions>
    </cue>
    ```
    
* **Register_Key**
  
    
  Function to register a key with an action.
      
  If this is the first key registered, it will start the key listening loop. This is used by the menu system to set up player custom keys, but may also be called by a user to directly assign a key to an action. Keys added by direct user calls will not be visible in the menu, and have fewer restrictions than the menu enforces. This should be re-sent each time Reloaded is signalled, and should follow the action's registration.
      
  Param  : Table with the following items:
  * key
    - String specifying the key/combo to capture.
  * id
    - String, id of the matching action sent to Register_Action.
    - The action should already exist.
        
  Usage example:
    ```xml
    <cue name="Register_Keys" instantiate="true">
      <conditions>
        <event_cue_signalled cue="md.Hotkey_API.Reloaded" />
      </conditions>
      <actions>
        <signal_cue_instantly 
          cue="md.Hotkey_API.Register_Key" 
          param="table[$key='shift w', $id='my_registered_key']"/>
      </actions>
    </cue>
    ```
      
  Key syntax:
  - Keys may be given singular or as a combination.
  - Combinations are space separated.
  - A combo is triggered when the last key is pressed while all prior keys are held.
    - Examples:
    - "shift ctrl k" : 'shift' and 'ctrl' held when 'k' pressed.
    - "space 5" : 'space' held when '5' pressed
  - Shift, alt, ctrl act as modifiers.
    - TODO: remove alt as a modifier, to better match x4 behavior.
  - Alphanumeric keys use their standard character.
  - Special keys use these names (from pynput with some additions):
    - alt
    - alt_l
    - alt_r
    - backspace
    - caps_lock
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
    - num_0
    - num_1
    - num_2
    - num_3
    - num_4
    - num_5
    - num_6
    - num_7
    - num_8
    - num_9
    - num_.
    - num_+
    - num_-
    - num_*
    - win_l
    - win_r
  - Note: numpad 'enter' and '/' alias to normal versions of those keys.
  
    
* **Unregister_Key**
    
  Function to unregister a key from an action. Params are the same as for Register_Key.
          
  Usage example:
    ```xml
      <signal_cue_instantly 
        cue="md.Hotkey_API.Unregister_Key" 
        param="table[$key='shift w', $id='my_registered_key']"/>
    ```
    