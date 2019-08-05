# X4 LUA Loader API
Implments a generic method of loading custom lua files into X4.

How to use
----------
In an MD script, add a cue that follows this template:

    <cue name="Load_Lua_Files" instantiate="true">
      <conditions>
        <event_ui_triggered screen="'Lua_Loader_Api'" control="'Ready'" />
      </conditions>
      <actions>
        <raise_lua_event 
          name="'Lua_Loader_Api.Load'" 
          param="'extensions.your_ext_name.your_lua_file_name'"/>
      </actions>
    </cue>

The cue name may be anything.
Replace "your_ext_name.your_lua_file_name" with the appropriate path to your lua file, without the ".lua" suffix.

How it works
------------
A small lua program is provided with two functions: to signal when it is loaded, and to receive file paths from MD scripts.
These files are loaded using lua's "require".
This api's lua file is itself loaded into x4 by replacing ui/addons/ego_debug/ui.xml file.


Summary of the problem
----------------------
The intended method of adding lua files is to place a ui.xml file in the extension's primary folder, which in turn specifies the lua files to load into the game.
As of X4 2.5, lua files loaded this way are provided some basic X4 functions (eg. DebugError), but their globals table is not initialized.
Without this table, the lua code cannot access the various UI functions exported by other X4 lua files, lacks FFI support, and lacks a way to communicate with the mission director.
Even basic lua functions are unavailable.

A workaround is to load in custom lua files alongside the egosoft lua.
This is done by editing one of a handful of ui.xml files in the ui/addons folders, adding the path to the custom lua file.
These ui.xml files cannot be diff patched.
The lua file must be given an xpl extension, and this xpl and the ui.xml must be packed in a "subst" cat/dat.
Since there are a limited number of such ui.xml files, there is a high likelyhood of conflicts in mods importing lua files this way.



Prior work
---------------------------
An initial workaround was provided by morbideth (https://forum.egosoft.com/viewtopic.php?t=411630).
However, this was presented alongside a much more complicated right-click-menu mod, leading to confusion among modders as to how to use the workaround, how reliable it is, and if they had permission to use it.
This new api has a new, somewhat simpler implementation, and is available under the MIT license.

