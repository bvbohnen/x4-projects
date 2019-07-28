
# Note: import pywin32 as win32api, if needed, though subpackages are
#  directly available.
# The top level has the "error" exception.
import win32api
# This has windows error codes.
import winerror
# This can open a pipe.
import win32pipe
# This reads/writes the pipe file.
import win32file

class Pipe:
    '''
    Named pipe object.
    The OS pipe will be opened for serving when this is created,
    and will wait to connect to the x4 client.

    Parameters:
    * pipe_name
      - String, name of the pipe without OS path prefix.
    * buffer_size
      - Int, bytes to reserve for the buffers in each direction.
      - This has to be larger than the largest message that will pass
        through the pipe, and large enough that writes from x4 to the
        server will never fill the pipe to capacity.
      - Defaults to 64 kB.

    Attributes:
    * pipe_file
      - Open pipe/file object.
    * pipe_path
      - String, path with name for the pipe.
      - Must be: "//<server>/pipe/<pipename>"
    '''
    def __init__(self, pipe_name, buffer_size = 64*1024):
        self.pipe_name = pipe_name
        self.pipe_path = "\\\\.\\pipe\\" + pipe_name
        self.buffer_size = buffer_size
        
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
        # Can either have x4 open it and python listen in, or python open
        # it and x4 listen. Or have either open it?  Unclear on how these work.
        # At any rate, try to open it.
        self.pipe_file = win32pipe.CreateNamedPipe(
            # Note: for some dumb reason, this doesn't use keyword args,
            #  so arg names included in comments.
            # pipeName
            self.pipe_path, 
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
            buffer_size, 
            # nInBufferSize
            # Can limit this to choke writes and see what errors they give.
            # In testing, this needs to be large enough for any single message,
            #  else the client write fails with no error code (eg. code 0).
            # In testing, a closed server and a full pipe generate the same
            #  error code, so x4 stalling on full buffers will not be supported.
            # This buffer should be sized large enough to never fill up.
            buffer_size,
            # nDefaultTimeOut
            300,
            # sa
            None)
        print('Started serving: ' + self.pipe_path)

        # Wait to connect automatically.
        # This appears to be a stall op that waits for a client to connect.
        # Returns 0, an integer for okayish errors (io pending, or pipe already
        #  connected), or raises an exception on other errors.
        # If the client connected first, don't consider that an error, so
        #  just ignore any error code but let exceptions get raised.
        win32pipe.ConnectNamedPipe(self.pipe_file, None)
        print('Connected to client')
        return


    def Read(self):
        '''
        Read a message from the open pipe.
        Blocks until data is available.
        '''
        # Get byte data, up to the size of the buffer.
        # Ignore any "error" for now; expected hard errors should get
        # raised as exceptions.
        error, data = win32file.ReadFile(self.pipe_file, self.buffer_size)
        # Default decode (utf8) into a string to return.
        return data.decode()
    

    def Write(self, message):
        '''
        Write a message to the open pipe.
        '''
        # Similar to above, ignore this error, rely on exceptions.
        # Data will be utf8 encoded.
        error, bytes_written = win32file.WriteFile(self.pipe_file, str(message).encode())
        return


    def Close(self):
        '''
        Close out this pipe cleanly, waiting for reader to empty its data.
        '''
        # Close the pipe.
        print('Closing ' + self.pipe_path)
        # The routine for closing is described here:
        # https://docs.microsoft.com/en-us/windows/win32/ipc/named-pipe-operations
        win32file.FlushFileBuffers(self.pipe_file)
        win32pipe.DisconnectNamedPipe(self.pipe_file)
        win32file.CloseHandle(self.pipe_file)
        return