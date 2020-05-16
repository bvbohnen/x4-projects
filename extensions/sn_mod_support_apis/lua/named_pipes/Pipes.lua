--[[
Functionality for opening, reading, writing to pipes.

Note: if the pipes dll fails to load, the behavior here will be to
still act as if pipes are supported, but the server is disconnected.
]]

local debug = {    
    -- If a connection message should print to chat.
    print_connect = true,
    -- If basic connection failure events should print to chat.
    print_connect_errors = false,
    -- If extra status messages should print to the chat window.
    print_to_chat = false,
    -- If status messages should print to the debuglog.
    print_to_log = false,
    }
    

-- Generic required ffi, to access C functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    bool IsGamePaused(void);
]]


-- Load in the winpipe dll, which has been set up with the necessary
-- Windows functions for working with pipes.
local winpipe = require("extensions.sn_mod_support_apis.lua.c_library.winpipe")
-- If not on windows, the above will be nil, and the pipe will be treated
-- as disconnected.

local Lib = require("extensions.sn_mod_support_apis.lua.named_pipes.Library")
FIFO = Lib.FIFO
-- Pass along any debug params.
Lib.debug.print_to_log = debug.print_to_log

local Time = require("extensions.sn_mod_support_apis.lua.time.Interface")


-- Local functions and state. These are returned on require().
local L = {
    -- Prefix to add to the pipe_name to get a file path.
    pipe_path_prefix = "\\\\.\\pipe\\",
        
    -- Flags to indicate if the Write poller and Read poller are registered
    -- to run each frame or not.
    write_polling_active = false,
    read_polling_active  = false,
}


--[[
Pipe state objects, generally alive while the link is set up.
Keys are the pipe names sent from the MD side, without path extension.
    
Each entry is a subtable with these fields:
* name
  - Name of the pipe (same as the key).
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
  - FIFO of lists of [callback IDs or function handles, continuous_read]
    for read completions.
  - Callback ID is a string.
  - Function handle is for any lua function, taking 1 argument.
  - continuous_read is a bool, if true then the current read request at the
    top of the fifo will not be removed by normal read messages.
  - Entries removed as reads complete.
  - When empty, stop trying to read this pipe.
* write_fifo
  - FIFO of lists of [callback ID, message pending writing]
  - Entries removed as writes complete succesfully or fail completely.
  - When empty, stop trying to write this pipe.
]]
-- Have this be plainly local, for easier usage.
local pipes = {}
-- Make this available to other modules that might want to peek at it.
L.pipes = pipes


-- Handle initial setup.
local function Init()
    -- Force lua to garbage collect.
    -- There may have been a File opened to a prior pipe which hasn't been
    -- GC'd yet, so the server won't yet know to reboot. New requests will
    -- then fail to be able to open a new pipe.
    -- By GC'ing here, the old File should close properly and the server
    -- can restart quicker.
    collectgarbage()
    -- Due to lua funkiness, this may need to be called twice to ensure
    -- cleanup.  (Things ran fine without a second call for a while, though
    -- this was added when trying to track down a crash bug.)
    collectgarbage()
end
-- Can run Init right away.
Init()


-- Set suppressing of read of the given pipe when the game is paused.
-- 'new_state' should be true or false.
function L.Set_Suppress_Paused_Reads(pipe_name, new_state)
    -- Make sure the pipe is declared already.
    Pipes.Declare_Pipe(pipe_name)
    pipes[pipe_name].suppress_reads_when_paused = new_state
end

-------------------------------------------------------------------------------
-- Scheduling reads/writes.

-- Schedule a pipe to be read.
function L.Schedule_Read(pipe_name, callback, continuous_read)
    -- Declare the pipe, if needed.
    L.Declare_Pipe(pipe_name)

    if continuous_read and debug.print_to_log then
        DebugError("Schedule_Read set for continuous_read of pipe "..pipe_name)
    end
    
    -- Add the callback and continuous_read flag to the fifo.
    FIFO.Write(pipes[pipe_name].read_fifo, {callback, continuous_read})


    -- If the read polling function isn't currently active, activate it.
    if L.read_polling_active == false then
        -- Do this by hooking into the onUpdate signal, which appears to
        -- run every frame. Use the time api, which has extra robustness.
        -- TODO: move this to Poll_For_Reads, and call it once.
        Time.Register_NewFrame_Callback(L.Poll_For_Reads)
        
        -- Debug printout.
        if debug.print_to_chat then
            CallEventScripts("directChatMessageReceived", "LUA;Registering Poll_For_Reads")
        end
            
        L.read_polling_active = true
        
        -- Kick off a first polling call, so it doesn't wait until
        -- the next frame.
        L.Poll_For_Reads()
    end
