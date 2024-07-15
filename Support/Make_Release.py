'''
Support code for preparing release zip files.
'''

from pathlib import Path
import os
import re
import sys
import shutil
import zipfile
import argparse
import json
import subprocess
from collections import defaultdict

import Make_Documentation

project_dir = Path(__file__).resolve().parents[1]

# Import the pipe server for its exe maker.
sys.path.append(str(project_dir))
from X4_Python_Pipe_Server import Make_Executable

# Grab the project specifications.
from Release_Specs import release_specs

x_tools_path = Path(r"D:\Games\Steam\SteamApps\common\X Tools\WorkshopTool.exe")


def Make(*args):
    # Set up command line arguments.
    argparser = argparse.ArgumentParser(
        description='Generate zip files for releases.',
        )
    
    argparser.add_argument(
        '-refresh', 
        action='store_true',
        help = 'Automatically call Make_Documentation and Make_Executable.')
    
    argparser.add_argument(
        '-steam', 
        action='store_true',
        help = 'Update the versions of steam-enabled extensions on steam.')
    
    argparser.add_argument(
        '-force', 
        action='store_true',
        help = 'Forces steam update even if version did not change.')

    #argparser.add_argument(
    #    '-catdat', 
    #    action='store_true',
    #    help = 'Remake cat/dat files (triggers datestamp update even if files unchanged).')
    

    # Run the parser on the input args.
    # Split off the remainder, mostly to make it easy to run this
    # in VS when its default args are still set for Main.
    args, remainder = argparser.parse_known_args(args)


    # Update the documentation and binary and patches.
    if args.refresh:
        print('Refreshing documentation.')
        Make_Documentation.Make()
        # TODO: only do this when the version of the pipe server changes.
        # (Though it is pretty quick since pyinstaller checks for changes
        #  as well.)
        print('Refreshing executable.')
        Make_Executable.Make()
        

    # Make the release folder, if needed.
    # Put these all in the same folder, to make it easier to upload
    # to github/wherever when needed.
    release_dir = project_dir / 'Release'
    if not release_dir.exists():
        release_dir.mkdir()
    
    for spec in release_specs:

        # Look up the version number, and put it into the name.
        version = spec.Get_Version()
        # Put zips in a release folder.
        zip_path = release_dir / ('{}_v{}.zip'.format(spec.name, version))

        # Add all files to the zip.
        Make_Zip(release_dir, zip_path, spec)
        
    if args.steam:
        Upload_To_Steam(release_specs, release_dir, force = args.force)

    return


def Make_Zip(release_dir, zip_path, spec):
    '''
    Make a single zip file out of the selected paths.
    '''
    # Loaded binary for all files to put in the zip.
    path_binaries = spec.Get_File_Binaries()

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
    for path, binary in path_binaries.items():

        # Use writestr, which also works with bytes.
        zip_file.writestr(
            # Give a in-zip path.
            zinfo_or_arcname = str(path),
            data = binary,
            )

    # Close the zip; this needs to be explicit, according to the
    #  documenation.
    zip_file.close()

    # Also write a version of these files to loose folders for each
    # extension, in preparation for steam upload using egosoft's tools.
    if spec.is_extension:

        # Clear old files (may have been renamed/etc.)
        # Note: shutil rmtree is slow/async and cause random permission
        # errors in following file gen. As a workaround, rename the folder
        # first (fast) and delete that.
        folder = release_dir / spec.name
        if folder.exists():
            delete_path = folder.parent / (folder.stem + '_deleting')
            folder.rename(delete_path)
            shutil.rmtree(str(delete_path))

        for rel_path, binary in path_binaries.items():

            # Make the real path, releases folder alongside the zip.
            path = release_dir / rel_path
            # May need to create the folder.
            path.parent.mkdir(parents = True, exist_ok = True)
            path.write_bytes(binary)

    # TODO:
    # Automatically call the X tools to upload to steam, if the files haven't
    # changed since a prior version (detect this somehow, or maybe just
    # always upload).

    print('Release written to {}'.format(zip_path))

    return


def Upload_To_Steam(release_specs, release_dir, force = False):
    '''
    Update the steam copy of this release, if the version has changed
    since the last update.
    '''
    '''
    To regulate how often steam updates (to avoid spamming its update log):
    - Save versions to a json (keep in repo)
    - Update json when steam is updated
    - On new extension, check if flagged for steam upload; if so, add
      a dummy preview pic and publish to steam.
    '''
    json_path = Path(__file__).resolve().parent / 'steam_versions.json'

    # Load the prior updated versions.
    steam_versions = defaultdict(int)
    if json_path.exists():
        with open(json_path, 'r') as file:
            steam_versions.update(json.load(file))

    # Work through the specs.
    for spec in release_specs:
        if not spec.is_extension or not spec.steam:
            continue

        # If this does not have a workshop id, then it is not yet on
        # steam.  TODO: support such cases.

        # Compare versions.
        this_version = spec.Get_Version()
        prior_version = steam_versions[spec.name]
        if prior_version != this_version or force:

            # Do the update (or publish).
            folder = release_dir / spec.name

            # Check if this already has a steam id; if not, treat as
            # unpublished.
            try:
                if spec.extension_id.startswith('ws_'):
                    Steam_Update(spec, folder)
                else:
                    assert prior_version == 0
                    Steam_Publish(spec, folder)

                # Update the version number.
                steam_versions[spec.name] = this_version
            except Exception as ex:
                print('Skipping steam update of {} due to exception: {}'.format(
                    spec.name, ex))
            
    # Store the new versions.
    with open(json_path, 'w') as file:
        json.dump( steam_versions, file, indent=2)
    return

def Steam_Update(spec, folder):
    'Update this mod on steam.'
    subprocess.run(
        [str(x_tools_path),
            'update',
            '-path',
            '{}'.format(folder),
            '-batchmode',
            '-minor',
            '-changenote',
            spec.change_log_notes,
            ], check = True)
    return


def Steam_Publish(spec, folder):
    '''
    Publish this mod on steam.
    Assumes a preview.png image is available in the source extension folder.
    '''
    # There should be a preview image to use.
    # (Let this raise an exception if not.)
    preview_path = spec.files['preview'][0]

    print('\nPublishing to steam; this may take a moment to update...\n')
    try:
        result = subprocess.run(
            [str(x_tools_path),
                'publishx4',
                '-path',
                '{}'.format(folder),
                '-preview',
                '{}'.format(preview_path),
                '-batchmode',
                ], 
                # Capture the output for use below, though this means no
                # runtime printout.
                capture_output = True,
                check = True)
    except Exception as ex:
        print(ex.stdout.decode())
        print(ex.stderr.decode())
        raise ex
    
    stdout = result.stdout.decode()
    print(stdout)
    print(result.stderr.decode())

    # Get the assigned content id and update the extension.
    new_ext_id = ''
    for line in stdout.splitlines():
        if 'ID: ' in line:
            split_line = line.split('ID: ')
            id_str = split_line[1].strip()
            new_ext_id = 'ws_' + id_str
            break
    if new_ext_id:
        spec.Set_Extension_ID(new_ext_id)
    else:
        print('Failed to set new content.xml extension id; update manually.')

    return


if __name__ == '__main__':
    Make(*sys.argv[1:])
