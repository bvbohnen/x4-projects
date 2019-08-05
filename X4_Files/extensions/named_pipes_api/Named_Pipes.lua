--[[
Support for communicating through windows named pipes with
an external process.

The external process will be responsible for serving pipes.
X4 will act purely as a client.

Behavior:

    MD triggers lua functions using raise_lua_event.
    Lua responds to MD by signalling the galaxy object with specific names.
    When loaded, sends the signal "lua_named_pipe_api_loaded".
    
    Requested reads and writes will be tagged with a unique <id> string,
    used to uniquify the signal raised when the request has completed.
    
    Requests are queued, and will be served as the pipe becomes available.
    Multiple requests may be serviced within the same frame.
    
    Pipe access is non-blocking; reading an empty pipe will not error, but
    instead kicks off a polling loop that will retry the pipe each frame 
    until the request succeeds or the pipe goes bad (eg. server disconnect).
    
    If the write buffer to the server fills up and doesn't have room for
    a new message, or the new message is larger than the entire buffer,
    the pipe will be treated as bad and closed. (This is due to windows
    not properly distinguishing these cases from broken pipes in
    its error codes.)
    
    Pipe file handles are opened automatically when handling requests.
    If a prior opened file handle goes bad when processing a request,
    one attempt will be made to reopen the file before the request will
    error out.
    
    Whenever the UI is reloaded, all queued requests and open pipes will
    be destroyed, with no signals to MD.  The MD is responsible for
    cancelling out such requests on its end, and the external server
    is responsible for resetting its provided pipe in this case.
    
    The pipe file handle will (should) be closed properly on UI/game reload,
    triggering a closed pipe error on the server, which the server should deal
    with reasonably (eg. restarting the server side pipe).
    

Reading a pipe from MD:

    Start with a trigger:
    
        <raise_lua_event 
            name="'pipeRead'" 
            param="'<pipe_name>;<id>'"/>
            
        Example:
        
        <raise_lua_event 
            name="'pipeRead'" 
            param="'myX4pipe;1234'"/>
        
    Capture completion with a new subcue (don't instantiate if already inside
    an instance), conditioned on response signal:
    
        <event_ui_triggered 
            screen="'Named_Pipes_Api'" 
            control="'pipeRead_complete_<id>'" />
        
    The returned value will be in "event.param3":
    
        <set_value 
            name="$pipe_read_value" 
            exact="event.param3" />
        
    <pipe_name> should be replaced with the full path name of the pipe
    being connected to. Example: "\\.\pipe\x4_pipe", with doubled backslashes
    as needed for escapes in the string creation.
    <id> is a string that uniquely identifies this read from other accesses
    that may be pending in the same time frame.
    
    If the read fails due to a closed pipe, a return signal will still be sent,
    but param2 will contain "ERROR".
    
    
Writing a pipe from MD:

    The message to be sent will be suffixed to the pipe_name and id, separated
    by semicolons.
    
        <raise_lua_event 
            name="'pipeWrite'" 
            param="'<pipe_name>;<id>;<message>'"/>    
            
        Example:
        
        <raise_lua_event 
            name="'pipeWrite'" 
            param="'myX4pipe;1234;hello'"/>
        
    Optionally capture the response signal, indicating success or failure.
    
        <event_ui_triggered 
            screen="'Named_Pipes_Api'" 
            control="'pipeWrite_complete_<id>'" />
    
    The returned status is "ERROR" on an error, else "SUCCESS".
    
        <set_value name="$status" exact="event.param3" />
        
        
Special writes:

    Certain write messages will be mapped to special values to be written,
    determined lua side.  This uses "pipeWriteSpecial" as the event name,
    and the message is the special command.
    
    Currently, the only such command is "package.path", sending the current
    value in lua for that.
    
        <raise_lua_event 
            name="'pipeWriteSpecial'" 
            param="'myX4pipe;1234;package.path'"/>
        
    
Checking pipe status:

    Test if the pipe is connected in a similar way to reading:
    
        <raise_lua_event name="'pipeCheck'" param="'<pipe_name>;<id>'" />
    
        <event_ui_triggered 
            screen="'Named_Pipes_Api'" 
            control="'pipeCheck_complete_<id>'" />
            
    In this case, event.param2 holds SUCCESS if the pipe appears to be
    succesfully opened, ERROR if not. Note that this does not robustly
    test the pipe, only if the File is open, so it will report success
    even if the server has disconnected if no operations have been
    performed since that disconnect.
    
    
Close pipe:

    Closing out a pipe has no callback.
    
        <raise_lua_event name="'pipeClose'" param="'<pipe_name>'" />
    
    This will close the File handle, and will force all pending reads
    and writes to signal errors.
        
      
Set a pipe to throw away reads during a pause:
    <raise_lua_event name="'pipeSuppressPausedReads'" param="'<pipe_name>'" />
    
Undo this with:
    <raise_lua_event name="'pipeUnsuppressPausedReads'" param="'<pipe_name>'" />
        

Detect a pipe closed:

    When there is a pipe error, this api will make one attempt to reconnect
    before returning an ERROR. Since the user may need to know about these
    disconnect events, a signal will be raised when they happen.
    The signal name is tied to the pipe name.
    
        <event_ui_triggered 
            screen="'Named_Pipes_Api'" 
            control="'<pipe_name>_disconnected'" />

    
TODO:    
    Add api hooks for other lua functions, instead of requiring callbacks
    to be ui signals for md always.
    
    Add option to auto-ack reads (send back "ack" on any read), to slightly
    reduce md api overhead.
    
]]


