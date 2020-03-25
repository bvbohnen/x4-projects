
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
# TODO: maybe move these to per-extension annotation files.
project_spec_table = {
    # Python style of pipe server.
    'X4_Python_Pipe_Server_py':{ 
        'root_path':project_dir, 
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
        'root_path':project_dir / 'X4_Python_Pipe_Server', 
        'doc_path' : '',
        'files':[
            '../bin/X4_Python_Pipe_Server.exe',
        ]},
    'Named_Pipes_API':{ 
        'root_path': project_dir / 'extensions',
        'doc_path' : 'sn_named_pipes_api',
        'files':[
            'sn_named_pipes_api/Readme.md',
            'sn_named_pipes_api/content.xml',
        ],
        'lua_files':[
            'sn_named_pipes_api/lua/Interface.lua',
            'sn_named_pipes_api/lua/Library.lua',
            'sn_named_pipes_api/lua/Pipes.lua',
            'sn_named_pipes_api/lualibs/winpipe.lua',
            'sn_named_pipes_api/lualibs/winpipe_64.dll',
        ],
        'ext_files':[
            'sn_named_pipes_api/md/Named_Pipes.xml',
            'sn_named_pipes_api/md/Pipe_Server_Host.xml',
            'sn_named_pipes_api/md/Pipe_Server_Lib.xml',
        ],
        'subst_files':[
        ],
        # TODO: explicitly list files, or autoparse from above?
        'docgen':[
            'sn_named_pipes_api/md/Named_Pipes.xml',
            'sn_named_pipes_api/md/Pipe_Server_Host.xml',
            'sn_named_pipes_api/md/Pipe_Server_Lib.xml',
            'sn_named_pipes_api/lua/Interface.lua',
        ]},
    'Hotkey_API':{ 
        'root_path':project_dir / 'extensions', 
        'doc_path' : 'sn_hotkey_api',
        'files':[
            'sn_hotkey_api/Readme.md',
            'sn_hotkey_api/content.xml',
            'sn_hotkey_api/Send_Keys.py',
        ],
        'lua_files':[
            'sn_hotkey_api/lua/Interface.lua',
            'sn_hotkey_api/lua/Library.lua',
            'sn_hotkey_api/lua/Tables.lua',
        ],
        'ext_files':[
            'sn_hotkey_api/md/Hotkey_API.xml',
            'sn_hotkey_api/md/HK_Stock_Actions.xml',
        ],
        'subst_files':[
        ],
        },
    'Lua_Loader_API':{ 
        'root_path':project_dir / 'extensions', 
        'doc_path' : 'sn_lua_loader_api',
        'files':[
            'sn_lua_loader_api/Readme.md',
            'sn_lua_loader_api/content.xml',
            #'sn_lua_loader_api/subst_01.cat',
            #'sn_lua_loader_api/subst_01.dat',
        ],
        'lua_files':[
        ],
        'ext_files':[
            'sn_lua_loader_api/md/Lua_Loader.xml',
        ],
        # Files that go in a subst extension.
        'subst_files':[
            'sn_lua_loader_api/ui/addons/ego_debug/Lua_Loader.lua',
            'sn_lua_loader_api/ui/addons/ego_debug/ui.xml',
        ],
        },
    'Simple_Menu_API':{ 
        'root_path':project_dir / 'extensions', 
        'doc_path' : 'sn_simple_menu_api',
        'files':[
            'sn_simple_menu_api/Readme.md',
            'sn_simple_menu_api/content.xml',
        ],
        'lua_files':[
            'sn_simple_menu_api/lua/Interface.lua',
            'sn_simple_menu_api/lua/Library.lua',
            'sn_simple_menu_api/lua/Options_Menu.lua',
            'sn_simple_menu_api/lua/Standalone_Menu.lua',
            'sn_simple_menu_api/lua/Tables.lua',
        ],
        'ext_files':[
            'sn_simple_menu_api/md/Simple_Menu_API.xml',
            'sn_simple_menu_api/md/Simple_Menu_Options.xml',
        ],
        'subst_files':[
        ],
        },
    'Better_Target_Monitor':{ 
        'root_path':project_dir / 'extensions', 
        'doc_path' : 'sn_better_target_monitor',
        'files':[
            'sn_better_target_monitor/content.xml',
        ],
        'lua_files':[
            'sn_better_target_monitor/lua/Target_Monitor.lua',
        ],
        'ext_files':[
            'sn_better_target_monitor/md/Better_Target_Monitor.xml',
        ],
        'subst_files':[
        ],
        },
    'Interact_Menu_API':{ 
        'root_path':project_dir / 'extensions', 
        'doc_path' : 'sn_interact_menu_api',
        'files':[
            'sn_interact_menu_api/content.xml',
        ],
        'lua_files':[
            'sn_interact_menu_api/lua/Interface.lua',
        ],
        'ext_files':[
            'sn_interact_menu_api/md/Interact_Menu_API.xml',
        ],
        'subst_files':[
        ],
        },
    'Extra_Game_Options':{ 
        'root_path':project_dir / 'extensions', 
        'doc_path' : 'sn_extra_game_options',
        'files':[
            'sn_extra_game_options/Readme.md',
            'sn_extra_game_options/content.xml',
        ],
        'lua_files':[
            'sn_extra_game_options/lua/Custom_Options.lua',
        ],
        'ext_files':[
            'sn_extra_game_options/md/Extra_Game_Options.xml',
        ],
        'subst_files':[
        ],
        },
    'Time_API':{ 
        'root_path':project_dir / 'extensions', 
        'doc_path' : 'sn_time_api',
        'files':[
            'sn_time_api/Readme.md',
            'sn_time_api/content.xml',
            'sn_time_api/Time_API.py',
        ],
        'lua_files':[
            'sn_time_api/lua/Interface.lua',
            'sn_time_api/lua/Pipe_Time.lua',
        ],
        'ext_files':[
            'sn_time_api/md/Time_API.xml',
        ],
        'subst_files':[
        ],
        },
    }


def _Init():
    for project_name, spec in project_spec_table.items():
        # Prefix the doc_path and all file paths with their root_path.
        spec['root_path'] = spec['root_path'].resolve()
        spec['doc_path']  = spec['root_path'] / spec['doc_path']
        # Lists of files.
        for key in ['files','ext_files','subst_files','lua_files']:
            if key in spec:
                spec[key]     = [(spec['root_path'] / x).resolve() for x in spec[key]]
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