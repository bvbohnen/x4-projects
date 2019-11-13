# X4 Simple Menu API

This extension adds support for generating menus using mission director scripts in X4. A lua backend handles the details of interfacing with the x4 ui system.

Two types of menus are supported: options menus that are integrated with the standard x4 options, and standalone menus which will display immediately.


### Requirements

* Lua Loader API extension
  - https://github.com/bvbohnen/x4-lua-loader-api.git

### Usage

* Standalone menu
  - Call Create_Menu to open a new menu, closing any others.
  - Fill the menu with rows and widgets, specifying callback cues.
  - Callback cues will be signalled on player input.
  - Access through a trigger condition of your choice.

* Options menu
  - Call Register_Options_Menu to register your menu with the backend.
  - Create a cue which will make the rows and widgets as above.
  - Set the above cue as the onOpen callback target during registration.
  - Access through the "Extension Options" page of the main menu.

### Examples

* Standalone menu:
  ```xml
  <cue name="Open_Menu" instantiate="true" namespace="this">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>
      <signal_cue_instantly
        cue = "md.Simple_Menu_API.Create_Menu"
        param = "table[
          $columns = 1, 
          $title   = 'My Menu',
          $width   = 500,
          ]"/>
      <signal_cue_instantly cue="md.Simple_Menu_API.Add_Row"/>
      <signal_cue_instantly
        cue = "md.Simple_Menu_API.Make_Label"
        param = "table[$col=1, $text='Hello world']"/>
    </actions>
  </cue>
  ```
* Options menu:
  ```xml
  <cue name="Register_Options_Menu" instantiate="true" namespace="this">
    <conditions>
      <event_cue_signalled cue="md.Simple_Menu_API.Reloaded"/>
    </conditions>
    <actions>
      <signal_cue_instantly
        cue="md.Simple_Menu_API.Register_Options_Menu"
        param = "table[
          $id = 'my_unique_menu',
          $columns = 1, 
          $title = 'My Options',
          $onOpen = Build_Options_Menu
          ]"/>
    </actions>
  </cue>

  <cue name="Build_Options_Menu" instantiate="true" namespace="this">
    <conditions>
      <event_cue_signalled/>
    </conditions>
    <actions>            
      <signal_cue_instantly cue="md.Simple_Menu_API.Add_Row"/>
      <signal_cue_instantly
        cue="md.Simple_Menu_API.Make_Label"
        param = "table[$col=1, $text='Hello world']"/>
    </actions>
  </cue>
  ```