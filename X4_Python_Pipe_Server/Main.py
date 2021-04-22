'''
Main entry function for the overall python based server.
This will load in individual pipe sub-servers and run their threads.

Initial version just runs a test server.
'''
'''

Note on security:
    Loading arbitrary python code can be unsafe.  As a light protection,
    the pipe server will only load modules that are part of extensions
    that have been given explicit permission to run python.

    Permissions will be held in a json file, holding the extension id
    (from content.xml) and its permission state (generally true).
    A special exception will be made for the modding api's id, so it can
    load without permission set up.
    The permission file will be generated if it doesn't already exist,
    but otherwise is left untouched to avoid overwriting user settings.

    The general idea is that, if some random extension added a python
    plugin to be loaded which may be unsafe, by default it will be rejected
    until the user of that extension gives it explicit permission.

TODO: change permissions to be folder name based instead of id based.

TODO: maybe permissions from json to ini format.

TODO: maybe use multiprocessing instead of threading.

TODO: think of a safe, scalable way to handle restarting threads,
particularly subthreads that a user server thread may have started,
which might get orphaned when that thread function exceptions out
on pipe closure.  (Currently pipe servers are responsible for
restarting their own subthreads.)

TODO: rethink server restart behavior; perhaps they should not auto-restart,
but instead be fully killed when the x4 pipe closes, and then only
restarted when x4 MD api requests the restart. In this way, mods can change
their python side code on the fly, reload their save, and the new code
would get loaded.
(The md api would need to re-announce servers whenever the game or ui reloads,
as well as whenever the server resets.)
(Perhaps this is less robust in some way?)
(Manual effort needed to clean out the imported packages, similar to what
is done in some gui code for rerunning scripts.)
Overall, it is probably reasonably easy for developers to just shut down
this host server and restart it, if they want to update their server code;
x4 side should automatically reconnect.

temp copy of test args:
-t -x "C:\Steam\steamapps\common\X4 Foundations" -m "extensions\sn_measure_perf\python\Measure_Perf.py"
'''
# Manually list the version for now, since packed exe won't have
# access to the change_log.
version = '1.4'

# Setup include path to this package.
import sys
import json
from pathlib import Path
from collections import defaultdict
import argparse
import time

# To support packages cross-referencing each other, set up this
# top level as a package, findable on the sys path.
# Extra 'frozen' stuff is to support pyinstaller generated exes.
# Note:
#  Running from python, home_path is X4_Projects (or whatever the parent
#  folder to this package is.
#  Running from exe, home_path is the folder with the exe itself.
# In either case, main_path will be to Main.py or the exe.
if getattr(sys, 'frozen', False):
    # Note: _MEIPASS gets the directory the packed exe unpacked into,
    # eg. in appdata/temp.  Need 'executable' for the original exe path.
    home_path = Path(sys.executable).parent
    main_path = home_path
else:
    home_path = Path(__file__).resolve().parents[1]
    main_path = Path(__file__).resolve().parent
if str(home_path) not in sys.path:
    sys.path.append(str(home_path))

    
#from X4_Python_Pipe_Server.Servers import Test1
#from X4_Python_Pipe_Server.Servers import Send_Keys
from X4_Python_Pipe_Server.Classes import Server_Thread
from X4_Python_Pipe_Server.Classes import Pipe_Server, Pipe_Client
from X4_Python_Pipe_Server.Classes import Client_Garbage_Collected
import win32api
import winerror
import win32file
import win32pipe
import threading
import traceback

# Note: in other projects importlib.machinery could be used directly,
# but appears to be failing when pyinstalling this package, so do
# a more directly import of machinery.
from importlib import machinery

# Flag to use during development, for extra exception throws.
developer = False

# Name of the host pipe.
pipe_name = 'x4_python_host'

# Loaded permissions from pipe_permissions.json.
permissions = None
# Permissions can be placed alongside the exe or Main.py.
# Or maybe in current working directory?
# Go with the exe/main directory.
permissions_path = main_path / 'permissions.json'