-- Generic required ffi, to access C functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    bool IsGamePaused(void);
]]


-- Load in the winpipe dll, which has been set up with the necessary
-- Windows functions for working with pipes.
local winpipe = require("winpipe")


-- Forward declarations of functions.
-- (Does redeclaring them local further below break things? TODO)
local Init
local Raise_Signal
local Declare_Pipe
local Connect_Pipe
local Disconnect_Pipe
local Close_Pipe

local Split_String
local Handle_pipeRead
local Schedule_Read
local Handle_pipeWrite
local Schedule_Write
local Handle_pipeCheck
local Handle_pipeClose
local Handle_pipeSuppressPausedReads
local Handle_pipeUnsuppressPausedReads

local Poll_For_Reads
local Poll_For_Writes

local _Read_Pipe_Raw
local Read_Pipe
local _Write_Pipe_Raw
local Write_Pipe

local Test


-- Match the style of egosoft lua, with a private table containing
-- static variables.
local private = {

    --[[
    Pipe state objects, generally alive while the link is set up.
    Keys are the pipe names sent from the MD side, without path extension.
    
    Each entry is a subtable with these fields:
    * file
      - File object to read/write/close.
    * retry_allowed
      - Bool, if a failed access is allowed one retry.
      - Set prior to an access attempt if the pipe was already open, but
        is not known to be still connected.
      - On a retry attempt, this flag should be cleared.
    * suppress_reads_when_paused
      - Bool, if true then messages read during a game pause are thrown away.
    * read_fifo
      - FIFO of callback IDs for read completions.
      - Callback ID is a string.
      - Entries removed as reads complete.
      - When empty, stop trying to read this pipe.
    * write_fifo
      - FIFO of lists of [callback ID, message pending writing]
      - Entries removed as writes complete succesfully or fail completely.
      - When empty, stop trying to write this pipe.
    ]]
    pipes = { },

    -- Flags to indicate if the Write poller and Read poller are registered
    -- to run each frame or not.
    write_polling_active = false,
    read_polling_active  = false,
    
    -- If extra status messages should print to the chat window.
    print_to_chat = false,
    -- If status messages should print to the debuglog.
    print_to_log = false,
    
    -- Prefix to add to the pipe_name to get a file path.
    pipe_path_prefix = "\\\\.\\pipe\\"
    }


-- FIFO definition, largely lifted from https://www.lua.org/pil/11.4.html
-- Adjusted for pure fifo behavior.
local FIFO = {}
function FIFO.new ()
  return {first = 0, last = -1}
end    

function FIFO.Write (fifo, value)
  local last = fifo.last + 1
  fifo.last = last
  fifo[last] = value
end

function FIFO.Read (fifo)
  local first = fifo.first
  if first > fifo.last then error("fifo is empty") end
  local value = fifo[first]
  fifo[first] = nil
  fifo.first = first + 1
  return value
end

-- Return the next Read value of the fifo, without removal.
function FIFO.Next (fifo)
  local first = fifo.first
  if first > fifo.last then error("fifo is empty") end
  return fifo[first]
end

-- Returns true if fifo is empty, else false.
function FIFO.Is_Empty (fifo)
  return fifo.first > fifo.last
end


-- Handle initial setup.
function Init()
    -- Force lua to garbage collect.
    -- There may have been a File opened to a prior pipe which hasn't been
    -- GC'd yet, so the server won't yet know to reboot. New requests will
    -- then fail to be able to open a new pipe.
    -- By GC'ing here, the old File should close properly and the server
    -- can restart quicker.
    collectgarbage()

    -- Connect the events to the matching functions.
    RegisterEvent("pipeRead", Handle_pipeRead)
    RegisterEvent("pipeWrite", Handle_pipeWrite)
    RegisterEvent("pipeWriteSpecial", Handle_pipeWrite)    
    RegisterEvent("pipeCheck", Handle_pipeCheck)
    RegisterEvent("pipeClose", Handle_pipeClose)
    RegisterEvent("pipeSuppressPausedReads", Handle_pipeSuppressPausedReads)
    RegisterEvent("pipeUnsuppressPausedReads", Handle_pipeUnsuppressPausedReads)
        
        
    -- Signal to MD that the lua has reloaded.
    Raise_Signal('reloaded')
    
    -- Testing for path detection.
    -- if package.path ~= nil then
    --     DebugError("package.path: "..package.path)
    -- end
end


-- Shared function to raise a named galaxy signal with an optional
-- return value.
function Raise_Signal(name, return_value)
    -- Clumsy way to lookup the galaxy.
    -- local player = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    -- local galaxy = GetComponentData(player, "galaxyid" )
    -- SignalObject( galaxy, name, return_value)
    
    -- Switching to AddUITriggeredEvent
    -- This will give the return_value in event.param3
    -- Use <event_ui_triggered screen="'Named_Pipes_Api'" control="'???'" />
    AddUITriggeredEvent("Named_Pipes_Api", name, return_value)
end


-------------------------------------------------------------------------------
-- Pipe management.


