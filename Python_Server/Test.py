'''
Named pipe testing.
'''
# This has an example of serving and clienting a pipe
# https://stackoverflow.com/questions/48542644/python-and-windows-named-pipes
#
# This discuesses when to create, connect, disconnect, close.
#  In short, create at start, connect/disconnect as needed, close at end.
# https://stackoverflow.com/questions/18077145/windows-named-pipes-in-practice

# Can see if a pipe server is open using this in the windows powershell:
# [System.IO.Directory]::GetFiles("\\.\\pipe\\")

# Note: import pywin32 as win32api, if needed, though subpackages are
# directly available.
import win32pipe
import win32file
import threading
import time

'''
Note: the lua side winapi uses this for opening the pipe:
  HANDLE hPipe = CreateFile(
      pipename,
      GENERIC_READ |  // read and write access
      GENERIC_WRITE,
      0,              // no sharing
      NULL,           // default security attributes
      OPEN_EXISTING,  // opens existing pipe
      0,              // default attributes
      NULL);          // no template file
'''
# Name of the pipe in the OS.
# Name must be: "//<server>/pipe/<pipename>"
# Note: not case sensitive on windows.
pipe_name = r"\\.\pipe\x4_pipe"


def Runtime_Test(pure_python = False):
    '''
    Fleshing out this test to be more thorough.
    The interface will use a memory style protocol, where 

    * pure_python
      - Bool, if True then the test is done purely in python, with a local
        client accessing the pipe.
      - Default is False, leaving the pipe open for x4 to connect to.
    '''
    # Can either have x4 open it and python listen in, or python open
    # it and x4 listen. Or have either open it?  Unclear on how these work.
    # At any rate, try to open it.
    pipe = win32pipe.CreateNamedPipe(
        # Note: for some dumb reason, this doesn't use keyword args,
        #  so arg names included in comments.
        # pipeName
        pipe_name, 
        # The lua winapi opens pipes as read/write; try to match that.
        # openMode
        win32pipe.PIPE_ACCESS_DUPLEX,
        # pipeMode
        # Set writes to message, reads to message.
        # This means reading from the pipe grabs a complete message
        # as written, instead of a lump of bytes.
        win32pipe.PIPE_TYPE_MESSAGE | win32pipe.PIPE_READMODE_MESSAGE | win32pipe.PIPE_WAIT,
        # nMaxInstances
        1, 
        # nOutBufferSize
        65536, 
        # nInBufferSize
        # Can limit this to choke writes and see what errors they give.
        # In testing, this needs to be large enough for any single message,
        #  else the client write fails with no error code (eg. code 0).
        # In testing, a closed server and a full pipe generate the same
        #  error code, so x4 stalling on full buffers will not be supported.
        # This buffer should be sized large enough to never fill up.
        65536,
        # nDefaultTimeOut
        300,
        # sa
        None)
    print('Started serving: '+pipe_name)

    # For python testing, kick off a client thread.
    if pure_python:
        # Set up the reader in another thread.
        reader_thread = threading.Thread(target = Pipe_Client_Test)
        reader_thread.start()
        

    # Set up connections.
    # This appears to be a stall op that waits for a client to connect.
    # Returns 0, an integer for okayish errors (io pending, or pipe already
    #  connected), or raises an exception on other errors.
    # If the client connected first, don't consider that an error, so
    #  just ignore any error code but let exceptions get raised.
    win32pipe.ConnectNamedPipe(pipe, None)
    print('Connected to client')


    # X4 will write to its output, read from its input.
    # These will be read/write transactions to a data table, stored here.
    # Loop ends on getting a 'close' command.
    data_store = {}
    close_requested = False
    while not close_requested:

        # Get the next control message.
        error, data = win32file.ReadFile(pipe, 64*1024)
        message = data.decode()
        print('Received: ' + message)

        # Testing: delay on processing write.
        # Used originally to let multiple x4 writes queue up, potentially
        # hitting a full buffer.
        if 0:
            print('Pausing for a moment...')
            time.sleep(0.5)

        # Handle based on prefix, write or read.
        if message.startswith('write:'):
            # Expected format is:
            #  write:[key]value
            # (Or possibly a chain of keys? just one for now)
            key, value = message.split(':')[1].split(']')
            # Pull out the starting bracket.
            key = key[1:]
            # Save.
            data_store[key] = value

        elif message.startswith('read:'):
            # Expected format is:
            #  read:[key]
            key = message.split(':')[1]
            key = key[1:-1]

            if key not in data_store:
                response = 'error: {} not found'.format(key)
            else:
                response = data_store[key]

            # Pipe the response back.
            # Note: data is binary in the pipe, but treated as string in lua,
            # plua lua apparently has no integers (just doubles), but does have
            # string pack/unpack functions.
            # Anyway, it is easiest to make strings canonical for this, for now.
            # TODO: consider passing some sort of format specifier so the
            #  data can be recast in the lua.
            # Optionally do a read timeout test, which doesn't return data.
            timeout_test = 0
            if timeout_test:
                print('Suppressing read return; testing timeout.')
            else:
                error2, bytes_written = win32file.WriteFile(pipe, str(response).encode('utf-8'))
                print('Returned: ' + response)

        elif message == 'close':
            # Close the pipe/server when requested.
            close_requested = True

        else:
            print('Unexpected message type')

    
    # Close the pipe.
    print('Closing pipe...')
    # The routine for closing is described here:
    # https://docs.microsoft.com/en-us/windows/win32/ipc/named-pipe-operations
    win32file.FlushFileBuffers(pipe)
    win32pipe.DisconnectNamedPipe(pipe)
    win32file.CloseHandle(pipe)
    return


def Pipe_Client_Test():
    '''
    Function to attach to the pipe and read from it.
    Used to test basic pipe win32api.
    '''
    # Send a plain write, then a read transaction.
    pipe = open(pipe_name, 'rb+', buffering=0)
    pipe.write(b'write:[test1]5')
    pipe.write(b'read:[test1]')
    message = pipe.read(65536)
    print('Client read: ' + message.decode())
    pipe.write(b'close')
    
    return



if __name__ == '__main__':
    Runtime_Test(pure_python = False)
