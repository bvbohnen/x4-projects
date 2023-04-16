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
- Remove modified tag entirely (text and parenthesis).
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
    GetCharacterDensityOption

- Remove the egosoft station announcement
    On page {10099,1014}.
    Played in md/Notifications.xml cue StationAnnouncements_PrepareSpeak.
    Can insert a node after "<set_value name="$textid" min="1001" max="1022" />"
    to detect the ego announcement and cancel the cue (it refires itself
    after a few seconds anyway).
    Condition on setting here.

- Look through the global config table to see if anything interesting is there.
    Note: most interesting stuff is in ui/core, but those don't see to be
    exported despite being globals.

- Higher ui scaling values
    menu.valueGameUIScale, menu.callbackGameUIScaleReset()
    Normally limited to 1.5x.
    Maybe of little use; ui is already problematic at 1.5 with text cuttoffs.

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
    void ZoomMap(UniverseID holomapid, float zoomstep);
    typedef struct {
        UIPosRot offset;
        float cameradistance;
    } HoloMapState;
    void GetMapState(UniverseID holomapid, HoloMapState* state);
    void SetMapState(UniverseID holomapid, HoloMapState state);
    float GetTextWidth(const char*const text, const char*const fontname, const float fontsize);
    void SetFocusMapComponent(UniverseID holomapid, UniverseID componentid, bool resetplayerpan);
    void SetMapPanOffset(UniverseID holomapid, UniverseID offsetcomponentid);
    void StartPanMap(UniverseID holomapid);
    bool StopPanMap(UniverseID holomapid);
    void SetSelectedMapComponents(UniverseID holomapid, UniverseID* componentids, uint32_t numcomponentids);
]]
--DebugError(tostring(ffi))


local debugger = {
    verbose = false,
}

-- Import library functions for strings and tables.
local Lib = require("extensions.sn_mod_support_apis.lua_interface").Library

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
    -- TODO: generalized handler, once figuring out a way to deal
    -- with special logic per option (eg. limit checks, rescaling, etc.).
    RegisterEvent("Simple_Menu_Options.disable_animations"    , L.Handle_Disable_Animations)
    RegisterEvent("Simple_Menu_Options.tooltip_fontsize"      , L.Handle_Tooltip_Font)
    RegisterEvent("Simple_Menu_Options.map_menu_alpha"        , L.Handle_Map_alpha)
    RegisterEvent("Simple_Menu_Options.map_menu_player_focus" , L.Handle_Map_Player_Focus)
    RegisterEvent("Simple_Menu_Options.map_menu_zoom"         , L.Handle_Map_Zoom_Distance)
    RegisterEvent("Simple_Menu_Options.adjust_fov"            , L.Handle_FOV)
    RegisterEvent("Simple_Menu_Options.disable_helptext"      , L.Handle_Hide_Helptext)
    --RegisterEvent("Simple_Menu_Options.tooltip_on_truncation" , L.Handle_Tooltip_On_Truncation)
    RegisterEvent("Simple_Menu_Options.traffic_density"       , L.Handle_Set_Traffic_Density)

    RegisterEvent("Simple_Menu_Options.Pause_Game"            , L.Handle_Pause_Game)
    RegisterEvent("Extra_Game_Options.get_lua_values"         , L.Handle_Get_Lua_Values)
    
    

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

-- Return some lua accessible values to md during setup.
function L.Handle_Get_Lua_Values()
    local ret_table = {}

    -- Traffic density lookup from config.xml.
    local value = GetTrafficDensityOption()
    -- Adjust to percent.
    value = math.floor(value * 100 + 0.5)
    value = math.max(0, value)
    value = math.min(100, value)
    ret_table['traffic_density'] = value
    
    -- Fov lookup from config.xml.
    -- No adjustments.
    -- Removed for now due to fov drift problems.
    --ret_table['adjust_fov'] = GetFOVOption()

    AddUITriggeredEvent("Extra_Game_Options", "return_lua_values", ret_table)
end