-- Garbage collection functions for pipe files.
--[[
    Without this, if the ui is reloaded and a pipe client file handle lost,
    the server still sees it as connected.
    Hopefully by setting close() to be called at garbage collection, this
    problem can be avoided.
    
    Lua notes: objects have metatables of implicit functions that get
    called on them. To control garbage collection, a new metatable needs
    to be set on the File with a __gc member that is the function to call.
    But this is only 5.2 onward, and x4 is 5.1.
    
    Apparently lua 5.1 is even more of a mess about this.
    https://stackoverflow.com/questions/27426704/lua-5-1-workaround-for-gc-metamethod-for-tables
    Copy this function below, use it on the pipe table, and hope.
        
    Success: with this the python server now sees the pipe properly
    closed on ui or game reload, though potentially with some delay
    that can be potentially fixed by forcing collectgarbage on
    a ui reload.
]]
local function Pipe_Garbage_Collection_Handler(pipe_table)
    -- Try to close out the file.
    if pipe_table.file ~= nil then
        -- Verification message.
        if private.print_to_log then
            DebugError("Pipe being garbage collected, file closed.")
        end
        -- TODO: repeated code with elsewhere; maybe reuse.
        success, message = pcall(function () pipe_table.file:close() end)
        if not success then
            if private.print_to_log then
                DebugError("Failed to close pipe file with error: "..message)
            end
        end
        -- TODO: maybe nil the file once closed.
    end
end


-- Call this function when the file is created to set up GC on it.
-- TODO: tighten up this code.
local function Attach_Pipe_Table_GC(pipe_table)
  
    -- Don't want to overwrite existing meta stuff, but need to use
    -- setmetatable else the gc function won't be registered, so aim
    -- to edit the existing metatable.
    local new_metatable = {}
    -- Maybe not needed; tables apparently dont have default metatables.
    --for key, value in pairs(getmetatable(pipe_table)) do
    --    new_metatable[key] = value
    --end
        
    -- Overwrite with the custom function.    
    new_metatable.__gc = Pipe_Garbage_Collection_Handler
    
    -- From stackoverflow, adjusted names.
    -- Not 100% clear on what this is doing.
    local prox = newproxy(true)
    getmetatable(prox).__gc = function() new_metatable.__gc(pipe_table) end
    pipe_table[prox] = true
    setmetatable(pipe_table, new_metatable)
    
end
        


-- Declare a pipe, setting up its initial data structure.
-- This does not attempt to open the pipe or validate it.
function Declare_Pipe(pipe_name)
    if private.pipes[pipe_name] == nil then
        -- Set up the pipe entry, with subfields.
        private.pipes[pipe_name] = {
            file = nil,
            retry_allowed = false,
            suppress_reads_when_paused = false,
            write_fifo = FIFO.new(),
            read_fifo  = FIFO.new()
        }
        
        -- Attach the garbage collector function.
        -- TODO: this used to be outside the if/then, but triggered GC
        --  many times (once for each Declare_Pipe call?). However, when
        --  this was first moved inside, x4 started crashing on reloadui,
        --  but that problem didn't persist.
        --  This may need a revisit in the future if crashes return.
        Attach_Pipe_Table_GC(private.pipes[pipe_name])
    end
           
end


-- Check if a pipe is currently open, and if not, try to open it.
-- An error will be raised if the pipe opening failed.
-- Note: if the pipe was open, but the server shut down and restarted,
-- the call to this function will look like the pipe is good when it
-- will actually fail the first access.
-- As such, if the pipe is already open, a retry_allowed flag will be
-- set, so that the first access that fails can close the pipe and
-- try to reopen it.
function Connect_Pipe(pipe_name)

    -- If the pipe not yet declared, declare it.
    Declare_Pipe(pipe_name)

    -- Check if a file is not open.
    if private.pipes[pipe_name].file == nil then
        -- Add a prefix to the pipe_name to get the path to use.
        private.pipes[pipe_name].file = winpipe.open_pipe(private.pipe_path_prefix .. pipe_name)
        
        -- If the entry is still nil, the open failed.
        if private.pipes[pipe_name].file == nil then
            -- TODO: maybe print an error to the chat window, but the concern
            -- is that scripts will keep attempting to access the pipe and
            -- will spam error messages.
            CallEventScripts("directChatMessageReceived", pipe_name..";open_pipe returned nil")
            -- A simple error description is used for the Test function.
            error("open_pipe returned nil for "..pipe_name)
        end
            
        -- Announce to the server that x4 just connected.
        -- Removed; depends on server protocol, and MD can send this signal
        -- if needed for a particular server.
        -- private.pipes[pipe_name].file:write('connected\n')
        
        -- Debug print.
        CallEventScripts("directChatMessageReceived", pipe_name..";Pipe connected in lua")
        
    else    
        -- Since no real testing done, allow one retry if an access fails.
        private.pipes[pipe_name].retry_allowed = true
    end
    
    -- TODO: test the pipe.
    -- Ideal would be an echo, sent to the server and bounced back,
    --  but the problem is that that would add delay, and the check should
    --  ideally occur on every test. Also, it may cause a data ordering
    --  problem when the user requests a read.
    -- For now, just hope things work out if the file opened, and check for
    --  errors in the Read/Write functions.
end


