'''
Top level definitions of releases to make.
'''
from pathlib import Path

project_dir = Path(__file__).resolve().parents[1]
from Release_Spec_class import Release_Spec

__all__ = [
    'release_specs',
    ]

release_specs = [
    Release_Spec(
        name = 'sn_x4_python_pipe_server_py',
        root_path = project_dir / 'X4_Python_Pipe_Server',
        files = [
            '__init__.py',
            'Main.py',
            'Classes/__init__.py',
            'Classes/Pipe.py',
            'Classes/Server_Thread.py',
        ],
        ),
    
    Release_Spec(
        name = 'sn_x4_python_pipe_server_exe',
        root_path = project_dir / 'X4_Python_Pipe_Server',
        files = [
            '../bin/X4_Python_Pipe_Server.exe',
        ],
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_asteroid_fade',
        steam = True,
        ),

    Release_Spec(
        root_path = project_dir / 'extensions/sn_better_target_monitor',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_debug_info',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_extra_game_options',
        steam = True,
        ),

    # TODO: friendlier fire when ready.
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_hotkey_collection',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_interact_collection',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_measure_fps',
        steam = False,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_mod_support_apis',
        steam = True,
        files = [
            'lua_interface.txt',
        ],
        doc_specs = {
            'documentation/Named_Pipes_API.md':[
                'md/Named_Pipes.xml',
                'md/Pipe_Server_Host.xml',
                'md/Pipe_Server_Lib.xml',
            ],
            'documentation/Hotkey_API.md':[
                'md/Hotkey_API.xml',
            ],
            'documentation/Simple_Menu_API.md':[
                'md/Simple_Menu_API.xml',
            ],
            'documentation/Simple_Menu_Options_API.md':[
                'md/Simple_Menu_Options.xml',
            ],
            'documentation/Time_API.md':[
                'lua/time/Interface.lua',
            ],
            'documentation/Interact_Menu_API.md':[
                'md/Interact_Menu_API.xml',
            ],
            'documentation/Chat_Window_API.md':[
                'md/Chat_Window_API.xml',
            ],
            'documentation/Userdata_API.md':[
                'md/Userdata.xml',
            ],
        },
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_quiet_target_range_clicks',
        steam = True,
        ),
    
    # Discontinued since fog perf improved in x4 4.0.
    #Release_Spec(
    #    root_path = project_dir / 'extensions/sn_reduce_fog',
    #    steam = True,
    #    ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_remove_blinking_lights',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_remove_dirty_glass',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_remove_dock_glow',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_remove_dock_symbol',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_remove_highway_blobs',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_script_profiler',
        steam = False,
        pack = False,
        skip_subfolders = True,
        # Control what is included; just want the base files, not those
        # generated.
        files = [
            #'content.xml',
            #'readme.md',
            'config_defaults.ini',
            'Modfy_Exe.py',
            'Modify_Scripts.py',
            'lua/Script_Profiler.lua',
            'md/SN_Script_Profiler.xml',
            'python/Script_Profiler.py',
        ],
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_start_with_seta',
        steam = True,
        ),
    
    Release_Spec(
        root_path = project_dir / 'extensions/sn_station_kill_helper',
        steam = True,
        ),
    
    ]