------------------------------------------------------------------------------
-- Testing edits to map menu opacity.
--[[
    The relevant code is in menu_map.lua, createMainFrame function.
    Here, alpha is hardcoded to 98.
    Update: in 3.3 the alpha is 98, or 100 if the globally saved value
    __CORE_DETAILMONITOR_MAPFILTER["other_misc_opacity"] is true.

    The global setting makes the need for this extra option less necessary,
    but since this custom style allows variable opacity (eg. 99), it will
    be kept functional for now.

    If the map "opacity" flag is set, this will be set to do nothing (let
    that vanilla setting override this opacity).
]]
-- State for this option.
L.menu_alpha = {
    -- Selected alpha level, up to 100 (higher level decides the min).
    alpha = 98,
    }
function L.Init_Menu_Alpha()

    local map_menu = Lib.Get_Egosoft_Menu("MapMenu")    
            
    -- Pick out the menu creation function.
    local original_createMainFrame = map_menu.createMainFrame
    map_menu.createMainFrame = function (...)

        -- If the using default value, don't attach extra code, as a safety
        -- if an x4 patch breaks the logic.
        if L.menu_alpha.alpha == 98 or __CORE_DETAILMONITOR_MAPFILTER["other_misc_opacity"] then            
            -- Build the menu.
            original_createMainFrame(...)

        else
            -- This normally calls frame:display() before returning.
            -- Suppress the call by intercepting the frame object, returned
            -- from Helper, to get the frame handle.
            -- Note: createFrameHandle can be called multiple times; only
            -- want to record the first returned frame (the main menu frame).
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
                -- Reconnect the createFrameHandle function, to avoid
                -- impacting other menu pages.
                Helper.createFrameHandle = ego_createFrameHandle
                -- Return the edited frame to displayControls.
                return frame
                end

            -- Build the menu.
            original_createMainFrame(...)

            if L.menu_alpha.alpha ~= nil then
                -- Look for the rendertarget member of the mainFrame.
                local rendertarget = nil
                for i=1,#map_menu.mainFrame.content do
                    if map_menu.mainFrame.content[i].type == "rendertarget" then
                        rendertarget = map_menu.mainFrame.content[i]
                    end
                end
                if rendertarget == nil then
                    -- Note, this was seen printed a few times; unclear on cause.
                    DebugError("Custom Options Map alpha: Failed to find map_menu rendertarget")
                else
                    -- Try to directly overwrite the alpha.
                    --DebugError("alpha: "..tostring(rendertarget.properties.alpha))
                    rendertarget.properties.alpha = L.menu_alpha.alpha
                end
            end

            -- Re-attach the original frame display, and call it.
            frame.display = frame_display
            frame:display()
        end

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
    The baseline value varies by resolution; not always 10.

    SetFOVOption(mult_x10)

    The ui gets squished or stretched with the fov adjustment, so it
    doesn't make sense to go smaller (cuts off ui) or much higher
    (ui hard to read). Though going smaller could be useful for a
    zoom feature.
    Update: a some point (3.0 betas probably), this was fixed and the
    ui now scales with fov properly.

    In testing:
        Works okay initially.
        Changing ship (getting in spacesuit) resets the fov to normal,
        but leaves the value used with SetFOVOption unchanged.
        Eg. if fov was changed to 12 (+20%), and player gets in a spacesuit,
        then 12 will become standard fov, and getting back the +20% would
        require setting fov to 14.4.
        This is still the case in v3.2.

    Go back to disabling this md-side as unsafe.

]]
function L.Handle_FOV(_, new_fov)
    if debugger.verbose then
        DebugError("Handle_FOV called with " .. tostring(new_fov))
    end
    SetFOVOption(new_fov)
end


------------------------------------------------------------------------------
--[[
    Mass traffic density is an option in the config file, apparently 
    functional, but not exposed in the options. There are, however,
    lua globals for modifying it.

    In spot checking, the value is a float, 0 to 1. Eg. 0.5 for half.
    Note: unlike other options, this one isn't saved in the md, but
    is part of the player config.xml. This will send the current config
    value back to md at startup.

    Note: md-side option will be in percent 0 to 100, converted to float
    0.0 to 1.0 here.
]]

