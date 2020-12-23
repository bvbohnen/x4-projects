
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
 - At least 1 frame of delay occurs on returning an operation result from lua back to md.
 - A user-supplied callback cue is called when access completes.
 - Any access error returns a special message to the callback cue.
 - Any pipe error will trigger an error on all pending accesses.
 - Such pipe errors will occur on game reloading, ui reload, server shutdown.
    
Usage:
 - See Read and Write cues below for how to call them.
 - User code should expect errors to occur often, and handle as needed.
 - Exact message protocol and transaction behavior depends on the external server handling a specific pipe.
 - If the OS pipe gets broken, the server should shutdown and remake the pipe, as the lua client cannot reconnect to the old pipe (in testing so far).
 - If passing rapid messages, recommend finding a way to join them together into one, or else have multiple read requests in flight at once, to avoid throttling due to the 1 frame lua->md delay.
    
Note on timeouts:
 - If an access times out in the MD, it will still be queued for service in the lua until the pipe is closed.
 - This is intentional, so that if the server is behaving correctly but tardy, writes and reads will still get serviced in the correct order.

### MD Named Pipe API Cues

* **Reloaded**
  
  Dummy cue used for signalling.
    
* **Write**
  
      
  User function to write a pipe.
      
  Param: Table with the following items:
  * pipe
    - Name of the pipe being written, without OS path prefix.
  * msg
    - Message string to write to the pipe.
  * cue
    - Callback, optional, the cue to call when the write completes.
  * time
    - Timeout, optional, the time until an unsent read is cancelled.
    - Currently not meaningful, as write stalling on a full pipe is not supported at the lua level.
        
  Returns:
  - Result is sent as event.param to the callback cue.
  - Writes receive 'SUCCESS' or 'ERROR'.
      
  Usage example:
  ```xml
    <signal_cue_instantly 
      name="md.Named_Pipes.Write" 
      param="table[
        $pipe='mypipe', 
        $msg='hello', 
        $cue=Write_Callback]">
  ```
    
* **Write_Special**
  
    
  As Write, but sends a special command in the message to the lua, which determines the actual message to send.  The only currently supported command is "package.path", which sends the current lua package import path list.
      
  Usage example:
  ```xml
    <signal_cue_instantly 
      name="md.Named_Pipes.Write_Special" 
      param="table[
        $pipe='mypipe', 
        $msg='package.path', 
        $cue=Write_Callback, 
        $time=5s]">
  ```
    
* **Read**
  
  User function to read a pipe. Note: the lua-to-md frame delay means that read responses will always be delayed by at least one frame.
      
  Param: Table with the following items:
  * pipe
    - Name of the pipe being written, without OS path prefix.
  * cue
    - Callback, optional, the cue to call when the read completes.
  * continuous
    - Bool, optional, if True then this read will continuously run, returning messages read but not ending the request.
    - This allows a pipe to be read multiple times in a single frame with a single read request (otherwise multiple parallel read requests would be needed).
    - Should not be used with timeout.
  * time
    - Timeout, optional, the time until a pending read is cancelled.
    - After a timeout, the pipe will still listen for the message and throw it away when it arrives. This behavior can be changed with the next arg.
  * cancel_on_timeout
    - Bool, if a timeout event should also cancel all pending reads to the pipe (triggers errors for requests other than this one).
    - Defaults false.
        
  Returns:
  - Whatever is read from the pipe in event.param to the callback cue.
  - If the read fails on bad pipe, returns 'ERROR'.
  - If the read times out, returns 'TIMEOUT'.
  - If the read is cancelled on game or ui reload, returns 'CANCELLED'.
      
  Usage example, initial read:
  ```xml
    <signal_cue_instantly 
      name="md.Named_Pipes.Read" 
      param="table[
        $pipe = 'mypipe', 
        $cue = Read_Callback, 
        $time = 5s]">
  ```
      
  Usage example, capture response:
  ```xml
    <cue name="Read_Callback" instantiate="true">
      <conditions>
        <event_cue_signalled/>
      </conditions>
      <actions>
        <set_value name="$read_result" exact="event.param"/>
        <do_if value="$read_result == 'ERROR'">
          <stuff to do on pipe error/>
        </do_if>
        <do_elseif value="$read_result == 'CANCELLED'">
          <stuff to do on cancelled request/>
        </do_elseif>
        <do_elseif value="$read_result == 'TIMEOUT'">
          <stuff to do on pipe timeout/>
        </do_elseif>
        <do_else>
          <stuff to do on read success/>
        </do_else>
      </actions>
    </cue>
  ```
    
