
import argparse
import sys
import os
import shutil
from pathlib import Path # TODO: complete switchover to pathlib.

# Conditional import of pyinstaller, checking if it is available.
try:
    import PyInstaller
    pyinstaller_found = True
except Exception:
    pyinstaller_found = False

import subprocess

This_dir = Path(__file__).parent

def Clear_Dir(dir_path):
    '''
    Clears contents of the given directory.
    '''
    # Note: rmtree is pretty flaky, so put it in a loop to keep
    # trying the removal.
    if os.path.exists(dir_path):
        for _ in range(10):
            try:
                shutil.rmtree(dir_path)
            except Exception:
                continue
            break
    return


def Make(*args):
    # Set up command line arguments.
    argparser = argparse.ArgumentParser(
        description='Generate an executable from the X4 Customizer source'
                    ' python code, using pyinstaller.',
        )
    
    argparser.add_argument(
        '-preclean', 
        action='store_true',
        help = 'Force pyinstaller to do a fresh compile, ignoring any'
               ' work from a prior build.')
    
    argparser.add_argument(
        '-postclean', 
        action='store_true',
        help = 'Delete the pyinstaller work folder when done, though this'
               ' will slow down rebuilds.')
    
    argparser.add_argument(
        '-onedir', 
        action='store_true',
        help =  'Puts files separated into a folder, mainly to aid in debug,'
                ' though also skips needing to unpack into a temp folder.')
    
    # Run the parser on the input args.
    args, remainder = argparser.parse_known_args(args)

    if not pyinstaller_found:
        raise RuntimeError('PyInstaller not found')
    
    # Set the output folder names.
    # Note: changing the pyinstaller build and dist folder names is
    #  possible, but not through the spec file (at least not easily),
    #  so do it through the command line call.
    build_folder = (This_dir / '..' / 'build').resolve()

    # Pick the final location to place the exe and support files.
    dist_folder = (This_dir / '..' / 'bin').resolve()
        
    # Note: it would be nice to put the spec file in a subfolder, but
    #  pyinstaller messes up (seems to change its directory to wherever
    #  the spec file is) and can't find the source python, so the spec
    #  file needs to be kept in the main dir and cleaned up at the end.
    spec_file_path = This_dir / 'X4_Python_Pipe_Server.spec'
    # Hook file probably works like the spec file.
    #hook_file_path = This_dir / 'pyinstaller_hook.py'

    # Change the working directory to here.
    # May not be necessary, but pyinstaller not tested for running
    #  from other directories, and this just makes things easier
    #  in general.
    original_cwd = os.getcwd()
    os.chdir(This_dir)
    
    # Set program name.
    program_name = 'X4_Python_Pipe_Server'

    # Delete the existing dist directory; pyinstaller has trouble with
    #  this for some reason (maybe using os.remove, which also seemed
    #  to have the same permission error pyinstaller gets).
    if dist_folder.exists():
        Clear_Dir(dist_folder)

    # Check the change_log for the latest version (last * line).
    version = ''
    for line in reversed(open(This_dir / 'change_log.md', 'r').readlines()):
        if line.strip().startswith('*'):
            version = line.replace('*','').strip()
            break

    # Somewhat clumsy, but edit the Main.py file to change its internal
    # version global.
    main_text = (This_dir / 'Main.py').read_text()
    for line in main_text.splitlines():
        # Find the version (should be only) version line.
        if line.startswith('version ='):
            # Only replace it if it changed.
            new_line = f"version = '{version}'"
            if line != new_line:
                main_text = main_text.replace(line, new_line)
                (This_dir / 'Main.py').write_text(main_text)
            break

        
    # Generate lines for a hook file.
    # Not currently used.
    #hook_lines = []

    # Prepare the specification file expected by pyinstaller.
    spec_lines = []

    # Note: most places where paths may be used should be set as
    #  raw strings, so the os.path forward slashes will get treated
    #  as escapes when python parses them again otherwise.

    # Analysis block specifies details of the source files to process.
    spec_lines += [
        'a = Analysis(',
        '    [',
        # Files to include.
        # It seems like only the main file is needed, everything
        #  else getting recognized correctly.
        '        "Main.py",',
        '    ],',

        # Relative path to work in; just use here.
        '    pathex = [r"{}"],'.format(str(This_dir)),
        # Misc external binaries; unnecessary.
        '    binaries = [],',
        # Misc data files. While the source/patches folders could be
        #  included, it makes more sense to somehow launch the generated
        #  exe from the expected location so those folders are
        #  seen as normal.
        '    datas = [],',

        # Misc imports pyinstaller didn't see.
        # This should include everything expected by extension specific
        # py modules that will be loaded at runtime.
        '    hiddenimports = [',
            # Note: most recent pynput (as of march 2021) doesnt appear to
            # work, giving import error when a launched module tries to import
            # it. Use older pynput, 1.6.8.
            # https://stackoverflow.com/questions/63681770/getting-error-when-using-pynput-with-pyinstaller
            '        r"pynput",',
            '        r"time",',
            '        r"configparser",',
            '        r"win32gui",',
            '        r"win32file",',
        '    ],',

        '    hookspath = [],',
        # Extra python files to run when the exe starts up. Unused.
        #'    runtime_hooks = [',
        #'        r"{}",'.format(str(hook_file_path)),
        #'    ],',

        # Any excluded files. None for now.
        '    excludes = [',
        '    ],',

        '    win_no_prefer_redirects = False,',
        '    win_private_assemblies = False,',
        '    cipher = None,',
        '    noarchive = False,',
        ')',
        '',
        ]
    
    spec_lines += [
        'pyz = PYZ(a.pure, a.zipped_data,',
        '     cipher = None,',
        ')',
        '',
    ]
    
    # Exe packing is different between one-dir and one-file.
    if not args.onedir:
        spec_lines += [
            'exe = EXE(pyz,',
            '    a.scripts,',
            '    a.binaries,',
            '    a.zipfiles,',
            '    a.datas,',
            '    [],',
            '    name = "{}",'.format(program_name),
            '    debug = False,',
            '    bootloader_ignore_signals = False,',
            '    strip = False,',
            '    upx = True,',
            '    runtime_tmpdir = None,',
            # Set to a console mode compile.
            '    console = True,',
            '    windowed = False,',
            ')',
            '',
        ]
        # No Collect block for onefile mode.
        
    else:
        spec_lines += [
            'exe = EXE(pyz,',
            '    a.scripts,',
            '    exclude_binaries = True,',
            '    name = "{}",'.format(program_name),
            '    debug = False,',
            '    strip = False,',
            '    upx = True,',
            # Set to a console mode compile.
            '    console = True,',
            '    windowed = False,',
            ')',
            '',
        ]

        # Says how to collect files into the one-dir.
        spec_lines += [
            'coll = COLLECT(exe,',
            '    a.binaries,',
            '    a.zipfiles,',
            '    a.datas,',
            '    strip = False,',
            '    upx = True,',
            '    name = "{}",'.format(program_name),
            ')',
            '',
        ]
    
    
    # Write the spec and hook files to the build folder, creating it
    #  if needed.
    if not build_folder.exists():
        build_folder.mkdir()
        
    with open(spec_file_path, 'w') as file:
        file.write('\n'.join(spec_lines))
    #with open(hook_file_path, 'w') as file:
    #    file.write('\n'.join(hook_lines))


    # Run pyinstaller.
    # This can call "pyinstaller" directly, assuming it is registered
    #  on the command line, but it may be more robust to run python
    #  and target the PyInstaller package.
    # By going through python, it is also possible to set optimization
    #  mode that will be applied to the compiled code.
    # TODO: add optimization flag.
    pyinstaller_call_args = [
        'python', 
        '-m', 'PyInstaller', 
        str(spec_file_path),
        '--distpath', str(dist_folder),
        '--workpath', str(build_folder),
        ]

    # Set a clean flag if requested, making pyinstaller do a fresh
    #  run. Alternatively, could just delete the work folder.
    # Update: pyinstaller cannot deal with nested folders (needs to be
    #  called once for each folder, so deletion should probably be done
    #  manually here.
    if args.preclean:
        #pyinstaller_call_args.append('--clean')
        if build_folder.exists():
            Clear_Dir(build_folder)

    # Run pyinstaller.
    subprocess.run(pyinstaller_call_args)


    # Check if the exe was created.
    # This is an extra folder deep in onedir mode.
    exe_path = dist_folder / (program_name if args.onedir else '') / (program_name + '.exe')
    if not exe_path.exists():
        # It wasn't found; quit early.
        print('Executable not created.')
        return

    # When setting to onedir, the files are buried an extra folder down.
    # This will bring them up, just to remove a level of nesting.
    if args.onedir:
        # Traverse the folder with the files; this was collected under
        #  another folder with the name of the program.
        path_to_exe_files = dist_folder / program_name
        for path in path_to_exe_files.iterdir():

            # Move the file up one level, and down to the support folder.
            # Note: after some digging, it appears shutil deals with folders
            #  by passing to 'copytree', which doesn't work well if the
            #  dest already has a folder of the same name (apparently
            #  copying over to underneath that folder, eg. copying /PyQt
            #  to someplace with /PyQt will end up copying to /PyQt/PyQt).
            # Only do this move if the destination doesn't already have
            #  a copy of the file/dir.
            dest_path = dist_folder / path.name
            if not dest_path.exists():
                shutil.move(path, dest_path)
            
        # Clean out the now empty folder in the dist directory.
        Clear_Dir(path_to_exe_files)


    # Clean up the spec and hook files.
    spec_file_path.unlink()
    #hook_file_path.unlink()
    

    # Delete the pyinstaller work folder, if requested.
    if args.postclean:
        # Note: rmtree is pretty flaky, so put it in a loop to keep
        # trying the removal.
        if build_folder.exists():
            Clear_Dir(build_folder)

    
    # Restory any original workind directory, in case this function
    #  was called from somewhere else.
    os.chdir(original_cwd)
    return


if __name__ == '__main__':
    # Feed all args except the first (which is the file name).
    Make(*sys.argv[1:])