function L.Handle_Set_Traffic_Density(_, new_value)
    if debugger.verbose then
        DebugError("Handle_Traffic_Density called with " .. tostring(new_value))
    end
    -- Reduce from percent to float.
    new_value = new_value / 100

    -- Verify in bounds.
    new_value = math.max(0, new_value)
    new_value = math.min(1.0, new_value)

    SetTrafficDensityOption(new_value)
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
    if L.helptext.start_time ~= GetCurRealTime() then
        L.helptext.clear_text_func()
    end
end

-- Set up the onUpdate script, and record the start time.
-- TODO: switch to Time api for 1 frame delay alarm.
L.helptext.setup_func = function()
    -- Note: several helptext calls may be done at once, seemingly,
    -- so prevent excess calls to SetScript (clean up log).
    if L.helptext.polling_active == false then
        L.helptext.polling_active = true
        L.helptext.start_time = GetCurRealTime()
        SetScript("onUpdate", L.helptext.delay_func)
    end
end

-- Setup wrappers.
function L.Init_Help_Text()

    RegisterEvent("helptext", L.helptext.setup_func)
    RegisterEvent("multihelptext", L.helptext.setup_func)

    -- TODO: disable sounds, eg. PlaySound("notification_hint")

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

    A secondary map characteristic is that the zoom is locked on the
    initial target, eg. mousing to another part of the map and zooming
    in will still lock the center of the map to the specific object
    (the player ship in this case). A random click anywhere on the map
    is necessary to enable zooming to other locations.
    (When locked, the camera moves with the object, which is indeed nice.)
    Could the code here be tweaked to change this behavior?

    The menu onUpdate function checks for a menu.focuscomponent, and
    if found, calls C.SetFocusMapComponent, which pans the map to
    the target. This is only done when the map is first opened.
    However, menu.focuscomponent needs to be set during importMenuParameters,
    else an error occurs.
    As such, clearing the focus component needs to be done later,
    eg. after onUpdate when first activated.
    However, there is no C.ClearFocusMapComponent or similar, so how is
    the camera-lock cleared?

    Test results: 
        C.SetFocusMapComponent with pan=false does not stop the panning.
        Giving a 0 object id just produces an error and messes up the menu.
        C.SetMapPanOffset didn't help when set to the player.
        Calling C.StartPanMap then C.StopPanMap didn't have any effect.
        C.SetSelectedMapComponents to select a group had no effect.
    Overall, giving up on this idea for now.

    Note: importMenuParameters is called by onShowMenu just prior to
    restoring prior state, so hopefully this doesn't interfere with
    restoring a minimized menu that focuses on something else.

    TODO: noticed in 4.10b5: map tries to open on last focused object, and
    this code no longer works. Map behavior janky, eg getting insistent on
    a particular object and not wanting to change defaults, so ignore
    initially.
]]
L.mapfocus = {
    onplayer = true,
    --unfocus = true,
}
-- Setup wrappers.
function L.Init_Map_Focus()

    local menu = Lib.Get_Egosoft_Menu("MapMenu")
    
    -- Change initial focus component.
    local ego_importMenuParameters = menu.importMenuParameters
    menu.importMenuParameters = function (...)

        -- Call it as normal.
        ego_importMenuParameters(...)

        -- Reset focus target.
        if L.mapfocus.onplayer then
            menu.focuscomponent = C.GetPlayerObjectID()
            menu.selectfocuscomponent = nil
            menu.focusoffset = nil
            -- TODO: should showzone always be false?
            --menu.showzone = false
            menu.currentsector = C.GetContextByClass(menu.focuscomponent, "sector", true)
        end
    end
    
    -- -Removed; couldn't get this working.
    ---- Clear default focus component on open.
    --local ego_onUpdate = menu.onUpdate
    --menu.onUpdate = function (...)
    --    -- Note if the map is getting activated on this call.
    --    local activatemap = menu.activatemap
    --
    --    -- Call it as normal.
    --    ego_onUpdate(...)
    --
    --    -- If just activated, clear the focus.
    --    if activatemap and L.mapfocus.unfocus and menu.holomap ~= 0 then
    --        --C.SetFocusMapComponent(menu.holomap, C.GetPlayerObjectID(), false)
    --        --C.SetMapPanOffset(menu.holomap, C.GetPlayerObjectID())
    --        --C.StartPanMap(menu.holomap)
    --        --C.StopPanMap(menu.holomap)
    --        
    --        --local components = ffi.new("UniverseID[?]", 1)
    --        --components[0] = C.GetPlayerObjectID()
    --        --C.SetSelectedMapComponents(menu.holomap, components, 1)
    --    end
    --end    

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
-- Change the default map zoom level on open.
--[[
    The ffi C.ZoomMap can be used for this, which accepts a zoom step.
    Step is positive to scroll out, negative to scroll in, and 
    appears to be relative, eg. 0 is no change.
    Note: this will behave like mouse scrolling, with a short delay during
    the zoom in/out animation.
    
    The menu initializes the holomap in onUpdate when menu.activate_map
    is True. The artificial zoom can potentially be applied after
    this event.

    In testing, 100 steps is a full zoom out, if the map starts somewhat
    zoomed. Though map initial zoom varies based on proximity to nearby
    objects.

    A better approach is to look at camera distance, from C.GetMapState.
    In testing, min distance is 1,000, max is 5,000,000.
    A dist of ~500,000 roughly covers one sector tile.
    Start distances vary, eg. 20k to 100k+, depending on nearby objects.
    In this case, the user can specify a fixed distance to open to, which
    should avoid a zoom delay by using SetMapState directly.

    Note: libraries/parameters.xml/universe/camera sets these 1k/5000k limits.
    TODO: think about how to scale to limits; or possibly mod the max
    zoom out to something that covers the full dlc map (would need to
    test for bugs).

    Since this range, 1k to 5000k, is very awkwardly wide, it may make
    sense to use a logarithmic curve.
    Eg. use specifies value 0 to 100 (0 being disabled).
        1  : shortest supported distance, eg. 5k.
        100: max distance, 5 million
    Example calculation:
        Set min dist, max dist.
        Scaling from user is 1 to 100.
        Dist = min_dist + (scale/100)^2 * (max_dist - min_dist).
        In the above, with limits 5km and 5000km:
            1 is very close to min_dist (~4.5 km)
            50 is ~1250 km (roughly 2 sectors tall)
            100 is max dist
    Example 2:
        Dist = min_dist + (scale/100)^3 * (max_dist - min_dist).
        In the above, with limits 5km and 5000km:
            1 is very very close to min_dist (~5 km)
            50 is ~625 km (roughly 1 sector tall)
            100 is max dist

    Update: detect if map was maximized after being minimized, and do not
    adjust zoom in that case (as it remembers prior zoom level).
    Menu logic is:
        On minimize:
            Call menu.onMinimizeMenu, save holomap state, clear holomap.
        Alternatively:
            Call menu.onSaveState, which returns map state to caller.
        On restore:
            Call menu.onRestoreMenu
                Call menu.displayMenu(firsttime = nil)
                    Does nothing with state.
        Alternatively, maybe this happens:
            Call menu.onShowMenu(state)
                Call menu.onRestoreState(state)
                    Repacks state into menu.mapstate.
                    Unpacks state fields directly into menu "stateKeys".
                    - Does not include camera zoom level.
                
        menu.onUpdate()
            If menu.mapstate found, sends to C.SetMapState.
            
    TODO: noticed in 4.10b5: map always opens with prior zoom level, and
    this does nothing. Maybe remove.
]]
L.mapzoom = {
    distance = 0,
    -- Min is >= 1k, max is <= 5000k.
    dist_min = 1000,
    dist_max = 5000000,
}
function L.Init_Map_Zoom()
    local menu = Lib.Get_Egosoft_Menu("MapMenu")

    -- Detect menu restoration which does not use mapstate.
    -- Removed; unnecessary.
    --local ego_onRestoreMenu = menu.onRestoreMenu
    --menu.onRestoreMenu = function (...)
    --    ego_onRestoreMenu(...)
    --    if debugger.verbose then
    --        DebugError("Detected map menu onRestoreMenu call")
    --    end
    --end
    
    -- Patch onUpdate for when it creates a new holomap.
    local ego_onUpdate = menu.onUpdate
    local function patch_function()
        -- Adjust the zoom level if the map just activated.
        -- To be safe, check for the holomap being changed from its
        -- default of 0.
        -- Skip if there was map state.
        if  menu.holomap ~= 0 
        and mapstate == nil 
        and L.mapzoom.distance ~= 0 then
            if debugger.verbose then
                DebugError("Changing map zoom level to " .. tostring(L.mapzoom.distance))
            end
            -- Get current state to edit (preserves position).
            local mapstate = ffi.new("HoloMapState")
            C.GetMapState(menu.holomap, mapstate)
            mapstate.cameradistance = L.mapzoom.distance
            C.SetMapState(menu.holomap, mapstate)
        end
    end

    menu.onUpdate = function (...)
        -- Note if the map is getting activated on this call.
        local activatemap = menu.activatemap
        
        -- Note if there is saved map state that is being restored, eg. When
        -- coming back from minimized, to preserve prior zoom level.
        -- The onUpdate function will read this and set it to nil, so store
        -- a reference here.
        local mapstate = menu.mapstate
        if mapstate and debugger.verbose and L.mapzoom.distance ~= 0 then
            DebugError("Skipping map zoom change, prior state found.")
        end

        -- Call it as normal.
        ego_onUpdate(...)

        -- Call the patcher, with safety, since otherwise the game crashes if
        -- this errors somehow. Skip if not a new activation or if it
        -- restored prior state.
        if activatemap and not mapstate then
            success, error = pcall(patch_function)
            if not success then
                DebugError("Zoom adjustment failed with error: "..tostring(error))
            end
        end
    end    
