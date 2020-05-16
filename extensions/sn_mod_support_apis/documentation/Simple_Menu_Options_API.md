
###  Cues

* **Reloaded**
  
  Dummy cue used for signalling that this api reloaded. Users that are registering options should listen to this cue being signalled.
      
* **Register_Option**
  
  User cue for registering a new option. Immediately on registration, the callback cue will be signalled with the currently stored setting (the default if this is a first-time registration, or what the player last selected).
        
  Input is a table with the following fields:
  * $id
    - String, unique identifier for this option.
  * $name
    - String, text to display on the menu widget label.
  * $category
    - Optional string, category name under which this option will be placed, along with any others of the same category.
    - If not given, or given as "General" will be set to General.
  * $mouseover
    - Optional string, text to display on menu widget mouseover.
  * $type
    - String, name of the type of widget to create.
    - "button": an on/off button.
    - "slidercell": a standard slider.
  * $default
    - Initial value of this option, if this $id hasn't been seen before.
    - "button" supports 0 or 1.
    - "slidercell" should have a value in the slider's range.
  * $args
    - Optional, Table of extra arguments to pass to the widget builder.
    - Supported fields match those listed in the simple menu api for the matching widget type.
    - Intended use is for setting slidercell limits.
  * $echo
    - Optional, anything (string, value, table, etc.), data to be attached to the callback cue param for convenience.
  * $callback
    - Cue to call when the player changes the option.
    - This is also called once during setup, after the existing md stored value is applied to the option.
    - Event.param will be a table of [$id, $echo, $value], where the value depends on the widget type.
    - "button" returns 0 (off) or 1 (on).
    - "slidercell" returns the slider value.
  * $skip_initial_callback
    - Optional, 0 or 1; if the initial callback during setup is skipped.
    - Defaults 0.
  * $disabled = 0
    - Optional, 0 or 1; if the option will not be displayed in the menu.
      
* **Write_Option_Value**
  
    User cue to write a new value for an option, overwriting what is stored in this lib. The callback cue will not be signalled.
          
  Input is a table with the following fields:
  * $id
    - String, unique identifier for this option.
  * $value
    - The new value to store.
      
* **Read_Option_Value**
  
    User cue to read a value stored for an option.
          
  Input is a table with the following fields:
  * $id
    - String, unique identifier for this option.
  * $callback
    - Cue that will be signalled with a table holding $id and $value.
      