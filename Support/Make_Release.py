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
from collections import defaultdict

import Make_Documentation

project_dir = Path(__file__).resolve().parents[1]

# Import the pipe server for its exe maker.
sys.path.append(str(project_dir))
from X4_Python_Pipe_Server import Make_Executable

# Grab the project specifications.
from Release_Specs import release_specs

# TODO: joint release that includes everything, maybe.


def Make(*args):
    # Set up command line arguments.
    argparser = argparse.ArgumentParser(
        description='Generate zip files for releases.',
        )
    
    argparser.add_argument(
        '-refresh', 
        action='store_true',
        help = 'Automatically call Make_Documentation and Make_Executable.')
    
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



if __name__ == '__main__':
    Make(*sys.argv[1:])