end


-- Schedule a pipe to be written.
function L.Schedule_Write(pipe_name, callback, message)
    -- Declare the pipe, if needed.
    L.Declare_Pipe(pipe_name)
    
    -- Add the id and message to the fifo.
    FIFO.Write(pipes[pipe_name].write_fifo, {callback, message})

    -- If the write polling function isn't currently active, activate it.
    if L.write_polling_active == false then
        -- Check every frame.
        Time.Register_NewFrame_Callback(L.Poll_For_Writes)
        
        -- Debug printout.
        if debug.print_to_chat then
            CallEventScripts("directChatMessageReceived", "LUA;Registering Poll_For_Writes")
        end
            
        L.write_polling_active = true
        
        -- Kick off a first polling call, so it doesn't wait until
        -- the next frame.
        L.Poll_For_Writes()
    end
end

-- Deschedule pending pipe reads, triggering error callbacks.
function L.Deschedule_Reads(pipe_name)
    if pipes[pipe_name] == nil then
        return
    end
    local read_fifo  = pipes[pipe_name].read_fifo

    while not FIFO.Is_Empty(read_fifo) do
        -- Grab the callback out of the fifo.
        local callback, continuous_read = unpack(FIFO.Read(state.read_fifo))
        
        -- Send back to md or lua with an error.
        if type(callback) == "string" then
            Lib.Raise_Signal('pipeRead_complete_'..callback, "ERROR")
        elseif type(callback) == "function" then
            callback("ERROR")
        end
    end
end

-- Deschedule pending pipe writes, triggering error callbacks.
function L.Deschedule_Writes(pipe_name)
    if pipes[pipe_name] == nil then
        return
    end
    local write_fifo  = pipes[pipe_name].write_fifo
    
    while not FIFO.Is_Empty(write_fifo) do    
        -- Grab the callback out of the fifo; throw away message.
        -- (Have to pull out list fields for this; base-1 indexing.)
        local callback = FIFO.Read(write_fifo)[1]

        -- Send back to md or lua with an error.
        if type(callback) == "string" then
            Lib.Raise_Signal('pipeWrite_complete_'..callback, "ERROR")
        elseif type(callback) == "function" then
            callback("ERROR")
        end
    end
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
function L.Pipe_Garbage_Collection_Handler(pipe_table)
    -- Try to close out the file.
    if pipe_table.file ~= nil then
        -- Verification message.
        if debug.print_to_log then
            DebugError("Pipe "..pipe_table.name.." being garbage collected...")
        end

        -- Note: during 3.0 beta this call started crashing the game, though
        -- calling file:close from a normal Disconnect point works fine
        -- (even if called repeatedly). Unknown reason why this stopped
        -- working; attempted fixes in the c dll failed to help.
        --success, message = pcall(function () pipe_table.file:close() end)

        -- As a workaround, instead explicitly try to message the server
        -- to restart the other end of the pipe.
        success, message = pcall(function () pipe_table.file:write("garbage_collected") end)

        if not success then
            if debug.print_to_log then
                DebugError("Failed to close with error: "..tostring(message))
            end
        end
        -- TODO: maybe nil the file once closed, though shouldn't be needed.
        pipe_table.file = nil
        if debug.print_to_log then
            DebugError("GC complete.")
        end
    end
end


-- Call this function when the file is created to set up GC on it.
-- TODO: tighten up this code.
function L.Attach_Pipe_Table_GC(pipe_table)
  
    -- Don't want to overwrite existing meta stuff, but need to use
    -- setmetatable else the gc function won't be registered, so aim
    -- to edit the existing metatable.
    local new_metatable = {}
    -- Maybe not needed; tables apparently dont have default metatables.
    --for key, value in pairs(getmetatable(pipe_table)) do
    --    new_metatable[key] = value
    --end
        
    -- Overwrite with the custom function.    
    new_metatable.__gc = L.Pipe_Garbage_Collection_Handler
    
    -- From stackoverflow, adjusted names.
    -- Not 100% clear on what this is doing.
    local prox = newproxy(true)
    getmetatable(prox).__gc = function() new_metatable.__gc(pipe_table) end
    pipe_table[prox] = true
    setmetatable(pipe_table, new_metatable)
    
end
        


