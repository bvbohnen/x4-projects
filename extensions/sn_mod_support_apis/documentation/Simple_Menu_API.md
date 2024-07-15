
### Simple Menu API Overview


MD api for interfacing with a simple lua menu. The menu will support a 2d table of labels, buttons, and text fields. On player interaction, the lua will inform this api, which will in turn activate callback cues provided by the api user.

After creation, widgets may be partially updated at any time. This is detailed in the Update_Widget cue.    

Note: raise_lua_event only supports passing strings, numbers, or components. This api will pass complex tables of args using a blackboard var: player.entity.$simple_menu_args
  



### Widget arguments and properties overview
    
Many of the following cues share some common arguments or arg data types, described here. Note: many of these can be replaced with a constant looked up in the egosoft api backend Helper module. Possible options are included at the end of this documentation.
    
API args (all widgets, partially for rows and menus)
  * col
    - Integer, column of the row to place the widget in.
    - Uses 1-based indexing.
    - Note: row columns may not always align with table columns:
      - This actually sets the widget as the Nth cell of the row,
      - Row column alignment with the table columns depends on the sizes of all prior row cells (as possibly adjusted by colSpan).
      - Eg. if the widget in col=1 had a colSpan=2, then a new col=2 widget will align with table column 3.
    - Required for now.
  * colSpan = 1
    - Int, how many columns the widget will span.
  * id = none
    - String, unique identifier for the widget.
    - Optional, but needed for Update_Widget calls.
  * echo = none
    - Optional, May be any data type.
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
  * cellBGColor = 'Color.row_background'
    - Color, cell background color.
  * uiTriggerID = none
    - String, if present then this is the control field for ui triggered events on widget activations.
    - Ignore for now; api handles callback cues directly.
        
Events (depends on widget)
  * on<___> (onClick, onTextChanged, etc.)
    - Optional callback cue.
    - When the player interacts with most widgets, ui events will occur. On such events, a provided cue will be called with the event results.
    - Most event.param tables will include these fields:
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
      * halign = 'Helper.standardHalignment'
      * x = 0
      * y = 0
      * color = 'Color.text_normal'
      * glowfactor = 'Color.text_normal.glow'
      * font = 'Helper.standardFont'
      * fontsize = 'Helper.standardFontSize'
      * scaling = true
  * IconProperty
    - Table describing an icon.
    - Fields:
      * icon = ""
        - Icon name
        - See libraries/icons.xml for options.
      * swapicon = ""
      * width = 0
      * height = 0
      * x = 0
      * y = 0
      * color = 'Color.icon_normal'
      * glowfactor = 'Color.icon_normal.glow'
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
  * StandardButtonProperty
    - Table specifying which menu level buttons to include.
    - Fields:
      * close = true
      * back = true
      * minimize = false
  * FrameTextureProperty
    - Table describing a frame background or overlay texture.
    - Fields:
		  * icon = ""
		  * color = 'Color.frame_background_default'
		  * width = 0
		  * height = 0
		  * rotationRate = 0
		  * rotationStart = 0
		  * rotationDuration = 0
		  * rotationInterval = 0
		  * initialScaleFactor = 1
		  * scaleDuration = 0
		  * glowfactor = 'Color.frame_background_default.glow'

### Simple Menu API Cues

* **Reloaded**
  
  Dummy cue used for signalling that the game or ui was reloaded. Users that are registering options menus should listen to this cue being signalled.
    



#### Generic Command Cue
    
* **Send_Command**
  
  Generic cue for sending commands to lua. Other api cues redirect here to interface with the lua backend. Users may utilize this cue if they find it more convenient. See other cues for arg descriptions.
      
  Param: Table with the following items:
  * command
    - String, the command to send.
    - Supported commands:
      - Register_Options_Menu
      - Create_Menu
      - Close_Menu
      - Add_Submenu_Link
      - Add_Row
      - Make_Widget
      - Update_Widget
  * ...
    - Any args requied for the command.
    - Note: Make_Widget commands require a $type string to specify the widget type (found quoted in per-widget descriptions).
      



