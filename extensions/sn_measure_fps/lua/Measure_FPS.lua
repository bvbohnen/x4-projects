--[[
Bounces fps sample data back to md.
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

L = {}

function Init()
    -- Sampler of current fps; gets called roughly once a second.
    RegisterEvent("Measure_FPS.Get_Sample", L.Get_Sample)
end

-- Simple sampler, returning framerate and gametime.
function L.Get_Sample()
    AddUITriggeredEvent("Measure_FPS", "Sample", {
        gametime     = GetCurTime(),
        fps          = C.GetFPS().fps,
    })
end

Init()

return