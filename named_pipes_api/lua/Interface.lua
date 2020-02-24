-- @doc-title MD to Lua Pipe API

--[[ @doc-overview

Lua support for communicating through windows named pipes with
an external process, with the help of the winpipe api dll, which
wraps select windows OS functions.

The external process will be responsible for serving pipes.
X4 will act purely as a client.

Note: if you are using the higher level MD API, you don't need to
worry about these lua details.

Behavior:
- MD triggers lua functions using raise_lua_event.
- Lua responds to MD by signalling the galaxy object with specific names.
- When loaded, sends the signal "lua_named_pipe_api_loaded".
- Requested reads and writes will be tagged with a unique <id> string,
  used to uniquify the signal raised when the request has completed.
- Requests are queued, and will be served as the pipe becomes available.
- Multiple requests may be serviced within the same frame.
- Pipe access is non-blocking; reading an empty pipe will not error, but
  instead kicks off a polling loop that will retry the pipe each frame 
  until the request succeeds or the pipe goes bad (eg. server disconnect).
- If the write buffer to the server fills up and doesn't have room for
  a new message, or the new message is larger than the entire buffer,
  the pipe will be treated as bad and closed. (This is due to windows
  not properly distinguishing these cases from broken pipes in
  its error codes.)
- Pipe file handles are opened automatically when handling requests.
- If a prior opened file handle goes bad when processing a request,
  one attempt will be made to reopen the file before the request will
  error out.
- Whenever the UI is reloaded, all queued requests and open pipes will
  be destroyed, with no signals to MD.  The MD is responsible for
  cancelling out such requests on its end, and the external server
  is responsible for resetting its provided pipe in this case.
- The pipe file handle will (should) be closed properly on UI/game reload,
  triggering a closed pipe error on the server, which the server should deal
  with reasonably (eg. restarting the server side pipe).
]]
   
