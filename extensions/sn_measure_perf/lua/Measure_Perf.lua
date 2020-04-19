--[[
    Simple lua-side data sampler, for information that is easiest
    to get with lua functions.
]]

local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef struct {
        double fps;
        double moveTime;
        double renderTime;
        double gpuTime;
    } FPSDetails;
    FPSDetails GetFPS();
]]

-- Table of local functions and data.
local L = {
    debug = false,
    }

function Init()
    -- Set up all unique events.
    RegisterEvent("Measure_Perf.Get_Sample", L.Get_Sample)
end


function L.Get_Sample()
    
    AddUITriggeredEvent("Measure_Perf", "Sample", {
        gametime = GetCurTime(),
        fps      = C.GetFPS().fps,
    })
end

Init()

return