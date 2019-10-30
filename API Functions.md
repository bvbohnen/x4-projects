
### Simple Menu API Cues

* Reloaded
  
  Dummy cue used for signalling that the game or ui was reloaded. Users that are registering options menus should listen to this cue being signalled.
    
* Clock
  
  Dummy cue used for signalling when the menu system is requesting an update, approximately every 0.1 seconds.  This will continue to trigger during game pauses, unlike MD delays. Users may listen to this to trigger widget property updates.
      
  Pending development.
    
* Register_Options_Menu
  
  Register an options menu, which will be accessible as a submenu of the normal game options.
      
  Param: Table with the following items:
    * $id
      - String, unique identifier for this menu.
      - Needs to differ from egosoft menu names, as well as any other mod registered menus.
    * $title
      - Text to display in the table header.
    * $columns
      - Integer, total number of columns in the menu table.
    * $cue
      - Cue to be called when the submenu needs to be built.
      - This cue should use addRow and makeX functions to build the menu.
      - Do not call Create_Menu from this cue.
    * $private
      - Int 0 or 1, optional, controls if the menu will be listed automatically in the general list of Extension Options menus.
      - Defaults to 0, non-private.
      - Set to private for submenus you will manually link to using Add_Submenu_Link.
                  
  Call this each time the Reloaded cue is signalled. Example:
  ```xml
    <cue name="Register_Options_Menu" instantiate="true" namespace="this">
      <conditions>
        <event_cue_signalled cue="md.Simple_Menu_API.Reloaded"/>
      </conditions>
      <actions>
        <signal_cue_instantly
          cue="md.Simple_Menu_API.Register_Options_Menu"
          param = "table[
            $id      = 'my_unique_menu_1',
            $title   = 'My Menu',
            $cue     = Fill_Options_Menu,
            $columns = 2, 
            ]"/>
      </actions>
    </cue>
  ```
      
* Create_Menu
  
  Create a fresh standalone menu. Note: these menus are not attached to the normal options menu. To be followed by Add_Row and similar cue calls to fill in the menu.
      
  Param: Table with the following items:
    * columns
      - Integer, total number of columns in the menu table.
    * title
      - Text to display in the table header.
    * width
      - Int, optional, menu width. Defaults to a predefined width.
    * height
      - Int, optional, menu height. Default expands to fit contents.
    * offsetX
    * offsetY
      - Ints, optional, amount of space between menu and screen edge.
      - Positive values taken from top/left of screen, negative values from bottom/right of screen.
      - Defaults will center the menu.
    * onClose_cue
      - Cue, optional, signalled when the menu is closed.
      - The event.param will be "back" or "close" depending on if the menu back button was pressed.
      
* Display_Menu
  
  Display the menu. Mainly for use with options menus, which requires this to know when all build commands are complete.
      
* Add_Submenu_Link
  
  Add a link to another options menu. The other option menu will need to registered by Register_Options_Menu. This will add a new row to the menu table, though that row will be ignored for the Make_ commands. Only for use with options menus, not those made through Create_Menu.
      
  Param: Table with the following items:
    * text
      - String, text to display in the selection line.
    * menu_id
      - String, unique id of the submenu to be opened, as set at registration.
      
* Add_Row
  
  Add a row to the current menu. Following Make_ commands add to the most recently added row.
      



### Widget arguments and properties overview
    
The following "Make_" cues create widgets. Many of them share some common arguments or arg data types, described here.
    
After creation, widgets may be partially updated at any time. This is detailed in the Update_Widget cue.
    
In the egosoft backend, there is a "Helper" module which defines many constants used in the standard menus such as colors, fonts, etc. Arguments may optionally be given as a string matching a Helper const, eg. "Helper.color.brightyellow".
    
    
API args (all widgets)
* col
  - Integer, column to place the widget in.
  - Uses 1-based indexing.
  - Required for now.
* id = none
  - String, unique identifier for the widget.
  - Optional, but needed for Update_Widget calls.
* echo = none
  - May be any data type.
  - This is returned in the table sent to signalled callback cues, for user convenience.
    
Widget properties (all widgets)
* scaling = true
  - Bool, coordinates and dimensions will be scaled by the ui scaling factor.
