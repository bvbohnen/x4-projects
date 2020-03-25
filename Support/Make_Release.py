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

import Version
import Make_Documentation

project_dir = Path(__file__).resolve().parents[1]

# Set up an import from the customizer for some text processing.
x4_customizer_dir = project_dir.parent / 'X4_Customizer'
sys.path.append(str(x4_customizer_dir))
import Framework as X4_Customizer

# Import the pipe server for its exe maker.
sys.path.append(str(project_dir))
from X4_Python_Pipe_Server import Make_Executable

# Grab the project specifications.
from Project_Specs import *

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


    # TODO: consider cat packing the extension files, using x4 customizer.
    # If done, the below code for the lua loader api can be generalized
    # to the generic packer.
    # TODO: maybe steam workshop stuff.

    #if args.catdat:
    #    # Pack up the subst cat/dat for the lua_loader_api.
    #    # This relies on x4 customizer, assumed to be in the same
    #    # parent directory as this git repo.
    #    lua_loader_path = project_spec_table['Lua_Loader_API']['root_path'] / 'lua_loader_api'
    #
    #    # Make a copy of the lua to xpl.
    #    shutil.copy(lua_loader_path / 'ui/addons/ego_debug/Lua_Loader.lua',
    #                lua_loader_path / 'ui/addons/ego_debug/Lua_Loader.xpl')
    #
    #    # This uses the argparse interface, so args need to be strings.
    #    X4_Customizer.Main.Run(
    #                '-nogui', 'Cat_Pack', '-argpass', 
    #                # Source dir.
    #                str(lua_loader_path), 
    #                # Dest file.
    #                str(lua_loader_path / 'subst_01.cat'), 
    #                # Want the ui.xml and the xpl version of the lua.
    #                '-include', 'ui/*.xml', 'ui/*.xpl')
    

    # Make the release folder, if needed.
    # Put these all in the same folder, to make it easier to upload
    # to github/wherever when needed.
    release_dir = project_dir / 'Release'
    if not release_dir.exists():
        release_dir.mkdir()
    
    # Gather some lua path string replacements from all projects.
    string_replacement_dict = Get_Lua_Path_Replacements(project_spec_table)

    for project_name, spec in project_spec_table.items():
        # Look up the version number, and put it into the name.
        version = Version.Get_Version(Get_Changelog_Path(spec))
        # Put zips in a release folder.
        zip_path = release_dir / ('{}_v{}.zip'.format(project_name, version))

        # Add all files to the zip.
        Make_Zip(zip_path, spec, string_replacement_dict)

    return

def Get_Lua_Path_Replacements(project_spec_table):
    '''
    Returns a dict of old_path:new_path pairings, for lua files that will
    be moved and renamed to the extension content.xml folder.
    This is gathered across all projects prior to project packing, so that
    cross-project references can be updated correctly.
    '''
    string_replacement_dict = {}
    for project_name, spec in project_spec_table.items():
        if spec['root_path'].stem != 'extensions':
            continue
        
        root_path  = spec['root_path']
        content_path = root_path / spec['doc_path']

        for path in spec['lua_files']:

            # Set up the adjusted path.
            new_path = content_path / (path.stem + '{}.txt'.format(path.suffix.replace('.','_')))

            # Get the original in-text string.
            if path.suffix == '.lua':
                # Goal is to replace "extensions.sn_simple_menu_api.lua.Custom_Options"
                # with "extensions.sn_simple_menu_api.Custom_Options", or similar.
                old_string = Path_To_Lua_Require_Path(path, root_path)
                new_string = Path_To_Lua_Require_Path(new_path, root_path)
                string_replacement_dict[old_string] = new_string

            # The dll is special, looking like:
            # ".\\extensions\\sn_named_pipes_api\\lualibs\\winpipe_64.dll"
            # This will also become a _dll.txt file, but needs different
            # string replacement.
            if path.suffix == '.dll':
                old_string = Path_To_Lua_Loadlib_Path(path, root_path)
                new_string = Path_To_Lua_Loadlib_Path(new_path, root_path)
                string_replacement_dict[old_string] = new_string

    return string_replacement_dict


