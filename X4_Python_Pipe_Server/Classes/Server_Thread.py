
import threading
import win32api
import winerror
from .Misc import Client_Garbage_Collected

class Server_Thread:
    '''
    Class to handle a single server thread.
    Starts a pipe server in a seperate thread, which runs until it closes.
    If the x4 client pipe is closed, the server will be restarted.
    
    TODO: support cleanly closing threads, likely with a global flag
    checked by pipe operations which raise a special exception.
    TODO: maybe make this a subclass of threading.Thread, and customize
    the run/start methods.

    Attributes:
    * entry_function
      - The function which will set up a Pipe and service it.
      - This should not expect to store any state through game reloads,
        since such events will cause the function to be restarted
        from scratch.
    * thread
      - Thread running the server.
    * test
      - Bool, if True then in test mode, and server will not reboot on
        a disconnect.
    '''
    def __init__(self, entry_function, test = False):
        # Set up the thread.
        # For potential future development, the thread will call a
        #  class method on this class object, inheriting any object
        #  attributes.
        self.entry_function = entry_function
        self.test = test
        self.thread = threading.Thread(target = self.Run_Server, 
                                       args = [])
        self.thread.start()
        return            


    def Run_Server(self):
        '''
        Entry point for a thread.
        This will run the server's entry_function, restarting it whenever
        the x4 pipe is broken, finishing when the function returns
        normally or on other exception.
        '''
        boot_server = True
        while boot_server:
            boot_server = False

            # Fire up the server, listening for particular errors.
            try:
                self.entry_function()
                
            except (win32api.error, Client_Garbage_Collected) as ex:
                # win32api.error exceptions have the fields:
                #  winerror : integer error code (eg. 109)
                #  funcname : Name of function that errored, eg. 'ReadFile'
                #  strerror : String description of error

                if self.test:
                    print('Pipe client disconnected; stopping test.')
                    
                elif isinstance(ex, Client_Garbage_Collected):
                    print('Pipe client garbage collected, restarting server.')
                    # Keep running the server.
                    boot_server = True
                
                # If X4 was reloaded, this results in a ERROR_BROKEN_PIPE error
                # (assuming x4 lua was wrestled into closing its pipe properly
                #  on garbage collection).
                elif ex.winerror == winerror.ERROR_BROKEN_PIPE:
                    print('Pipe client disconnected, restarting server.')
                    # Keep running the server.
                    boot_server = True

            #except Exception as ex:
            #    # Any other exception, reraise for now.
            #    raise ex

        return
    

    def Close(self):
        '''
        Close the server thread, perhaps unsafely.
        Pending development.
        '''
        return


    def Join(self):
        '''
        Calls thread.join, blocking until the thread returns.
        '''
        self.thread.join()
        return