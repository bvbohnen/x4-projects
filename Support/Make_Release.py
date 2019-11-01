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
import Version
import Make_Documentation

project_dir = Path(__file__).resolve().parents[1]

# Set up an import from the customizer for some text processing.
x4_customizer_dir = project_dir.parent / 'X4_Customizer'
sys.path.append(str(x4_customizer_dir))
import Framework as X4_Customizer

# Dict matching each release zip with the files it includes.
# Note: root_dir is where other paths are taken relative to, and also the
#  base dir for the zip file (eg. relative paths are what will be seen
#  when zipped).
# TODO: cat/dat packing of lua_loader_api (run the bat, or rewrite).
# TODO: maybe go back to globbing, but this is safer against unwanted
# files.
release_files_specs = {
    'Named_Pipes_API':{ 
        'root_path': project_dir / 'X4_Named_Pipes_API' / 'X4_Files',
        'doc_path' : '..',
        'files':[
            '../Readme.md',
            'ui/core/lualibs/winpipe_64.dll',
            'extensions/named_pipes_api/content.xml',
            'extensions/named_pipes_api/Named_Pipes.lua',
            'extensions/named_pipes_api/md/Named_Pipes.xml',
            'extensions/named_pipes_api/md/Pipe_Server_Host.xml',
            'extensions/named_pipes_api/md/Pipe_Server_Lib.xml',
        ]},
    'X4_Python_Pipe_Server':{ 
        'root_path':project_dir / 'X4_Named_Pipes_API', 
        'doc_path' : 'X4_Python_Pipe_Server',
        'files':[
            'X4_Python_Pipe_Server/__init__.py',
            'X4_Python_Pipe_Server/Main.py',
            'X4_Python_Pipe_Server/Classes/__init__.py',
            'X4_Python_Pipe_Server/Classes/Pipe.py',
            'X4_Python_Pipe_Server/Classes/Server_Thread.py',
        ]},
    'Key_Capture_API':{ 
        'root_path':project_dir / 'X4_Key_Capture_API', 
        'doc_path' : '',
        'files':[
            'Readme.md',
            'key_capture_api/content.xml',
            'key_capture_api/Send_Keys.py',
            'key_capture_api/md/Key_Capture.xml',
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
    'Time_API':{ 
        'root_path':project_dir / 'X4_Time_API', 
        'doc_path' : '',
        'files':[
            'Readme.md',
            'time_api/content.xml',
            'time_api/md/Time_API.xml',
            'time_api/Time_API.lua',
        ]},
    }

def Run():

    # Update documentation.
    Make_Documentation.Run()

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

    # Add all files to the zip, with an extra nesting folder to
    # that the files don't sprawl out when unpacked.
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
    Run()
