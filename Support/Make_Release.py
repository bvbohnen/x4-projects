'''
Pack the extension and winpipe_64.dll into a zip folder for release,
suitable for unpacking to the X4 directory.

TODO
'''

from pathlib import Path
import os
import re
import sys
import shutil
import zipfile
import argparse

import Version
import Make_Documentation

project_dir = Path(__file__).resolve().parents[1]

# Set up an import from the customizer for some text processing.
x4_customizer_dir = project_dir.parent / 'X4_Customizer'
sys.path.append(str(x4_customizer_dir))
import Framework as X4_Customizer

# Import the pipe server for its exe maker.
sys.path.append(str(project_dir / 'X4_Named_Pipes_API'))
from X4_Python_Pipe_Server import Make_Executable

# Dict matching each release zip with the files it includes.
# Note: root_dir is where other paths are taken relative to, and also the
#  base dir for the zip file (eg. relative paths are what will be seen
#  when zipped).
# TODO: cat/dat packing of lua_loader_api (run the bat, or rewrite).
# TODO: maybe go back to globbing, but this is safer against unwanted
# files.
release_files_specs = {
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
        'root_path':project_dir / 'X4_Simple_Menu_API', 
        'doc_path' :project_dir / 'X4_Simple_Menu_API' / 'better_target_monitor',
        'files':[
            'better_target_monitor/content.xml',
            'better_target_monitor/md/Better_Target_Monitor.xml',
            'better_target_monitor/lua/Target_Monitor.lua',
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

# TODO: package up pipe server binary into a separate exe for users
# without python.
# TODO: join release that includes everything.

def Make(*args):
    # Set up command line arguments.
    argparser = argparse.ArgumentParser(
        description='Generate zip files for releases.',
        )
    
    argparser.add_argument(
        '-refresh', 
        action='store_true',
        help = 'Automatically call Make_Documentation and Make_Executable.')
    

    # Run the parser on the input args.
    # Split off the remainder, mostly to make it easy to run this
    # in VS when its default args are still set for Main.
    args, remainder = argparser.parse_known_args(args)


    # Update the documentation and binary and patches.
    if args.refresh:
        print('Refreshing documentation.')
        Make_Documentation.Make()
        print('Refreshing executable.')
        Make_Executable.Make()


    # TODO: consider cat packing the extension files, using x4 customizer.


    # Pack up the subst cat/dat for the lua_loader_api.
    # This relies on x4 customizer, assumed to be in the same
    # parent directory as this git repo.
    lua_loader_path = release_files_specs['Lua_Loader_API']['root_path'] / 'lua_loader_api'

    # Make a copy of the lua to xpl.
    shutil.copy(lua_loader_path / 'ui/addons/ego_debug/Lua_Loader.lua',
                lua_loader_path / 'ui/addons/ego_debug/Lua_Loader.xpl')

    # This uses the argparse interface, so args need to be strings.
    X4_Customizer.Main.Run(
                '-nogui', 'Cat_Pack', '-argpass', 
                # Source dir.
                str(lua_loader_path), 
                # Dest file.
                str(lua_loader_path / 'subst_01.cat'), 
                # Want the ui.xml and the xpl version of the lua.
                '-include', 'ui/*.xml', 'ui/*.xpl')
    

    # Make the release folder, if needed.
    # Put these all in the same folder, to make it easier to upload
    # to github/wherever when needed.
    release_dir = project_dir / 'Release'
    if not release_dir.exists():
        release_dir.mkdir()
    
    for project_name, spec in release_files_specs.items():
        # Prefix all file paths with their root_path.
        file_paths = [(spec['root_path'] / x).resolve() for x in spec['files']]

        # Look up the version number, and put it into the name.
        version = Version.Get_Version(spec['root_path'] / spec['doc_path'])
        # Put zips in a release folder.
        zip_path = release_dir / ('{}_v{}.zip'.format(project_name, version))

        # Add all files to the zip.
        Make_Zip(zip_path, spec['root_path'], file_paths)

    return


def Make_Zip(zip_path, root_path, file_paths):
    '''
    Make a single zip file out of the selected paths.
    '''

    # Optionally open it with compression.
    if False:
        zip_file = zipfile.ZipFile(zip_path, 'w')
    else:
        zip_file = zipfile.ZipFile(
            zip_path, 'w',
            # Can try out different zip algorithms, though from a really
            # brief search it seems lzma is the newest and strongest.
            # Result: seems to work well, dropping the ~90M qt version
            # down to ~25M.
            # Note: LZMA is the 7-zip format, not native to windows.
            #compression = zipfile.ZIP_LZMA,
            # Deflate is the most commonly supported format.
            # With max compression, this is ~36M, so still kinda okay.
            compression = zipfile.ZIP_DEFLATED,
            # Compression level only matters for bzip2 and deflated.
            compresslevel = 9 # 9 is max for deflated
            )

    # Add all files to the zip.
    for path in file_paths:
        # Give an alternate internal path and name.
        # This will be relative to the root dir.
        # Note: relpath seems to bugger up if the directories match,
        #  returning a blank instead of the file name.
        # Note: the path may be a parent of root_path; detect this and
        #  just place the file in the zip root.
        if root_path in path.parents:
            arcname = os.path.relpath(path, root_path)
        else:
            arcname = path.name
        zip_file.write(
            # Give a full path.
            path,
            # Give a in-zip path.
            arcname = arcname,
            )

    # Close the zip; this needs to be explicit, according to the
    #  documenation.
    zip_file.close()

    print('Release written to {}'.format(zip_path))

    return


if __name__ == '__main__':
    Make(*sys.argv[1:])