-- Close a pipe file.
-- If the file isn't open, this does nothing.
-- If the pipe was open, this will signal that the disconnect occurred.
function Disconnect_Pipe(pipe_name)
    if private.pipes[pipe_name].file ~= nil then
        -- Do a safe file close() attempt, ignoring errors.
        -- TODO: does this need an anon function around it?
        success, message = pcall(function () private.pipes[pipe_name].file:close() end)
        if not success then
            if private.print_to_log then
                DebugError("Failed to close pipe file with error: "..message)
            end
        end
        
        -- Unlink from the file entirely.
        private.pipes[pipe_name].file = nil
        
        -- Signal the disconnect.
        Raise_Signal(pipe_name.."_disconnected")
        CallEventScripts("directChatMessageReceived", pipe_name..";Pipe disconnected in lua")
    end
end


-- Close a pipe.
-- This sends error messages to MD for any pending pipe writes or reads.
function Close_Pipe(pipe_name)
    -- Close out the file itself.
    Disconnect_Pipe(pipe_name)
    
    -- Convenience renamings.
    local write_fifo = private.pipes[pipe_name].write_fifo
    local read_fifo  = private.pipes[pipe_name].read_fifo
    
    -- Send error signals to the MD for all pending writes and reads.
    while not FIFO.Is_Empty(write_fifo) do    
        -- Grab the access_id out of the fifo; throw away message.
        -- (Have to pull out list fields for this; base-1 indexing.)
        local access_id = FIFO.Read(write_fifo)[1]
        -- Signal the MD with an error.
        Raise_Signal('pipeWrite_complete_'..access_id, "ERROR")
    end
    
    while not FIFO.Is_Empty(read_fifo) do    
        -- Grab the access_id out of the fifo.
        local access_id = FIFO.Read(read_fifo)        
        -- Signal the MD with an error.
        Raise_Signal('pipeRead_complete_'..access_id, "ERROR")
    end
            
    -- Clear the pipe state entirely to force it to reset on new accesses.
    private.pipes[pipe_name] = nil
end


-------------------------------------------------------------------------------
-- MD callables.


-- Split a string on the first semicolon.
-- Note: works on the MD passed arrays of characters.
-- Returns two substrings.
function Split_String(this_string)

    -- Get the position of the separator.
    local position = string.find(this_string, ";")
    if position == nil then
        if private.print_to_log then
            DebugError("No ; separator found in: "..this_string)
        end
        error("Bad separator")
    end

    -- Split into pre- and post- separator strings.
    local left  = string.sub(this_string, 0, position -1)
    local right = string.sub(this_string, position +1)
    
    return left, right
end


-- MD interface: read a message from a pipe.
-- Input is one term, semicolon separated string with pipe name, callback id.
function Handle_pipeRead(_, pipe_name_id)

    -- Isolate the pipe_name and access id.
    -- Here, 'match' is set to capture all chars but semicolon ([^;]),
    --  twice with semicolon separation. The paranthesis create groupings
    --  in the result, splitting it out to two terms.
    -- Note: match doesn't work; complains about input being an 
    -- array and not string.
    --local pipe_name, access_id = string:match(pipe_name_id, "([^;]+);([^;]+)")
    
    -- Use find/sub for splitting instead.
    local pipe_name, access_id = Split_String(pipe_name_id)
       
    -- Declare the pipe, if needed.
    Declare_Pipe(pipe_name)
    
    -- Pass to the scheduler.
    Schedule_Read(pipe_name, access_id)
end


-- Schedule a pipe to be read.
function Schedule_Read(pipe_name, access_id)
    -- Add the id to the fifo.
    FIFO.Write(private.pipes[pipe_name].read_fifo, access_id)

    -- If the read polling function isn't currently active, activate it.
    if private.read_polling_active == false then
        -- Do this by hooking into the onUpdate signal, which appears to
        -- run every frame.
        -- TODO: move this to Poll_For_Reads, and call it once.
        SetScript("onUpdate", Poll_For_Reads)
        
        -- Debug printout.
        if private.print_to_chat then
            CallEventScripts("directChatMessageReceived", "LUA;Registering Poll_For_Reads")
        end
            
        private.read_polling_active = true
        
        -- Kick off a first polling call, so it doesn't wait until
        -- the next frame.
        Poll_For_Reads()
    end
end



-- MD interface: write to a pipe.
-- Input is one term, semicolon separates string with pipe name, callback id,
-- and message.
-- If signal_name was "pipeWriteSpecial", this message is treated as
-- a special command that is used to determine what to write.
function Handle_pipeWrite(signal_name, pipe_name_id_message)

    -- Isolate the pipe_name, id, value.
    -- local pipe_name, access_id, message = string:match(pipe_name_id_message, "([^;]+);([^;]+)")
    
    local pipe_name, temp = Split_String(pipe_name_id_message)
    local access_id, message = Split_String(temp)
    
    -- Handle special commands.
    -- Note: if the command not recognized, it just gets sent as-is.
    if signal_name == "pipeWriteSpecial" then
        -- Table of commands to consider.
        if message == "package.path" then
            -- Want to write out the current package.path.
            message = "package.path:"..package.path
        end
    end
        
    -- Declare the pipe, if needed.
    Declare_Pipe(pipe_name)
    
    -- Pass to the scheduler.
    Schedule_Write(pipe_name, access_id, message)    
end


