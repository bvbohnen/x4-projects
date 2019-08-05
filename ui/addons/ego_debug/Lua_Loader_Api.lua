--[[
Simple api for loading in mod lua files.
This works around a bug in the x4 ui.xml style lua loading which fails
to initialize the globals table.

Usage is kept simple:
    When the ui reloads or a game is loaded, a ui event is raised.
    User MD code will set a cue to trigger on this event and signal to
    lua which file to load.
    Lua will then "require" the file, effectively loading it into the game.

This lua file is itself included by modding an official ui.xml. Lua added
in this way is imported correctly into X4, though there are limited
official ui.xml files which can be modified in this way.
    
Example from MD:

    <cue name="Load_Lua_Files" instantiate="true">
    <conditions>
        <event_ui_triggered screen="'Lua_Loader_Api'" control="'Ready'" />
    </conditions>
    <actions>
        <raise_lua_event name="'Lua_Loader_Api.Load'" param="'extensions.named_pipes_api.Named_Pipes'"/>
    </actions>
    </cue>
  
    Here, the cue name can be anything, and the param is the specific
    path to the lua file to load, without extension.
    
]]
local function on_Load_Lua_File(_, file_path)
    require(file_path)
    DebugError("LUA Loader API: loaded "..file_path)
end
local function Announce_Reload()
    -- DebugError("LUA Loader API: Signalling 'Lua_Loader_Api, Ready'")
    -- Send a ui signal, telling all md cues to rerun.
    AddUITriggeredEvent("Lua_Loader_Api", "Ready")
end
local function Init()    
    DebugError("LUA Loader API: Running Init()")
    -- Hook up an md->lua signal.
    RegisterEvent("Lua_Loader_Api.Load", on_Load_Lua_File)
    
    -- Re-announce the UI signal on game reload, signalled by MD.
    -- (Used since ui gets set up and signals thrown away before md loads).
    RegisterEvent("Lua_Loader_Api.Signal", Announce_Reload)
    
    -- Also call the function once on ui reload itself, to catch /reloadui
    -- commands while the md is running.
    Announce_Reload()
end
Init()