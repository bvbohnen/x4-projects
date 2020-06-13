
### MD Chat Window API Overview

 
MD API support for working with the chat window. Can be used to listen to player entered chat text, set up custom commands and callback cues, and print new text.
  
In addition to what is described below for the cues, there is some additional functionality regarding the standard egosoft commands:
  
* `/rmd`, `/rai`, `/rui` may be used in place of `/refreshmd`, `/refreshai`, `/reloadui`.
* When a refresh event occurs, scripts may detect this using the conditions:
  - `<event_ui_triggered screen="'Chat_Window_API'" control="'refreshmd'"/>`
  - `<event_ui_triggered screen="'Chat_Window_API'" control="'refreshai'"/>`
  

### MD Chat Window API Cues

* **Reloaded**
  
  Cue signalled when the api is reloaded. Users that are registering commands should do so when this cue is signalled.
      
* **Print**
  
  Print a line to the chat window. This will not evaluate the line as a command.
      
* **Text_Entered**
  
  Cue signalled when text is entered into the chat window. Users may listen to this to capture all entered text, as an alternative to registering specific commands.
        
  Param is a table with two items:
  * $text
    - String, the raw text entered by the player.
    - Will always have at least one non-space character.
  * $terms
    - List of strings, the text space separated.
    - Multiple spaces in a row are treated as one space.
    - There will always be at least one item in the list.
          
  Note: aiscripts can instead listen to the ui signal directly: `<event_ui_triggered screen="'Chat_Window_API'" control="'text_entered'" />` with the text and terms in the event.param3 table.
      
* **Register_Command**
  
      
  Add a new command to the chat window.  This is primarily for convenience, and can be skipped in favor of listening directly to Text_Entered.
      
  This should be called whenever the API signals md.Chat_Window_API.Reloaded.
        
  Input to this cue is a table with the following fields:
    * $name
      - String, text of the command. Does not need to start with '/'.
    * $callback
      - Cue to call when this command is entered.
      - See below for event.param contents.
    * $echo
      - Optional, anything (string, value, table, etc.), data to be attached to the callback cue param for convenience.
          
          
  The callback cue is given an event.param table with the following:
    * $name
      - Same as $name above.
    * $echo
      - Same as $echo above.
    * $terms
      - List of strings, space separated terms given by the player.
      - The first term is always the $name.
      
  Example:
  ```xml
  <cue name="Add_Commands" instantiate="true">
    <conditions>
      <event_cue_signalled cue="md.Chat_Window_API.Reloaded" />
    </conditions>
    <actions>
      <signal_cue_instantly
        cue="md.Chat_Window_API.Register_Command"
        param = "table[
            $name       = '/mytest',
            $callback   = Command_Callback,
            $echo       = table[],
          ]"/>
    </actions>
  </cue>
  ```
      