-- Declare a pipe, setting up its initial data structure.
-- This does not attempt to open the pipe or validate it.
function L.Declare_Pipe(pipe_name)
    if pipes[pipe_name] == nil then
        -- Set up the pipe entry, with subfields.
        pipes[pipe_name] = {
            name = pipe_name,
            file = nil,
            retry_allowed = false,
            suppress_reads_when_paused = false,
            write_fifo = FIFO.new(),
            read_fifo  = FIFO.new(),
        }
        
        -- Attach the garbage collector function.
        -- TODO: this used to be outside the if/then, but triggered GC
        --  many times (once for each Declare_Pipe call?). However, when
        --  this was first moved inside, x4 started crashing on reloadui,
        --  but that problem didn't persist.
        --  This may need a revisit in the future if crashes return.
        L.Attach_Pipe_Table_GC(pipes[pipe_name])
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
function L.Connect_Pipe(pipe_name)

    -- If the pipe not yet declared, declare it.
    L.Declare_Pipe(pipe_name)

    -- Check if a file is not open.
    if pipes[pipe_name].file == nil then

        if winpipe ~= nil then
            -- Add a prefix to the pipe_name to get the path to use.
            pipes[pipe_name].file = winpipe.open_pipe(L.pipe_path_prefix .. pipe_name)
        end

        -- If the entry is still nil, the open failed.
        if pipes[pipe_name].file == nil then
            if debug.print_connect_errors then
                CallEventScripts("directChatMessageReceived", pipe_name..";open_pipe returned nil")
            end
            -- A simple error description is used for the Test function.
            error("open_pipe returned nil for "..pipe_name)
        end
        -- Announce to the server that x4 just connected.
        -- Removed; depends on server protocol, and MD can send this signal
        -- if needed for a particular server.
        -- pipes[pipe_name].file:write('connected\n')
        
        -- Debug print.
        if debug.print_connect then
            CallEventScripts("directChatMessageReceived", pipe_name..";Pipe connected in lua")
        end
        if debug.print_to_log then
            DebugError(pipe_name.." connected in lua")
        end
        
    else    
        -- Since no real testing done, allow one retry if an access fails.
        pipes[pipe_name].retry_allowed = true
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
function L.Disconnect_Pipe(pipe_name)
    if pipes[pipe_name].file ~= nil then
        -- Do a safe file close() attempt, ignoring errors.
        success, message = pcall(function () pipes[pipe_name].file:close() end)
        if not success then
            if debug.print_to_log then
                DebugError("Failed to close pipe file with error: "..tostring(message))
            end
        end
        
        -- Unlink from the file entirely.
        pipes[pipe_name].file = nil
        
        -- Signal the disconnect.
        Lib.Raise_Signal(pipe_name.."_disconnected")
        if debug.print_connect_errors then
            CallEventScripts("directChatMessageReceived", pipe_name..";Pipe disconnected in lua")
        end
        if debug.print_to_log then
            DebugError(pipe_name.." disconnected in lua")
        end
    end
end


-- Close a pipe.
-- This sends error messages to MD for any pending pipe writes or reads.
function L.Close_Pipe(pipe_name)
    -- Close out the file itself.
    L.Disconnect_Pipe(pipe_name)
    
    -- Convenience renamings.
    local write_fifo = pipes[pipe_name].write_fifo
    local read_fifo  = pipes[pipe_name].read_fifo
    
    -- Send error signals to the MD for all pending writes and reads.
    while not FIFO.Is_Empty(write_fifo) do    
        -- Grab the callback out of the fifo; throw away message.
        -- (Have to pull out list fields for this; base-1 indexing.)
        local callback = FIFO.Read(write_fifo)[1]

        -- Send back to md or lua with an error.
        if type(callback) == "string" then
            Lib.Raise_Signal('pipeWrite_complete_'..callback, "ERROR")
        elseif type(callback) == "function" then
            callback("ERROR")
        end
    end
    
    while not FIFO.Is_Empty(read_fifo) do
        -- Grab the callback out of the fifo.
        local callback, continuous_read = unpack(FIFO.Read(state.read_fifo))
        
        -- Send back to md or lua with an error.
        if type(callback) == "string" then
            Lib.Raise_Signal('pipeRead_complete_'..callback, "ERROR")
        elseif type(callback) == "function" then
            callback("ERROR")
        end
    end
            
    -- Clear the pipe state entirely to force it to reset on new accesses.
    pipes[pipe_name] = nil
end


-------------------------------------------------------------------------------
-- Polling loops.


