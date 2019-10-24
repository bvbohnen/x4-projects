
### MD Named Pipe API Overview

 
MD API support for working with named pipes for inter-process communication. An external server (eg. written in Python) will create an OS named pipe, and this api will connect to it as a client. This will tie into related functions in an accompanying lua script.

Note: lua module supports only Windows named pipes.

Goals:
 - Allow user to access one or more named pipes, with arbitrary names.
 - Handle pipe write and read requests, in a non-blocking manner.
 - Recover safely on game save/reload, server shutdown/restart, ui reload, etc.
  
Operation notes:
 - The actual OS level pipe connections are handled in lua.
 - Minimal global state is tracked here; each access cue is self-sufficient.
 - Read/Write requests kick off cue instances that schedule the operation with the lua code, and then listen for a lua callback, ui reload (which wipes lua state), or timeout.
 - A user-supplied callback cue is called when access completes.
 - Any access error returns a special message to the callback cue.
 - Any pipe error will trigger an error on all pending accesses.
 - Such pipe errors will occur on game reloading, ui reload, server shutdown.
    
Usage:
 - See Read and Write cues below for how to call them.
 - User code should expect errors to occur often, and handle as needed.
 - Exact message protocol and transaction behavior depends on the external server handling a specific pipe.
 - If the OS pipe gets broken, the server should shutdown and remake the pipe, as the lua client cannot reconnect to the old pipe (in testing so far).
    
Note on timeouts:
 - If an access times out in the MD, it will still be queued for service in the lua until the pipe is closed.
 - This is intentional, so that if the server is behaving correctly but tardy, writes and reads will still get serviced in the correct order.

### MD Named Pipe API Cues

* Write
  
      
  User function to write a pipe. Called through signal_cue_instantly.
      
  Param: Table with the following items:
    - pipe : Name of the pipe being written, without OS path prefix.
    - msg  : Message string to write to the pipe.
    - cue  : Callback, optional, the cue to call when the write completes.
    - time : Timeout, optional, the time until an unsent read is cancelled. Currently not meaningful, as write stalling on a full pipe is not supported at the lua level.
        
  Returns:
  - Result is sent as event.param to the callback cue.
  - Writes receive 'SUCCESS' or 'ERROR'.
      
  Usage example:
  
      <signal_cue_instantly 
        name="md.Named_Pipes.Write" 
        param="table[
          $pipe='mypipe', 
          $msg='hello', 
          $cue=Write_Callback]">
  
    
* Write_Special
  
    
  As Write, but sends a special command in the message to the lua, which determines the actual message to send.  The only currently supported command is "package.path", which sends the current lua package import path list.
      
  Usage example:
  
      <signal_cue_instantly 
        name="md.Named_Pipes.Write_Special" 
        param="table[
          $pipe='mypipe', 
          $msg='package.path', 
          $cue=Write_Callback, 
          $time=5s]">
  
    
* Read
  
  User function to read a pipe. Called through signal_cue_instantly.
      
  Param: Table with the following items:
    - pipe : Name of the pipe being written, without OS path prefix.
    - cue  : Callback, optional, the cue to call when the read completes.
    - time : Timeout, optional, the time until a pending read is cancelled.
        
  Returns:
  - Whatever is read from the pipe in event.param to the callback cue.
  - If the read fails on bad pipe, returns 'ERROR'.
  - If the read times out, returns 'TIMEOUT'.
  - If the read is cancelled on game or ui reload, returns 'CANCELLED'.
      
  Usage example:
  
      <signal_cue_instantly 
        name="md.Named_Pipes.Read" 
        param="table[
          $pipe = 'mypipe', 
          $cue = Read_Callback, 
          $time = 5s]">
            
      ...
      <cue name="Read_Callback" instantiate="true">
        <conditions>
          <event_cue_signalled/>
        </conditions>
        <actions>
          <set_value name="$read_result" exact="event.param"/>
          <do_if value="$read_result == 'ERROR'">
            <stuff to do on pipe error>
          </do_if>
          <do_elseif value="$read_result == 'CANCELLED'">
            <stuff to do on cancelled request>
          </do_elseif>
          <do_elseif value="$read_result == 'TIMEOUT'">
            <stuff to do on pipe timeout>
          </do_elseif>
          <do_else>
            <stuff to do on read success>
          </do_else>
        </actions>
      </cue>
  
    
