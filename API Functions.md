
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
        
  Keypress events will return the shortcut id in event.param.
      
  Usage example:
  
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
              ]"/>
        </actions>
      </cue>
  
    
* Register_Key
  
  Function to register a key with a shortcut. If this is the first key registered, it will start the key listening loop. This is used by the menu system to set up player custom keys, but may also be called by a user to directly assign a key to a shortcut. This should be re-sent each time Reloaded is signalled.
      
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
  
    
* Unregister_Key
  
  Function to unregister a key from a shortcut. Params are the same as for Register_Key. If this was the only cue registered (across all keys), the key listerner loop will stop itself.
      
  Note: in development, untested.
      
  Usage example:
  
      <signal_cue_instantly 
        cue="md.Key_Capture.Unregister_Key" 
        param="table[$key='w', $id='my_registered_key']">
  
    