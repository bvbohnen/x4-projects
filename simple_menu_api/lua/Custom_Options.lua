--[[
This module implements a custom options menu entry, separate from the
general api, for changing various behaviors of interest.

An md script will build an options submenu and handle callbacks.
Based on what changes, the MD will raise lua events to trigger functions
found here.

TODO: consider switching to reading md settings state directly from a
blackboard table instead of using signal params (limited to string/int/nil).

TODO: possible future options
    - Reduce config.startAnimation.duration for faster open animations.
    - Increase ui scaling factor beyond 1.5 (needs monkeypatch).
]]

-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    void SkipNextStartAnimation(void);
]]

-- Import config and widget_properties tables.
local Tables = require("extensions.simple_menu_api.lua.Tables")
local debugger          = Tables.debugger

-- Import library functions for strings and tables.
local Lib = require("extensions.simple_menu_api.lua.Library")



-- Table of locals.
local loc = {}


-- Global config customization.
-- A lot of ui config is in widget_fullscreen.lua, where its 'config'
-- table is global, allowing editing of various values.
-- Rename the global config, to not interfere with local.
local global_config = config
if global_config == nil then
    error("Failed to find global config from widget_fullscreen.lua")
end


function loc.Init()
    -- Event registration.
    RegisterEvent("Simple_Menu_Options.disable_animations", loc.Handle_Disable_Animations)
    RegisterEvent("Simple_Menu_Options.tooltip_fontsize"  , loc.Handle_Tooltip_Font)
end


------------------------------------------------------------------------------
-- Support for enabling/disabling default menu opening animations.
--[[
    All ego top level menus appear to be opened by the lua event system.
    Helper.registerMenu will create the showMenuCallback and register
    the open event to call it.

    Here, showMenuCallback can be intercepted to first make a call
    to the C.SkipNextStartAnimation(), which will effectively suppress
    the opening animation.

    For now, this will be done across all menus.
]]
-- State for this option.
loc.animations = {
    -- If animation suppression is currently enabled.
    disable = true,
    }


function loc.Init_Animations()

    -- Stop if something went wrong.
    if Menus == nil then
        error("Menus global not yet initialized")
    end
    
    -- Debug: list all menu names.
    --local message = "Registered Menus:\n"
    --for i, ego_menu in ipairs(Menus) do
    --    message = message .. "  " .. ego_menu.name .. "\n"
    --end
    --DebugError(message)

    -- Loop over all ego menus, or whatever might be registered.
    -- Note: this can affect the Simple Menu API standalone menu,
    -- depending on when this is run; it should be fine either way
    -- since by experience they don't have an opening delay anyway.
    for i, ego_menu in ipairs(Menus) do
        
        -- Temp copy of the original callback.
        local original_callback = ego_menu.showMenuCallback

        -- Wrapper.
        -- To be thorough, this will be replaced in the menu's table
        -- as well as the event system, though the event is the important
        -- part.
        ego_menu.showMenuCallback = function (...)
            -- Suppress based on the current setting.
            if loc.animations.disable then
                C.SkipNextStartAnimation()
            end
            original_callback(...)
        end
        -- The original function was fed to RegisterEvent. Need to swap it
        -- out there as well.    
        UnregisterEvent("show"..ego_menu.name, original_callback)
        RegisterEvent(  "show"..ego_menu.name, ego_menu.showMenuCallback)
    end
    
end
loc.Init_Animations()


-- Runtime md signal handler to change the option state.
-- Param is an int, 0 (don't disable) or 1 (do disable).
function loc.Handle_Disable_Animations(_, param)
    if debugger.verbose then
        DebugError("Handle_Disable_Animations called with " .. tostring(param))
    end

    -- Convert param to true/false, since lua confuses 0 with true.
    if param == 1 then param = true else param = false end

    -- Store it.
    loc.animations.disable = param
end

------------------------------------------------------------------------------
-- Support for changing tooltip font size
--[[
    This fontsize is set globally for all menus in widget_fullscreen.lua
    which exports a global config table.
]]

-- Table of valid font sizes; uses dummy values, just want key checking.
local valid_font_sizes = {[8]=0, [9]=0, [10]=0, [11]=0, [12]=0, [13]=0}
function loc.Handle_Tooltip_Font(_, new_size)
    -- Validate within reasonable size limits.
    if valid_font_sizes[new_size] == nil then
        error("Handle_Tooltip_Font received invalid font size: "..tostring(new_size))
    end
    if debugger.verbose then
        DebugError("Handle_Tooltip_Font called with " .. tostring(new_size))
    end

    -- Apply font size directly.
    global_config.mouseOverText.fontsize = new_size

    -- Compute a new largest box size accordingly.
    -- Base was set to 225 wide.
    local maxWidth = math.floor(225 * new_size / 9)
    global_config.mouseOverText.maxWidth = maxWidth
end


-- Final init.
loc.Init()