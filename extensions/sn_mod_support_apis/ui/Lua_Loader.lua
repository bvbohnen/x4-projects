
--[[ @doc-title
Lua Loader API
]]

--[[ @doc-overview
Provides support functions that aid in running lua files, addressing some
issues in X4.

* Register lua Init functions to run after the game fully loads.
  - Lua files added to the game using ui.xml are loaded before the game
    initializes; delaying the Init call allows for accessing game state
    (eg. C.GetPlayerID() only works after the game loads).
* Register module path strings and return values for "require" calls.
  - In protected UI mode, "require" is limited to whitelisted lua files;
    this api patches "require" to add support for registered lua files.
* Trigger loading of loose lua files using MD script cues.
  - Solved an former issue: before X4 7.5, mods loaded through ui.xml had
    uninitialized globals ("_G is nil").
  - This functionality is retained as legacy support for older mods; newer
    mods should ignore this in favor of ui.xml loading.
]]

--[[ @doc-functions

Adds these functions to the lua Globals:

* Register_Require_Response(require_path, value)
  - Adds "require" support for the require_path, returning the value.
  - The path does not need to match the actual file path.
* Register_OnLoad_Init(function, path)
  - Calls the given function to be called on game start, reload, or ui reload.
  - Path is optional, a description path printed to the debuglog if the
    function fails.
  - Functions are called in order of registration, which can be controlled
    through intermod dependencies and the order of inclusion in ui.xml.
* Register_Require_With_Init(require_path, value, function)
  - Combination of Register_Require_Response and Register_OnLoad_Init.

To load loose lua files through MD script, listen for the Lua_Loader Ready
signal and raise a Lua_Loader.Load event with the path to the lua file.
The lua file may have extension .lua or .txt, but should not be packed
in a cat/dat. Example:

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
]]

--[[
Old description follows:

Simple api for loading in mod lua files.
This works around a bug in the x4 ui.xml style lua loading which fails
to initialize the globals table.

Usage is kept simple:
    When the ui reloads or a game is loaded, a ui event is raised.
    User MD code will set up a cue to trigger on this event and signal to
    lua which file to load.
    Lua will then "require" the file, effectively loading it into the game.

Here, the cue name can be anything, and the param is the specific
path to the lua file to load, without extension.
The file extension may be ".lua" or ".txt", where the latter may be
needed to distribute lua files through steam workshop.
The lua file needs to be loose, not packed in a cat/dat.

When a loading is complete, a message is printed to the debuglog, and
a ui signal is raised. The "control" field will be "Loaded " followed
by the original file_path. This can be used to set up loading
dependencies, so that one lua file only loads after a prior one.

Example dependency condition:

    <conditions>
        <event_ui_triggered screen="'Lua_Loader'" 
            control="'Loaded extensions.sn_named_pipes_api.Named_Pipes'" />
    </conditions>
    
To enable early loading of the Userdata handler, this will also support
an early ready signal, which resolves before the normal ready.
- On reloadui or md signalling Priority_Signal, send Priority_Ready.
- Next frame, md cues which listen to this may signal to load their lua.
- Md side will see Priority_Ready, and send Signal.
- Back end of frame, priority lua files load, and api signals standard Ready.
- Next frame, md cues which listen to Ready may signal to load their lua.


Description of the pre-7.5 problem, moved from the readme:

The intended method of adding lua files is to place a ui.xml file in the 
extension's primary folder, which in turn specifies the lua files to load 
into the game. As of X4 2.5, lua files loaded this way are provided some basic 
X4 functions (eg. DebugError), but their globals table is not initialized. 
Without this table, the lua code cannot access the various UI functions 
exported by other X4 lua files, lacks FFI support, and lacks a way to 
communicate with the mission director. Even basic lua functions are unavailable.

A workaround is to load in custom lua files alongside the egosoft lua. 
This is done by editing one of a handful of ui.xml files in the ui/addons 
folders, adding the path to the custom lua file. These ui.xml files cannot be 
diff patched. The lua file must be given an xpl extension, and this xpl and 
the ui.xml must be packed in a "subst" cat/dat.

Since there are a limited number of such ui.xml files, there is a high 
likelyhood of conflicts in mods importing lua files this way. Additionally, 
when editing code, this method of lua inclusion will generally require a 
restart of X4 to load any changes properly due to the "subst" packing.

]]

-- Table with keys for all module_names that registered exports, even
-- if they want to return nil. (Values are 0s to keep keys alive.)
local modules_with_registered_exports = {}
-- Table mapping module_name to its export value (if not nil).
local module_exports = {}
-- List of tuples of (module_name, init func) holding init functions to 
-- be called when the game is loaded or ui is reloaded, in order of 
-- registration (hence controlled by ordering in ui.xml).
local module_inits = {}