def Main():
    '''
    Launch the server. This generally does not return.
    '''
    
    # Set up command line arguments.
    argparser = argparse.ArgumentParser(
        description = ('Host pipe server for X4 interprocess communication.'
                       ' This will launch extension python modules that are'
                       ' registered by the game through the pipe api.'),
        )

    argparser.add_argument(
        '-p', '--permissions-path',
        default = None,
        help =  'Optional path to a permissions.json file specifying which'
                ' extensions are allowed to load modules. If not given, the'
                ' main server directory is used.' )
    
    argparser.add_argument(
        '-t', '--test',
        action='store_true',
        help =  'Puts this server into test mode. Requires following args:'
                ' --x4-path, --test_module' )
    
    argparser.add_argument(
        '-x', '--x4-path',
        default = None,
        metavar = 'Path',
        help =  'Path to the X4 installation folder. Only needed in test mode.')

    argparser.add_argument(
        '-m', '--module',
        default = None,
        help =  'Path to a specific python module to run in test mode,'
                ' relative to the x4-path.' )
    
    #argparser.add_argument(
    #    '-v', '--verbose',
    #    action='store_true',
    #    help =  'Print extra messages.' )
       
    args = argparser.parse_args(sys.argv[1:])

    if args.permissions_path:
        global permissions_path
        permissions_path = Path.cwd() / (Path(args.permissions_path).resolve())
        # The directory should exist.
        if not permissions_path.parent.exists():
            print('Error: permissions_path directory not found')
            return

    # Check if running in test mode.
    test_python_client = False
    if args.test:
        test_python_client = True

        if not args.x4_path:
            print('Error: x4_path required in test mode')
            return

        if not args.module:
            print('Error: module required in test mode')
            return

        # Make x4 path absolute.
        args.x4_path = Path.cwd() / (Path(args.x4_path).resolve())
        if not args.x4_path.exists():
            print('Error: x4_path invalid: {}'.format(args.x4_path))
            return
        
        # Keep module path relative.
        args.module = Path(args.module)
        module_path = args.x4_path / args.module
        if not module_path.exists():
            print('Error: module invalid: {}'.format(module_path))
            return


    # List of directly launched threads.
    threads = []
    # List of relative path strings received from x4, to python server
    # modules that have been loaded before.
    module_relpaths = []

    print('X4 Python Pipe Server v{}\n'.format(version))

    # Load permissions, if the permissions file found.
    Load_Permissions()

    # Put this into a loop, to keep rebooting the server when the
    # pipe gets disconnected (eg. x4 loaded a save).
    shutdown = False
    while not shutdown:

        # Start up the baseline control pipe, listening for particular errors.
        # TODO: maybe reuse Server_Thread somehow, though don't actually
        # want a separate thread for this.
        try:
            pipe = Pipe_Server(pipe_name)
        
            # For python testing, kick off a client thread.
            if test_python_client:
                # Set up the reader in another thread.
                reader_thread = threading.Thread(target = Pipe_Client_Test, args = (args,))
                reader_thread.start()

            # Wait for client.
            pipe.Connect()

            # Clear out any old x4 path; the game may have shut down and
            # relaunched from a different location.
            x4_path = None

            # Listen to runtime messages, announcing relative paths to
            # python modules to load from extensions.
            while 1:
                # TODO: put this loop into try/except to catch some error
                # types without needing a full reboot, eg. keyboard interrupt.
                # Blocking read.
                message = pipe.Read()
                print('Received: ' + message)

                # A ping will be sent first, testing the pipe from x4 side.
                if message == 'ping':
                    pass

                # Handle restart requests similar to pipe disconnect exceptions.
                elif message == 'restart':
                    raise Reset_Requested()
            
                elif message.startswith('package.path:'):
                    message = message.replace('package.path:','')

                    # Parse into the base x4 path.
                    # Example return:
                    # ".\?.lua;C:\Steam\steamapps\common\X4 Foundations\lua\?.lua;C:\Steam\steamapps\common\X4 Foundations\lua\?\init.lua;"
                    # Split and convert to proper Paths.
                    paths = [Path(x) for x in message.split(';')]

                    # Search for a wanted path.
                    x4_path = None
                    for path in paths:
                        # Different ways to possibly do this.
                        # This approach will iterate through parents to find the
                        # "lua" folder, then get its parent.
                        # (The folder should not be assumed to match the default
                        # x4 installation folder name, since a user may have
                        # changed it if running multiple installs.)
                        test_path = path
                        # Loop while more parents are present.
                        while test_path.parents:
                            # Check the parent.
                            test_path = test_path.parent
                            if test_path.stem == "lua":
                                x4_path = test_path.parent
                                break
                        # Stop looping once an x4_path found.
                        if x4_path:
                            break


                elif message.startswith('modules:'):
                    message = message.replace('modules:','')

                    # If no x4_path yet seen, ignore.
                    if not x4_path:
                        continue

                    # Break apart the modules. Semicolon separated, with an
                    # ending separator.
                    # This list will end with an empty entry, even if the message
                    # has no paths, so can throw away the last list item.
                    module_paths = [Path(x) for x in message.split(';')[:-1]]

                    # Handle each path.
                    for module_path in module_paths:

                        # If this module has already been processed, ignore it.
                        # This will happen when x4 reloads saves and such, and all
                        # md scripts re-announce their server files.
                        if module_path in module_relpaths:
                            print('Module was already loaded: {}'.format(module_path))
                            continue

                        # Put together the full path.         
                        full_path = x4_path / module_path

                        # Check if this module is part of an extension
                        #  that has permission to run, and skip if not.
                        if not Check_Permission(x4_path, module_path):
                            continue

                        # Record this path as seen.
                        module_relpaths.append(module_path)

                        # Import the module.
                        module = Import(full_path)

                        # Continue if the import succeeded.
                        if module != None:
                            # Pull out the main() function.
                            main = getattr(module, 'main', None)

                            # Start the thread.
                            if main != None:
                                thread = Server_Thread(module.main, test = test_python_client)
                                threads.append(thread)
                            else:
                                print('Module lacks "main()": {}'.format(module_path))


        except (win32api.error, Client_Garbage_Collected) as ex:
            # win32api.error exceptions have the fields:
            #  winerror : integer error code (eg. 109)
            #  funcname : Name of function that errored, eg. 'ReadFile'
            #  strerror : String description of error

            # If just in testing mode, assume the tests completed and
            #  shut down.
            if test_python_client:
                print('Stopping test.')
                shutdown = True

            elif isinstance(ex, Client_Garbage_Collected):
                print('Pipe client garbage collected, restarting.')
                
            # If another host was already running, there will have been
            # an error when trying to set up the pipe.
            elif ex.funcname == 'CreateNamedPipe':
                print('Pipe creation error. Is another instance already running?')
                shutdown = True
                
            # If X4 was reloaded, this results in a ERROR_BROKEN_PIPE error
            # (assuming x4 lua was wrestled into closing its pipe properly
            #  on garbage collection).
            # Update: as of x4 3.0 or so, garbage collection started crashing
            #  the game, so this error is only expected when x4 shuts down
            #  entirely.
            elif ex.winerror == winerror.ERROR_BROKEN_PIPE:
                # Keep running the server.
                print('Pipe client disconnected.')

            else:
                print(f'Unhandled win32api error: {ex.winerror} in {ex.funcname} : {ex.strerror}')
                shutdown = True
                
            # This should now loop back and restart the pipe, if
            # shutdown wasn't set.
            if not shutdown:
                print('Restarting host.')
            else:
                # Pause before closing, so user can see the error.
                input('Press <enter> to finish exiting...')
                
        except Exception as ex:
            # Any other exception, reraise for now.
            raise ex

        finally:
            # Close the pipe if open.
            # This will error if the exit condition was a CreateNamedPipe
            # error, so just wrap it for safety.
            try:
                pipe.Close()
            except Exception as ex:
                pass
            
            # Let subthreads keep running; they internally loop.
            #if threads:
            #    print('Shutting down subthreads.')
            ## Close all subthreads.
            #for thread in threads:
            #    thread.Close()
            ## Wait for closures to complete.
            #for thread in threads:
            #    thread.Join()



    #base_thread = Server_Thread(Control)

    # TODO: dynamically load in server modules from extensions.
    # Need to check which extensions are enabled/disabled, and determine
    # what the protocol will be for file naming.

    #-Removed; old test code for hardcoded server paths.
    ## Start all server threads.
    ## Just a test for now.
    #threads = [
    #    Server_Thread(Test1.main),
    #    Server_Thread(Send_Keys.main),
    #]
    ## Wait for them all to finish.
    #for thread in threads:
    #    thread.Join()


    return