* **Cancel_Reads**
  
  User function to cancel pending reads of a pipe. Does nothing if the pipe does not exist. Can be used to stop a continuous read.
      
  Param: Name of the pipe being opened.
            
  Usage example:
  ```xml
    <signal_cue_instantly 
      name="md.Named_Pipes.Cancel_Reads" 
      param="'mypipe'">
  ```
    
* **Check**
  
  User function to check if a pipe is connected to a server, making the connection if needed.
      
  Note: if a pipe was connected in the past but the server has since closed, and no other operations have been attempted in the meantime, this function will report the pipe as still connected.
      
  Param: Table with the following items:
  * pipe
    - Name of the pipe being checked, without OS path prefix.
  * cue
    - Callback, the cue to call when the check completes.
        
  Returns:
  - Value is is sent as event.param to the callback cue.
  - Checks receive 'SUCCESS' or 'ERROR'.
      
  Usage example:
  ```xml
    <signal_cue_instantly 
      name="md.Named_Pipes.Write" 
      param="table[
        $pipe='mypipe', 
        $msg='hello', 
        $cue=Write_Callback, 
        $time=5s]">
  ```
    
* **Close**
  
  User function to close a pipe. This is passed down to the lua level, where the pipe file is closed and all pending accesses killed (return errors). Does nothing if the pipe does not exist.
      
  Param: Name of the pipe being opened.
            
  Usage example:
  ```xml
    <signal_cue_instantly 
      name="md.Named_Pipes.Close" 
      param="'mypipe'">
  ```
    
* **Access_Handler**
  
  Start a new pipe access. Several other access cues (Read, Write, etc.) redirect to here.
      
  Param: Table with the following items:
    * $pipe
      - String, name of the pipe being accessed, without path prefix.
    * $command
      - String, one of ['Read','Write','WriteSpecial','Check'].
    * $msg
      - String, message to send for writes.
      - Unused for non-writes.
    * $cue
      - Cue to call with the result when operation completes.
      - Optional for writes.
    * $time
      - Time, how long to allow for access before cancelling it.
      - A timeout will trigger a 'TIMEOUT' return value to the callback cue.
      - Optional.
      - Defaults to 1000000s (~270 hours), to basically be disabled.
      - Note: timeout kills this access cue, but does not prevent the lua from continuing the operation.  The lua op complete signal will be ignored, if/when it arrives.  See option below to change this behavior.
    * $cancel_on_timeout
      - Bool or int, if a timeout event should also cancel all pending accesses to the pipe (either reads or writes).
      - Defaults false.
      - This will trigger error responses on all cancelled accesses except for this one that timed out.
      - Intended for use with reads when the timed-out access is not expecting any response, eg. was passively reading.
    * $continuous
      - Bool, optional, if True and this is a Read, then this read will continuously run, returning messages read but not ending the request.
      - Should not be used with timeout.
        
  Returns: Value is is sent as event.param to the callback cue. Writes and Checks receive 'SUCCESS' or 'ERROR'. Reads receive pipe response or 'ERROR' or 'TIMEOUT' or 'CANCELLED'.
    

### MD Pipe Python Host Overview

 
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
 - Simple python example, echo messages sent from x4 back to it:
    ```python
    from X4_Python_Pipe_Server import Pipe_Server
    def main():
        pipe = Pipe_Server('x4_echo')
        pipe.Connect()
        while 1:
            message = pipe.Read()
            pipe.Write(message)
    ```
    

### MD Pipe Python Host Cues

