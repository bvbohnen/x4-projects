
### Simple Menu API Cues

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
    
In the egosoft backend, there is a "Helper" module which defines many constants used in the standard menus such as colors, fonts, etc. Arguments may optionally be given as a string matching a Helper const, eg. "Helper.color.brightyellow".
    
API args (all widgets)
* col
  - Integer, column to place the widget in.
  - Generally required for all widgets.
* echo
  - Optional, any data type.
  - This is returned in the table sent to signalled callback cues, for user convenience.
        
Widget properties (all widgets)
* scaling = true
  - Bool, coordinates and dimensions will be scaled by the ui scaling factor.
  - Generally unused.
* width, height = 0
  - Ints, widget dimension overrides.
  - Generally unused.
* x, y = 0
  - Ints, placement offsets.
  - Generally unused.
* mouseOverText = ""
  - String, text to display on mouseover.
        
Cell properties (all widgets)
* cellBGColor = Helper.defaultSimpleBackgroundColor
  - Color, cell background color.
* uiTriggerID = none
  - String, if present then this is the control field for ui triggered events on widget activations.
  - Ignore for now; api handles callback cues more directly.
        
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
  - Note: in some widgets "text" is a string, others "text" is a text_properties table.
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
  - Likely of limited or no usefulness.
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
      
  Param: Table with the following items:
    * col
    * echo
    * mouseOverText
    * text
      - Text to display, without semicolons.
    * mouseover
      - Optional string, extra text to display on mouseover.
    * halign
    * color
    * titleColor
      - If given, puts the widget in title mode.
    * font
    * fontsize
    * wordwrap
    * x
    * y
    * minRowHeight
      
* Make_Button
  
  Make a pressable button cell. Adds to the most recent row.
      
  Param: Table with the following items:
    * col
      - Integer, column to place the widget in.
    * cue
      - Cue to callback on interact event.
    * text
    * text2
      - TextProperty.
    * active = true
      - Bool, if the button is active.
    * bgColor = Helper.defaultButtonBackgroundColor
      - Color of background.
    * highlightColor = Helper.defaultButtonHighlightColor
      - Color when highlighted.
    * height = Helper.standardButtonHeight
    * icon
    * icon2
      - IconProperty
    * hotkey
      - HotkeyProperty
        
  onClick event returns a table with:
    * row
      - Longfloat, row of the widget.
    * col
      - Longfloat, col of the widget.
    * echo
      - Present if param had echo.
      
* Make_EditBox
  
  Make a edit box cell, for text entry. Adds to the most recent row. Every letter change will trigger a callback.
      
  Warning: due to a (likely) typo bug, x4 is limited to 5 text edit boxes. If many edit fields are needed, consider using sliders for numeric values (limit 50), where users can click the slider displayed value to use it like an editbox.
      
  Param: Table with the following items:
    * col
      - Integer, column to place the widget in.
    * cue
      - Cue to callback on interact event.
    * text
      - Optional, initial text to display, without semicolons.
    * echo
      - Optional, anything, returned on callback.
        
  onTextChanged event returns a table with:
    * row
      - Longfloat, row of the widget.
    * col
      - Longfloat, col of the widget.
    * text
      - String, new text in the box.
    * echo
      - Present if param had echo.
      
* Make_Slider
  
  Make a horizontal slider cell. Adds to the most recent row. Every slider adjustment (many per sweep) triggers a callback.
      
  Param: Table with the following items:
    * col
      - Integer, column to place the widget in.
    * cue
      - Cue to callback on interact event.
    * min
      - Int, min value.
    * minSelect
      - Int, optional, min selectable value if different than min.
    * max
      - Int, max value.
    * maxSelect
      - Int, optional, max selectable value if different than max.
    * start
      - Int, optional, initial value; defaults 0.
    * step
      - Int, optional, step size; defaults 1.
    * suffix
      - String, optional, suffix displayed on the value, eg. " %".
    * echo
      - Optional, anything, returned on callback.
        
  onSliderCellChanged event returns a table with:
    * row
      - Longfloat, row of the widget.
    * col
      - Longfloat, col of the widget.
    * value
      - Longfloat, the new slider value.
    * echo
      - Present if param had echo.
      
* Make_Dropdown
  
  Make a dropdown selection cell. Adds to the most recent row. Note: indices start at 1.
      
  Param: Table with the following items:
    * col
      - Integer, column to place the widget in.
    * cue
      - Cue to callback on interact event.
    * options
      - String, comma separated listing of selectable options.
    * start
      - Int, optional, index of the initially selected option.
    * echo
      - Optional, anything, returned on callback.
        
  onDropDownConfirmed event returns a table with:
    * row
      - Longfloat, row of the widget.
    * col
      - Longfloat, col of the widget.
    * option
      - Longfloat, the index of the selected option.
    * echo
      - Present if param had echo.
      
* Send_Command
  
  General cue for packaging up a request and sending it to lua. This may be used instead of the Make_ command, by filling in a matching command name in the param table.
      
  Param: Table with the following items:
    * command
      - String, command to send to lua.
    * ...
      - Any args requied for the command.
    