def Import(full_path):
    '''
    Code for importing a module, broken out for convenience.
    '''
    
    try:
        # Attempt to load/run the module.
        module = machinery.SourceFileLoader(
            # Provide the name sys will use for this module.
            # Use the basename to get rid of any path, and prefix
            #  to ensure the name is unique (don't want to collide
            #  with other loaded modules).
            'user_module_' + full_path.name.replace(' ','_'),
            # Just grab the name; it should be found on included paths.
            str(full_path)
            ).load_module()
        print('Imported {}'.format(full_path))
                
    except Exception as ex:
        module = None

        # Make a nice message, to prevent a full stack trace being
        #  dropped on the user.
        print('Failed to import {}'.format(full_path))
        print('Exception of type "{}" encountered.\n'.format(
            type(ex).__name__))
        ex_text = str(ex)
        if ex_text:
            print(ex_text)

        # In dev mode, print the exception traceback.
        if developer:
            print(traceback.format_exc())
            # Raise it again, just in case vs can helpfully break
            # at the problem point. (This won't help with the gui up.)
            raise ex
        #else:
        #    Print('Enable developer mode for exception stack trace.')

    return module


def Load_Permissions():
    '''
    Loads the permissions json file, or creates one if needed.
    '''
    global permissions
    if permissions_path.exists():
        try:
            with open(permissions_path, 'r') as file:
                permissions = json.load(file)
            print('Loaded permissions file at {}\n'.format(permissions_path))
        except Exception as ex:
            print('Error when loading permissions file')

    # If nothing was loaded, write (or overwrite) the default permissions file.
    if permissions == None:
        permissions = {
            'instructions': 'Set which extensions are allowed to load modules,'
                            ' based on extension id (in content.xml).',
            # Workshop id of the mod support apis.
            'ws_2042901274' : True,
            }
        print('Generating default permissions file at {}\n'.format(permissions_path))
        with open(permissions_path, 'w') as file:
            json.dump(permissions, file, indent = 2)
    return