-- Schedule a pipe to be written.
function Schedule_Write(pipe_name, access_id, message)
    -- Add the id and message to the fifo.
    FIFO.Write(private.pipes[pipe_name].write_fifo, {access_id, message})

    -- If the write polling function isn't currently active, activate it.
    if private.write_polling_active == false then
        -- Do this by hooking into the onUpdate signal, which appears to
        -- run every frame.
        SetScript("onUpdate", Poll_For_Writes)
        
        -- Debug printout.
        if private.print_to_chat then
            CallEventScripts("directChatMessageReceived", "LUA;Registering Poll_For_Writes")
        end
            
        private.write_polling_active = true
        
        -- Kick off a first polling call, so it doesn't wait until
        -- the next frame.
        Poll_For_Writes()
    end
end


-- MD interface: check if a pipe is connected.
-- While id isn't important for this, it is included for interface
-- consistency and code reuse in the MD.
function Handle_pipeCheck(_, pipe_name_id)
    -- Use find/sub for splitting instead.
    local pipe_name, access_id = Split_String(pipe_name_id)
    
    local success = pcall(Connect_Pipe, pipe_name)
    -- Translate to strings that match read/write returns.
    local message
    if success then
        message = "SUCCESS"
    else
        message = "ERROR"
    end
    Raise_Signal('pipeCheck_complete_'..access_id, message)
end


-- MD interface: close a pipe.
-- This will not signal back, for now.
function Handle_pipeClose(_, pipe_name)
    Close_Pipe(pipe_name)
end

-- MD interface: flag a pipe to suppress paused reads.
function Handle_pipeSuppressPausedReads(_, pipe_name)
    -- Make sure the pipe is declared already.
    Declare_Pipe(pipe_name)
    private.pipes[pipe_name].suppress_reads_when_paused = true
end

function Handle_pipeUnsuppressPausedReads(_, pipe_name)
    -- Make sure the pipe is declared already.
    Declare_Pipe(pipe_name)
    private.pipes[pipe_name].suppress_reads_when_paused = false
end


-------------------------------------------------------------------------------
-- Polling loops.


-- Generic polling function that will attempt reads on all pipes with
--  reads pending.
-- This should be scheduled to run every game frame while reads are pending.
-- If all reads satisfied, this will unschedule itself for running.
-- TODO: move the code to register this on updates internally, and just
--  require the Schedule_Read function to call this once to kick things off.
function Poll_For_Reads()
    
    -- Flag to indicate if any reads are still pending at the end
    -- of this loop.
    local activity_still_pending = false
    
    -- Loop over pipes.
    for pipe_name, state in pairs(private.pipes) do
    
        -- Loop as long as reads are pending.
        -- TODO: maybe just loop as many times as there are entries;
        --  that is safer if a bug doesn't empty the fifo.
        while not FIFO.Is_Empty(state.read_fifo) do
        
            -- Try to read.
            -- On hard failure, success if false and message is the error.
            -- On success, message is nil (pipe empty) or the message string.
            local call_success, message_or_nil = Read_Pipe(pipe_name)
            
            if call_success then 
                if message_or_nil ~= nil then
                    -- Obtained a message.
                
                    -- Grab the read_id out of the fifo.
                    local access_id = FIFO.Read(state.read_fifo)
                    
                    -- Debug print.
                    if private.print_to_chat then
                        CallEventScripts("directChatMessageReceived", pipe_name..";Read: "..message_or_nil)
                    end
                    
                    -- Maybe ignore this if paused.
                    if state.suppress_reads_when_paused and C.IsGamePaused() then
                        -- Do nothing.
                        -- TODO: an option to Ack the read to the pipe automatically,
                        --  since md cannot do it in this case.
                    else
                        -- Signal the MD with message return the data, suffixing
                        -- the signal name with the id.
                        Raise_Signal('pipeRead_complete_'..access_id, message_or_nil)
                    end                    
                    
                else
                    -- Pipe is empty.
                    -- Flag the read poller to stay active.
                    activity_still_pending = true
                    -- Stop trying to read this pipe.
                    break                    
                end
                
            else
                -- Debug print.
                if private.print_to_chat then
                    CallEventScripts("directChatMessageReceived", pipe_name..";Read error; closing")
                end
        
                -- Something went wrong, other than an empty fifo.
                -- Close out the pipe; this call will send error messages
                -- for each pending write or read.
                Close_Pipe(pipe_name)
                
                -- Stop trying to access this pipe.
                break
            end 
        end
    end
    
    -- If no reads are pending, unschedule this function.
    if activity_still_pending == false then
        RemoveScript("onUpdate", Poll_For_Reads)
        -- Debug printout.
        if private.print_to_chat then
            CallEventScripts("directChatMessageReceived", "LUA;Unregistering Poll_For_Reads")
        end
        private.read_polling_active = false
    end
end