local debug_print_require_info = false

-- Register a module name and response for 'require' support.
function Register_Require_Response(module_name, response)
    Register_Require_With_Init(module_name, response)
end

-- Register a module name and init function to run on md game load signal.
function Register_OnLoad_Init(init, module_name)
    if(module_name == nil) then
        module_name = ""
    end
    Register_Require_With_Init(module_name, nil, init)
end

-- Register a module name with its 'require' response and onload init function.
function Register_Require_With_Init(module_name, response, init)
    if(debug_print_require_info) then
        DebugError("LUA Loader API: registering require response for "..module_name)
    end
    modules_with_registered_exports[module_name] = 0
    module_exports[module_name] = response
    if(init ~= nil) then
        table.insert(module_inits, {module_name, init})
    end
end

-- Patched "require" function that supports registered responses.
if(debug_print_require_info) then
    DebugError("LUA Loader API: patching 'require' function")
end
local orig_require = require
require = function (module_name)
    local is_registered = modules_with_registered_exports[module_name] ~= nil
    if(debug_print_require_info) then
        local status = is_registered and "found" or "not found"
        DebugError("LUA Loader API: handling require of "..module_name.."; registered response is "..status)
    end
    -- Return the preregistered response when available.
    if(is_registered) then
        return module_exports[module_name]
    end
    if(orig_require == nil) then
        DebugError("LUA Loader API: standard require is nil and module named "
            ..module_name.." has not been seen by Register_Require_Response")
    end
    -- Fall back on standard require, including any error it may throw,
    -- eg. complaining about being nil.
    return orig_require(module_name)
end


local function Send_Priority_Ready()
    --DebugError("LUA Loader API: Signalling 'Lua_Loader, Priority_Ready'")
    -- Send a ui signal, telling all md cues to rerun.
    AddUITriggeredEvent("Lua_Loader", "Priority_Ready")
    -- TODO: maybe support priority init functions.
end

local function Send_Ready()
    --DebugError("LUA Loader API: Signalling 'Lua_Loader, Ready'")
    -- Send a ui signal, telling all md cues to rerun.
    AddUITriggeredEvent("Lua_Loader", "Ready")

    -- Also run all lua init functions.
    for index, name_func in ipairs(module_inits) do
        local name = name_func[1]
        local func = name_func[2]
        local success, message = pcall(func)
        if(success == false) then
            DebugError("LUA Loader API: init for module "..name.." failed with message: "..message)
        end
    end
end

local function on_Load_Lua_File(_, file_path)

    if(package ~= nil) then
        -- Support lua files distributed as txt (which has more general
        -- stream workshop support).
        -- This is done on every load, since the package.path was observed to
        -- get reset after Init runs (noticed in x4 3.3hf1).
        if not string.find(package.path, "?.txt;") then
            package.path = "?.txt;"..package.path
        end
    
        -- As of 7.5, .lua files are not searched automatically, so add this
        -- extension as well.
        if not string.find(package.path, "?.lua;") then
            package.path = "?.lua;"..package.path
        end
    end

    require(file_path)
    -- Removing the debug message; if a user really wants to know,
    -- they can listen to the ui event.
    --DebugError("LUA Loader API: loaded "..file_path)

    -- Generic signal that the load completed, for use when there
    -- are inter-lua dependencies (to control loading order).
    AddUITriggeredEvent("Lua_Loader", "Loaded "..file_path)
end

local function Init()
    --DebugError("LUA Loader API: Running Init()")
    --DebugError("require:"..tostring(require).." ("..type(require)..")")
    --DebugError("package:"..tostring(package).." ("..type(package)..")")
    
    -- Hook up an md->lua signal.
    RegisterEvent("Lua_Loader.Load", on_Load_Lua_File)
    
    -- Listen to md side timing on when to send Ready signals.
    -- Priority ready is triggered on game start/load.
    RegisterEvent("Lua_Loader.Send_Priority_Ready", Send_Priority_Ready)
    RegisterEvent("Lua_Loader.Send_Ready", Send_Ready)
    
    -- Also call the function once on ui reload itself, to catch /reloadui
    -- commands while the md is running.
    -- Only triggers priority ready; md will then signal Send_Ready for
    -- the second part.
    -- Note: before the game md scripts are set up this is expected to
    -- do nothing since there is no listener.
    Send_Priority_Ready()
end

-- Note: have to init this right away to set up mechanism so other
-- lua files can delay init until load.
Init()