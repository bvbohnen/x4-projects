
### Lua Loader API Overview

 
Provides support for loading lua files.

* ui.xml based lua files are loaded before the game initializes
  - Fix: init functions can be registered to run only after game load.
* "require" is limited to whitelisted lua files in protected ui mode
  - Fix: allows lua files to register return values for use in "require" calls.
* pre-7.5 mods using ui.xml have uninitialized globals ("_G is nil")
  - Fix: provide MD cues that will trigger loading of loose lua files through a patched egosoft ui.xml.
  - Legacy support for older mods, no longer recommended for use.

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