-- Generic polling function that will attempt writes on all pipes with
--  writes pending.
-- This should be scheduled to run every game frame while writes are pending.
-- If all writes satisfied, this will unschedule itself for running.
function Poll_For_Writes()
    
    -- Flag to indicate if any activity is still pending at the end
    -- of this loop.
    local activity_still_pending = false
    
    -- Loop over pipes.
    for pipe_name, state in pairs(private.pipes) do
    
        -- Loop as long as writes are pending.
        while not FIFO.Is_Empty(state.write_fifo) do
        
            -- Peek at the next message to be sent; don't remove yet.
            -- (Have to pull out list fields for this; base-1 indexing.)
            local access_id = FIFO.Next(state.write_fifo)[1]
            local message   = FIFO.Next(state.write_fifo)[2]
        
            -- Try to write.
            -- If call_success is False, a hard error occurred with the pipe.
            -- Otherwise retval is True on succesful write, false on full pipe.
            -- (Not calling it write_success to avoid confusing it with an
            --  error string.)
            local call_success, retval = Write_Pipe(pipe_name, message)
            
            if call_success then
                -- Handle succesful writes.
                if retval then
                    -- Debug print.
                    if private.print_to_chat then
                        CallEventScripts("directChatMessageReceived", pipe_name..";Wrote: "..message)
                    end
                
                    -- Remove the entry from the fifo.
                    FIFO.Read(state.write_fifo)
                    
                    -- Signal the MD, if listening.
                    Raise_Signal('pipeWrite_complete_'..access_id, 'SUCCESS')
                    
                -- Otherwise a full pipe.
                else
                    -- Flag the poller to stay active.
                    activity_still_pending = true
                    -- Stop trying to write this pipe.
                    break
                end
                
            -- Handle errors.
            else
                -- Debug print.
                if private.print_to_chat then
                    CallEventScripts("directChatMessageReceived", pipe_name..";Write error; closing")
                end
        
                -- Something went wrong, other than a full fifo.
                -- Close out the pipe; this call will send error messages
                -- for each pending write or read.
                Close_Pipe(pipe_name)
                
                -- Stop trying to access this pipe.
                break
            end                  
        end
    end
    
    -- If no accesses are pending, unschedule this function.
    if activity_still_pending == false then
        RemoveScript("onUpdate", Poll_For_Writes)
        -- Debug printout.
        if private.print_to_chat then
            CallEventScripts("directChatMessageReceived", "LUA;Unregistering Poll_For_Writes")
        end
        private.write_polling_active = false
    end
end



-------------------------------------------------------------------------------
-- Reading interface.


-- Attempt to read a pipe, possibly throwing an error.
-- Returns a string if the read succesful.
-- Returns nil if the pipe is empty but otherwise looks good.
-- Raises an error on other problems.
function _Read_Pipe_Raw(pipe_name)
    -- Open the pipe if needed. Let errors carry upward.
    Connect_Pipe(pipe_name)
    
    -- Read in whatever is in the pipe.
    -- Apparently this either returns text, or [nil, error_message].
    -- The error_message is a formatted string for display, and will be
    --  nil if the read succeeded.
    local return_value, lua_error_message = private.pipes[pipe_name].file:read()
    
    -- In docs, GetLastError() should be ERROR_IO_PENDING for a read from a good
    --  pipe that is empty, and hence returned early.
    -- A C function has been added to call GetLastError directly, and its
    --  const brought up to here for checking.    
    -- Update: microsoft docs incomplete; this actually returns ERROR_NO_DATA.
    -- If the message is larger than the lua side buffer, returns partial
    --  data and error ERROR_MORE_DATA. TODO: look into this.
    
    if lua_error_message ~= nil then
        -- Error occurred; either pipe is bad or empty.
        if winpipe.GetLastError() == winpipe.ERROR_NO_DATA then
            -- Pipe is empty. Want to wait a while.
            return_value = nil
        else
            -- Something else went wrong.
            if private.print_to_chat then
                CallEventScripts("directChatMessageReceived", pipe_name..";read failure")
            end
            if private.print_to_log then
                DebugError(pipe_name.."; read failure, lua message: "..lua_error_message)
            end
            
            -- Raise an error in this case.
            error("read failed with error: "..lua_error_message)
        end
    end
    return return_value
end


-- Read a pipe, with possibly one retry.
-- Returns success and message, the outputs of a pcall with the same meaning.
-- On success, message is a string (pipe read succesfully) or nil (pipe empty).
function Read_Pipe(pipe_name)
    local success, message = pcall(_Read_Pipe_Raw, pipe_name)
    
    if not success then
        -- Disconnect the pipe (close file) on any hard error.
        Disconnect_Pipe(pipe_name)
            
        -- Try once more if allowed.
        if private.pipes[pipe_name].retry_allowed then
        
            -- Debug message.
            if private.print_to_chat then
                CallEventScripts("directChatMessageReceived", pipe_name..";Retrying read...")
            end
                
            -- Overwrite the success flag.
            success, message = pcall(_Read_Pipe_Raw, pipe_name)
            -- Clear the retry flag.
            private.pipes[pipe_name].retry_allowed = false
            
            if not success then
                -- Disconnect the pipe (close file) on any hard error.
                Disconnect_Pipe(pipe_name)
            end
        end
    end
    
    return success, message
end


-------------------------------------------------------------------------------
-- Writing interface.

