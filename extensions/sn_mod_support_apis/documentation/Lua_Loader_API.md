
### Lua Loader API Overview

 
Provides support functions that aid in running lua files, addressing some issues in X4.

* Register lua Init functions to run after the game fully loads.
  - Lua files added to the game using ui.xml are loaded before the game initializes; delaying the Init call allows for accessing game state (eg. C.GetPlayerID() only works after the game loads).
* Register module path strings and return values for "require" calls.
  - In protected UI mode, "require" is limited to whitelisted lua files; this api patches "require" to add support for registered lua files.
* Trigger loading of loose lua files using MD script cues.
  - Solved an former issue: before X4 7.5, mods loaded through ui.xml had uninitialized globals ("_G is nil").
  - This functionality is retained as legacy support for older mods; newer mods should ignore this in favor of ui.xml loading.

### Lua Loader API Functions

 

Adds these functions to the lua Globals:

* Register_Require_Response(require_path, value)
  - Adds "require" support for the require_path, returning the value.
  - The path does not need to match the actual file path.
* Register_OnLoad_Init(function, path)
  - Calls the given function to be called on game start, reload, or ui reload.
  - Path is optional, a description path printed to the debuglog if the function fails.
  - Functions are called in order of registration, which can be controlled through intermod dependencies and the order of inclusion in ui.xml.
* Register_Require_With_Init(require_path, value, function)
  - Combination of Register_Require_Response and Register_OnLoad_Init.

To load loose lua files through MD script, listen for the Lua_Loader Ready signal and raise a Lua_Loader.Load event with the path to the lua file. The lua file may have extension .lua or .txt, but should not be packed in a cat/dat. Example:

```
<cue name="Load_Lua_Files" instantiate="true">
<conditions>
    <event_ui_triggered screen="'Lua_Loader'" control="'Ready'" />
</conditions>
<actions>
    <raise_lua_event name="'Lua_Loader.Load'" 
        param="'extensions.sn_named_pipes_api.Named_Pipes'"/>
</actions>
</cue>
```