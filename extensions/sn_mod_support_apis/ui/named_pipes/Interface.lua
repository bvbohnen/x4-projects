Lua_Loader.define("extensions.sn_mod_support_apis.lua.named_pipes.Interface",function(require)
--[[
MD to Lua Pipe API

Lua support for communicating through windows named pipes with
an external process, with the help of the winpipe api dll, which
wraps select windows OS functions.

The external process will be responsible for serving pipes.
X4 will act purely as a client.

Note: if you are using the higher level MD API, you don't need to
worry about these lua details.

Behavior:
- MD triggers lua functions using raise_lua_event.
- Lua responds to MD by signalling a ui event.
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

- Complex request args will be passed from md to lua using a player
  blackboard var $pipe_api_args.
- A Process_Command signal may accompany multiple command args due to
  md->lua latency in a frame.
- Each Process_Command will consume only one command args entry, just in
  case ordering of these lua signals matters relative to something elsewhere.


Other lua modules may use this api to access pipes as well. Behavior is
largely the same as for the MD interface, except that results will be
returned to lua callback functions instead of being signalled to MD.
It may be imported using a require statement:
```lua
  local pipes_api = require('extensions.sn_named_pipes_api.lua.Interface')
```

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


-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef uint64_t UniverseID;
    UniverseID GetPlayerID(void);   
]]

-- Import lib functions and pipe management.
local Lib = require("extensions.sn_mod_support_apis.lua.named_pipes.Library")
local Pipes = require("extensions.sn_mod_support_apis.lua.named_pipes.Pipes")
local Print_Table = require("extensions.sn_mod_support_apis.lua.Library").Print_Table


-- Table of local functions or data.
local L = {
    -- Any command arguments not yet processed.
    queued_args = {},
    -- Fields holding booleans.
    bool_fields = {'continuous'},
}


-- Handle initial setup.
local function Init()
    -- Generic command handler.
    RegisterEvent("pipeProcessCommand", L.Process_Command)
    
    -- Cache the player component id.
    L.player_id = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
                
    -- Clear any old command args.
    SetNPCBlackboard(L.player_id, "$pipe_api_args", nil)

    -- Signal to MD that the lua has reloaded.
    Lib.Raise_Signal('reloaded')
end


-- Get args from the player blackboard, and return the next entry.
function L.Get_Next_Args()
    -- If the list of queued args is empty, grab more from md.
    if #L.queued_args == 0 then
    
        -- Args are attached to the player component object.
        local args_list = GetNPCBlackboard(L.player_id, "$pipe_api_args")
        
        -- Loop over it and move entries to the queue.
        for i, v in ipairs(args_list) do
            table.insert(L.queued_args, v)
        end
        
        -- Clear the md var by writing nil.
        SetNPCBlackboard(L.player_id, "$pipe_api_args", nil)
    end
    --DebugError("num args: "..tostring(#L.queued_args))
    
    -- Pop the first table entry.
    local args = table.remove(L.queued_args, 1)

    -- Check args for any 0 entries on bool fields, convert to false.
    for _, field in ipairs(L.bool_fields) do
        if args[field] == 0 then
            args[field] = false
        end
    end

    return args
end

-- Generic command handler.
-- When this is signalled, there may be multiple commands queued.
function L.Process_Command()
    local args = L.Get_Next_Args()

    if Lib.debug.print_to_log then
        Print_Table(args, "Pipes.Interface.Process_Command args")
    end
    
    if args.command == "Read" then
        Pipes.Schedule_Read(args.pipe_name, args.access_id, args.continuous)

    elseif args.command == "Write" then
        Pipes.Schedule_Write(args.pipe_name, args.access_id, args.message)

    elseif args.command == "WriteSpecial" then    
        -- Handle special commands.
        -- Note: if the command not recognized, it just gets sent as-is.
        if args.message == "package.path" then
            -- Want to write out the current package.path.
            args.message = "package.path:"..package.path
        end        
        -- Pass to the scheduler.
        Pipes.Schedule_Write(args.pipe_name, args.access_id, args.message) 

    elseif args.command == "CancelReads" then
        Pipes.Deschedule_Reads(args.pipe_name)

    elseif args.command == "CancelWrites" then
        Pipes.Deschedule_Writes(args.pipe_name)

    elseif args.command == "Check" then    
        -- Check if a pipe is connected.
    
        local success = pcall(Pipes.Connect_Pipe, args.pipe_name)
        -- Translate to strings that match read/write returns.
        local message
        if success then
            message = "SUCCESS"
        else
            message = "ERROR"
        end
        -- Send back to md.
        if type(args.callback) == "string" then
            L.Raise_Signal('pipeCheck_complete_'..args.callback, message)
        end

    elseif args.command == "Close" then
        Pipes.Close_Pipe(args.pipe_name)
        
    elseif args.command == "SuppressPausedReads" then
        Pipes.Set_Suppress_Paused_Reads(args.pipe_name, true)

    elseif args.command == "UnsuppressPausedReads" then
        Pipes.Set_Suppress_Paused_Reads(args.pipe_name, false)
    end
end


-- On require(), just return the Pipes functions to other lua modules.
return Pipes, Init
end)