* Check
  
  User function to check if a pipe is connected to a server, making the connection if needed. Note: if a pipe was connected in the past but the server has since closed, and no other operations have been attempted in the meantime, this function will report the pipe as still connected. Note: this may return prior to following writes or reads. Called through signal_cue_instantly.
      
  Param: Table with the following items:
    - pipe : Name of the pipe being checked, without OS path prefix.
    - cue  : Callback, the cue to call when the check completes.
        
  Returns:
  - Value is is sent as event.param to the callback cue.
  - Checks receive 'SUCCESS' or 'ERROR'.
      
  Usage example:
  
      <signal_cue_instantly 
        name="md.Named_Pipes.Write" 
        param="table[
          $pipe='mypipe', 
          $msg='hello', 
          $cue=Write_Callback, 
          $time=5s]">
  
    
* Close
  
  User function to close a pipe. This is passed down to the lua level, where the pipe file is closed and all pending accesses killed (return errors). Does nothing if the pipe does not exist.
      
  Param: Name of the pipe being opened.
            
  Usage example:
  
      <signal_cue_instantly 
        name="md.Named_Pipes.Close" 
        param="'mypipe'">
  
    

### MD Pipe Server API Overview

 
MD API for interfacing with an external Python based pipe server. This allows user MD code to register a python module with the host server. The host (if running) will dynamically import the custom module. Such modules are distributed with extensions. Builds on top of the Named Pipes API.


Goals:
 - Connect to the running python host server process.
 - Allows user to specify the relative path to a python server plugin.
 - Extract the absolute path of x4 and transmit it to the server, for the currently running x4 installation (assume multiple on a computer).
 - Transmit user file paths to the host server, to be dynamically imported and started.
 - Detect host server errors, and re-announce user files upon reconnection.
    
Operation notes:
 - Requires the Python host server be set up and started. This is done by the player outside of the game, though can be started before or after x4.
 - Pings the server pipe until getting a connection.
 - Failed pings will wait some time before the next ping.
 - Transfers the lua package.paths to the server, where python code parses out the x4 absolute path. (Should be adaptable to multiple x4 installations without requiring extra player setup.)
 - Reloads on any error, as well as on game or ui reloads.
 - When reloading, signals the Reloaded cue, telling users to register their server plugin paths.
 - Passively reads the host server, watching for disconnect errors.
  
Usage:  
 - From MD code, call Register_Module to tell the host to import a python module from your extension.   
 - Write the corresponding python server module. This requires a "main" function to act as the entry point, and should preferably import the Pipe_Server class from X4_Python_Pipe_Server.   
 - Simple example, echo messages sent from x4 back to it:

       from X4_Python_Pipe_Server import Pipe_Server
       def main():
           pipe = Pipe_Server('x4_echo')
           while 1:
               message = pipe.Read()
               pipe.Write(message)
           return

    

### MD Pipe Server API Cues

* Register_Module
   
  User function to register a python server module. This should be resent each time Reloaded is signalled.
      
  Param: String, relative path to the python file from the x4 base dir. Use forward slashes between folders.
      
  Usage example:
  
      <cue name="Register_Pipe_Server" instantiate="true">
        <conditions>
          <event_cue_signalled cue="md.Pipe_Server_Host.Reloaded" />
        </conditions>
        <actions>
          <signal_cue_instantly 
            cue="md.Pipe_Server_Host.Register_Module" 
            param="'extensions/key_capture_api/Send_Keys.py'"/>
        </actions>
      </cue>
  
    

### Lua Pipe API Overview

 

Lua support for communicating through windows named pipes with an external process, with the help of the winpipe api dll, which wraps select windows OS functions.

The external process will be responsible for serving pipes. X4 will act purely as a client.