-- Attempt to write a pipe, possibly throwing an error.
-- Returns true on succesful write, false on pipe full but otherwise good.
-- Raises an error on other problems.
function _Write_Pipe_Raw(pipe_name, message)
    -- Open the pipe if needed. Let errors carry upward.
    Connect_Pipe(pipe_name)
    
    -- Send the write request on the output pipe.
    -- Presumably this returns the number of bytes actually written, or
    -- 0 if there is an error or full pipe.
    -- Lua returns no error message for this, unlike for reads.
    local bytes_written = private.pipes[pipe_name].file:write(message)
    
    if bytes_written == 0 then
        -- Error occurred; either pipe is bad or full.
        -- TODO: what is the actual error code for this?
        --  Maybe ERROR_PIPE_BUSY ?
        -- Note: gets ERROR_NO_DATA if the server disconnected.
        -- In testing, also gets ERROR_NO_DATA if the pipe doesn't have room
        -- currently.
        -- If the pipe doesn't have enough buffer for the message, the
        -- error code is oddly 0, which isn't helpful, but that case shouldn't
        -- come up with a healthy buffer size (eg. 65k).
        -- Overall, there is no apparent way to know if a pipe is full or
        -- broken, so no way to support waiting for a full pipe to empty.
        -- Any error will be treated as a hard error for now.
        --if winpipe.GetLastError() == winpipe.ERROR_IO_PENDING then
        --    -- Pipe is full. Want to wait a while.
        --    return false
        --else
            -- Something else went wrong.
            -- Raise an error in this case.
            if private.print_to_chat then
                CallEventScripts("directChatMessageReceived", pipe_name..";write failure")
            end
            if private.print_to_log then
                DebugError(pipe_name.."; write failure, error code: "..winpipe.GetLastError())
            end
            
            error("write failed")
        --end
    end
    
    -- If here, write was succesful.
    return true
end


-- Write a pipe, with possibly one retry.
-- Returns success and retval, the outputs of a pcall with the same meaning.
-- On success, retval is a bool: true if write completed, false if pipe full.
-- On non-success, retval is the lua error.
function Write_Pipe(pipe_name, message)
    local call_success, retval = pcall(_Write_Pipe_Raw, pipe_name, message)
    
    if not call_success then
        -- Disconnect the pipe (close file) on any hard error.
        Disconnect_Pipe(pipe_name)
                
        -- Try once more if allowed.
        if private.pipes[pipe_name].retry_allowed then
            -- Debug message.
            if private.print_to_chat then
                CallEventScripts("directChatMessageReceived", pipe_name..";Retrying write...")
            end
            -- Overwrite the success flag.
            local call_success, retval = pcall(_Write_Pipe_Raw, pipe_name, message)
            -- Clear the retry flag.
            private.pipes[pipe_name].retry_allowed = false            
            
            if not success then
                -- Disconnect the pipe (close file) on any hard error.
                Disconnect_Pipe(pipe_name)
            end
        end
    end
    
    return call_success, retval
end



-------------------------------------------------------------------------------
-- Misc

-- Small test function.
-- Only run this if the external named pipes are set up and ready.
-- Note: when logging to the chat window, it was noticed that sometimes
--  the window doesn't display the latest activity, and needs to be
--  closed/reopened to see all messages.
-- Note: this doesn't have a way to capture read results through the polling
--  routine, so just do raw access (that might fail on empty fifo) for now.
-- TODO: tweak test somehow to capture read results properly.
function Test()
    local pipe_name = "\\\\.\\pipe\\x4_pipe"
    if private.print_to_chat then
        CallEventScripts("directChatMessageReceived", "pipes;Starting pipe test on "..pipe_name)
    end
    
    Declare_Pipe(pipe_name)
    Connect_Pipe(pipe_name)

    -- Individual writes
    -- (Note: cannot do "if 0" because 0 is true, water is foot,
    --  spaceships are puppy, and lua is dumb.)
    if 1 then
        Schedule_Write(pipe_name, "0", "write:[test1]5")
    end
    if 1 then
        Schedule_Write(pipe_name, "0", "write:[test2]6")
        Schedule_Write(pipe_name, "0", "write:[test3]7")
        Schedule_Write(pipe_name, "0", "write:[test4]8")
    end

    -- Transaction write/read
    if 1 then
        Schedule_Write(pipe_name, "0", "read:[test1]")
        Schedule_Read (pipe_name, "0")
    end

    -- Pipelined transactions.
    if 1 then
        Schedule_Write(pipe_name, "0", "read:[test2]")
        Schedule_Write(pipe_name, "0", "read:[test3]")
        Schedule_Write(pipe_name, "0", "read:[test4]")
        Schedule_Read (pipe_name, "0")
        Schedule_Read (pipe_name, "0")
        Schedule_Read (pipe_name, "0")
    end

    if nil then
        -- Tell the server to close (for this particular server test).
        Schedule_Write(pipe_name, "0", "close")
    end

    -- Close out the pipe.
    -- Remove this now that reads are nonblocking; it kills the pipe
    -- before reads finish.
    -- Close_Pipe(pipe_name)
end


-- Finalize with initial setup.
Init()

-- Uncomment to run a test. Used during development.
--Test()

-- TODO: consider exporting functions for other lua modules.


