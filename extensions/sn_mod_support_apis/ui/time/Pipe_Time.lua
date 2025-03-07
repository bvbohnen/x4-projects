local module = Lua_Loader.define("extensions.sn_mod_support_apis.lua.time.Pipe_Time",function(require)
--[[
Python pipe interface functions.
Split into a separate file so that the pipe api can import the general
frame update functions, and this can import the pipe api, without
an import loop.
]]

-- TODO: conditionally include pipes api. For now hardcode.
local pipes_api = require("extensions.sn_mod_support_apis.lua.time.Interface")

-- Table of local functions and data.
local L = {
    debug = false,
    -- Name of the pipe for higher precision timing.
    pipe_name = 'x4_time',
    }
    

function Init()
    -- Pipe interfacing functions.    
    RegisterEvent("Time.getSystemTime", L.Get_System_Time)
    RegisterEvent("Time.tic"          , L.Tic)
    RegisterEvent("Time.toc"          , L.Toc)
end

-- Raise an event for md to capture.
function L.Raise_Signal(name, return_value)
    AddUITriggeredEvent("Time", name, return_value)
end


function L.Get_System_Time(_, id)
    -- Send a request to the pipe api. Optimistically assume the server
    -- is running. Ignore result.
    pipes_api.Schedule_Write(L.pipe_name, nil, 'get')

    -- Read the response, providing a callback function.
    pipes_api.Schedule_Read(
        L.pipe_name, 
        function(message)
            -- Punt on errors for now.
            if message ~= 'ERROR' then
                -- Put the time in the log.
                DebugError(string.format("Request id '%s' system time: %f seconds", id, message))
                -- Return to md.
                L.Raise_Signal(id, message)
            else
                DebugError("Time.Get_System_Time failed; pipe not connected.")
            end
        end
        )
end


function L.Tic(_, id)
    -- Send a request to the pipe api.
    pipes_api.Schedule_Write(L.pipe_name, nil, 'tic')
end


function L.Toc(_, id)
    -- Send a request to the pipe api.
    pipes_api.Schedule_Write(L.pipe_name, nil, 'toc')
    
    -- Read the response, providing a callback function.
    pipes_api.Schedule_Read(
        L.pipe_name, 
        function(message)
            -- Punt on errors for now.
            if message ~= 'ERROR' then
                -- Put the time in the log.
                DebugError(string.format("Toc id '%s': %f seconds", id, message))
                -- Return to md.
                L.Raise_Signal(id, message)
            else
                DebugError("Time.Toc failed; pipe not connected.")
            end
        end
        )
end

return nil,Init
end)