* **Register_Module**
   
  User function to register a python server module. This should be resent each time Reloaded is signalled.
      
  Param: String, relative path to the python file from the x4 base dir. Use forward slashes between folders.
      
  Usage example:
  ```xml
    <cue name="Register_Pipe_Server" instantiate="true">
      <conditions>
        <event_cue_signalled cue="md.Pipe_Server_Host.Reloaded" />
      </conditions>
      <actions>
        <signal_cue_instantly 
          cue="md.Pipe_Server_Host.Register_Module" 
          param="'extensions/sn_hotkey_api/Send_Keys.py'"/>
      </actions>
    </cue>
  ```
    

### MD Pipe Connection Helper Cues

* **Server_Reader**
  
  Library package of cues used to simplify handling server connections by supporting the following behaviors:
  * Ping server until succesfully connecting,
  * Listen for server messages,
  * Detect disconnections and recover.
      
  Note: the parameters of this library will all be references to other libraries containing action blocks to execute here.  Such action blocks will use the namespace of the Server_Reader instance, and their scope for md cue lookups will be from the Pipe_Server_Lib file.
          
  Parameters:
  * Actions_On_Reload
    - Library of actions to perform when reloading after a pipe disconnect, savegame reload, ui reload, as well as initial creation.
    - Should set attributes: Pipe_Name, and optionally DebugChance.
    - May add other variables to the library instance, if desired.
  * Actions_On_Connect
    - Optional library of actions to perform upon connecting to the server.
    - May signal $Start_Reading to begin passive reading of the pipe.
  * Actions_On_Read
    - Optional library of actions to perform when reading a message from the server.
    - The message will be in event.param.
        
  Attributes (write these in Actions_On_Reload):
  * $Pipe_Name
    - Name of the pipe used to communicate with the python host.
  * $DebugChance
    - Optional, 0 or 100.
        
  Interface variables:
  * $Start_Reading
    - Internal cue, made available as a variable.
    - Must be signalled to start the server connection routine.
    - If the connection is ever broken, which will occur on a Reload or possibly through param actions, this needs to be signalled again to reconnect.
    - Note: this is only available 2 frames after the Server_Reader cue is set up (as opposed to 1 frame delay for other attributes).
    
  Local variables:
  * $server_access_loop_cue
    - Cue or null, the currently active Server_Access_Loop cue instance.
    - Starts as null. If an active instance dies, the "exists" property will return false.
  * $server_connected
    - Flag, 1 when the server has been pinged succesfully and appears to have a valid connection. 0 before connection is set up, or after an error/disconnect. Used to suppress some writes before a connection is made, though shouldn't be critical to functionality.
  * $ping_count
    - Int, how many failed pings have occurred.
    - Used to increase ping delay after failures.
    - Not an exactly count; only goes up to the highest delay, eg. 10.
          
  Note: x4 has problems when a cue using this library is created alongside the action-libraries to be given as parameters.  While other cues can be passed in this way, libraries cannot. As a workaround, a dummy cue can be wrapped around the cue that refs this library.
        
  Example usage:
  ```xml
    <cue name="Server_Reader_Wrapper">
      <cues>
        <cue name="Server_Reader" ref="md.Pipe_Server_Lib.Server_Reader">
          <param name="Actions_On_Reload"   value="Actions_On_Reload"/>
          <param name="Actions_On_Connect"  value="Actions_On_Connect"/>
          <param name="Actions_On_Read"     value="Actions_On_Read"/>
        </cue>
      </cues>
    </cue>
        
    <library name="Actions_On_Reload">
      <actions>
        <set_value name="$Pipe_Name" exact="'my_x4_pipe'" />
      </actions>
    </library>
        
    <library name="Actions_On_Connect">
      <actions>
        <signal_cue cue="$Start_Reading" />
      </actions>
    </library>
        
    <library name="Actions_On_Read">
      <actions>
        <debug_text text="'received mesage: %s.'.[event.param]"
                  chance="$DebugChance" filter="general"/>
      </actions>
    </library>
  
      ```
          