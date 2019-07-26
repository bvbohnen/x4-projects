--[[
Support for communicating through windows named pipes with
an external process.

The external process will be responsible for serving pipes.
X4 will act purely as a client.


Reading:
    Start with a trigger:
    
        <raise_lua_event name="'pipeRead'" param="'<pipe_name>;<id>'"/>
        
    Capture completion with a new subcue (don't instantiate if already inside
    an instance), conditioned on response signal:
    
        <event_object_signalled 
            object="player.galaxy" 
            param="'pipeRead_complete_<id>'"/>
        
    The returned value will be in "event.param2":
    
        <set_value name="$pipe_read_value" exact="event.param2" />
        
    <pipe_name> should be replaced with the full path name of the pipe
    being connected to. Example: "\\.\pipe\x4_pipe", with doubled backslashes
    as needed for escapes in the string creation.
    <id> is a string that uniquely identifies this read from other accesses
    that may be pending in the same time frame.
    
    If the read fails due to a closed pipe, a return signal will still be sent,
    but param2 will contain "ERROR".
    
    
Writing:
    The message to be sent will be suffixed to the pipe_name and id, separated
    by semicolons.
    
        <raise_lua_event name="'pipeWrite'" param="'<pipe_name>;<id>;message'"/>    
            
    Optionally capture the response signal, indicating success or failure.
    
        <event_object_signalled 
            object="player.galaxy" 
            param="'pipeWrite_complete_<id>'"/>
    
    The returned code is "ERROR" on an error, else "SUCCESS".
    
        <set_value name="$error" exact="event.param2" />
        
        
    
Check if pipes open:
    Test if the pipe is open in a similar way to reading:
    
        <raise_lua_event name="'pipeCheck'" param="'<pipe_name>'" />
    
        <event_object_signalled 
            object="player.galaxy" 
            param="'pipeCheck_complete_<pipe_name>'"/>
            
    In this case, event.param2 holds true if the pipe appears to be
    succesfully opened, false if not. Note that this does not robustly
    test the pipe.
        
    
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
    

    
Note:
    The external pipe names are (with extra lua escape slashes):
        "\\\\.\\pipe\\x4input"  (\\.\pipe\x4_input)
        "\\\\.\\pipe\\x4output" (\\.\pipe\x4_output)
]]


-- Generic required ffi.
local ffi = require("ffi")
local C = ffi.C


-- This will use winpipe, based on winapi and trimmed down to just the
--  needed pipe functions.
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

local Poll_For_Reads
local Poll_For_Writes

local _Read_Pipe_Raw
local Read_Pipe
local _Write_Pipe_Raw
local Write_Pipe

local Test


