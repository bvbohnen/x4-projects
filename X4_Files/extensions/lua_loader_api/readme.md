# X4 LUA Loader API
This extension implements a generic method of loading custom lua files into X4, working around a bug in the intended method of loading lua code.

### How to use

In an MD script, add a cue that follows this template code:

    <cue name="Load_Lua_Files" instantiate="true">
      <conditions>
        <event_ui_triggered screen="'Lua_Loader'" control="'Ready'" />
      </conditions>
      <actions>
        <raise_lua_event 
          name="'Lua_Loader.Load'" 
          param="'extensions.your_ext_name.your_lua_file_name'"/>
      </actions>
    </cue>

The cue name may be anything. Replace "your_ext_name.your_lua_file_name" with the appropriate path to your lua file, without file extension. The lua file needs to be loose, not packed in a cat/dat. The file extension may be ".lua" or ".txt", where the latter may be needed if distributing through steam workshop. If editing the lua code, it can be updated in-game using "/reloadui" in the chat window.

When a loading is complete, a message is printed to the debuglog, and a ui signal is raised. The signal "control" field will be "Loaded " followed by the original param file path. This can be used to set up loading dependencies, so that one lua file only loads after a prior one.

Example dependency condition code:

    <conditions>
      <event_ui_triggered screen="'Lua_Loader'" 
        control="'Loaded extensions.other_ext_name.other_lua_file_name'" />
    </conditions>

### How it works

A small lua program is provided with two functions: to signal when it is loaded, and to receive file paths from MD scripts. These files are loaded using lua's "require". This api's lua file is itself loaded into x4 by replacing ui/addons/ego_debug/ui.xml file.

### Summary of the problem

The intended method of adding lua files is to place a ui.xml file in the extension's primary folder, which in turn specifies the lua files to load into the game. As of X4 2.5, lua files loaded this way are provided some basic X4 functions (eg. DebugError), but their globals table is not initialized. Without this table, the lua code cannot access the various UI functions exported by other X4 lua files, lacks FFI support, and lacks a way to communicate with the mission director. Even basic lua functions are unavailable.

A workaround is to load in custom lua files alongside the egosoft lua. This is done by editing one of a handful of ui.xml files in the ui/addons folders, adding the path to the custom lua file. These ui.xml files cannot be diff patched. The lua file must be given an xpl extension, and this xpl and the ui.xml must be packed in a "subst" cat/dat.

Since there are a limited number of such ui.xml files, there is a high likelyhood of conflicts in mods importing lua files this way. Additionally, when editing code, this method of lua inclusion will generally require a restart of X4 to load any changes properly due to the "subst" packing.

### Prior work

An initial workaround was provided by morbideth (https://forum.egosoft.com/viewtopic.php?t=411630). However, this was presented alongside a much more complicated right-click-menu mod, leading to confusion among modders as to how to use the workaround, how reliable it is, and if they had permission to use it.

This new api has a new, somewhat simpler implementation; supports txt files; and is available under the MIT license.

