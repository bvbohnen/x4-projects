
from pathlib import Path
project_dir = Path(__file__).resolve().parents[1]

__all__ = [
    'project_spec_table',
    'Get_Content_Path',
    'Get_Changelog_Path',
    ]

# Dict matching each release zip with the files it includes.
# Note: root_dir is where other paths are taken relative to, and also the
#  base dir for the zip file (eg. relative paths are what will be seen
#  when zipped). However, all paths are polished into absolute paths
#  for other modules to use.
project_spec_table = {
    'Named_Pipes_API':{ 
        'root_path': project_dir / 'X4_Named_Pipes_API',
        'doc_path' : '',
        'files':[
            'Readme.md',
            'named_pipes_api/content.xml',
            'named_pipes_api/md/Named_Pipes.xml',
            'named_pipes_api/md/Pipe_Server_Host.xml',
            'named_pipes_api/md/Pipe_Server_Lib.xml',
            'named_pipes_api/lua/Interface.lua',
            'named_pipes_api/lua/Library.lua',
            'named_pipes_api/lua/Pipes.lua',
            'named_pipes_api/lualibs/winpipe.lua',
            'named_pipes_api/lualibs/winpipe_64.dll',
        ]},
    # Python style of pipe server.
    'X4_Python_Pipe_Server_py':{ 
        'root_path':project_dir / 'X4_Named_Pipes_API', 
        'doc_path' : 'X4_Python_Pipe_Server',
        'files':[
            'X4_Python_Pipe_Server/__init__.py',
            'X4_Python_Pipe_Server/Main.py',
            'X4_Python_Pipe_Server/Classes/__init__.py',
            'X4_Python_Pipe_Server/Classes/Pipe.py',
            'X4_Python_Pipe_Server/Classes/Server_Thread.py',
        ]},
    # Exe style of pipe server. TODO: just combine with above?
    'X4_Python_Pipe_Server_exe':{ 
        'root_path':project_dir / 'X4_Named_Pipes_API' / 'X4_Python_Pipe_Server', 
        'doc_path' : '',
        'files':[
            '../bin/X4_Python_Pipe_Server.exe',
        ]},
    'Hotkey_API':{ 
        'root_path':project_dir / 'X4_Hotkey_API', 
        'doc_path' : '',
        'files':[
            'Readme.md',
            'hotkey_api/content.xml',
            'hotkey_api/Send_Keys.py',
            'hotkey_api/md/Hotkey_API.xml',
            'hotkey_api/md/HK_Stock_Actions.xml',
            'hotkey_api/lua/Interface.lua',
            'hotkey_api/lua/Library.lua',
            'hotkey_api/lua/Tables.lua',
        ]},
    'Lua_Loader_API':{ 
        'root_path':project_dir / 'X4_Lua_Loader_API', 
        'doc_path' : '',
        'files':[
            'Readme.md',
            'lua_loader_api/content.xml',
            'lua_loader_api/subst_01.cat',
            'lua_loader_api/subst_01.dat',
            'lua_loader_api/md/Lua_Loader.xml',
            'lua_loader_api/ui/addons/ego_debug/Lua_Loader.lua',
            'lua_loader_api/ui/addons/ego_debug/ui.xml',
        ]},
    'Simple_Menu_API':{ 
        'root_path':project_dir / 'X4_Simple_Menu_API', 
        'doc_path' : '',
        'files':[
            'Readme.md',
            'simple_menu_api/content.xml',
            'simple_menu_api/md/Simple_Menu_API.xml',
            'simple_menu_api/md/Simple_Menu_Options.xml',
            'simple_menu_api/lua/Custom_Options.lua',
            'simple_menu_api/lua/Interface.lua',
            'simple_menu_api/lua/Library.lua',
            'simple_menu_api/lua/Options_Menu.lua',
            'simple_menu_api/lua/Standalone_Menu.lua',
            'simple_menu_api/lua/Tables.lua',
        ]},
    'Better_Target_Monitor':{ 
        'root_path':project_dir / 'X4_Better_Target_Monitor', 
        'doc_path' : '',
        'files':[
            'better_target_monitor/content.xml',
            'better_target_monitor/md/Better_Target_Monitor.xml',
            'better_target_monitor/lua/Target_Monitor.lua',
        ]},
    'Interact_Menu_API':{ 
        'root_path':project_dir / 'X4_Interact_Menu_API', 
        'doc_path' : '',
        'files':[
            'interact_menu_api/content.xml',
            'interact_menu_api/md/Interact_Menu_API.xml',
            'interact_menu_api/lua/Interface.lua',
        ]},
    'Time_API':{ 
        'root_path':project_dir / 'X4_Time_API', 
        'doc_path' : '',
        'files':[
            'Readme.md',
            'time_api/content.xml',
            'time_api/md/Time_API.xml',
            'time_api/lua/Interface.lua',
            'time_api/lua/Pipe_Time.lua',
            'time_api/Time_API.py',
        ]},
    }


def _Init():
    for project_name, spec in project_spec_table.items():
        # Prefix the doc_path and all file paths with their root_path.
        spec['root_path'] = spec['root_path'].resolve()
        spec['doc_path']  = spec['root_path'] / spec['doc_path']
        spec['files']     = [(spec['root_path'] / x).resolve() for x in spec['files']]
_Init()

def Get_Content_Path(spec):
    'Returns a path to the content.xml file, or None if not present.'
    # Search for content.xml in the files.
    for file in spec['files']:
        if file.name == 'content.xml':
            return file
    return


def Get_Changelog_Path(spec):
    'Returns a path to the change_log.md file.'
    return spec['doc_path'] / 'change_log.md'