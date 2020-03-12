'''
Main entry function for the overall python based server.
This will load in individual pipe sub-servers and run their threads.

Initial version just runs a test server.
'''
'''
TODO: dynamic imports from extension folders:
Set up server control pipe, and have x4 lua transmit the package.path
from lua. Example string:
".\?.lua;C:\Steam\steamapps\common\X4 Foundations\lua\?.lua;C:\Steam\steamapps\common\X4 Foundations\lua\?\init.lua;"
Add md api call where user announces the relative path to their py plugin.
Dynamically import that plugin, using package.path and relative path.

TODO: maybe use multiprocessing instead of threading.

TODO: think of a safe, scalable way to handle restarting threads,
particularly subthreads that a user server thread may have started,
which might get orphaned when that thread function exceptions out
on pipe closure.

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

'''

# Setup include path to this package.
import sys
from pathlib import Path

# To support packages cross-referencing each other, set up this
# top level as a package, findable on the sys path.
# Extra 'frozen' stuff is to support pyinstaller generated exes.
# TODO: this is a little redundant with Home_Path, but it is unclear
# on how to import home_path before this is done, so just repeat
# the effort for now.
if getattr(sys, 'frozen', False):
    home_path = Path(sys._MEIPASS).parent
else:
    home_path = Path(__file__).resolve().parents[1]
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

# Use a python test client, instead of needing x4 open.
# Note: putting breakpoints on tested modules requires opening them from
# their extension folder path, not their git repo path that was symlinked over.
test_python_client = 0

# Name of the host pipe.
pipe_name = 'x4_python_host'


# TODO: any interesting argparsing.
def Main():
    '''
    '''
    # List of directly launched threads.
    threads = []
    # List of relative path strings received from x4, to python server
    # modules that have been loaded before.
    module_relpaths = []

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
                reader_thread = threading.Thread(target = Pipe_Client_Test)
                reader_thread.start()

            # Wait for client.
            pipe.Connect()

            # Clear out any old x4 path; the game may have shut down and
            # relaunched from a different location.
            x4_path = None

            # Listen to runtime messages, announcing relative paths to
            # python modules to load from extensions.
            while 1:
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
                        # This approach will iterate through parents to fine the
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

                        # Record this path as seen.
                        module_relpaths.append(module_path)

                        # Put together the full path.         
                        full_path = x4_path / module_path

                        # Import the module.
                        module = Import(full_path)

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
                
            # This should now loop back and restart the pipe, if
            # shutdown wasn't set.
            if not shutdown:
                print('Restarting host.')
                
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


def Pipe_Client_Test():
    '''
    Function to mimic the x4 client.
    '''
    pipe = Pipe_Client(pipe_name)

    # Example lua package path.
    package_path = r".\?.lua;C:\Steam\steamapps\common\X4 Foundations\lua\?.lua;C:\Steam\steamapps\common\X4 Foundations\lua\?\init.lua;"

    # Announce the package path.
    pipe.Write("package.path:" + package_path)

    # Announce module relative paths.
    # TODO: make it easy to specify an extension being tested.
    modules = [
        "extensions/hotkey_api/Send_Keys.py",
        #"extensions/time_api/Time_API.py",
        ]
    # Separated with ';', end with a ';'.
    message = ';'.join(modules) + ';'
    pipe.Write("modules:" + message)

    # Keep-alive blocking read.
    pipe.Read()
                
    return


if __name__ == '__main__':
    Main()