end
L.Init_Map_Zoom()

function L.Handle_Map_Zoom_Distance(_, param)
    if debugger.verbose then
        DebugError("Handle_Map_Zoom_Distance called with " .. tostring(param))
    end
    --  Adjust it to a meter value.
    local percent = param / 100
    -- Cube it for now.
    local distance = L.mapzoom.dist_min + percent * percent * percent * (L.mapzoom.dist_max - L.mapzoom.dist_min)
    -- If given 0, keep as 0 (disabled).
    if param == 0 then distance = 0 end
    --DebugError("Setting cam distance to "..tostring(distance))
    -- Store it.
    L.mapzoom.distance = distance
end

------------------------------------------------------------------------------
-- Testing cheat enables
--[[
    The base game has an IsCheatVersion() global function, that controls
    inclusion of some extra cheat commands through the ui.

    Can try forcing it to return True. May not work perfectly if this
    depends on lower level cheat functionality that is missing.

    The map_menu records this global function as a condition check
    prior to it getting monkey patched here.
    However, this link is stored in the menu config, and the function that
    checks it looks are config directly. As such, the cheat icon needs to
    be patched back in after the relevant function returns, copy/pasting
    any necessary innards.

    Result: cheat menu shows up fine in the map menu, but most of the options
    don't seem to work or give errors. It is possible some of the ffi callbacks
    have another cheat check that fails.
    Several options set up a conversation menu, handled in the md
    script MainMenu which listens to event_conversation_started. It seems
    no actual conversation menu is opened; this is just used for
    signalling the md cue. However, the md cues appear to not be maintained,
    and give errors (eg. lookup failures on people when selecting to increase
    crew skill).

    For now, scratch support for ego cheats.
]]
--[[
L.cheats = {
    enable = true,
}

local global_IsCheatVersion = IsCheatVersion
IsCheatVersion = function(...)
    --CallEventScripts("directChatMessageReceived", "Event;IsCheatVersion called")
    return L.cheats.enable
    --global_IsCheatVersion(...)
end

-- Setup wrappers.
function L.Init_Cheats()

    local menu = Lib.Get_Egosoft_Menu("MapMenu")
    local ego_createSideBar = menu.createSideBar

    menu.createSideBar = function(firsttime, frame, ...)

        -- Save the current selection.
        local sideBar = menu.selectedRows.sideBar

        -- Run the standard logic.
        ego_createSideBar(firsttime, frame, ...)

        -- Insert the cheat option back in.
        if IsCheatVersion() then


            -- Look up the ftable the above function added.
            -- Expect the newest ftable to be the last table in the frame.
            local ftable
            for i = 1, #frame.content do
                if frame.content[i].type == "table" then
                    ftable = frame.content[i]
                end
            end

            -- Copy of the ego leftbar entries from config.
            local entry = {
                name = "Cheats",
                icon = "mapst_cheats",
                mode = "cheats"}

            -- Note: following code chunk is a heavily pruned bit of ego code.

            -- Blank space.
            local spacingHeight = menu.sideBarWidth / 4
            local row = ftable:addRow(false, { fixed = true })
            row[1]:createIcon("mapst_seperator_line", { width = menu.sideBarWidth, height = spacingHeight })

            -- Cheats entry.
            local row = ftable:addRow(true, { fixed = true })

            local bgcolor = Helper.defaultTitleBackgroundColor
            if menu.infoTableMode == "cheats" then
                bgcolor = Helper.defaultArrowRowBackgroundColor
            end

            local color = Helper.color.white
            if menu.highlightLeftBar["cheats"] then
                color = Helper.color.mission
            end
                
            row[1]:createButton({ active = true, height = menu.sideBarWidth, bgColor = bgcolor, mouseOverText = entry.name, helpOverlayID = entry.helpOverlayID, helpOverlayText = entry.helpOverlayText }):setIcon(entry.icon, { color = color })
            row[1].handlers.onClick = function () return menu.buttonToggleObjectList("cheats") end

            -- Restore the selection.
            ftable:setSelectedRow(sideBar)
        end
    end    
end
L.Init_Cheats()
]]

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
-- Auto-generation of mouseover text.
--[[
    Many of the text boxes utilize a call to CreateFontString, some
    global function that takes various text properties, including the
    raw test string and the display width.

    Assuming this function is what does truncation, it can potentially
    be intercepted to good effect.
    The function returns userdata to be passed to other global
    functions, and is not suitable for lua exploration.
    However, the input to CreateFontString can potentially add mouseover
    text, if it expects the text might not fit.

    The above works well for text boxes, but several other widget
    types make a separate call to TruncateText before setting up
    their descriptor. In such cases, it will take more work to patch
    the individual widgets to detect truncation and add the mouseover.

    Some other ui elements may use TruncateText, and possibly do mouseover
    generation (most menu_map truncations do this, for instance). Don't
    worry about those for now.

    For buttons, there are two ways to set them up:
        Helper.createButton
        cell:createbutton
    The former can be patched easily enough, but the latter makes use
    of metatables and such to eventually call:
        widgetHelpers.button:createDescriptor
    The above has similar TruncateText logic to Helper.createButton, but
    unfortunately widgetHelpers is local.

    Update: 5.10 in widget_fullsceen make changes to updateFontString 
    related to adding mouseover text on truncation (using similar logic
    to compare pre- and post-truncation string lengths), so disabling
    this option. Otherwise, end up with duplicated tooltips.
]]
--[[
L.auto_mouseover = {
    enabled = false,
}
-- Setup wrappers.
function L.Init_Auto_Mouseover()

    local ego_CreateFontString = CreateFontString

    CreateFontString = function(
            text, halignment, 
            color_r, color_g, color_b, color_a, fontname, 
            fontsize, wordwrap, offsetx, offsety, 
            height, width, mouseovertext, ...)

        --Lib.Print_Table({
        --    text          = text,
        --    halignment    = halignment,
        --    color_r       = color_r,
        --    color_g       = color_g,
        --    color_b       = color_b,
        --    color_a       = color_a,
        --    fontname      = fontname,
        --    fontsize      = fontsize,
        --    wordwrap      = wordwrap,
        --    offsetx       = offsetx,
        --    offsety       = offsety,
        --    height        = height,
        --    width         = width,
        --    mouseovertext = mouseovertext,
        --}, "CreateFontString_Args")

        -- Ran into an issue with text being a number; convert manually.
        text = tostring(text)

        -- Check if the text width may be truncated, if all info is
        -- specified and the mouseover is available.
        if L.auto_mouseover.enabled 
        and width 
        and fontname 
        and fontsize 
        and not wordwrap
        and (not mouseovertext or mouseovertext == "") then
            local text_width = C.GetTextWidth(text, fontname, fontsize)
            if text_width > width then
                -- Expecting truncation.
                mouseovertext = text
                --DebugError("Adding mouseover to truncate text: "..text)
            end
        end

        -- Pass to the ego function.
        -- Note: the description is a userdata object.
        return ego_CreateFontString(
            text, halignment, 
            color_r, color_g, color_b, color_a, 
            fontname, fontsize, wordwrap, offsetx, offsety, 
            height, width, mouseovertext, ...)
    end

    -- Patch Helper.createButton.
    ego_createButton = Helper.createButton
    Helper.createButton = function(
            text, icon, noscaling, active, offsetx, offsety, 
            width, height, color, hotkey, icon2, mouseovertext)

        --if text then
        --    DebugError("Intercepted createButton with text "..tostring(text.text))
        --else
        --    DebugError("Intercepted createButton without text ")
        --end

        -- Is this likely to truncate?
        -- (Actual ego code also subtracts some offset, but ignore for now.)
        if L.auto_mouseover.enabled 
        and text 
        and width 
        and width ~= 0 
        and (not mouseovertext or mouseovertext == "") then
            -- Note, next few lines are mostly copied with slight edits.
            -- Apply scaling to the text.
            local est_fontsize = text.fontsize
            if not noscaling then
                est_fontsize = text.fontsize and Helper.scaleFont(text.fontname, text.fontsize) or text.fontsize
            end
            -- Scale the width.
            local est_width = width and Helper.scaleX(width) or width
            -- Get the truncation.
            local trunc_text = TruncateText(text.text, text.fontname, est_fontsize, est_width - (text.x and (2 * text.x) or 0))

            -- Does it differ?
            if text.text ~= trunc_text then
                -- Add mouseover.
                mouseovertext = text.text
            end
        end

        -- Pass it all to the ego function.
        return ego_createButton(
            text, icon, noscaling, active, offsetx, offsety, 
            width, height, color, hotkey, icon2, mouseovertext)
    end

    -- The following also relate to buttons calling TruncateText.
    -- TODO:  widgetHelpers.button:createDescriptor()
    -- TODO:  widgetPrototypes.frame:update()

end
L.Init_Auto_Mouseover()

function L.Handle_Tooltip_On_Truncation(_, param)
    if debugger.verbose then
        DebugError("Handle_Tooltip_On_Truncation called with " .. tostring(param))
    end

    -- Convert param to true/false, since lua confuses 0 with true.
    if param == 1 then param = true else param = false end

    -- Store it.
    L.auto_mouseover.enabled  = param
end
]]
------------------------------------------------------------------------------
--[[
    Automatically pause the game upon loading.
    This will only have an effect a short time after loading into a save,
    after userdata is available.

    Note: this event is only called when md determined a pause should happen,
    so no param is passed.
]]
function L.Handle_Pause_Game()
    Pause()