Behavior:
 - MD triggers lua functions using raise_lua_event.
 - Lua responds to MD by signalling the galaxy object with specific names.
 - When loaded, sends the signal "lua_named_pipe_api_loaded".
 
 - Requested reads and writes will be tagged with a unique <id> string, used to uniquify the signal raised when the request has completed.
 
 - Requests are queued, and will be served as the pipe becomes available.
 - Multiple requests may be serviced within the same frame.
 
 - Pipe access is non-blocking; reading an empty pipe will not error, but instead kicks off a polling loop that will retry the pipe each frame until the request succeeds or the pipe goes bad (eg. server disconnect).
 
 - If the write buffer to the server fills up and doesn't have room for a new message, or the new message is larger than the entire buffer, the pipe will be treated as bad and closed. (This is due to windows not properly distinguishing these cases from broken pipes in its error codes.)
 
 - Pipe file handles are opened automatically when handling requests.
 - If a prior opened file handle goes bad when processing a request, one attempt will be made to reopen the file before the request will error out.
 
 - Whenever the UI is reloaded, all queued requests and open pipes will be destroyed, with no signals to MD.  The MD is responsible for cancelling out such requests on its end, and the external server is responsible for resetting its provided pipe in this case.
 
 - The pipe file handle will (should) be closed properly on UI/game reload, triggering a closed pipe error on the server, which the server should deal with reasonably (eg. restarting the server side pipe).

### Lua Pipe API Functions

 
* Reading a pipe from MD:

  Start with a trigger:

      <raise_lua_event 
          name="'pipeRead'" 
          param="'<pipe_name>;<id>'"/>

  Example:

      <raise_lua_event 
          name="'pipeRead'" 
          param="'myX4pipe;1234'"/>

      
  Capture completion with a new subcue (don't instantiate if already inside an instance), conditioned on response signal:

      <event_ui_triggered 
          screen="'Named_Pipes'" 
          control="'pipeRead_complete_<id>'" />

      
  The returned value will be in "event.param3":

      <set_value 
          name="$pipe_read_value" 
          exact="event.param3" />

      
  <pipe_name> should be the unique name of the pipe being connected to. Locally, this name is prefixed with "\\.\pipe\".

  <id> is a string that uniquely identifies this read from other accesses that may be pending in the same time frame.
  
  If the read fails due to a closed pipe, a return signal will still be sent, but param2 will contain "ERROR".
    
    
* Writing a pipe from MD:

  The message to be sent will be suffixed to the pipe_name and id, separated by semicolons.

      <raise_lua_event 
        name="'pipeWrite'" 
        param="'<pipe_name>;<id>;<message>'"/>

            
  Example:

      <raise_lua_event 
        name="'pipeWrite'" 
        param="'myX4pipe;1234;hello'"/>

        
  Optionally capture the response signal, indicating success or failure.

      <event_ui_triggered 
        screen="'Named_Pipes'" 
        control="'pipeWrite_complete_<id>'" />

    
  The returned status is "ERROR" on an error, else "SUCCESS".

      <set_value name="$status" exact="event.param3" />

        
        
* Special writes:

  Certain write messages will be mapped to special values to be written, determined lua side.  This uses "pipeWriteSpecial" as the event name, and the message is the special command.
  
  Currently, the only such command is "package.path", sending the current value in lua for that.
  

      <raise_lua_event 
          name="'pipeWriteSpecial'" 
          param="'myX4pipe;1234;package.path'"/>

        
    
* Checking pipe status:

  Test if the pipe is connected in a similar way to reading:

      <raise_lua_event 
        name="'pipeCheck'" 
        param="'<pipe_name>;<id>'" />


      <event_ui_triggered 
        screen="'Named_Pipes'" 
        control="'pipeCheck_complete_<id>'" />

          
  In this case, event.param2 holds SUCCESS if the pipe appears to be succesfully opened, ERROR if not. Note that this does not robustly test the pipe, only if the File is open, so it will report success even if the server has disconnected if no operations have been performed since that disconnect.
    
    
* Close pipe:

      <raise_lua_event 
          name="'pipeClose'" 
          param="'<pipe_name>'" />

    
  Closing out a pipe has no callback. This will close the File handle, and will force all pending reads and writes to signal errors.
        
      
* Set a pipe to throw away reads during a pause:

      <raise_lua_event 
        name="'pipeSuppressPausedReads'" 
        param="'<pipe_name>'" />

    
* Undo this with:

      <raise_lua_event 
        name="'pipeUnsuppressPausedReads'" 
        param="'<pipe_name>'" />

        

* Detect a pipe closed:

  When there is a pipe error, this api will make one attempt to reconnect before returning an ERROR. Since the user may need to know about these disconnect events, a signal will be raised when they happen. The signal name is tied to the pipe name.
  

      <event_ui_triggered 
        screen="'Named_Pipes'" 
        control="'<pipe_name>_disconnected'" />