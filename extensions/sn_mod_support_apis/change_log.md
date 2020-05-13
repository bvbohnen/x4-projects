
Change Log for overall api package.

* 1.0
  - Apis packaged together.
* 1.1
  - Fixed content.xml text nodes.
* 1.2
  - Fixing missing dll from prior release.
* 1.70
  - Start of joint change log.
  - named_pipes:
    - added continuous read requests.
  - hotkeys:
    - Suppress hotkeys when typing into text boxes.
    - Support for processing multiple keys per frame.
  - simple_options: 
    - Added $skip_initial_callback param.
    - Added Write_Option_Value and Read_Option_Value cues.
  - simple_menu:
    - Fixed column indexing for Call_Table_Method on options menus.
    - Added options menu onOpen signal param with $id, $echo, $columns.