end

------------------------------------------------------------------------------
--[[
    Hiding the "modified" tag can partially be done in the t file, but that
    leaves orange parentheses behind.
    This orange text is buried in a private options menu lambda function.
    However, it was observed in the above that CreateFontString is used
    for when creating the text of interest, where the text input
    has the color code: "#FFff8a00#" just before the modified flag,
    eg. "#FFff8a00#(Modified)".
    This pattern can be searched for and suppressed.

    Result: succeeds initially, but then the modified tag redraws itself
    without the help of CreateFontString, so ultimately unsuccesful.
]]
--[[
function L.Init_Hide_Modified()
    local ego_CreateFontString = CreateFontString

    -- Look up the Modified text string, and construct the search string.
    -- Note: parentheses need % escape (because lua).
    local pattern = "#FFff8a00#%("..ReadText(1001,8901).."%)"
    DebugError("pattern: "..pattern)

    CreateFontString = function(text, ...)

        -- Make sure text is a string.
        text = tostring(text)
        -- Do the replacement.
        DebugError("text pre-gsub: "..text)
        text = string.gsub(text, pattern, "")
        DebugError("text post-gsub: "..text)

        -- Pass to the ego function.
        return ego_CreateFontString(text, ...)
    end
end
L.Init_Hide_Modified()
]]

------------------------------------------------------------------------------
-- Final init.
L.Init()