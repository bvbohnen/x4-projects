--[[
This module implements a custom options menu entry, separate from the
general api, for changing various behaviors of interest.

An md script will build an options submenu and handle callbacks.
Based on what changes, the MD will raise lua events to trigger functions
found here.

Note:   Only addons and widget_fullscreen appear to be available in
        the general lua system.  Stuff in ui/core seem hidden.

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

- Look through the global config table to see if anything interesting is there.
    Note: most interesting stuff is in ui/core, but those don't see to be
    exported despite being globals.

- Edit helptext.lua to suppress display of help messages. Should be simple
    to intercept onShowHelp and onShowHelpMulti calls with doing nothing.
    Main problem is that testing the edit would be annoying; need to find
    a situation that consistently pops up the text. Probably will be
    correct on first try, though.

]]

-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef uint64_t UniverseID;
    void SkipNextStartAnimation(void);
    bool IsGameModified(void);
    UniverseID GetPlayerObjectID(void);
    UniverseID GetContextByClass(UniverseID componentid, const char* classname, bool includeself);
]]
--DebugError(tostring(ffi))


local debugger = {
    verbose = false,
}

-- Import library functions for strings and tables.
local Lib = require("extensions.sn_simple_menu_api.lua.Library")

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
    RegisterEvent("Simple_Menu_Options.map_menu_player_focus" , L.Handle_Map_Player_Focus)
    RegisterEvent("Simple_Menu_Options.adjust_fov"        , L.Handle_FOV)
    RegisterEvent("Simple_Menu_Options.disable_helptext"  , L.Handle_Hide_Helptext)
    

    -- Testing.
    --Lib.Print_Table(_G, "_G")
    --Lib.Print_Table(global_config, "global_config")
    -- Note: debug.getinfo(function) is pretty useless.
    --Lib.Print_Table(DebugConfig, "DebugConfig")
    --Lib.Print_Table(Color, "Color")
    
    -- Egosoft packages are not directly accessible through the
    -- normal library mechanism; this only returns mostly normal packages
    -- like "string" and "math".
    --Lib.Print_Table(package.loaded, "packages_loaded")
    
    -- Global config table.
    --Lib.Print_Table(config, "global_config")
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
    map_menu.createMainFrame = function (...)

        -- This normally calls frame:display() before returning.
        -- Suppress the call by intercepting the frame object, returned
        -- from Helper.
        local ego_createFrameHandle = Helper.createFrameHandle
        -- Store the frame and its display function.
        local frame
        local frame_display
        Helper.createFrameHandle = function(...)
            -- Build the frame.
            frame = ego_createFrameHandle(...)
            -- Record its display function.
            frame_display = frame.display
            -- Replace it with a dummy.
            frame.display = function() return end
            -- Return the edited frame to displayControls.
            return frame
            end

        -- Build the menu.
        original_createMainFrame(...)
        
        -- Reconnect the createFrameHandle function, to avoid impacting
        -- other menu pages.
        Helper.createFrameHandle = ego_createFrameHandle

        if L.menu_alpha.alpha ~= nil then
            -- Look for the rendertarget member of the mainFrame.
            local rendertarget = nil
            for i=1,#map_menu.mainFrame.content do
                if map_menu.mainFrame.content[i].type == "rendertarget" then
                    rendertarget = map_menu.mainFrame.content[i]
                end
            end
            if rendertarget == nil then
                -- Note, this was seen printed once; unclear on cause.
                DebugError("Failed to find map_menu rendertarget")
                return retval
            else
                -- Try to directly overwrite the alpha.
                --DebugError("alpha: "..tostring(rendertarget.properties.alpha))
                rendertarget.properties.alpha = L.menu_alpha.alpha
            end
        end

        -- Try a full frame background if alpha doesn't work.
        -- (Alpha seems to work fine; don't need this.)
        --map_menu.mainFrame.backgroundID = "solid"

        -- -Removed; display done smarter.
        -- Redisplay the menu to refresh it.
        -- (Clear existing scripts before the refresh.)
        -- Layer taken from config of menu_map.lua.
        -- TODO: replace this with the new method that suppresses the
        -- original frame:display temporarily.
        --local mainFrameLayer = 5
        --Helper.removeAllWidgetScripts(map_menu, mainFrameLayer)
        --map_menu.mainFrame:display()
        
        -- Re-attach the original frame display, and call it.
        frame.display = frame_display
        frame:display()

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
-- Support for disabling tips
--[[
    Tips are handled in helptext.lua, which listens to "helptext" and
    "multihelptext" events to call onShowHelp and onShowHelpMulti.

    Both of those functions return early if the gamesave data indicates
    the tip was already shown before.
    Can wrap those to also return early when the custom option is set.

    However, the HelpTextMenu is not registers in the normal way.
    Instead of being set up during its init, it only registers its
    event listeners.
    Menu registration is only performed upon a displayHelp() call, and is
    unregistered in cleanup(). In neither case is it added to the
    global list of Menus.

    The only place to intercept the menu as a whole would be in its call
    to Helper.setMenuScript(menu, ...), but that only occurs if "allowclose"
    is enabled for the tip, so wouldn't be a reliable way to capture the
    menu object before display.

    Another option is to intercept the View.registerMenu() call, which
    allows for swapping out the menu.viewCreated and menu.cleanup links
    to instead clear the menu when it attempts to be created, and clear
    out the standard cleanup to do nothing.
    In the above case, following registerMenu() is a registration of
    the menu's update function using SetScript, which does not get
    cleared out by the normal clearCallback.  Intercepting that and
    suppressing it may be needed as well.
    For a little safety, only clear the next onUpdate SetScript, and don't
    try to clear if something else is seen first, to protect slightly
    against source code changes.

    
    New approach:
    Above is clumsy.  Maybe an alternative would be to listen for
    the helptext or multihelptext events, then fire a clearhelptext event
    right afterward (same frame?).

    Initial attempt spammed the log with GoToSlide errors. Adding a 1-frame
    delay works okay, though.

]]
-- State for helptext edit.
L.helptext = {
    disable = false,
    -- Temp flag when the next onUpdate script should be suppressed.
    --suppress_update_script = false,
    -- Time clearhelptext was scheduled.
    start_time = nil,
    -- Flag for when the delay_func is being polled.
    polling_active = false,
}
-- Note: this should slot in after the helptext event script, so
-- the menu will be set up already and ready to be cleared.
-- Note: this works, but get 30 GotoSlide errors following a
-- clear; uncertain why. Maybe try a delay.
L.helptext.clear_text_func = function()
    -- Clear the polling function.
    RemoveScript("onUpdate", L.helptext.delay_func)
    L.helptext.polling_active = false
    -- Conditionally send the followup event.
    if L.helptext.disable then
        -- Second arg is a string, "all" should clear all helptexts queued.
        CallEventScripts("clearhelptext", "all")          
        --DebugError("Sending clearhelptext")
    end
end

-- This gets checked on each onUpdate, looking for a time change.
L.helptext.delay_func = function()
    if L.helptext.start_time ~= GetCurTime() then
        L.helptext.clear_text_func()
    end
end

-- Set up the onUpdate script, and record the start time.
L.helptext.setup_func = function()
    -- Note: several helptext calls may be done at once, seemingly,
    -- so prevent excess calls to SetScript (clean up log).
    if L.helptext.polling_active == false then
        L.helptext.polling_active = true
        L.helptext.start_time = GetCurTime()
        SetScript("onUpdate", L.helptext.delay_func)
    end
end

-- Setup wrappers.
function L.Init_Help_Text()

    RegisterEvent("helptext", L.helptext.setup_func)
    RegisterEvent("multihelptext", L.helptext.setup_func)

    -- Removed; only semi-functional.
    --[[
    -- Intercept menu registration.
    if View == nil then
        error("View global not yet initialized")
    end

    -- Patch it to clear the menu when it tries to be created.
    local ego_registerMenu = View.registerMenu
    View.registerMenu = function(id, type, callback, clearCallback, ...)

        -- Check for the helptext menu, with disabling enabled.
        if L.helptext.disable and id == "helptext" then
            -- Swap the clear function in for the normal callback.
            callback = clearCallback
            clearCallback = nil
            -- Flag the next onUpdate script registration to be ignored.
            L.helptext.suppress_update_script = true
            -- Temp message to see that this thing worked.
            DebugError("Suppressing help text")
        end

        -- Continue with the standard call.
        return ego_registerMenu(id, type, callback, clearCallback, ...)
    end

    -- Patch SetScript to suppress the onUpdate registration.
    local ego_SetScript = SetScript
    SetScript = function(handle, ...)

        -- In practice the first arg could be "widget", and handle as second,
        -- but the intercepted call has handle as first.
        if L.helptext.suppress_update_script then

            if handle == "onUpdate" then
                -- This should be the helptext function to ignore.
                return
            else
                -- Something went wrong; should not have seen a different
                -- handle type first.
                -- Note: this has been triggered in testing.
                DebugError("Expected helptext 'onUpdate' script; saw '"..tostring(handle).."' instead")
            end

            -- In either case, stop trying to suppress.
            L.helptext.suppress_update_script = false
        end

        -- Pass on to the normal call.
        return ego_SetScript(handle, ...)
    end
    ]]

    -- Removed; doesn't work since the menu isn't part of Menus.
    --[[
    -- Stop if something went wrong.
    if Menus == nil then
        error("Menus global not yet initialized")
    end
    
    local menu
    for i, ego_menu in ipairs(Menus) do
        if ego_menu.name == "HelpTextMenu" then
            menu = ego_menu
        end
    end
    
    -- Stop if something went wrong.
    if menu == nil then
        error("Failed to find egosoft's HelpTextMenu")
    end

    -- Patch the functions.
    for i, name in ipairs({"onShowHelp", "onShowHelpMulti"}) do
        local ego_func = menu[name]
        menu[name] = function (...)
            if L.helptext.disable then
                if debugger.verbose then
                    DebugError("Suppressing helptext display")
                end
            else
                ego_func(...)
            end
        end
    end
    ]]
end
L.Init_Help_Text()


function L.Handle_Hide_Helptext(_, param)
    if debugger.verbose then
        DebugError("Handle_Hide_Helptext called with " .. tostring(param))
    end

    -- Convert param to true/false, since lua confuses 0 with true.
    if param == 1 then param = true else param = false end

    -- Store it.
    L.helptext.disable = param
end

------------------------------------------------------------------------------
-- Testing force map to open on player (as if no target selected)
--[[
    Code of interest appears to be menu_map.lua menu.importMenuParameters(),
    wherein it sets up menu.focuscomponent and menu.selectfocuscomponent.
    There is a fallback in this code for when no soft target is present
    to focus on the player ship.
    Can monkey patch this to follow up by focusing on player ship,
    regardless of what was set before.
]]
L.mapfocus = {
    onplayer = true,
}
-- Setup wrappers.
function L.Init_Map_Focus()

    -- Stop if something went wrong.
    if Menus == nil then
        error("Menus global not yet initialized")
    end
    
    local menu = nil
    for i, ego_menu in ipairs(Menus) do
        if ego_menu.name == "MapMenu" then
            menu = ego_menu
        end
    end
    
    -- Stop if something went wrong.
    if menu == nil then
        error("Failed to find egosoft's MapMenu")
    end

    local ego_importMenuParameters = menu["importMenuParameters"]
    menu["importMenuParameters"] = function (...)
        -- Call it as normal.
        ego_importMenuParameters(...)
        -- Reset focus target.
        if L.mapfocus.onplayer then
            menu.focuscomponent = C.GetPlayerObjectID()
            menu.selectfocuscomponent = nil
            menu.currentsector = C.GetContextByClass(menu.focuscomponent, "sector", true)
        end
    end
end
L.Init_Map_Focus()


function L.Handle_Map_Player_Focus(_, param)
    if debugger.verbose then
        DebugError("Handle_Map_Player_Focus called with " .. tostring(param))
    end

    -- Convert param to true/false, since lua confuses 0 with true.
    if param == 1 then param = true else param = false end

    -- Store it.
    L.mapfocus.onplayer = param
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

    Testing results: works fine, but only catches some stuff, and not
    stuff from the base lua files.
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