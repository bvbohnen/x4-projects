--[[
    Lua side of hotkey api, for doing things only lua can do.
]]

-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
]]


local debugger = {
    verbose = false,
}

-- Import library functions for strings and tables.
local Lib  = require("extensions.sn_mod_support_apis.lua_interface").Library
local Time = require("extensions.sn_mod_support_apis.lua_interface").Time

-- Table of locals.
local L = {}


-- Global config customization.
-- A lot of ui config is in widget_fullscreen.lua, where its 'config'
-- table is global, allowing editing of various values.
-- Rename the global config, to not interfere with local.
local global_config = config
if global_config == nil then
    error("Failed to find global config from widget_fullscreen.lua")
end


function L.Init()    
    RegisterEvent("SN_Hotkeys.zoom_in", L.Handle_Zoom_In)
end


-- Zoom-in.
--[[
General behavior will be to roughly match X3:
- Each press increases zoom stepping (up from 1x), on some granularity.
- Holding key maintains zoom (local timeout gets reset on key repeat).
- Releasing key, or no hold events until timeout (safety), releases zoom.
- Two zoom states: zoom wanted, and zoom current.
- Some transition speed between current and wanted, so zoom is smoother.

TODO: develop this out with smooth transitions.
version 1 will just be fixed instant steppings.

TODO: doesnt always reset fully, why?
- It looks like the recalibration problem isn't just on switching ships,
but often happens when switching fovs. Just one fov step down and back
up seems to normally work, but multiple steps screw up. Not consistently,
though.
Observations: 
- [zoom -> back] recovers okay
- [zoom -> zoom -> back] only goes to some intermediate point between 
  original and first zoom. Eg. if started at 100 degrees, may end up at 90,
  even though this doesn't match any of the intermediate steps.
- [zoom - zoom - back] could also end up with a wider fov then started,
  if it was already really narrow to begin with. Eg. 40°-20°-10°-90°.
- Float/int doesn't seem to matter; game has already drifted to the baseline
  being a <1 float during these tests.
- Switching first zoom point to 1.5x, [zoom -> back] no longer restores,
  but drifts in, eg. 100°->67°->90°.

Could there be some sort of background rollover occurring?
- 2x-4x-8x test below had zoom-in drift, but never went back
  to a wider zoom in the amount of tests done (maybe not enough).
- However, the larger zooms (eg. 10x) with big jumps do have some sort
  of rollover occurring.
- So yes, probably.

Is there a snapback mechanic, where one fov step-and-back is okay, but
going two fov steps in a row triggers recalibration somehow?
- No; trying different multipliers recreates issue with one step.

Are powers-of-2 stable, but unstable otherwise?
- Not entirely.  2x and 4x zoom recovered, 8x did not.
- However, though 8x had zoom drift, it never went back to wide fov,
  just kept zooming more and more.

Could truncation be occurring?
- Seems plausible.  10x zoom snap back would sometimes go to wider fov,
  but 8x zoome snap back always goes to narrower fov.

Is it a float/int issue, where part of the code supports floats, part doesnt?
- Possible; hard to say. Graphics should be working in radians/floats, but
  could have some fixed point and precision loss occurring.

Tests on specific zoom levels:
1.5 : drift in
2   : stable
3   : drift out
4   : stable
5   : drift in
6   : drift in
7   : drift in
8   : drift in (large)
9   : drift out (large)
10  : drift out (large)

For now, limit to 2x and 4x and see how it does.

Note: if a user exits the game while zoomed (eg. set the hotkey to alt and
used alt-f4), the user config.xml saves the zoomed fov value, and repeatedly
doing this eventually sets the saved fov to 0.0. After this point, using
the zoom hotkey will make the whole screen go black.
TODO: think of a workaround for this (eg. detect game quitting somehow and
restore fov).
]]
local fov = {
    -- The baseline fov is per-user based on resolution.
    -- TODO: update this on res changes, or occasionally poll for updates.
    baseline = GetFOVOption(),

    -- Scaling factors. Nominally 1x. >1 when zooming.
    current = 1,
    wanted  = 1,

    -- Zoom factors per key press. Gets assigned to 'wanted'.
    factors = {1, 2, 4},
    current_factor_index = 1,

    -- How fast to zoom in, in terms of factor/second.
    zoom_in_rate = 10,
    -- How fast to zoom out.
    zoom_in_rate = 50,

    -- How long to wait between key pressed before auto zoom-out.
    -- OS key repetition should be shorter than this.
    -- This is a backup in case the key release is missed (eg. player
    -- tabbed out with key held, released outside scope).
    timeout = 1,

    -- The current scheduled timeout, in engine time.
    scheduled_timeout = nil,
    -- Id to use for the timer alarm.
    alarm_id = 'zoom_timeout',
}
function L.Handle_Zoom_In(_, event)

    -- Check the event type.
    -- If this is a fresh press, step forward.
    if event == "onPress" then

        if debugger.verbose then
            DebugError("Handle_Zoom_In called with " .. tostring(event))
        end
        
        -- If not yet zooming, recalibrate the baseline fov.
        if fov.current == 1 then
            fov.baseline = GetFOVOption()
            if debugger.verbose then
                DebugError("Handle_Zoom_In recalibrated baseline to " .. tostring(fov.baseline))
            end
        end

        -- Only increase if not at max zoom.
        if fov.current_factor_index < #fov.factors then
            fov.current_factor_index = fov.current_factor_index + 1
            fov.wanted = fov.factors[fov.current_factor_index]
        end

        -- Start or refresh the timeout.
        Time.Set_Alarm(fov.alarm_id, fov.timeout, L.Reset_Zoom)
    else
        -- If not actively zooming, ignore excess repeat/release messages,
        -- in case they got delayed somehow until after a timeout.
        if fov.current == 1 then
            return
        end
    end

    -- If this is a repeat, refresh the timeout timer.
    if event == "onRepeat" then
        -- Can do this by overwriting the current alarm id.
        Time.Set_Alarm(fov.alarm_id, fov.timeout, L.Reset_Zoom)

    -- TODO: what to do on a release? Could reset zoom, but that interferes
    --  the the multi-press-for-more-zoon idea.
    elseif event == "onRelease" then
        --L.Reset_Zoom()
    end

    -- For now, if wanted ~= current, just force the zoom.
    -- TODO: maybe split off into a step smoothing function.
    if fov.wanted ~= fov.current then
        -- Compute the wanted fov.
        fov.current = fov.wanted
        local new_fov = fov.baseline / fov.current
        -- Force it.
        SetFOVOption(new_fov)
        if debugger.verbose then
            DebugError("Handle_Zoom_In adjusted fov to " .. tostring(new_fov))
        end
    end
end

-- Reset the zoom back to baseline.
function L.Reset_Zoom()
    -- Reset the wanted back to 1.
    fov.current_factor_index = 1
    fov.wanted = 1

    -- For now, just force update the fov.
    fov.current = fov.wanted
    SetFOVOption(fov.baseline)
    if debugger.verbose then
        DebugError("Reset_Zoom returned fov to " .. tostring(fov.baseline))
    end
end

-- Final init.
Register_OnLoad_Init(L.Init, "sn_hotkey_collection.ui.Hotkeys")