--[[ @doc-functions
* Reading a pipe from MD:

  Start with a trigger:
  ```xml
    <raise_lua_event 
        name="'pipeRead'" 
        param="'<pipe_name>;<id>'"/>
  ```
  Example:
  ```xml
    <raise_lua_event 
        name="'pipeRead'" 
        param="'myX4pipe;1234'"/>
  ```
      
  Capture completion with a new subcue (don't instantiate if already inside
  an instance), conditioned on response signal:
  ```xml
    <event_ui_triggered 
        screen="'Named_Pipes'" 
        control="'pipeRead_complete_<id>'" />
  ```
      
  The returned value will be in "event.param3":
  ```xml
    <set_value 
        name="$pipe_read_value" 
        exact="event.param3" />
  ```
      
  `<pipe_name>` should be the unique name of the pipe being connected to.
  Locally, this name is prefixed with `\\.\pipe\`.

  `<id>` is a string that uniquely identifies this read from other accesses
  that may be pending in the same time frame.
  
  If the read fails due to a closed pipe, a return signal will still be sent,
  but param2 will contain "ERROR".
    
    
* Writing a pipe from MD:

  The message to be sent will be suffixed to the pipe_name and id, separated
  by semicolons.
  ```xml
    <raise_lua_event 
        name="'pipeWrite'" 
        param="'<pipe_name>;<id>;<message>'"/>
  ```
            
  Example:
  ```xml
    <raise_lua_event 
        name="'pipeWrite'" 
        param="'myX4pipe;1234;hello'"/>
  ```
        
  Optionally capture the response signal, indicating success or failure.
  ```xml
    <event_ui_triggered 
        screen="'Named_Pipes'" 
        control="'pipeWrite_complete_<id>'" />
  ```
    
  The returned status is "ERROR" on an error, else "SUCCESS".
  ```xml
    <set_value name="$status" exact="event.param3" />
  ```
        
        
* Special writes:

  Certain write messages will be mapped to special values to be written,
  determined lua side.  This uses "pipeWriteSpecial" as the event name,
  and the message is the special command.
  
  Currently, the only such command is "package.path", sending the current
  value in lua for that.
  
  ```xml
    <raise_lua_event 
        name="'pipeWriteSpecial'" 
        param="'myX4pipe;1234;package.path'"/>
  ```
        
    
* Checking pipe status:

  Test if the pipe is connected in a similar way to reading:
  ```xml
    <raise_lua_event 
        name="'pipeCheck'" 
        param="'<pipe_name>;<id>'" />
  ```
  ```xml
    <event_ui_triggered 
        screen="'Named_Pipes'" 
        control="'pipeCheck_complete_<id>'" />
  ```
          
  In this case, event.param2 holds SUCCESS if the pipe appears to be
  succesfully opened, ERROR if not. Note that this does not robustly
  test the pipe, only if the File is open, so it will report success
  even if the server has disconnected if no operations have been
  performed since that disconnect.
    
    
* Close pipe:
  ```xml
    <raise_lua_event 
        name="'pipeClose'" 
        param="'<pipe_name>'" />
  ```
    
  Closing out a pipe has no callback.
  This will close the File handle, and will force all pending reads
  and writes to signal errors.
        
      
* Set a pipe to throw away reads during a pause:
  ```xml
    <raise_lua_event 
        name="'pipeSuppressPausedReads'" 
        param="'<pipe_name>'" />
  ```
    
* Undo this with:
  ```xml
    <raise_lua_event 
        name="'pipeUnsuppressPausedReads'" 
        param="'<pipe_name>'" />
  ```
        

* Detect a pipe closed:

  When there is a pipe error, this api will make one attempt to reconnect
  before returning an ERROR. Since the user may need to know about these
  disconnect events, a signal will be raised when they happen.
  The signal name is tied to the pipe name.
  
  ```xml
    <event_ui_triggered 
        screen="'Named_Pipes'" 
        control="'<pipe_name>_disconnected'" />
  ```

]]

-- @doc-title Lua to Lua Pipe API

--[[ @doc-overview

Other lua modules may use this api to access pipes as well. Behavior is
largely the same as for the MD interface, except that results will be
returned to lua callback functions instead of being signalled to MD.
It may be imported using a require statement:
```lua
  local pipes_api = require('extensions.named_pipes_api.lua.Interface')
```
]]
--[[ @doc-functions
See named_pipes_api/lua/Pipes.lua for everything available. Basic
writing and reading functions are shown here.

* Schedule_Write(pipe_name, callback, message)
  - pipe_name
    - String, name of the pipe.
  - callback
    - Optional, lua function to call, taking one argument.
  - message
    - String, message to write.

* Schedule_Read(pipe_name, callback)
  - pipe_name
    - String, name of the pipe.
  - callback
    - Optional, lua function to call, taking one argument.
]]

-- Import lib functions and pipe management.
local Lib = require("extensions.named_pipes_api.lua.Library")
local Pipes = require("extensions.named_pipes_api.lua.Pipes")


-- Table of local functions.
local L = {}


-- Handle initial setup.
local function Init()
    -- Connect the events to the matching functions.
    RegisterEvent("pipeRead",                  L.Handle_pipeRead)
    RegisterEvent("pipeWrite",                 L.Handle_pipeWrite)
    RegisterEvent("pipeWriteSpecial",          L.Handle_pipeWrite)    
    RegisterEvent("pipeCheck",                 L.Handle_pipeCheck)
    RegisterEvent("pipeClose",                 L.Handle_pipeClose)
    RegisterEvent("pipeCancelReads",           L.Handle_pipeCancelReads)
    RegisterEvent("pipeCancelWrites",          L.Handle_pipeCancelWrites)
    RegisterEvent("pipeSuppressPausedReads",   L.Handle_pipeSuppressPausedReads)
    RegisterEvent("pipeUnsuppressPausedReads", L.Handle_pipeUnsuppressPausedReads)
                
    -- Signal to MD that the lua has reloaded.
    Lib.Raise_Signal('reloaded')
end


-- Read a message from a pipe.
-- Input is one term, semicolon separated string with pipe name, callback id.
function L.Handle_pipeRead(_, pipe_name_id)

    -- Isolate the pipe_name and access id.
    local pipe_name, callback = Lib.Split_String(pipe_name_id)
       
    -- Pass to the scheduler.
    Pipes.Schedule_Read(pipe_name, callback)
end



-- Write to a pipe.
-- Input is one term, semicolon separates string with pipe name, callback id,
-- and message.
-- If signal_name was "pipeWriteSpecial", this message is treated as
-- a special command that is used to determine what to write.
function L.Handle_pipeWrite(signal_name, pipe_name_id_message)

    -- Isolate the pipe_name, id, value.
    local pipe_name, temp = Lib.Split_String(pipe_name_id_message)
    local callback, message = Lib.Split_String(temp)
    
    -- Handle special commands.
    -- Note: if the command not recognized, it just gets sent as-is.
    if signal_name == "pipeWriteSpecial" then
        -- Table of commands to consider.
        if message == "package.path" then
            -- Want to write out the current package.path.
            message = "package.path:"..package.path
        end
    end
        
    -- Pass to the scheduler.
    Pipes.Schedule_Write(pipe_name, callback, message) 
end


-- Cancel a read or write requests on the pipe.
function L.Handle_pipeCancelReads(_, pipe_name)
    -- Pass to the descheduler.
    Pipes.Deschedule_Reads(pipe_name)
end

function L.Handle_pipeCancelWrites(_, pipe_name)
    -- Pass to the descheduler.
    Pipes.Deschedule_Writes(pipe_name)
end


-- Check if a pipe is connected.
-- While id isn't important for this, it is included for interface
-- consistency and code reuse in the MD.
function L.Handle_pipeCheck(_, pipe_name_id)
    -- Use find/sub for splitting instead.
    local pipe_name, callback = Lib.Split_String(pipe_name_id)
    
    local success = pcall(L.Connect_Pipe, pipe_name)
    -- Translate to strings that match read/write returns.
    local message
    if success then
        message = "SUCCESS"
    else
        message = "ERROR"
    end
    -- Send back to md or lua.
    if type(callback) == "string" then
        L.Raise_Signal('pipeCheck_complete_'..callback, message)
    elseif type(callback) == "function" then
        callback(message)
    end
end


-- Close a pipe.
-- This will not signal back, for now.
function L.Handle_pipeClose(_, pipe_name)
    Pipes.Close_Pipe(pipe_name)
end

-- Flag a pipe to suppress paused reads.
function L.Handle_pipeSuppressPausedReads(_, pipe_name)
    Pipes.Set_Suppress_Paused_Reads(pipe_name, true)
end

function L.Handle_pipeUnsuppressPausedReads(_, pipe_name)
    Pipes.Set_Suppress_Paused_Reads(pipe_name, false)
end

-- Finalize initial setup.
Init()


-- On require(), just return the Pipes functions to other lua modules.
return Pipes