def Check_Permission(x4_path, module_path):
    '''
    Check if the module on the given path has permission to run.
    Return True if permitted, else False with a printed message.
    '''
    try:
        # Find the extension's root folder.
        if not module_path.as_posix().startswith('extensions/'):
            raise Exception('Module is not in extensions')

        # The module_path should start with 'extensions', so find the
        # second folder.
        # (Note: pathlib is dump and doesn't allow negative indices on parents.)
        ext_dir = x4_path / [x for x in module_path.parents][-3]

        # Load the content.xml. Can do xml or raw text; text should
        # be good enough for now (avoid adding lxml to the exe).
        content_text = (ext_dir / 'content.xml').read_text()

        # The first id="..." should be the extension id.
        content_id = content_text.split('id="')[1].split('"')[0]

        # Check its permission.
        if permissions.get(content_id) == True:
            return True
        print('\n'.join([
            '',
            'Rejecting module due to missing permission:',
            ' content_id: {}'.format(content_id),
            ' path: {}'.format(x4_path / module_path),
            'To allow loading, enable this content_id in {}'.format(permissions_path),
            '',
            ]))
        return False

    except Exception as ex:
        print('\n'.join([
            '',
            'Rejecting module due to error during extension id permission check:',
            ' path: {}'.format(x4_path / module_path),
            '{}: {}'.format(type(ex).__name__, ex if str(ex) else 'Unspecified'),
            '',
            ]))
        return False


def Pipe_Client_Test(args):
    '''
    Function to mimic the x4 client.
    '''
    pipe = Pipe_Client(pipe_name)

    if not args.x4_path or not args.x4_path.exists():
        raise Exception('Test error: invalid x4 path')

    # Example lua package path.
    #package_path = r".\?.lua;C:\Steam\steamapps\common\X4 Foundations\lua\?.lua;C:\Steam\steamapps\common\X4 Foundations\lua\?\init.lua;"
    package_path = r".\?.lua;{0}\lua\?.lua;{0}\lua\?\init.lua;".format(args.x4_path)

    # Announce the package path.
    pipe.Write("package.path:" + package_path)

    # Announce module relative paths.
    # Just one test module for now.
    # Give as_posix style.
    modules = [
        args.module.as_posix(),
        ]
    # Separated with ';', end with a ';'.
    message = ';'.join(modules) + ';'
    pipe.Write("modules:" + message)

    # Keep-alive blocking read.
    pipe.Read()
                
    return


if __name__ == '__main__':
    Main()

