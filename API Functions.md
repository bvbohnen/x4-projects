
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
  
    