#### Menu Creation Cues
    
* **Create_Menu**
  
      Create a fresh standalone menu. Note: these menus are not attached to the normal options menu. To be followed by Add_Row and similar cue calls to fill in the menu.
      
      Each menu created will internally be given a frame to hold a table in which widgets will be placed.  The frame and table properties are also set with this cue.
      
      Param: Table with the following items:
      * id, echo
        - Standard api args
      * columns
        - Integer, total number of columns in the menu table.
        - Max is 13 (as of x4 4.0).
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
      * onCloseElement
        - Cue, optional, signalled when the menu is closed.
      * onRowChanged
        - Cue, optional, signalled when the player highlights a different row, either by clicking or using arrow keys.
        - This is the row that is highlighted.
        - Fires when the menu is first opened and a default row selected.
      * onColChanged
        - Cue, optional, signalled when the player highlights a different column, either by clicking or using arrow keys.
        - This will fire if the row changes and there is an interactive widget on the new row.
        - Does not fire when selecting a row with no interactive widgets.
      * onSelectElement
        - Cue, optional, signalled when the player selects a different element.
        - In practice, this appears to only work well for row selection.
        - An element is selected when:
          - It is clicked after already being highlighted.
          - 'Enter' is pressed with it highlighted.
        - Example use: the default options menu uses this to know when the player wants to open a submenu, eg. by 'selecting' Load Game.
      * frame
        - Subtable, properties for the frame, as follows:
  		  * background
          - FrameTextureProperty
  		  * background2
          - FrameTextureProperty
  		  * overlay
          - FrameTextureProperty
        * standardButtons = 'Helper.standardButtons_CloseBack'
          - StandardButtonProperty
          - Which standard buttons will be included, eg. back/minimize/close.
          - These are generally placed in the top right.
        * standardButtonX = 0
          - Int, x offset for the buttons.
        * standardButtonY = 0
          - Int, y offset for the buttons.
        * showBrackets = false
          - Bool, if frame brackets will be shown.
        * closeOnUnhandledClick = false
          - Bool, if the menu triggers an onHide event if the player clicks outside of its area.
          - Pending development.
        * playerControls = false
          - Bool, if player controls are enabled while the menu is open.
          - Can use this to create an info menu in the corner while the player continues flying.
        * enableDefaultInteractions = true
          - Bool, if default inputs are enabled (escape, delete, etc.).
          - When false, these inputs have their normal non-menu effect, eg. escape will open the main options menu (which closes this menu automatically).
      * table
        - Subtable, properties for the table of widgets, as follows:
        * borderEnabled = true
          - Bool, if the table cells have a background color.
          - When set false, the mouse can no longer change row selection, only arrow keys can.
        * reserveScrollBar = true
          - Bool, if the table width reserves space for a scrollbar by adjusting column sizes.
        * wraparound = true
          - Bool, if arrow key traversal of table cells will wrap around edges.
        * highlightMode = "on"
          - String, controls highlighting behavior of table selections.
          - One of ["on","column","off","grey"]
            - "on"     : highlight row with blue box
            - "column" : highlight cell with blue box
            - "grey"   : highlight row with grey box
            - "off"    : no highlights of selected cell
        * multiSelect = false
          - Bool, whether the table allows selection of multiple cells.
        * backgroundID = ""
          - String, name of an icon to use as the background texture.
          - Set to a blank string to disable the background.
        * backgroundColor = 'Color.table_background_default'
          - Color of the background texture.
            
      onCloseElement event returns:
      * echo, event, id
      * reason 
        - String, reason for the closure.
        - "back" if the player pressed the back button, or pressed 'escape' with enableDefaultInteractions == true.
        - "close" if the player pressed the close button, pressed 'delete' with enableDefaultInteractions == true, or opened a different menu.
        - "minimize" if the player pressed the minimize button.
      
      onRowChanged event returns:
      * echo, event, id
      * row
        - Int, index of the newly highlighted row.
      * row_id
        - ID of the selected row, if available.
      * row_echo
        - Echo field of the row, if available.
      
      onColChanged event returns:
      * echo, event, id
      * row, col
        - Ints, row/col highlighted, generally corresponding to a widget.
      * widget_id
        - ID of the any selected widget at the give row/col, if available.
      * widget_echo
        - Echo field of the widget, if available.
      
      onSelectElement event returns:
      * echo, event, id
      * row
        - Int, index of the selected row.
      * row_id
        - ID of the selected row, if available.
      * row_echo
        - Echo field of the row, if available.
        
      
