
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
# This provides support for changing access permissions (for users where
# the defaults don't work). Note: defaults work for most users.
import win32security
import ntsecuritycon as con

from .Misc import Client_Garbage_Collected

class Pipe:
    '''
    Base class for Pipe_Server and Pipe_Client.
    Aims to implement any shared functionality.

    TODO: switch to paired unidirectional pipes instead of a single
    bidirectional pipe, to better match what linux would need, and
    to enable servers to set parallel read/write threads without them
    blocking each other by trying to use the same pipe (eg. pipe
    waiting to be Read will obstruct to other thread trying to Write)
    
    Parameters:
    * pipe_name
      - String, name of the pipe without OS path prefix.
    * buffer_size
      - Int, bytes to reserve for the buffers in each direction.
      - This has to be larger than the largest message that will pass
        through the pipe, and large enough that writes from x4 to the
        server will never fill the pipe to capacity.
      - Defaults to 64 kB.
      - Pipe_Clients use this for knowing how much to read.

    Attributes:
    * pipe_file
      - Open pipe/file object.
    * pipe_path
      - String, path with name for the pipe.
      - Must be: "//<server>/pipe/<pipename>"
    * nowait_set
      - Bool, if True then the pipe is in non-blocking mode, and doesn't
        wait for read/write to go through.
      - Defaults to not-set (blocks).
    '''
    def __init__(self, pipe_name, buffer_size = None):
        self.pipe_name = pipe_name
        self.pipe_path = "\\\\.\\pipe\\" + pipe_name
        # Default None to 64k buffer.
        self.buffer_size = buffer_size if buffer_size else 64*1024
        self.nowait_set = False
        return


    def Read(self):
        '''
        Read a message from the open pipe.
        This will block unless Set_Nonblocking has been called.

        Raises Client_Garbage_Collected exception if this gets a
        "garbage_collected" message.
        '''
        # Get byte data, up to the size of the buffer.
        # Non-blocking reads raise ERROR_NO_DATA if the pipe is empty.
        # TODO: maybe find a way to interrupt blocking reads on a ctrl-c
        # keyboard interrupt. Currently, ctrl-c does nothing during readfile,
        # though ctrl-pause still works.
        try:
            error, data = win32file.ReadFile(self.pipe_file, self.buffer_size)
            # Default decode (utf8) into a string to return.
            message = data.decode()

        except win32api.error as ex:
            # These exceptions have the fields:
            #  winerror : integer error code (eg. 109)
            #  funcname : Name of function that errored, eg. 'ReadFile'
            #  strerror : String description of error
            if ex.winerror == winerror.ERROR_NO_DATA and self.nowait_set:
                # Return None in this case.
                message = None
            else:
                # Re-raise other exceptions.
                raise ex

        if message == 'garbage_collected':
            raise Client_Garbage_Collected()
        return message

    
    def Write(self, message):
        '''
        Write a message to the open pipe.
        This generally shouldn't block (plenty of room in pipe), but will
        explicitly not-block if Set_Nonblocking has been called.
        '''
        # Similar to above, ignore this error, rely on exceptions.
        # Data will be utf8 encoded.
        # Don't worry about non-blocking full-pipe exceptions for now;
        #  assume there is always room.
        error, bytes_written = win32file.WriteFile(self.pipe_file, str(message).encode())
        return
    

    def Set_Nonblocking(self):
        '''
        Set this pipe to non-blocking access mode.
        '''
        # Only need to change state if nowait is not already set.
        # (Use this to reduce overhead for these calls.)
        if not self.nowait_set:
            self.nowait_set = True
            win32pipe.SetNamedPipeHandleState(
                self.pipe_file, 
                win32pipe.PIPE_READMODE_MESSAGE | win32pipe.PIPE_NOWAIT, 
                None, 
                None)
        return

    def Set_Blocking(self):
        '''
        Set this pipe to blocking access mode.
        '''
        # Only need to change state if nowait is set.
        if  self.nowait_set:
            self.nowait_set = False
            win32pipe.SetNamedPipeHandleState(
                self.pipe_file, 
                win32pipe.PIPE_READMODE_MESSAGE | win32pipe.PIPE_WAIT, 
                None, 
                None)
        return