-- Match the style of egosoft lua, with a private table containing
-- static variables.
-- For safety, most higher level state (transmit buffers and such) will
-- be kept at the MD level, to be recorded in saved games.
local private = {

    --[[
    Pipe state objects, generally alive while the link is set up.
    Keys are the basic pipe names sent from the MD side, with full path
    extension.
    
    Each entry is subtable with these fields:
    * file
      - File object to read/write/close
    * retry_allowed
      - Bool, if a failed access is allowed one retry.
      - Set prior to an access attempt if the pipe was already open, but
        is not known to be still connected.
      - On a retry attempt, this flag should be cleared.
    * read_fifo
      - FIFO of callback IDs for read completions.
      - Callback ID is a string.
      - Index 0 is next read to service.
      - Entries removed as reads complete.
      - When empty, stop trying to read.
    * write_fifo
      - FIFO of lists of [callback ID, message pending writing]
      - Index 0 is the next write to service.
      - Entries removed as writes complete succesfully or fail completely.
      - When empty, stop trying to write.
    ]]
    pipes = { },

    -- Flags to indicate if the Write poller and Read poller are registered
    -- to run each frame or not.
    write_polling_active = false,
    read_polling_active  = false,
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
    -- Connect the events to the matching functions.
    RegisterEvent("pipeRead", Handle_pipeRead)
    RegisterEvent("pipeWrite", Handle_pipeWrite)
    RegisterEvent("pipeCheck", Handle_pipeCheck)
    RegisterEvent("pipeClose", Handle_pipeClose)
        
    -- Signal to MD that the lua has reloaded.
    Raise_Signal('lua_named_pipe_api_loaded')
end


-- Shared function to raise a named galaxy signal with an optional
-- return value.
function Raise_Signal(name, return_value)
    -- Clumsy way to lookup the galaxy.
    local player = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    local galaxy = GetComponentData(player, "galaxyid" )
    SignalObject( galaxy, name, return_value)
end


-------------------------------------------------------------------------------
-- Pipe management.

-- Declare a pipe, setting up its initial data structure.
-- This does not attempt to open the pipe or validate it.
function Declare_Pipe(pipe_name)
    if private.pipes[pipe_name] == nil then
        -- Set up the pipe entry, with subfields.
        private.pipes[pipe_name] = {
            file = nil,
            retry_allowed = false,
            write_fifo = FIFO.new(),
            read_fifo  = FIFO.new()
        }
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

    -- Assume the pipe has been declared, and state data available.

    -- Check if a file is not open.
    if private.pipes[pipe_name].file == nil then
        private.pipes[pipe_name].file = winpipe.open_pipe(pipe_name)
        
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
        -- TODO
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
function Close_File(pipe_name)
    -- Do a safe file close() attempt, ignoring errors.
    pcall(function () private.pipes[pipe_name].file.close() end)
    -- Unlink from the file entirely.
    private.pipes[pipe_name].file = nil
    CallEventScripts("directChatMessageReceived", pipe_name..";Pipe disconnected in lua")
end


-- Close a pipe.
-- This sends error messages to MD for any pending pipe writes or reads.
function Close_Pipe(pipe_name)
    -- Close out the file itself.
    Close_File(pipe_name)
    
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
        -- TODO: error in message construction.
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
        CallEventScripts("directChatMessageReceived", "pipe;Registering Poll_For_Reads")
        private.read_polling_active = true
        
        -- Kick off a first polling call, so it doesn't wait until
        -- the next frame.
        Poll_For_Reads()
    end
end



-- MD interface: write to a pipe.
-- Input is one term, semicolon separates string with pipe name, callback id,
-- and message.
function Handle_pipeWrite(_, pipe_name_id_message)

    -- Isolate the pipe_name, id, value.
    -- local pipe_name, access_id, message = string:match(pipe_name_id_message, "([^;]+);([^;]+)")
    
    local pipe_name, temp = Split_String(pipe_name_id_message)
    local access_id, message = Split_String(temp)
        
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
        CallEventScripts("directChatMessageReceived", "pipe;Registering Poll_For_Writes")
        private.write_polling_active = true
        
        -- Kick off a first polling call, so it doesn't wait until
        -- the next frame.
        Poll_For_Writes()
    end
end


-- MD interface: check if a pipe is connected.
function Handle_pipeCheck(pipe_name)
    local success = pcall(Connect_Pipe, pipe_name)
    Raise_Signal('pipeCheck_complete_pipe_name', success)
end


-- MD interface: close a pipe.
-- This will not signal back, for now.
function Handle_pipeClose(pipe_name)
    Close_Pipe(pipe_name)
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
                    local read_id = FIFO.Read(state.read_fifo)
                    
                    -- Debug print.
                    CallEventScripts("directChatMessageReceived", pipe_name..";Read: "..message_or_nil)                
                    
                    -- Signal the MD with message return the data, suffixing
                    -- the signal name with the id.
                    Raise_Signal('pipeRead_complete_'..read_id, message_or_nil)
                    
                else
                    -- Pipe is empty.
                    -- Flag the read poller to stay active.
                    activity_still_pending = true
                    -- Stop trying to read this pipe.
                    break                    
                end
                
            else
                -- Debug print.
                CallEventScripts("directChatMessageReceived", pipe_name..";Read error; closing")
        
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
        CallEventScripts("directChatMessageReceived", "pipe;Unregistering Poll_For_Reads")
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
            -- Note: both return flags will never be true at the same time.
            -- If both are false, the pipe was full.
            local write_success, error_occurred = Write_Pipe(pipe_name, message)
            
            -- Handle succesful writes.
            if write_success then
                -- Debug print.
                CallEventScripts("directChatMessageReceived", pipe_name..";Wrote: "..message)
            
                -- Empty the entry from the fifo.
                FIFO.Read(state.write_fifo)
                
                -- Signal the MD, if listening.
                Raise_Signal('pipeWrite_complete_'..access_id, 'SUCCESS')
                                
            -- Handle errors.
            elseif write_success then
                -- Debug print.
                CallEventScripts("directChatMessageReceived", pipe_name..";Write error; closing")
        
                -- Something went wrong, other than a full fifo.
                -- Close out the pipe; this call will send error messages
                -- for each pending write or read.
                Close_Pipe(pipe_name)
                
                -- Stop trying to access this pipe.
                break
            
            -- Otherwise a full pipe.
            else
                -- Flag the poller to stay active.
                activity_still_pending = true
                -- Stop trying to write this pipe.
                break
            end                    
        end
    end
    
    -- If no accesses are pending, unschedule this function.
    if activity_still_pending == false then
        RemoveScript("onUpdate", Poll_For_Writes)
        -- Debug printout.
        CallEventScripts("directChatMessageReceived", "pipe;Unregistering Poll_For_Writes")
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
            CallEventScripts("directChatMessageReceived", pipe_name..";read failure")
            DebugError(pipe_name.."; read failure, lua message: "..lua_error_message)
            -- Always disconnect the pipe in this case; assume unrecoverable.
            Disconnect_Pipe(pipe_name)
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
        -- Try once more if allowed.
        if private.pipes[pipe_name].retry_allowed then
            -- Debug message.
            CallEventScripts("directChatMessageReceived", pipe_name..";Retrying read...")
            -- Overwrite the success flag.
            success, message = pcall(_Read_Pipe_Raw, pipe_name)
            -- Clear the retry flag.
            private.pipes[pipe_name].retry_allowed = false
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
    
    if not bytes_written then
        -- Error occurred; either pipe is bad or full.
        -- TODO: what is the actual error code for this?
        --  Maybe ERROR_PIPE_BUSY ?
        if winpipe.GetLastError() == winpipe.ERROR_IO_PENDING then
            -- Pipe is full. Want to wait a while.
            return false
        else
            -- Something else went wrong.
            -- Raise an error in this case.
            CallEventScripts("directChatMessageReceived", pipe_name..";write failure")
            DebugError(pipe_name.."; write failure, error code: "..winpipe.GetLastError())
            -- Always disconnect the pipe in this case; assume unrecoverable.
            Disconnect_Pipe(pipe_name)
            error("write failed")
        end
    end
    
    -- If here, write was succesful.
    return true
end


-- Write a pipe, with possibly one retry.
-- Returns write_success, error_occurred, boolean flags.
-- If both flags are false, the fifo was full but otherwise okay.
-- Both flags won't be true.
function Write_Pipe(pipe_name, message)
    local call_success, write_success = pcall(_Write_Pipe_Raw, pipe_name, message)
    
    if not call_success then
        -- Try once more if allowed.
        if private.pipes[pipe_name].retry_allowed then
            -- Debug message.
            CallEventScripts("directChatMessageReceived", pipe_name..";Retrying write...")
            -- Overwrite the success flag.
            local call_success, write_success = pcall(_Write_Pipe_Raw, pipe_name, message)
            -- Clear the retry flag.
            private.pipes[pipe_name].retry_allowed = false
        end
    end
    
    -- Flip the flags around for the response.
    -- Write success is first; call_success is inverted to indicate error.
    return write_success, not call_success
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
    CallEventScripts("directChatMessageReceived", "pipes;Starting pipe test on "..pipe_name)
    
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