* width, height = 0
  - Ints, widget dimension overrides.
* x, y = 0
  - Ints, placement offsets.
* mouseOverText = ""
  - String, text to display on mouseover.
        
Cell properties (all widgets)
* cellBGColor = Helper.defaultSimpleBackgroundColor
  - Color, cell background color.
* uiTriggerID = none
  - String, if present then this is the control field for ui triggered events on widget activations.
  - Ignore for now; api handles callback cues directly.
        
Events (depends on widget)
* on<___> (onClick, onTextChanged, etc.)
  - Optional callback cue.
  - When the player interacts with most widgets, ui events will occur. On such events, a provided cue will be called with the event results.
  - All event.param tables will include these fields:
    * row, col
      - Longfloat, coordinate of the activated widget.
      - Primarily for use by this backend.
    * id
      - String id given to the widget at creation, or null.
    * event
      - String, name of the event, matching the arg name.
      - Eg. "onClick".
    * echo
      - Same as the "echo" arg provided to widget creation.
  - Extra contents of the event.param are described per widget below.
        
Misc properties (depends on widget):
* font
  - String, font to use.
  - Typical options: 
    - "Zekton"
    - "Zekton bold"
    - "Zekton fixed"
    - "Zekton bold fixed"
    - "Zekton outlined"
    - "Zekton bold outlined"
* fontsize
  - Int, typically in the 9 to 12 range.
* halign
  - String, text alignment, one of ["left", "center", "right"].
* minRowHeight
  - Int, minimal row height, including y offset.
        
Complex properties:
* Color
  - Table of ["r", "g", "b", "a"] integer values in the 0-255 range.
* TextProperty
  - Table describing a text field.
  - Note: in some widgets "text" is a string, others "text" is a TextProperty table.
  - Fields:
    * text = ""
    * halign = Helper.standardHalignment
    * x = 0
    * y = 0
    * color = Helper.standardColor
    * font = Helper.standardFont
    * fontsize = Helper.standardFontSize
    * scaling = true
* IconProperty
  - Table describing an icon.
  - Fields:
    * icon = ""
      - Icon ID/name
    * swapicon = ""
    * width = 0
    * height = 0
    * x = 0
    * y = 0
    * color = Helper.standardColor
    * scaling = true
* HotkeyProperty
  - Table describing an activation hotkey.
  - See libraries/contexts.xml for potential options.
  - Note: hotkeys have not yet worked in testing.
  - Fields:
    * hotkey = ""
      - String, the hotkey action, matching a valid INPUT_STATE.
    * displayIcon = false
      - Bool, if the widget displays the associated icon as a hotkey.
    * x = 0
    * y = 0
      - Offsets of the icon if displayIcon is true.
          
  



### Widget Creation Cues
    
* Make_Label
  
  Make a label cell for displaying text. Adds to the most recent row.
      
  Param: Table with the following items
  * col, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties    
  * text
    - String, text to display.
    - Updateable
  * halign
  * color
    - Updateable
  * titleColor
    - If given, puts the widget in title mode.
  * font
  * fontsize
  * wordwrap
  * minRowHeight
      
* Make_BoxText
  
  Make a box-text cell.  Similar to a label. Adds to the most recent row.
      
  Pending development.
      
  Param: Table with the following items
  * col, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties    
  * text
    - String, text to display.
    - Updateable
  * halign
  * color
    - Updateable
  * boxColor
    - Updateable
  * font
  * fontsize
  * wordwrap
  * minRowHeight
      
* Make_Button
  
  Make a pressable button cell. Adds to the most recent row.
      
  Param: Table with the following items.
  * col, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties   
  * onClick
    - Cue to callback when the button is left clicked.
  * onRightClick
    - Cue to callback when the button is right clicked.
  * text
    - TextProperty.
    - Updateable text and color
  * text2
    - TextProperty.
    - Updateable text and color
  * active = true
    - Bool, if the button is active.
    - Updateable
  * bgColor = Helper.defaultButtonBackgroundColor
    - Color of background.
    - Updateable
  * highlightColor = Helper.defaultButtonHighlightColor
    - Color when highlighted.
    - Updateable
  * icon
    - IconProperty
  * icon2
    - IconProperty
  * hotkey
    - HotkeyProperty
        
        
  onClick event returns:
  * row, col, echo, event, id
        
  onRightClick event returns:
  * row, col, echo, event, id
      