class Pipe_Server(Pipe):
    '''
    Named pipe object.
    The OS pipe will be opened for serving when this is created.
    Call Connect to wait for a client to connect to the pipe.
    Use Read and Write to interact with the pipe.
    '''
    def __init__(self, pipe_name, buffer_size = None, verbose = False):
        super().__init__(pipe_name, buffer_size)
        self.verbose = verbose
        
        
        # Note: at least one user had access_denied errors from the x4
        # lua code, not resolved by running x4 as admin, possibly linked
        # to pipe permissions.
        # Documentation on setting up security is very sparse. The only
        # solid python example found is here:
        # http://timgolden.me.uk/python/win32_how_do_i/add-security-to-a-file.html
        # This edits permissions after creation, though in testing this
        # approach requires a separate read connection to the pipe, and
        # would prevent nMaxInstances==1 from working.
        # As such, it would be possible for x4 to connect twice to the same
        # pipe after the security permissions are done, which is undesirable.

        # Security attributes have a SECURITY_DESCRIPTOR member to modify.
        sec_attr = win32security.SECURITY_ATTRIBUTES()
        sec_desc = sec_attr.SECURITY_DESCRIPTOR
        
        
        # Create a new dacl ("discretionary access control list").
        dacl = win32security.ACL ()
        
        # Look up windows users.
        # Note: for the person with perm problems, "Everyone" and 
        # "Administrators" lookups failed (1332 error), but the user lookup
        # worked, and just setting read/write for the user was sufficient.
        perms_set = False
        for account_name in [win32api.GetUserName()]:
            # One user indicated the printed account name for them was blank,
            # followed by perms not working. Warn in that case, and leave
            # perms at default.
            # TODO: this didn't fix the problem; would need more input from
            # the user to figure out exactly what is going on.
            if not account_name.strip():
                if self.verbose:
                    print(f'Failed to retrieve account name with win32api.GetUserName')
                continue

            try:
                account_id, domain, type = win32security.LookupAccountName (None, account_name)
                # Set read/write permission (execute doesn't make sense).
                dacl.AddAccessAllowedAce(win32security.ACL_REVISION, 
                                            con.FILE_GENERIC_READ | con.FILE_GENERIC_WRITE, 
                                            account_id)
                perms_set = True
                if self.verbose:
                    print(f'Setting pipe read/write permission for account "{account_name}"')
            except win32api.error as ex:
                if self.verbose:
                    print(f'Failed to set pipe read/write permission for account '
                            f'"{account_name}"; error code {ex.winerror} in '
                            f'{ex.funcname} : {ex.strerror}')
                continue

        if perms_set:
            # Apply to the security object.
            # Args are: (1 if dacle used, dacl, 1 if using defaults)
            sec_desc.SetSecurityDescriptorDacl(1, dacl, 0)
            # Leave user/group/etc. at defaults (eg. unspecified).
        else:
            # If all perms failed, just clear this and use defaults.
            sec_attr = None

        # Create the pipe in server mode.
        self.pipe_file = win32pipe.CreateNamedPipe(
            # Note: for some reason this doesn't use keyword args,
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
            self.buffer_size, 
            # nInBufferSize
            # Can limit this to choke writes and see what errors they give.
            # In testing, this needs to be large enough for any single message,
            #  else the client write fails with no error code (eg. code 0).
            # In testing, a closed server and a full pipe generate the same
            #  error code, so x4 stalling on full buffers will not be supported.
            # This buffer should be sized large enough to never fill up.
            self.buffer_size,
            # nDefaultTimeOut
            300,

            # sa, security access.
            # If set to None, will use some system defaults, with rd/wr
            # access for the owner and rd for others (maybe, unclear).
            sec_attr,
            )
        
        # -Removed; requires nMaxInstances > 1 (or does it? maybe some other problem)
        ## Get the existing file security to be modified, dacl information.
        #sd = win32security.GetFileSecurity (self.pipe_path, win32security.DACL_SECURITY_INFORMATION)
        ## Apply the dacl.
        #sd.SetSecurityDescriptorDacl (1, dacl, 0)
        #win32security.SetFileSecurity (self.pipe_path, win32security.DACL_SECURITY_INFORMATION, sd)

        print('Started serving: ' + self.pipe_path)
        return


    def Connect(self):
        '''
        Wait for a client to connect to this pipe.
        '''
        # Wait to connect automatically.
        # This appears to be a stall op that waits for a client to connect.
        # Returns 0, an integer for okayish errors (io pending, or pipe already
        #  connected), or raises an exception on other errors.
        # If the client connected first, don't consider that an error, so
        #  just ignore any error code but let exceptions get raised.
        win32pipe.ConnectNamedPipe(self.pipe_file, None)
        print('Connected to client')


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


class Pipe_Client(Pipe):
    '''
    Opens a pipe as a client.
    To be used for testing servers by building a model of the x4 side.
    TODO: maybe share some functions with Pipe.
    
    Attributes:
    * pipe_file
      - Open pipe/file object.
    * pipe_path
      - String, path with name for the pipe.
      - Must be: "//<server>/pipe/<pipename>"
    '''
    def __init__(self, pipe_name, buffer_size = None):
        super().__init__(pipe_name, buffer_size)
        
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
        self.pipe_file = win32file.CreateFile(
            # pipeName
            self.pipe_path, 
            # Access mode; both read and write.
            win32file.GENERIC_WRITE | win32file.GENERIC_READ, 
            # No sharing.
            0, 
            # Default security.
            None, 
            # Open existing.
            win32file.OPEN_EXISTING, 
            # Default attributes.
            0, 
            # No template.
            None)

        # The above defaults to byte mode. Switch to message.
        win32pipe.SetNamedPipeHandleState(
            self.pipe_file, 
            win32pipe.PIPE_READMODE_MESSAGE, 
            None, 
            None)

        print('Client opened: ' + self.pipe_path)
        return