-- Generic polling function that will attempt reads on all pipes with
--  reads pending.
-- This should be scheduled to run every game frame while reads are pending.
-- If all reads satisfied, this will unschedule itself for running.
-- TODO: move the code to register this on updates internally, and just
--  require the Schedule_Read function to call this once to kick things off.
function L.Poll_For_Reads()
    
    -- Flag to indicate if any reads are still pending at the end
    -- of this loop.
    local activity_still_pending = false
    
    -- Loop over pipes.
    for pipe_name, state in pairs(pipes) do
    
        -- Loop as long as reads are pending.
        -- TODO: maybe just loop as many times as there are entries;
        --  that is safer if a bug doesn't empty the fifo.
        while not FIFO.Is_Empty(state.read_fifo) do
        
            -- Try to read.
            -- On hard failure, success if false and message is the error.
            -- On success, message is nil (pipe empty) or the message string.
            local call_success, message_or_nil = L.Read_Pipe(pipe_name)
            
            if call_success then 
                if message_or_nil ~= nil then
                    -- Obtained a message.
                
                    -- Grab the read_id out of the fifo.
                    -- Don't remove if in continuous read mode.
                    local callback, continuous_read = unpack(FIFO.Next(state.read_fifo))
                    if not continuous_read then
                        FIFO.Read(state.read_fifo)
                    end
                    
                    -- Debug print.
                    if debug.print_to_chat then
                        CallEventScripts("directChatMessageReceived", pipe_name..";Read: "..message_or_nil)
                    end
                    
                    -- Maybe ignore this if paused.
                    if state.suppress_reads_when_paused and C.IsGamePaused() then
                        -- Do nothing.
                        -- TODO: an option to Ack the read to the pipe automatically,
                        --  since md cannot do it in this case.
                    else
                        if type(callback) == "string" then
                            -- Signal the MD with message return the data,
                            -- suffixing the signal name with the id.
                            Lib.Raise_Signal('pipeRead_complete_'..callback, message_or_nil)
                        -- Callback a lua function if listening.
                        elseif type(callback) == "function" then
                            callback(message_or_nil)
                        end
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
                if debug.print_to_chat then
                    CallEventScripts("directChatMessageReceived", pipe_name..";Read error; closing")
                end
        
                -- Something went wrong, other than an empty fifo.
                -- Close out the pipe; this call will send error messages
                -- for each pending write or read.
                L.Close_Pipe(pipe_name)
                
                -- Stop trying to access this pipe.
                break
            end 
        end
    end
    
    -- If no reads are pending, unschedule this function.
    if activity_still_pending == false then
        --RemoveScript("onUpdate", L.Poll_For_Reads)
        Time.Unregister_NewFrame_Callback(L.Poll_For_Reads)
        -- Debug printout.
        if debug.print_to_chat then
            CallEventScripts("directChatMessageReceived", "LUA;Unregistering Poll_For_Reads")
        end
        L.read_polling_active = false
    end
end


-- Generic polling function that will attempt writes on all pipes with
--  writes pending.
-- This should be scheduled to run every game frame while writes are pending.
-- If all writes satisfied, this will unschedule itself for running.
function L.Poll_For_Writes()
    
    -- Flag to indicate if any activity is still pending at the end
    -- of this loop.
    local activity_still_pending = false
    
    -- Loop over pipes.
    for pipe_name, state in pairs(pipes) do
    
        -- Loop as long as writes are pending.
        while not FIFO.Is_Empty(state.write_fifo) do
        
            -- Peek at the next message to be sent; don't remove yet.
            -- (Have to pull out list fields for this; base-1 indexing.)
            local callback = FIFO.Next(state.write_fifo)[1]
            local message   = FIFO.Next(state.write_fifo)[2]
        
            -- Try to write.
            -- If call_success is False, a hard error occurred with the pipe.
            -- Otherwise retval is True on succesful write, false on full pipe.
            -- (Not calling it write_success to avoid confusing it with an
            --  error string.)
            local call_success, retval = L.Write_Pipe(pipe_name, message)
            
            if call_success then
                -- Handle succesful writes.
                if retval then
                    -- Debug print.
                    if debug.print_to_chat then
                        CallEventScripts("directChatMessageReceived", pipe_name..";Wrote: "..message)
                    end
                    if debug.print_to_log then
                        DebugError(pipe_name.." Wrote: '"..message.."' with callback "..tostring(callback))
                    end
                    
                
                    -- Remove the entry from the fifo.
                    FIFO.Read(state.write_fifo)
                    
                    -- Signal the MD, if listening.
                    if type(callback) == "string" then
                        Lib.Raise_Signal('pipeWrite_complete_'..callback, 'SUCCESS')
                    -- Callback a lua function if listening.
                    elseif type(callback) == "function" then
                        callback('SUCCESS')
                    end
                    
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
                if debug.print_to_chat then
                    CallEventScripts("directChatMessageReceived", pipe_name..";Write error; closing")
                end
        
                -- Something went wrong, other than a full fifo.
                -- Close out the pipe; this call will send error messages
                -- for each pending write or read.
                L.Close_Pipe(pipe_name)
                
                -- Stop trying to access this pipe.
                break
            end                  
        end
    end
    
    -- If no accesses are pending, unschedule this function.
    if activity_still_pending == false then
        --RemoveScript("onUpdate", L.Poll_For_Writes)
        Time.Unregister_NewFrame_Callback(L.Poll_For_Writes)
        -- Debug printout.
        if debug.print_to_chat then
            CallEventScripts("directChatMessageReceived", "LUA;Unregistering Poll_For_Writes")
        end
        L.write_polling_active = false
    end