* Make_EditBox
  
  Make a edit box cell, for text entry. Adds to the most recent row. Every letter change will trigger a callback.
      
  Warning: due to a (likely) typo bug, x4 is limited to 5 text edit boxes. If many edit fields are needed, consider using sliders for numeric values (limit 50), where users can click the slider displayed value to use it like an editbox.
      
  Param: Table with the following items
  * col, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties
  * onTextChanged
    - Cue to call when the player changes the box text. 
    - Occurs on every letter change.
  * onEditBoxDeactivated
    - Cue to call when the player deselects the box.
    - Deselection may occur when selecting another element, pressing enter, or pressing escape.
    - Does not trigger if the menu is closed.
  * bgColor = Helper.defaultEditBoxBackgroundColor
    - Color of background.
  * closeMenuOnBack = false
    - Bool, if the menu is closed when the 'back' button is pressed while the editbox is active.
    - Description unclear.
  * defaultText
    - String, the default text to display when nothing present.
    - Updateable
  * textHidden = false
    - Bool, if the text is invisible.
  * encrypted = false
    - Bool, if the input has an encrypted style of display.
  * text
    - TextProperty
  * hotkey
    - HotkeyProperty
        
        
  onTextChanged event returns:
  * row, col, echo, event, id
  * text
    - String, the new text in the box.
          
  onEditBoxDeactivated event returns:
  * row, col, echo, event, id
  * text
    - String, the current text in the box.
  * textchanged
    - Bool, if the text was changed since being activated.
  * wasconfirmed
    - Bool, false if the player pressed "escape", else true.
      
* Make_Slider
  
  Make a horizontal slider cell. Adds to the most recent row.
      
  Param: Table with the following items
  * col, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties
  * onSliderCellChanged
    - Cue to call when the slider value is changed.
    - When the player drags the slider around, this will be called repeatedly at intermediate points.
    - When the player types into the editbox, this will trigger on every typed character.
  * onSliderCellActivated
    - Cue to call when the player activates the slider.
  * onSliderCellConfirm
    - Cue to call when the player deactivates the slider.
    - Triggers less often than onSliderCellChanged.
    - Recommend using this in general.
  * bgColor = Helper.defaultSliderCellBackgroundColor
    - Color of background.
  * valueColor = Helper.defaultSliderCellValueColor
    - Color of value.
  * posValueColor = Helper.defaultSliderCellPositiveValueColor
    - Color, positive value if fromCenter is true
  * negValueColor = Helper.defaultSliderCellNegativeValueColor
    - Color, negative value if fromCenter is true
  * min = 0
    - Min value the bar is sized for
  * max = 0
    - Max value the bar is sized for
    - Updateable
  * minSelect = none
    - Min value the player may select.
    - Defaults to min
    - Do not use maxSelect if exceedMaxValue is true
  * maxSelect
    - Max value the player may select.
    - Defaults to max
    - Updateable
  * start = 0
    - Initial value
  * step = 1
    - Step size between slider points
  * suffix = ""
    - String, suffix on the displayed current value.
  * exceedMaxValue = false
    - Bool, if the player can go over the max value.
    - Requires min >= 0.
  * hideMaxValue = false
    - Bool, hides the max value.
  * rightToLeft = false
    - Bool, enables a right/left mirrored bar.
  * fromCenter = false
    - Bool, bar extends from a zero point in the center.
  * readOnly = false
    - Bool, disallows player changes.
  * useInfiniteValue = false
    - Bool, sets slider to show infinity when infiniteValue is reached.
  * infiniteValue = 0
    - Value at which to show infinity when useInfiniteValue is true.
  * useTimeFormat = false
    - Bool, sets the slider to use a time format.
      
      
  onSliderCellChanged event returns:
  * row, col, echo, event, id
  * value
    - Longfloat, current value of the slider.
        
  onSliderCellActivated event returns:
  * row, col, echo, event, id
        
  onRightClick event returns:
  * row, col, echo, event, id
  * posx, posy
    - Coordinates of the widget (likely not useful).
        
  onSliderCellConfirm event returns:
  * row, col, echo, event, id
  * value
    - Longfloat, current value of the slider.
  * valuechanged
    - Bool, true if the value changed since being activated.
    - If the player escapes out of the editbox, this will be false and the value will be the pre-edit value.
        
      
