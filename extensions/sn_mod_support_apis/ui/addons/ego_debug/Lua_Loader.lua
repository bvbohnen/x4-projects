--[[
Simple api for loading in mod lua files, and for accessing ui userdata.
This works around a bug in the x4 ui.xml style lua loading which fails
to initialize the globals table.

Usage is kept simple:
    When the ui reloads or a game is loaded, a ui event is raised.
    User MD code will set up a cue to trigger on this event and signal to
    lua which file to load.
    Lua will then "require" the file, effectively loading it into the game.

This lua file is itself included by modding an official ui.xml. Lua added
in this way is imported correctly into X4, though there are limited
official ui.xml files which can be modified in this way.
    

Example from MD:

    <cue name="Load_Lua_Files" instantiate="true">
    <conditions>
        <event_ui_triggered screen="'Lua_Loader'" control="'Ready'" />
    </conditions>
    <actions>
        <raise_lua_event name="'Lua_Loader.Load'" 
            param="'extensions.sn_named_pipes_api.Named_Pipes'"/>
    </actions>
    </cue>
  
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
    

This api also provides for saving data into the uidata.xml file.
All such saved data is in the __MOD_USERDATA global table.
Each individual mod should add a unique key to this table, and save its
data under that key. Nested tables are supported.
Care should be used in the top level key, to avoid cross-mod conflicts.

To enable early loading of the Userdata handler, this will also support
an early ready signal, which resolves before the normal ready.
- On reloadui or md signalling Priority_Signal, send Priority_Ready.
- Next frame, md cues which listen to this may signal to load their lua.
- Md side will see Priority_Ready, and send Signal.
- Back end of frame, priority lua files load, and api signals standard Ready.
- Next frame, md cues which listen to Ready may signal to load their lua.

TODO: allow for more md arguments, including specifying dependendencies
which are resolved at this level (eg. store and delay the require until
all dependencies are met).
]]

local function Send_Priority_Ready()
    --DebugError("LUA Loader API: Signalling 'Lua_Loader, Priority_Ready'")
    -- Send a ui signal, telling all md cues to rerun.
    AddUITriggeredEvent("Lua_Loader", "Priority_Ready")
end

local function Send_Ready()
    --DebugError("LUA Loader API: Signalling 'Lua_Loader, Ready'")
    -- Send a ui signal, telling all md cues to rerun.
    AddUITriggeredEvent("Lua_Loader", "Ready")
end

local function on_Load_Lua_File(_, file_path)

    -- Since lua files cannot be distributed with steam workshop stuff,
    -- but txt can, use a trick to change the package search path to
    -- also look for txt files (which can be put on steam).
    -- This is done on every load, since the package.path was observed to
    -- get reset after Init runs (noticed in x4 3.3hf1).
    if not string.find(package.path, "?.txt;") then
        package.path = "?.txt;"..package.path
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
    Send_Priority_Ready()
end

Init()