* **Register_Options_Menu**
  
  Register an options menu, which will be accessible as a submenu of the normal game options. These menus will be set to use the same visual style as the standard options menus, and so support a reduced set of args compared to standalone menus.
      
  Param: Table with the following items:
  * id
    - String, required unique identifier for this menu.
    - Needs to differ from egosoft menu names, as well as any other mod registered menus.
  * echo
    - Standard api args
  * title
    - Text to display in the table header.
  * columns
    - Integer, total number of columns in the menu table.
  * private
    - Int 0 or 1, optional, controls if the menu will be listed automatically in the general list of Extension Options menus.
    - Defaults to 0, non-private.
    - Set to private for submenus you will manually link to using Add_Submenu_Link.
  * onOpen
    - Cue to be called when the submenu is being opened by the player.
    - This cue should use addRow and Make_ functions to build the menu.
    - Do not call Create_Menu from this cue.
    - Widgets should be set up in the same frame; menu will display on the following frame.
    - The event.param will hold a table including $id, $echo, $columns.
  * onRowChanged
    - Same as for Create_Menu.
  * onColChanged
    - Same as for Create_Menu.
  * onSelectElement
    - Same as for Create_Menu.
  * table
    - Same as for Create_Menu.
        
        
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
            $onOpen  = Fill_Options_Menu,
            $columns = 2, 
            ]"/>
      </actions>
    </cue>
  ```
      
* **Add_Submenu_Link**
  
  Add a link to another options menu. The other option menu will need to registered by Register_Options_Menu (normally with the private flag set). This will add a new row to the menu table, though that row will be ignored for the Make_ commands. Only for use with options menus, not those made through Create_Menu.
      
  Param: Table with the following items:
    * text
      - String, text to display in the selection line.
    * id
      - String, unique id of the submenu to be opened, as set at registration.
      
* **Refresh_Menu**
  
  Refresh the current options menu by clearing its contents and calling the onOpen callback cue.  Does not change the depth of the options menu (eg. the back button is unaltered).
      
  For options menus only; standalone menus can refresh using a new call to Create_Menu.
      



#### Table Cues
    
* **Add_Row**
  
    Add a row to the current menu. Following widget creation commands add to the most recently added row. Max is 160 rows (as of x4 4.0).
      
    Param: Table with the following items.
    * id, echo
      - Standard api args
    * selectable = true
      - Bool, if the row is selectable by the player.
      - Should always be true for rows with interactable widgets.
    * scaling = true
      - Bool, default ui scaling of cells (width/height/coordinates).
      - For now, this is expected to be overridden by per-widget settings.
    * fixed = false
      - Bool, fixes the row in place so it cannot be scrolled.
      - Requires prior rows also be fixed.
    * borderBelow = true
      - Shows a border gap before the next row, if present.
    * interactive = true
    * bgColor = 'Color.row_background'
      - Color, default background of the row's cells.
    * multiSelected = false
      - Bool, row is preselected for multiselect menu tables. },
      
* **Call_Table_Method**
  
  Adjust some aspect of the table calling a backend table method. Generally for adjusting column widths.
      
  Param: Table with the following items.
  * method
    - String, name of the method being called.
    - Further args depend on the method, as follows:
  * ...
    - Further args depending on the method called.
    - Args described below.
        
  The possible methods are:
  - "setColWidth"
    * col
    - Int, column index to adjust. Indexing starts at 1.
    * width
      - Int, pixel width of column
    * scaling = true
      - Bool, if the width is ui scaled.          
  - "setColWidthMin"
    * col
    * width
      - Int, minimum pixel width of column
    * weight = 1
      - Int, how heavily this column is favored vs others when widths are calculated.
    * scaling = true
      - Bool, if the width is ui scaled.            
  - "setColWidthPercent"
    * col
    * width
      - Int, percent width of column of total table.          
  - "setColWidthMinPercent"
    * col
    * width
      - Int, percent width of column of total table.
    * weight = 1
      - Int, how heavily this column is favored vs others.          
  - "setDefaultColSpan"
    * col
    * colspan
      - Int, how many extra columns widgets created in this column will be stretched across.          
  - "setDefaultBackgroundColSpan"
    * col
    * bgcolspan
      - Int, how many extra columns the backgrounds of widgets created in this column will be stretched across.
      



#### Widget Creation Cues
    
* **Make_Text**
  
  Make a "text" cell for displaying non-interactive text. Adds to the most recent row.
      
  Param: Table with the following items
  * col, colspan, id, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties    
  * text
    - String, text to display.
    - Updateable
  * halign = 'Helper.standardHalignment'
  * color = Color.text_normal
    - Updateable
  * glowfactor = Color.text_normal.glow
  * titleColor
    - If given, puts the widget in title mode, which includes an automatic cell underline.
  * font = 'Helper.standardFont'
  * fontsize = 'Helper.standardFontSize'
  * wordwrap = false
  * textX = 'Helper.standardTextOffsetx'
  * textY = 'Helper.standardTextOffsety'
  * minRowHeight = 'Helper.standardTextHeight'
      
      
  Hint: egosoft menus make vertical space using wide, empty text cells. Example, assuming 2 table columns:
  ```xml      
    <signal_cue_instantly cue="md.Simple_Menu_API.Add_Row"
                          param ="table[$selectable = false]"/>
    <signal_cue_instantly
      cue="md.Simple_Menu_API.Make_Text"
      param = "table[
        $col = 1, 
        $colSpan = 2,
        $height = 'Helper.borderSize',
        $fontsize = 1,
        $cellBGColor = 'Color.optionsmenu_cell_background',
        ]"/>
  ```
      
* **Make_BoxText**
  
  Make a "boxtext" cell.  Similar to text, but with an outlining box. Note: the outline box highlighting can behave oddly as the player interacts with other widgets. Adds to the most recent row.
          
  Param: Table with the following items
  * col, colspan, id, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties    
  * text
    - String, text to display.
    - Updateable
  * halign
  * color = 'Color.text_normal'
    - Updateable
  * glowfactor = 'Color.text_normal.glow'
  * boxColor = 'Color.boxtext_box_default'
    - Color of the surrounding box.
    - Updateable
  * minRowHeight = 'Helper.standardTextHeight'
  * font
  * fontsize
  * wordwrap
  * minRowHeight
      
* **Make_Button**
  
  Make a "button" cell. Adds to the most recent row.
      
  Param: Table with the following items.
  * col, colspan, id, echo
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
  * bgColor = 'Color.button_background_default'
    - Color of background.
    - Updateable
  * highlightColor = 'Color.button_highlight_default'
    - Color when highlighted.
    - Updateable
  * height = 'Helper.standardButtonHeight'
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
      
* **Make_EditBox**
  
  Make an "editbox" cell, for text entry. Adds to the most recent row.
      
  Warning: due to a (likely) typo bug, x4 is limited to 5 text edit boxes in a single menu. If many edit fields are needed, consider using sliders for numeric values (limit 50), where users can click the slider displayed value to use it like an editbox.
      
  Param: Table with the following items
  * col, colspan, id, echo
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
  * bgColor = 'Color.editbox_background_default'
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
  * selectTextOnActivation = true
    - Bool, if the text is preselected on activation.
  * active = true
  * restoreInteractiveObject = false
    - Bool, if the focus is returned to the prior input object when this editBox is deactivated.
  * maxChars = 50
    - Int, maximum number of chars that may be entered.
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
      
* **Make_Slider**
  
  Make a horizontal "slidercell" cell. Adds to the most recent row.
      
  Param: Table with the following items
  * col, colspan, id, echo
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
    - Recommended to use this over other events.
  * bgColor = 'Color.slider_background_default'
    - Color of background.
  * inactiveBGColor = 'Color.slider_background_inactive'
  * valueColor = 'Color.slider_value'
    - Color of value.
  * posValueColor = 'Color.slider_diff_pos'
    - Color, positive value if fromCenter is true
  * negValueColor = 'Color.slider_diff_neg'
    - Color, negative value if fromCenter is true
  * min = 0
    - Min value the bar is sized for
  * max = 0
    - Max value the bar is sized for
    - Updateable
  * exceedMaxValue = false
    - Bool, if the player can go over the max value.
    - Requires min >= 0.
  * minSelect = none
    - Optional, Min value the player may select.
    - Defaults to min
  * maxSelect
    - Max value the player may select.
    - Defaults to max
    - Updateable
    - Do not use maxSelect if exceedMaxValue is true
  * hideMaxValue = false
    - Bool, hides the max value.
  * start = 0
    - Initial value
  * value
    - The current value of the slider.
    - Not used during setup (which instead uses start), but can be used to update the slider after creation.
    - Updateable
  * step = 1
    - Step size between slider points
  * suffix = ""
    - String, suffix on the displayed current value.
  * rightToLeft = false
    - Bool, enables a right/left mirrored bar.
  * fromCenter = false
    - Bool, bar extends from a zero point in the center.
  * readOnly = false
    - Bool, disallows player changes.
  * forceArrows = false
    - Bool, show force arrows in readOnly case.
  * useInfiniteValue = false
    - Bool, sets slider to show infinity when infiniteValue is reached.
  * infiniteValue = 0
    - Value at which to show infinity when useInfiniteValue is true.
  * useTimeFormat = false
    - Bool, sets the slider to use a time format.
  * text
    - TextProperty
      
      
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
        
      
* **Make_Dropdown**
  
  Make a "dropdown" selection cell. Adds to the most recent row. Note: indices start at 1.
      
  Param: Table with the following items
  * col, colspan, id, echo
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
      * displayremoveoption = false
        - Bool, if true the option will show an 'x' that the player can click to remove it from the dropdown list.
      * ...
        - Similar to "echo", other subtable fields will be included in the cue callback.
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
  * bgColor = 'Color.dropdown_background_default'
   - Color of background.
  * highlightColor = 'Color.dropdown_highlight_default'
   - Color when highlighted.
  * optionColor = 'Color.dropdown_background_options'
    - Color of the options.
  * optionWidth, optionHeight = 0
    - Dimensions of the options.
  * allowMouseOverInteraction = false
  * textOverride = ""
  * text2Override = ""
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
  * option_index
    - Number, index of the selected option.
  * option
    - Table, the original option specification subtable given to widget creation that matches the option_index.
        
  onDropDownRemoved event returns:
  * row, col, echo, event, id
  * option_index
    - Number, index of the selected option.
  * option
    - Table, the original option specification subtable given to widget creation that matches the player selection.
        
      
* **Make_Icon**
  
  Make an "icon" cell. Note: many icons are large, and may need explicit width/height to adjust the sizing. Adds to the most recent row.
          
  Param: Table with the following items
  * col, colspan, id, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties    
  * icon = ""
    - String, icon id
    - Updateable
  * color = 'Color.icon_normal'
    - Color
    - Updateable
  * glowfactor = 'Color.icon_normal.glow'
  * bgColor = 'Color.checkbox_background_default'
  * active = true
  * symbol = 'circle'
    - String, 'circle or 'arrow', the symbol shown in a checked box.
  * text
    - TextProperty
    - Updateable text
  * text2
    - TextProperty
    - Updateable text
      
* **Make_CheckBox**
  
  Make a "checkbox" cell. Adds to the most recent row.
      
  Param: Table with the following items
  * col, colspan, id, echo
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
  * bgColor = 'Color.checkbox_background_default'
   - Color of background.
  * active = true
   - Bool, if the widget is active.
  * symbol = 'circle'
  * glowfactor = 'Color.icon_normal.glow'
       
  onClick event returns:
  * row, col, echo, event, id
  * checked
    - Int, 0 or 1, checkbox status after click.
        
      
* **Make_StatusBar**
  
  Make a "statusbar" cell. This is a bar that have a baseline value, is filled based on current value, and coloring is based on if the current is greater or less than the baseline. Adds to the most recent row.
      
  Param: Table with the following items
  * col, colspan, id, echo
    - Standard api args
  * scaling, width, height, x, y, mouseOverText
    - Standard widget properties
  * cellBGColor, uiTriggerID
    - Standard cell properties
  * current = 0
    - Int, determines fill of the bar.
    - Updateable
  * start = 0
    - Int, baseline value of the bar. Coloring of bar depends on current compared to start.
    - Updateable
  * max = 0
    - Int, max value of the bar, used for graphic scaling.
    - Min value of the bar is always pinned at 0.
    - Updateable
  * valueColor = 'Color.statusbar_value_default'
    - Color
  * posChangeColor = 'Color.statusbar_diff_pos_default'
    - Color
  * negChangeColor = 'Color.statusbar_diff_neg_default'
    - Color
  * markerColor = 'Color.statusbar_marker_default'
    - Color
  * titleColor
    - Color, optional.
      
* **Update_Widget**
  
  Update a widget's state after creation.
      
  Param: Table with the following items
  * id
    - String, original id assigned to the widget at creation.
  * ...
    - Any args to be updated, matching the original widget creation args layout.
    - Which widget properties can be updated depends on the specific widget.
    



#### Helper Consts

In the egosoft backend, there is a "Helper" module which defines many constants used in the standard menus such as fonts, etc. Colors are available in lua through the Color global, with fields defined in the libraries/colors.xml mapping entries (but the color entries are not accessible). Arguments may optionally be given as a string matching a Helper const, eg. 'Helper.standardFontBold', or a Color const, eg. 'Color.row_separator_white'. A selected list of possibly useful helper consts follows (and may be out of date with the current patch).
  
* Font related
  - Helper.standardFontBold = "Zekton bold"
  - Helper.standardFontMono = "Zekton fixed"
  - Helper.standardFontBoldMono = "Zekton bold fixed"
  - Helper.standardFontOutlined = "Zekton outlined"
  - Helper.standardFontBoldOutlined = "Zekton bold outlined"
  - Helper.standardFont = "Zekton"
  - Helper.standardFontSize = 9
  - Helper.standardTextOffsetx = 5
  - Helper.standardTextOffsety = 0
  - Helper.standardTextHeight = 16
  - Helper.standardTextWidth = 0
  - Helper.titleFont = "Zekton bold"
  - Helper.titleFontSize = 12
  - Helper.titleOffsetX = 3
  - Helper.titleOffsetY = 2
  - Helper.titleHeight = 20
  - Helper.headerRow1Font = "Zekton bold"
  - Helper.headerRow1FontSize = 10
  - Helper.headerRow1Offsetx = 3
  - Helper.headerRow1Offsety = 2
  - Helper.headerRow1Height = 20
  - Helper.headerRow1Width = 0
  
* Sizing
  - Helper.standardButtonWidth = 30
  - Helper.standardButtonHeight = 20
  - Helper.standardFlowchartNodeHeight = 30
  - Helper.standardFlowchartConnectorSize = 10
  - Helper.standardHotkeyIconSizex = 19
  - Helper.standardHotkeyIconSizey = 19
  - Helper.subHeaderHeight = 18
  - Helper.largeIconFontSize = 16
  - Helper.largeIconTextHeight = 32
  - Helper.configButtonBorderSize = 2
  - Helper.scrollbarWidth = 19
  - Helper.buttonMinHeight = 23
  - Helper.standardIndentStep = 15
  - Helper.borderSize = 3
  - Helper.slidercellMinHeight = 16
  - Helper.editboxMinHeight = 23
  - Helper.sidebarWidth = 40
  - Helper.frameBorder = 25
    
* StandardButtonProperty
  - Helper.standardButtons_CloseBack
  - Helper.standardButtons_Close
  
  