end



-------------------------------------------------------------------------------
-- Reading interface.


-- Attempt to read a pipe, possibly throwing an error.
-- Returns a string if the read succesful.
-- Returns nil if the pipe is empty but otherwise looks good.
-- Raises an error on other problems.
function L._Read_Pipe_Raw(pipe_name)
    -- Open the pipe if needed. Let errors carry upward.
    L.Connect_Pipe(pipe_name)
    
    -- Read in whatever is in the pipe.
    -- Apparently this either returns text, or [nil, error_message].
    -- The error_message is a formatted string for display, and will be
    --  nil if the read succeeded.
    local return_value, lua_error_message = pipes[pipe_name].file:read()
    
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
            if debug.print_to_chat then
                CallEventScripts("directChatMessageReceived", pipe_name..";read failure")
            end
            if debug.print_to_log then
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
function L.Read_Pipe(pipe_name)
    local success, message = pcall(L._Read_Pipe_Raw, pipe_name)
    
    if not success then
        -- Disconnect the pipe (close file) on any hard error.
        L.Disconnect_Pipe(pipe_name)
            
        -- Try once more if allowed.
        if pipes[pipe_name].retry_allowed then
        
            -- Debug message.
            if debug.print_to_chat then
                CallEventScripts("directChatMessageReceived", pipe_name..";Retrying read...")
            end
                
            -- Overwrite the success flag.
            success, message = pcall(L._Read_Pipe_Raw, pipe_name)
            
            if not success then
                -- Disconnect the pipe (close file) on any hard error.
                L.Disconnect_Pipe(pipe_name)
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
function L._Write_Pipe_Raw(pipe_name, message)
    -- Open the pipe if needed. Let errors carry upward.
    L.Connect_Pipe(pipe_name)
    
    -- Send the write request on the output pipe.
    -- Presumably this returns the number of bytes actually written, or
    -- 0 if there is an error or full pipe.
    -- Lua returns no error message for this, unlike for reads.
    local bytes_written = pipes[pipe_name].file:write(message)
    
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
            if debug.print_to_chat then
                CallEventScripts("directChatMessageReceived", pipe_name..";write failure")
            end
            if debug.print_to_log then
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
function L.Write_Pipe(pipe_name, message)
    local call_success, retval = pcall(L._Write_Pipe_Raw, pipe_name, message)
    
    if not call_success then
        -- Disconnect the pipe (close file) on any hard error.
        L.Disconnect_Pipe(pipe_name)
                
        -- Try once more if allowed.
        if pipes[pipe_name].retry_allowed then
            -- Debug message.
            if debug.print_to_chat then
                CallEventScripts("directChatMessageReceived", pipe_name..";Retrying write...")
            end
            -- Overwrite the success flag.
            local call_success, retval = pcall(L._Write_Pipe_Raw, pipe_name, message)       
            
            if not success then
                -- Disconnect the pipe (close file) on any hard error.
                L.Disconnect_Pipe(pipe_name)
            end
        end
    end
    
    return call_success, retval
end


-- Test connect/disconnect. Host should be running when x4 loads.
-- This will not try to reconnect right away, since the host is
-- expected to have some delay to detect disconnection and restart.
local function Test_Disconnect()
    local pipe_name = 'x4_python_host'
    DebugError("Testing Connect_Pipe")
    L.Connect_Pipe(pipe_name)
    DebugError("Testing Disconnect_Pipe")
    L.Disconnect_Pipe(pipe_name)
end
-- Uncomment to enable this test.
-- Test_Disconnect()


-- Pass all local functions back on require() for now.
-- TODO: maybe be selective.
return L