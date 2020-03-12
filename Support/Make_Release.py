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

# Grab the project specifications.
from Project_Specs import project_spec_table

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
    lua_loader_path = project_spec_table['Lua_Loader_API']['root_path'] / 'lua_loader_api'

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
    
    for project_name, spec in project_spec_table.items():
        # Look up the version number, and put it into the name.
        version = Version.Get_Version(spec['doc_path'])
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
