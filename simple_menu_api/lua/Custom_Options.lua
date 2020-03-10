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
- Remove modified tag entirely.
    Requires accessing gameoptions config.optionDefinitions (private),
    or monkeypatching wherever it gets used with a custom copy/pasted
    version with the modified text function removed.
- Adjust stuff in targetsystem.lua
    Here, all config is added to the global 'config' from widget_fullscreen.
    Update: in testing, targetsystem config entires don't show up in the global
    table, for some unknown reason.
- ExecuteDebugCommand
    Maybe set up buttons to refreshmd/refreshai/reloadui (latter closes
    the menu). This is probably not the place for it, though. Perhaps
    a debug menu.

- Try out some global functions:
    GetTrafficDensityOption / SetTrafficDensityOption
    GetCharacterDensityOption
    ClearLogbook


]]

-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    void SkipNextStartAnimation(void);
    bool IsGameModified(void);
]]
--DebugError(tostring(ffi))

-- Import config and widget_properties tables.
local Tables = require("extensions.simple_menu_api.lua.Tables")
local debugger          = Tables.debugger

-- Import library functions for strings and tables.
local Lib = require("extensions.simple_menu_api.lua.Library")



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
    -- Event registration.
    -- TODO: switch to single event, general table of args sent
    -- through blackboard var.
    RegisterEvent("Simple_Menu_Options.disable_animations", L.Handle_Disable_Animations)
    RegisterEvent("Simple_Menu_Options.tooltip_fontsize"  , L.Handle_Tooltip_Font)
    RegisterEvent("Simple_Menu_Options.map_menu_alpha"    , L.Handle_Map_alpha)
    RegisterEvent("Simple_Menu_Options.adjust_fov"        , L.Handle_FOV)
    

    -- Testing.
    --Lib.Print_Table(_G, "_G")
    --Lib.Print_Table(global_config, "global_config")
    -- Note: debug.getinfo(function) is pretty useless.
    --Lib.Print_Table(DebugConfig, "DebugConfig")
    --Lib.Print_Table(Color, "Color")
    
    -- Egosoft packages are not directly accessible through the
    -- normal library mechanism.
    --Lib.Print_Table(package.loaded, "packages_loaded")
end

------------------------------------------------------------------------------
-- Testing edits to map menu opacity.
--[[
    The relevant code is in menu_map.lua, createMainFrame function.
    Here, alpha is hardcoded to 98.
    While the whole function could be replaced with just the one edit,
    perhaps there is a cleaner solution to updating the alpha live?
]]
-- State for this option.
L.menu_alpha = {
    -- Selected alpha level, up to 100 (higher level decides the min).
    alpha = 98,
    }