def Make_Zip(zip_path, spec, string_replacement_dict):
    '''
    Make a single zip file out of the selected paths.
    '''
    root_path  = spec['root_path']

    # Loaded binary for all files to put in the zip.
    path_binaries = {}

    # All extensions are in the ext folder.
    is_extension = spec['root_path'].stem == 'extensions'

    # Non-extensions just copy over their listed files.
    if not is_extension:
        for path in spec['files']:
            path_binaries[path] = path.read_bytes()

    # Extensions go through more effort.
    if is_extension:
        content_path = root_path / spec['doc_path']

        # Gather paths to all files under the main extension dir.
        # This assumes there is not excess clutter in subfolders; clutter
        # in the main folder is fine.
        # TODO; for now just have files listed explicitly in file_paths.

        '''
        Pack all of the game files into a cat/dat pairs.
        Some files may need to go into a subst folder (eg. lua loader), and
        will need to be clarified as such in some way.
        Normal lua files cannot be packed. They may be left alone for general
        release, though on steam they will need to be renamed .txt and moved
        to the main folder. Further, all references to them will need to
        be edited accordingly (include cross-extension references).
        '''
        # Gather all lua files to be moved/renamed.
        lua_path_newpath_dict = {}
        for path in spec['lua_files']:
            # Set up the adjusted path.
            new_path = content_path / (path.stem + '{}.txt'.format(path.suffix.replace('.','_')))
            lua_path_newpath_dict[path] = new_path
                                           
    
        # Load all md xml and lua file texts, and adjust paths.
        file_text_dict = {}
        for path in spec['lua_files'] + spec['ext_files']:
            if path.suffix == '.lua' or (path.suffix == '.xml' and path.parent.stem == 'md'):
                # better_target_monitor gets some gibberish it just doing
                # a plain read_text, so clarify encoding. Apparently this
                # relates to ufeff (zero-width byte order mark, that came
                # from somewhere, related to utf-8 files). Also, the infinity
                # symbol needs the extra help.
                text = path.read_text(encoding = 'utf-8')
                if path.name == 'Target_Monitor.lua':
                    bla = 0
                for old_string, new_string in string_replacement_dict.items():
                    text = text.replace(old_string, new_string)
                file_text_dict[path] = text


        # Collect lists of files to be put into the ext_01 and subst_01.
        ext_game_files   = []
        subst_game_files = []

        for path in spec['ext_files']:
            # Set the catalog virtual path.
            virtual_path = Path_To_Cat_Path(path, content_path)

            # If test is already loaded, set up a text Misc_File, else binary.
            if path in file_text_dict:
                game_file = X4_Customizer.File_Manager.Misc_File(
                    virtual_path = virtual_path,
                    text = file_text_dict[path])
            else:
                game_file = X4_Customizer.File_Manager.Misc_File(
                    virtual_path = virtual_path,
                    binary = path.read_bytes())
            ext_game_files.append(game_file)


        # Subst files are in a separate list.
        for path in spec['subst_files']:
            virtual_path = Path_To_Cat_Path(path, content_path)

            # These will always record as binary.
            game_file = X4_Customizer.File_Manager.Misc_File(
                virtual_path = virtual_path,
                binary = path.read_bytes())
            subst_game_files.append(game_file)

            # If this is a lua file, also create an xpl copy.
            if path.suffix == '.lua':
                game_file = X4_Customizer.File_Manager.Misc_File(
                    virtual_path = virtual_path.replace('.lua','.xpl'),
                    binary = path.read_bytes())
                subst_game_files.append(game_file)


        # Collect files for cat/dat packing.
        cat_dat_paths = []
        for game_files, cat_name in [(ext_game_files  , 'ext_01.cat'),
                                     (subst_game_files, 'subst_01.cat')]:
            # Skip if there are no files to pack.
            if not game_files:
                continue

            # Set up the writer for this cat.
            # It will be created in the content.xml folder.
            # TODO: redirect to some other folder, maybe.
            cat = X4_Customizer.File_Manager.Cat_Writer.Cat_Writer(
                        cat_path = content_path / cat_name)
            # Add the files.
            for file in game_files:
                cat.Add_File(file)
            # Write it.
            cat.Write()
            # Record paths.
            cat_dat_paths.append(cat.cat_path)
            cat_dat_paths.append(cat.dat_path)


        # Finally, start gathering the actual files to include in
        # the zip, as binary data.
        # Generic files copy over directly.
        for path in spec['files']:
            path_binaries[path] = path.read_bytes()

        # Lua files copy over from their edited text, using their new path.
        for old_path, new_path in lua_path_newpath_dict.items():
            if old_path in file_text_dict:
                # Stick to utf-8 for now.
                path_binaries[new_path] = file_text_dict[old_path].encode('utf-8')
            else:
                # Otherwise this should be the dll file.
                path_binaries[new_path] = old_path.read_bytes()

        # Include the new cat/dat files.
        for path in cat_dat_paths:
            path_binaries[path] = path.read_bytes()
            
        # Delete cat/dat files, except subst, so that the local extensions
        # continue to use loose files.
        # TODO: maybe a way to get raw binary from the cat_writer, instead
        # of it having to write the file first.
        for path in cat_dat_paths:
            if 'subst' not in path.name:
                path.unlink()

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

        # Use writestr, which also works with bytes.
        zip_file.writestr(
            # Give a full path.
            #path,
            # Give a in-zip path.
            zinfo_or_arcname = arcname,
            data = binary,
            )

    # Close the zip; this needs to be explicit, according to the
    #  documenation.
    zip_file.close()

    # TODO: unpack the zip file, and run the X Tools option for updating steam.

    print('Release written to {}'.format(zip_path))

    return


def Categorize_Ext_Files(spec):
    '''
    Search the extension's folder for files, and put them into categories.
    TODO: as an alternative to manual listing.
    '''


def Path_To_Cat_Path(path, content_path):
    '''
    Convert a pathlib.Path into the virtual_path used in catalog files,
    eg. forward slash separated, relative to the content.xml folder.
    '''
    rel_path = Path(os.path.relpath(path, content_path))
    # Format should match the as_posix() form.
    return rel_path.as_posix()


def Path_To_Lua_Require_Path(path, root_path):
    '''
    Convert a pathlib.Path into the internal format used in lua "require",
    eg. dot separated with no suffix, relative to the extensions folder.
    '''
    # Get the relative path to the root_path.
    rel_path = Path(os.path.relpath(path, root_path))
    # Break into pieces: directory, then name; don't want extension.
    # Replace slashes with dots; do this as_posix for consistency.
    dir_path = rel_path.parent.as_posix().replace('/','.')
    name = rel_path.stem
    return dir_path + '.' + name


def Path_To_Lua_Loadlib_Path(path, root_path):
    '''
    Convert a pathlib.Path into the internal format used in lua "loadlib",
    eg. double backslash separated, with suffix.
    '''
    # Get the relative path to the root_path.
    rel_path = Path(os.path.relpath(path, root_path))
    # Break into pieces: directory, then name.
    # Replace slashes with \\; do this as_posix for consistency.
    dir_path = rel_path.parent.as_posix().replace('/','\\\\')
    return dir_path + '\\\\' + rel_path.name


if __name__ == '__main__':
    Make(*sys.argv[1:])