-- Random thoughts when overhauling the design:
--[[
    
Challenges:
    A)  To avoid game lockup when a pipe is valid but not ready, eg. full when
        writing or empty when reading, non-blocking logic is needed.
        Note: with the pipe in message mode, it appears this code doesn't
        need to worry about partially completed transfers (eg. if only 10
        of 20 bytes were written), since operations should either succeed
        completely or fail completely.
        TODO: watch this.
        
    B)  Game may be saved during an operation.  This does not directly affect
        the pipe state.  However, reloading such a save will have the MD
        expecting accesses are being carried out, while this lua interface
        has been completely reset (empty buffers, closed pipes).
        A similar situation would occur on a /reloadui command.
        
        A reasonable goal would be for all interrupted accesses to be
        flagged as failures, returning Error results upward.
        However, identification of these failures is not trivial.
        
        Some example scenarios:
        - MD made write request, the write hasn't been served yet,
          or is only partially sent.
        - MD made read request, similarly not serviced or partially complete.
        - MD made 1+ serviced write requests and is expecting responses, but
          has not yet posted the follup read requests, yet will do so soon.
        - MD made write request, not yet served, and is expecting a response
          and will post a read request soon.
                  
    Ideas:
    1)  If the client (lua) pipe is closed for any reason, the server
        should fully reset the pipe and service logic.
        Eg. if the server received a request and hasn't yet sent the
        response (waiting on compute or similar), that response should
        be cancelled out and never sent.
        
    2)  Whenever a user posts a Write which is expected to trigger a server
        response, for which the user posts a Read, this should be required
        to instead be a single Transact event (or for both Write and Read
        to be in the same frame).
        This can avoid cases where the Write is posted, game saved/reloaded,
        then Read posted, in which case the Write and server response were
        lost, leaving the Read dangling.
        If the Write/Read are posted together, the game cannot be saved in
        this danger window.
        
    3)  Apply a unique ID to all pipe transactions (eg. 3-digit integer,
        rollover at 1000, needing only 3 characters).
        IDs can be shared across all open pipes for simplicity, as long
        as rollover isn't expected to occur within a danger window of
        any given pipe.
        Messages are prefixed with this ID in a standard way.
        
        A transaction will be an x4->pipe write prefixed by this ID,
        to be followed by a pipe->x4 read prefixed with a matched ID.
        The server will be responsible for echoing this ID.
        
        The MD will handle these IDs.
        Three basic user exposed operations:
        - Write; no response expected; ID doesn't matter.
        - Read; not following any prior write; ID doesn't matter.
        - Transact; pairs a write and a read; ID is used here.

        If the user interfaces with a server that validates all written
        values, this will be done through Transact events, where the
        user can ignore or use read data as desired (eg. server may
        send a 'success'/'error').
        
        The MD can maintain a record of expected read IDs, and will match
        the received ID against that table to know which read request
        has been serviced.
        Table entries can time out with an Error if their ID not matched,
        and IDs with no table match can be ignored (assumed to pair with
        a timed out request).
                
    4)  MD api should support timeouts, so that an expected Read that
        doesn't arrive within a window will be cancelled (md side, and
        maybe lua side) with a returned error code.  If this Read later
        arrives late, when the MD is trying to read something else,
        it needs to be identified as unwanted and ignored.
        
    5)  The interface could be simplified by specifying that the entire
        thing resets, and all pending accessed cancelled, on a savegame
        reload or ui reload.
        The lua code here can signal when this file is loaded (in init())
        to the MD, plus the MD has access to game loadings.
        
        The MD doesn't need to signal anything to the lua in these cases,
        since the lua already has had its state wiped, though some thought
        is needed on how to safely reset the server in case it has a
        transaction it is still servicing and will soon send back
        a read response. That complexity is largely server-side, though.
    
    
    Overall, (5) seems like the best approach overall, with some of (1)
    for delayed reads.  (4) may not be needed if (2) is required, assuming
    the server behaves properly.  (3) is overly complex and should be
    avoided.
    
]]

--[[
A couple old, quick winapi tests.
local winapi = require("winapi")
-- Launching the calculator works!
-- winapi.shell_exec('open','calc.exe')

-- Match this name to what was opened python-side.
-- Result: test succesfully sent message to python.
local pipe = winapi.open_pipe("\\\\.\\pipe\\x4pipe")
pipe:write 'hello\n'
pipe:close()
]]


-- Old ffi related notes/attempts:
--
-- Testing using ffi for file access, since x4 doesn't include the io library.
-- One possibility (maybe overly complex):
--     https://github.com/luapower/stdio/blob/master/stdio.lua
--
-- Simpler example:
--  https://stackoverflow.com/questions/30585574/write-to-file-using-lua-ffi
-- Above failed to find fopen/etc.
--
-- New approach: 
-- Get C ffi functions from: https://github.com/jmckaskill/luaffi
-- Download lua 5.1 binary (exe)
-- Grab X4 lua dll; obtain lib file using:
--  https://stackoverflow.com/questions/9946322/how-to-generate-an-import-library-lib-file-from-a-dll
-- Edit bat file: change paths, comment out "/I"msvc"" or else comment the bool header to not define _Bool.
--  (VS2017 already defined _Bool as bool, causing errors.)
--  (Also change the output target from ffi.dll to something else.)
-- Put this dll in x4/ui/core/lualibs
-- Require it here
-- ???
-- profit
-- Result: sorta success, though the luaffi only has limited functionality
--  and nothing for opening/closing files, just stuff for writing them.
--  Hence, the "fopen" still fails to be found.
--
--
-- ffi.cdef[[
-- typedef struct {
--   char *fpos;
--   void *base;
--   unsigned short handle;
--   short flags;
--   short unget;
--   unsigned long alloc;
--   unsigned short buffincrement;
-- } FILE;
-- 
-- FILE *fopen(const char *filename, const char *mode);
-- int fprintf(FILE *stream, const char *format, ...);
-- int fclose(FILE *stream);
-- ]]
-- -- Apparently ffi.load goes after the cdef?
-- local clib = ffi.load("C:\\Steam\\steamapps\\common\\X4 Foundations\\ui\\core\\lualibs\\ffi_c.dll")
-- 
-- local f = C.fopen("ffi_test.txt", "a+")
-- C.fprintf(f, "Hello World")
-- C.fclose(f)