* Make_Dropdown
  
  Make a dropdown selection cell. Adds to the most recent row. Note: indices start at 1.
      
  Param: Table with the following items
  * col, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties
  * options
    - List of tables describing each option.
    - Each subtable has these fields:
      * text = ""
        - String, option text.
      * icon = ""
        - String, icon name.
      * id
        - Optional string or number, identifier of the option.
        - Returned to callbacks to indicate option selected.
        - Defaults to the option's list index (1-based).
      * displayremoveoption = false
        - Bool, if true the option will show an 'x' that the player can click to remove it from the dropdown list.
  * onDropDownActivated
    - Cue to call when the player activates the dropdown.
  * onDropDownConfirmed
    - Cue to call when the player selects an option.
  * onDropDownRemoved
    - Cue to call when the player removes an option.
  * startOption = ""
    - String or number, id of the initially selected option.
    - Updateable
  * active = true
   - Bool, if the widget is active.
  * bgColor = Helper.defaultButtonBackgroundColor
   - Color of background.
  * highlightColor = Helper.defaultButtonHighlightColor
   - Color when highlighted.
  * optionColor = Helper.color.black
    - Color of the options.
  * optionWidth, optionHeight = 0
    - Dimensions of the options.
  * allowMouseOverInteraction = false
    - Bool, ?
  * textOverride = ""
    - String, ?
  * text2Override = ""
    - String, ?
  * text
   - TextProperty
  * text2
   - TextProperty
  * icon
   - IconProperty
  * hotkey
   - HotkeyProperty
        
        
  onDropDownActivated event returns:
  * row, col, echo, event, id
          
  onDropDownConfirmed event returns:
  * row, col, echo, event, id
  * id
    - String or number, id of the selected option.
        
  onDropDownRemoved event returns:
  * row, col, echo, event, id
  * id
    - String or number, id of the removed option.
        
      
* Make_Icon
  
  Make an icon cell. Adds to the most recent row.
      
  Pending development.
      
  Param: Table with the following items
  * col, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties    
  * icon = ""
    - String, icon id
    - Updateable
  * color = Helper.standardColor
    - Color
    - Updateable
  * text
    - TextProperty
    - Updateable text
  * text2
    - TextProperty
    - Updateable text
      
* Make_CheckBox
  
  Make a check-box. Adds to the most recent row.
      
  Param: Table with the following items
  * col, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties
  * onClick
    - Cue to callback when the checkbox is clicked.
  * checked = false
    - Bool or int, if checked initially.
    - Updateable
  * bgColor = Helper.defaultCheckBoxBackgroundColor
   - Color of background.
  * active = true
   - Bool, if the widget is active.
       
  onClick event returns:
  * row, col, echo, event, id
  * checked
    - Int, 0 or 1, checkbox status after click.
        
      
* Make_StatusBar
  
  Make a status bar. Adds to the most recent row.
      
  Pending development.
      
  Param: Table with the following items
  * col, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties
  * current = 0
    - Int
    - Updateable
  * start = 0
    - Int
    - Updateable
  * max = 0
    - Int
    - Updateable
  * valueColor = Helper.defaultStatusBarValueColor
    - Color
  * posChangeColor = Helper.defaultStatusBarPosChangeColor
    - Color
  * negChangeColor = Helper.defaultStatusBarNegChangeColor
    - Color
  * markerColor = Helper.defaultStatusBarMarkerColor
    - Color
      
* Send_Command
  
  General cue for packaging up a request and sending it to lua. This may be used instead of the Make_ command, by filling in a matching command name in the param table.
      
  Param: Table with the following items
  * command
    - String, command to send to lua.
  * ...
    - Any args requied for the command.
    
* Update_Widget
  
  Update a widget's state after creation.
      
  Param: Table with the following items
  * id
    - String, original id assigned to the widget at creation.
  * ...
    - Any args to be updated, matching the original widget creation args layout.
    - Which widget properties can be updated depends on the specific widget.
    