function L.Init_Menu_Alpha()

    -- Stop if something went wrong.
    if Menus == nil then
        error("Menus global not yet initialized")
    end
    
    local map_menu = nil
    for i, ego_menu in ipairs(Menus) do
        if ego_menu.name == "MapMenu" then
            map_menu = ego_menu
        end
    end
    
    -- Stop if something went wrong.
    if map_menu == nil then
        error("Failed to find egosoft's MapMenu")
    end
    
            
    -- Pick out the menu creation function.
    local original_createMainFrame = map_menu.createMainFrame
    -- Wrapper.
    map_menu.createMainFrame = function (...)
        local retval = original_createMainFrame(...)
        
        -- Look for the rendertarget member of the mainFrame.
        local rendertarget = nil
        for i=1,#map_menu.mainFrame.content do
            if map_menu.mainFrame.content[i].type == "rendertarget" then
                rendertarget = map_menu.mainFrame.content[i]
            end
        end
        if rendertarget == nil then
            DebugError("Failed to find map_menu rendertarget")
            return retval
        else
            -- Try to directly overwrite the alpha.
            --DebugError("alpha: "..tostring(rendertarget.properties.alpha))
            rendertarget.properties.alpha = L.menu_alpha.alpha
        end

        -- Try a full frame background if alpha doesn't work.
        -- (Alpha seems to work fine; don't need this.)
        --map_menu.mainFrame.backgroundID = "solid"

        --DebugError("Trying to make map solid")
        
        -- Redisplay the menu to refresh it.
        -- (Clear existing scripts before the refresh.)
        -- Layer taken from config of menu_map.lua.
        local mainFrameLayer = 5
        Helper.removeAllWidgetScripts(map_menu, mainFrameLayer)
        map_menu.mainFrame:display()
        return retval
    end    
end
L.Init_Menu_Alpha()

function L.Handle_Map_alpha(_, new_alpha)
    -- Validate within reasonable limits.
    if new_alpha < 50 or new_alpha > 100 then
        error("Handle_Map_alpha received unsupported value: "..tostring(new_alpha))
    end
    if debugger.verbose then
        DebugError("Handle_Map_alpha called with " .. tostring(new_alpha))
    end

    -- Adjust the % to center around 10.
    L.menu_alpha.alpha = new_alpha
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
L.animations = {
    -- If animation suppression is currently enabled.
    disable = true,
    }


function L.Init_Animations()

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
            if L.animations.disable then
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
L.Init_Animations()


-- Runtime md signal handler to change the option state.
-- Param is an int, 0 (don't disable) or 1 (do disable).
function L.Handle_Disable_Animations(_, param)
    if debugger.verbose then
        DebugError("Handle_Disable_Animations called with " .. tostring(param))
    end

    -- Convert param to true/false, since lua confuses 0 with true.
    if param == 1 then param = true else param = false end

    -- Store it.
    L.animations.disable = param
end

------------------------------------------------------------------------------
-- Support for changing tooltip font size
--[[
    This fontsize is set globally for all menus in widget_fullscreen.lua
    which exports a global config table.
]]

-- Table of valid font sizes; uses dummy values, just want key checking.
local valid_font_sizes = {[8]=0, [9]=0, [10]=0, [11]=0, [12]=0, [13]=0}
function L.Handle_Tooltip_Font(_, new_size)
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

------------------------------------------------------------------------------
-- Support for changing fov
--[[
    There is an unused global function for changing field of view.
    By experiment, its input appears to be a multiplier on the default
    fov, upscaled 10x.  Eg. '10' is nominal, '13' adds 30%, etc.
    SetFOVOption(mult_x10)

    The ui gets squished or stretched with the fov adjustment, so it
    doesn't make sense to go smaller (cuts off ui) or much higher
    (ui hard to read). This will limit to 1x to 1.3x for now.

    In testing:
        Works okay initially.
        Changing ship (getting in spacesuit) resets the fov to normal,
        but leaves the value used with SetFOVOption unchanged.
        Eg. if fov was changed to 12 (+20%), and player gets in a spacesuit,
        then 12 will become standard fov, and getting back the +20% would
        require setting fov to 14.4.

    For now, this is disabled in the options menu pending further development
    to work around issues.
    (Would GetFOVOption be helpful at all?)
]]
-- This will take the multiplier as a %.
function L.Handle_FOV(_, new_mult)
    -- Validate within reasonable size limits.
    if new_mult < 100 or new_mult > 130 then
        error("Handle_FOV received unsupported size: "..tostring(new_mult))
    end
    if debugger.verbose then
        DebugError("Handle_FOV called with " .. tostring(new_mult))
    end

    -- Adjust the % to center around 10.
    SetFOVOption(new_mult / 10)
end

------------------------------------------------------------------------------
-- Testing sound disables.
--[[
    Can record and replace the global PlaySound function with a
    custom filtering one. By rebinding the global, other ego code will
    use the customized function.

    In practice, this only affects a small number of sounds, those
    called directly in Lua.  As such, it is not very powerful unless
    there is a particular menu sound that is bothersome.  Some menu
    sounds are bound to widgets, and may be handled outside PlaySound
    calls.

    Testing results: works fine.
    Comment out if not used for anything yet.

    TODO: try out blocking these (but not hopeful):
    "ui_weapon_out_range"
    "ui_weapon_in_range"
]]
--[[
local global_PlaySound = PlaySound
PlaySound = function(name)
    CallEventScripts("directChatMessageReceived", "Event;PlaySound: "..name)
    global_PlaySound(name)
end
]]

------------------------------------------------------------------------------
-- Testing text disables.
--[[
    Like above, intercept the ReadText calls and do whatever.
    Can maybe do alternating color codes or other wackiness, based on
    a timer.

    Note: this works fine for ReadText itself, though isn't so powerful
    when it comes to strings built from ReadTexts and hardcoded bits.

    Disable for now until a nice use is found.
]]
--[[
local global_ReadText = ReadText
ReadText = function(page, key)
    -- "modified" string suppression.
    if page == 1001 and key == 8901 then
        -- Don't really want to print anything, since this gets called a lot.
        --CallEventScripts("directChatMessageReceived", "ReadText;("..page..", "..key..")")
        return ""
    else
        return global_ReadText(page, key)
    end
end
]]

------------------------------------------------------------------------------
-- Testing patching the ffi library.
--[[
    This might be a little dangerous.
    When doing `require("ffi")`, it presumably returns a table with
    its internal values. One of these is "C", itself a table of
    the ffi functions.

    Note: when testing "DebugError(tostring(ffi))" on different modules,
    the log indicates all ffi modules are the same returned from require("ffi").

    However, testing below indicates that the egosoft ffi modules may be
    separate from those loaded by modded-in (eg. not jitted?) lua code.
    Possibly, every base module loaded from ui.xml gets its own ffi, but
    all of these custom modules are loaded through Lua_Loader_API.

    Overall result:  skip this, not too promising.
]]
--local function Return_False() return false end

-- Try direct rebinding.
--C.IsGameModified = function()
--    return false
--end
-- Test result: Error, "attempt to write to constant location"
-- Maybe related to http://lua-users.org/wiki/ReadOnlyTables

-- Try forced rebinding.
--rawset(C, "IsGameModified", function() return false end)
-- Test result: Error, bad argument #1 to 'rawset' (table expected, got userdata)

-- Try an intermediate metatable, which captures lookups and pipes all but
--  select names to the original C userdata.
-- '__index' is called when the table is missing a key, which is always here.
--[[
local original_C = ffi.C
ffi.C = setmetatable({}, {
    __index = function (table, key)
        CallEventScripts("directChatMessageReceived", "ffi;Calling "..key)
        if key == "IsGameModified" then
            return Return_False
        else
            return original_C[key]
        end
    end})
]]
-- Test result: no error, but not much impact;
-- Catches "GetPlayerID" and maybe other calls from dynamically loaded modules,
--  but catches nothing from egosoft code.
-- Extra testing indicates all require("ffi") calls return the same object,
--  but maybe egosoft stuff gets their own copies (perhaps since they load
--  from separate ui.xml files, while these dynamic loads are all from the
--  same Lua_Loader_API parent).


------------------------------------------------------------------------------
-- Final init.
L.Init()