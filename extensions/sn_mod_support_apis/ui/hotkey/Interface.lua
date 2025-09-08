--[[
Lua side of the hotkey api.
This primarily aims to interface tightly with the egosoft menu system,
to leverage existing code for allowing players to customize hotkeys.

Patches the OptionsMenu.

Notes on edit boxes:
    The external hotkey detection has no implicit knowledge of the in-game
    context of the keys.
    Contexts are resolved partially below and in md by detecting if the
    player is flying, on foot, or in a menu (and which menu).
    However, complexity arises when the player is trying to type into
    an edit box (or similar), where hotkeys should be suppressed.
    Edit box activation and deactivation callbacks can be difficult to
    get at, notably the chat window that is present in a flying context.

    As a possible workaround, registerForEvent can be used on the ui to
    catch directtextinput events, which fire once per key press for an
    edit box. This can potentially be used to suppress key events.

    Functionality: on direct input key, set an alarm for some time in the
    future.  Immediately signal the md to suppress keys. After the alarm
    goes off, signal md to reenable keys. If more direct inputs come in
    during this period, have them just reset the alarm time.
    The alarm should be long enough to cover the latency from the external
    python code through the pipe to the game. That is not well measured,
    but some generous delay should handle the large majority of cases,
    unless there was some odd hiccup on key processing.

TODO: split apart md interface stuff from the menu plugin stuff,
to reduce file sizes.
]]

-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef uint64_t UniverseID;
    UniverseID GetPlayerID(void);
]]
-- Unused functions for now.
--[[
    void ActivateDirectInput(void);
    uint32_t GetMouseHUDModeOption(void);
    void DisableAutoMouseEmulation(void);
    void EnableAutoMouseEmulation(void);
]]

-- Imports.
local Lib = require("extensions.sn_mod_support_apis.ui.Library")
local Time = require("extensions.sn_mod_support_apis.ui.time.Interface")
local T = require("extensions.sn_mod_support_apis.ui.Text")
-- Reuse the config table from simple menu api.
local Tables = require("extensions.sn_mod_support_apis.ui.simple_menu.Tables")
local config = Tables.config

-- Local functions and data.
local debug = {
    print_keycodes = false,
    print_keynames = false,
}
local L = {
    -- Shadow copy of the md's action registry.
    action_registry = {},

    -- Table of assigned keys and their actions, keyed by id.
    -- This is mirrored in a player blackboard var whenever it changes.
    player_action_keys = {},

    -- Wrapper functions on remapInput to be used in registering for input events.
    input_event_handlers = {},

    -- Status of the pipe connection, updated from md.
    pipe_connected = false,

    -- How long to wait after a direct input before reenabling hotkeys.
    direct_input_suppress_time = 0.5,
    -- Id to use for the alarm.
    alarm_id = "hotkey_directinput_timeout",
    -- If input currently disabled. Used to suppress some excess signals.
    alarm_pending = false,
    
    -- When captuing a key, the action_id of the key.
    capture_action_id = nil,
    -- When captuing a key, the index in the input list to write to.
    capture_input_index = nil,
    }


-- Proxy for the gameoptions menu, linked further below.
local menu = nil


-- Signalling results from lua to md.
-- Takes the row,col of the activated widget, and an optional new value
-- for that widget.
-- TODO: think about this more.
local function Raise_Signal(name, value)
    AddUITriggeredEvent("Hotkey", name, value)
end


local function Init()

    -- Set up ui linkage to listen for text entry state changes.
    -- (Goal is to suppress hotkeys when entering text.)
    L.scene            = getElement("Scene")
    L.contract         = getElement("UIContract", L.scene)
    registerForEvent("directtextinput"          , L.contract, L.onEvent_directtextinput)

    -- MD triggered events.
    RegisterEvent("Hotkey.Update_Actions", L.Update_Actions)
    RegisterEvent("Hotkey.Update_Player_Keys", L.Read_Player_Keys)
    RegisterEvent("Hotkey.Update_Connection_Status", L.Update_Connection_Status)
    RegisterEvent("Hotkey.Process_Message", L.Process_Message)
    
    -- Cache the player component id.
    L.player_id = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    
    -- Signal to md that a reload event occurred.
    -- This will also trigger md to send over its stored list of
    -- player assigned keys.
    Raise_Signal("reloaded")

    -- Run the menu init stuff.
    L.Init_Menu()
end

-------------------------------------------------------------------------------
-- Handle direct input detection.

-- Handler for direct input key presses.
-- Fires once for each key.
function L.onEvent_directtextinput(some_userdata, char_entered)
    -- Note: to get number of vargs, use: select("#",...)
    -- This appears to receive 3 args according to the "...", but when trying
    -- to capture them only get 2 args.
    -- First arg is some userdata object, second is the key pressed (not
    -- as a keycode).

    --DebugError("Caught directtextinput event; starting disable")

    -- Signal md to suppress hotkeys, if not already disabled.
    if not L.alarm_pending then
        Raise_Signal("disable")
        L.alarm_pending = true
    end

    -- Start or reset the timer.
    Time.Set_Alarm(L.alarm_id, L.direct_input_suppress_time, L.Reenable_Hotkeys)
end

function L.Reenable_Hotkeys()
    --DebugError("directtextinput event timed out; ending disable")
    Raise_Signal("enable")
    L.alarm_pending = false
end


-------------------------------------------------------------------------------
-- MD -> Lua signal handlers

-- Process a pipe message, a series of matched hotkey event names
-- semicolon separated.
function L.Process_Message(_, message)
    -- Split it.
    local events = Lib.Split_String_Multi(message, ";")
    -- Add '$' prefixes and return.
    for i, event in ipairs(events) do
        events[i] = "$"..event
    end
    -- Send back.
    Raise_Signal("handle_events", events)
end

-- Handle md pipe connection status update. Param is 0 or 1.
function L.Update_Connection_Status(_, connected)
    -- Translate the 0 or 1 to false/true.
    if connected == 0 then 
        L.pipe_connected = false 
    else 
        L.pipe_connected = true 
    end
end

-- Handle md requests to update the action registry.
-- Reads data from a player blackboard var.
function L.Update_Actions()
    -- Args are attached to the player component object.
    local md_table = GetNPCBlackboard(L.player_id, "$hotkey_api_actions")

    -- Note: md may have sent several of these events on the same frame,
    -- in which case the blackboard var has just the args for the latest
    -- event, and later events processed will get nil.
    -- Skip those nil cases.
    if not md_table then return end
    L.action_registry = md_table

    -- Clear the md var by writing nil.
    SetNPCBlackboard(L.player_id, "$hotkey_api_actions", nil)
    
    --Lib.Print_Table(L.action_registry, "Update_Actions action_registry")
end

-- Read in the stored list of player action keys.
-- Generally md will send this on init.
function L.Read_Player_Keys()
    -- Args are attached to the player component object.
    local md_table = GetNPCBlackboard(L.player_id, "$hotkey_api_player_keys_from_md")
    -- This shouldn't get getting nil values since the md init is
    -- sent just once, but play it safe.
    if not md_table then return end
    L.player_action_keys = md_table

    -- Clear the md var by writing nil.
    SetNPCBlackboard(L.player_id, "$hotkey_api_player_keys_from_md", nil)
    
    -- Remove unused inputs from pre-7.0.
    L.Cleanup_Unused_Inputs()
        
    --Lib.Print_Table(L.player_action_keys, "Read_Player_Keys player_action_keys")
end

-- Write to the list of player action keys to be stored in md.
-- This could be integrated into remapInput, but kept separate for now.
function L.Write_Player_Keys()
    -- Args are attached to the player component object.
    SetNPCBlackboard(L.player_id, "$hotkey_api_player_keys_from_lua", L.player_action_keys)
    Raise_Signal("Store_Player_Keys")
    
    --Lib.Print_Table(L.player_action_keys, "Write_Player_Keys player_action_keys")
end



-------------------------------------------------------------------------------
-- Menu setup.
-- TODO: break into more init subfunctions for organization.

function L.Init_Menu()
    --DebugError("HotkeyAPI: Patching menu functions")

    -- Look up the menu, store in this module's local.
    menu = Lib.Get_Egosoft_Menu("OptionsMenu")
    
    -- Patch displayOptions.
    local ego_displayControls = menu.displayControls
    menu.displayControls = function(...)
        --DebugError("GameOptions.displayControls() called")

        -- Start by building the original manu.

        -- Note that displayControls calls frame:display(), which would need
        -- to be called a second time after new rows are added, but leads
        -- to backend confusion.

        -- Since attempts to re-display after adding new rows lead to many
        -- debuglog errors when the menu closes (widgets still alive not
        -- having a table), the original display() can be suppressed by
        -- intercepting the frame building function, and putting in a
        -- dummy function for the frame's display member.
        local ego_createOptionsFrame = menu.createOptionsFrame
        -- Store the frame and its display function.
        local frame
        local frame_display
        menu.createOptionsFrame = function(...)
            -- Build the frame.
            frame = ego_createOptionsFrame(...)
            -- Record its display function.
            frame_display = frame.display
            -- Replace it with a dummy.
            frame.display = function() return end
            -- Return the edited frame to displayControls.
            return frame
            end

        -- Record the prior selected option, since the below call clears it.
        local preselectOption = menu.preselectOption
        -- Build the menu.
        ego_displayControls(...)

        -- Reconnect the createOptionsFrame function, to avoid impacting
        -- other menu pages.
        menu.createOptionsFrame = ego_createOptionsFrame

        -- Safety call to add in the new rows.
        local success, error = pcall(L.displayControls, preselectOption, ...)
        if not success then
            DebugError("displayControls error: "..tostring(error))
        end

        -- Re-attach the original frame display, and call it.
        -- (Note: this method worked out great, much better than attempts
        -- to re-display after clearing scripts or whatever.)
        frame.display = frame_display
        frame:display()
    end
    
    -- Patch remapInput, which catches the player's new keys.
    local ego_remapInput = menu.remapInput
    menu.remapInput = function(...)
        -- Hand off to ego function if this isn't a custom key.
        if menu.remapControl.controlcontext ~= "hotkey_api" then
            ego_remapInput(...)
            return
        end        
        -- Safety call.
        local success, error = pcall(L.remapInput, ...)
        if not success then
            DebugError("remapInput error: "..tostring(error))
        end
    end

    -- Patch getControlName, to support custom controls when 
    -- menu.createContextMenuDirectInput is called.
    local ego_getControlName = menu.getControlName
    menu.getControlName = function(controltype, controlcode)
        -- Use the ego function if the code (which will be action_id)
        -- is not registered.
        -- Note: the api uses strings for action_id, and egosoft uses ints
        -- for controlcodes, so don't expect an accidental match.
        if L.action_registry[controlcode] == nil then
            return ego_getControlName(controltype, controlcode)
        end
        return L.action_registry[controlcode].name
    end
    
    -- TODO: replace the event registration functions which select which
    -- input types to capture.  Just want keyboard for custom controls.
    -- TODO: also need to suppress hotkey_api from triggering cues while
    -- this is going on.
    --L.input_event_handlers = {
    --    -- Args patterned off of config.input.directInputHookDefinitions.
    --    -- Just keyboard for now.
    --    ["keyboardInput"] = function (_, keycode) L.remapInput(1, keycode, 0) end,
    --    }
    --
    ---- Patch registration.
    --local ego_registerDirectInput = menu.registerDirectInput
    --menu.registerDirectInput = function()
    --    L.registerDirectInput(ego_registerDirectInput)
    --    end
    --
    ---- Patch unregistration.
    --local ego_unregisterDirectInput = menu.unregisterDirectInput
    --menu.unregisterDirectInput = function()
    --    L.unregisterDirectInput(ego_unregisterDirectInput)
    --    end
    

    -- Listen for when menus open/close, to inform the md side what the
    -- current hotkey context is (eg. suppress space-based hotkeys while
    -- menus are open).
    -- (Alternatively, can check this live by scanning all menus for
    -- the menu.shown flag being set and menu.minimized being false.)

    --[[
        Closing raises a ui signal of the menu name, but that is awkward
        to catch for all menus, and not reasonable to account for
        modded menus (outside of known mods).

        However, any menu closing should eventually call Helper's
        local closeMenu() function, which ends by calling
        Helper.clearMenu(...), so in theory wrapping clearMenu should
        be sufficient to capturing all menu closings.

        However, UserQuestionMenu doesn't get caught like others, even though
        it has a clear path by which it calls the Helper close function,
        even if the menu is set to auto-confirm (eg. when ejecting into
        a spacesuit).  From a glance at the code, it is unclear why
        this particular menu would be difficult.

        TODO: maybe revisit this to figure it out.
        For now, just ignore the menu.
    ]]

    -- Patch into Helper.clearMenu for closings.
    local ego_helper_clearMenu = Helper.clearMenu
    Helper.clearMenu = function(menu, ...)
        ego_helper_clearMenu(menu, ...)
        L.Menu_Closed(menu)
        end
    -- Unnecessary.
    --local function patch_onCloseElement(menu)
    --    local ego_onCloseElement = menu.onCloseElement
    --    if ego_onCloseElement ~= nil then
    --        menu.onCloseElement = function(...)
    --            ego_onCloseElement(...)
    --            L.Menu_Closed(menu)
    --            end
    --    end
    --end

    -- Patch into all menu.showMenuCallback functions to catch when
    -- they open.  Two steps: patch existing menus, and patch helper
    -- for any future registered menus.
    -- Both share this bit of logic:
    local function patch_showMenuCallback(menu)
        local ego_showMenuCallback = menu.showMenuCallback
        menu.showMenuCallback = function(...)
            ego_showMenuCallback(...)
            L.Menu_Opened(menu)
            end
        -- These callbacks were registered to a 'show<name>' event, so update
        -- that registry.
        UnregisterEvent("show"..menu.name, ego_showMenuCallback)
        RegisterEvent("show"..menu.name, menu.showMenuCallback)
    end

    -- Patch exiting menus.
    for _, menu in ipairs(Menus) do
        patch_showMenuCallback(menu)
        --patch_onCloseElement(menu)
    end
    -- Patch future menus.
    local ego_registerMenu = Helper.registerMenu
    Helper.registerMenu = function(menu, ...)
        -- Run helper function first to set up the menu's callback func.
        ego_registerMenu(menu, ...)
        -- Can now patch it.
        patch_showMenuCallback(menu)
        --patch_onCloseElement(menu)
        end

    -- Also want to catch minimized menus.
    local ego_minimizeMenu = Helper.minimizeMenu
    Helper.minimizeMenu = function(menu, ...)
        ego_minimizeMenu(menu, ...)
        L.Menu_Minimized(menu)
        end
    -- And restored menus.
    local ego_restoreMenu = Helper.restoreMenu
    Helper.restoreMenu = function(menu, ...)
        ego_restoreMenu(menu, ...)
        L.Menu_Restored(menu)
        end
    

end

-------------------------------------------------------------------------------
-- Menu open/close handlers.

-- Note: TopLevelMenu is the default when no other menus are open, and will
-- generally be ignored here.
-- This is called when menus are closed in Helper.
function L.Menu_Closed(menu)
    if menu.name == "TopLevelMenu" then return end
    --DebugError("Menu closed: "..tostring(menu.name))
    Raise_Signal("Menu_Closed", menu.name)
    -- TODO: in practice, some menu closures might get missed.
    --  Can maybe check all menu open states, and indicate if they
    --  are all closed at the time (to recover from bad information).
    -- Can scan all menus for .shown and not .minimized to see if
    --  any are open.
end

-- This is called when menus are opened in Helper.
function L.Menu_Opened(menu)
    if menu.name == "TopLevelMenu" then return end
    if menu.name == "UserQuestionMenu" then return end
    --DebugError("Menu opened: "..tostring(menu.name))
    Raise_Signal("Menu_Opened", menu.name)
end

-- This is called when menus are minimized in Helper.
-- Treats menu as closing for the md side.
function L.Menu_Minimized(menu)
    if menu.name == "TopLevelMenu" then return end
    --DebugError("Menu minimized: "..tostring(menu.name))
    Raise_Signal("Menu_Closed", menu.name)
end

-- This is called when menus are restored (unminimized) in Helper.
-- Treats menu as opening for the md side.
function L.Menu_Restored(menu)
    if menu.name == "TopLevelMenu" then return end
    --DebugError("Menu restored: "..tostring(menu.name))
    Raise_Signal("Menu_Opened", menu.name)
end

-- TODO: a timed check to occasionally go through all the menus and
-- verify which are open/closed, just incase there is a problem above
-- with missing an opened/closed signal, so that the api can recover.


-- Test code: catching inputs directly.
-- Result: ListenForInput is only good for one key press, and it will
-- prevent that keypress from any other in-game effect.
-- So this is a dead end without a way to refire the caught key artificially.
-- There is also a C.ActivateDirectInput function, but that appears to be
-- just for editboxes when selected to enable typing.
--[[
local keys_to_catch = 10
function L.Input_Listener()
    ListenForInput(true)
    RegisterEvent("keyboardInput", L.Handle_Caught_Key)
    -- In testing, the above only catch a single input, suggesting
    -- either ListenForInput or the event registration gets cleared
    -- after one catch.
end
function L.Handle_Caught_Key(_, keycode)
    DebugError("Caught keyboard keycode: "..tostring(keycode))
    keys_to_catch = keys_to_catch -1
    if keys_to_catch > 0 then
        -- Restart the listen function.
        -- Limit how many times it happens, in case this locks out
        -- inputs to the game.
        ListenForInput(true)
    end
end
-- Fire it off.
L.Input_Listener()
]]


-- Searches for and removes unused input entries.
function L.Cleanup_Unused_Inputs()
    for _, key_infos in pairs(L.player_action_keys) do
        -- Check for blank combos.
        local need_new_inputs = false
        for _, input in ipairs(key_infos.inputs) do
            if input.combo == "" then
                need_new_inputs = true
                break
            end
        end

        if need_new_inputs then
            local new_inputs = {}
            for _, input in ipairs(key_infos.inputs) do
                if input.combo ~= "" then
                    table.insert(new_inputs, input)
                end
            end
            key_infos.inputs = new_inputs
        end
    end
end


-- Patch to add custom keys to the control remap menu.
function L.displayControls (preselectOption, optionParameter)
    --DebugError("HotkeyAPI: Interface.displayControls() called")

    -- Skip if the pipe is not connected, to avoid clutter for users that
    -- have this api installed but aren't using the server.
    if not L.pipe_connected then return end

    -- TODO: skip if there are no actions available. For now, the
    -- stock example actions should always be present, so can skip this
    -- check.

    -- TODO: skip if hotkey menu items are disabled using an extension options
    -- debug flag, in case this code breaks the menu otherwise.

    -- For now, stick keys on the keyboard/space submenu.
    -- Skip others.
    if optionParameter ~= "keyboard_space" then return end

    -- Look up the frame with the table.
    -- This should be in layer 3, matching config.optionsLayer.
    local frame = menu.optionsFrame
    if frame == nil then
        error("Failed to find gameoptions menu main frame")
    end
            
    -- Look up the table in the frame.
    -- There is probably just the one content entry, but to be safe
    -- search content for a table.
    local ftable = nil
    for i=1,#frame.content do
        if frame.content[i].type == "table" then
            if ftable ~= nil then
                error("Found multiple gameoptions menu tables")
            end
            ftable = frame.content[i]
            break
        end
    end
    if ftable == nil then
        error("Failed to find gameoptions menu main table")
    end

    -- Error check.
    if not L.action_registry then
        DebugError("action_registry is nil")
        return
    end

    -- Add some space.
    -- TODO: mayby skip.
    row = ftable:addRow(false, { })
    row[2]:setColSpan(7):createText(" ", { 
        fontsize = 1
        --height = config.infoTextHeight
        })

    -- Add a nice title.
    -- TODO: delay until finding at least one control.
    local row = ftable:addRow(false, { })
    row[2]:setColSpan(7):createText(T.extensions, config.subHeaderTextProperties)
    
    -- Make sure all actions have an entry in the player keys table.
    for _, action in pairs(L.action_registry) do
        if not L.player_action_keys[action.id] then
            L.player_action_keys[action.id] = {
                -- Repetition of id, in case it is ever useful.
                -- (This will not get a $ prefix when sent to md.)
                id = action.id,
                inputs = {}
            }
        end
    end


    -- Set up the custom actions.
    -- These will be sorted into their categories, with uncategorized
    -- lumped together at the top of the menu.
    -- Start by sorting actions into categories.
    local cat_action_dict = {}
    for _, action in pairs(L.action_registry) do
        local cat = action.category
        -- Set default category.
        if not cat then cat = "" end
        -- Set up a new sublist if needed.
        if not cat_action_dict[cat] then cat_action_dict[cat] = {} end
        -- Add it in.
        table.insert(cat_action_dict[cat], action)
    end

    -- Convert the cat table to a list, to enable lua sorting.
    local cats_sorted = {}
    for cat, sublist in pairs(cat_action_dict) do 
        table.insert(cats_sorted, cat)
        -- Also sort the actions by name while here.
        -- This lambda function returns True if the left arg goes first.
        table.sort(sublist, function (a,b) return (a.name < b.name) end)
    end
    -- Sort the cat names.
    table.sort(cats_sorted)

    -- Loop over cat names.
    for _, cat in ipairs(cats_sorted) do
        -- Make a header if this is a named category.
        if cat ~= "" then
            local row = ftable:addRow(false, { })
            row[2]:setColSpan(7):createText(cat, config.subHeaderTextProperties)
        end
        -- Loop over the sorted action list.
        local first = true
        for _, action in ipairs(cat_action_dict[cat]) do
            -- Hand off to custom function.
            L.displayControlRow(ftable, action.id, first)
            first = false
        end
    end

    -- Fix the row selection.
    -- The preselectOption should match the id of the desired row.
    -- TODO: maybe fix the preselectCol as well, though not as important;
    -- see gameoptions around line 2482.
    for i = 1, #ftable.rows do
        if ftable.rows[i].index == preselectOption then
            ftable:setSelectedRow(ftable.rows[i].index)
            break
        end
    end
            
    -- -Removed; display is handled above.
    --[[
    -- Need to re-display.
    -- TODO: stress test for problems.
    -- In practice, this causes log warning spam if display() done directly,
    -- since the display() function builds a whole new frame, but the old
    -- frame's scripts weren't cleared out.
    -- Manually do the script clear first.
    -- (Unlike clearDataForRefresh, this call just removes scripts,
    -- not existing widget descriptors.)
    Helper.removeAllWidgetScripts(menu, config.optionsLayer)
    -- TODO: need to revit this all again; when the menu is closed it throws
    -- ~1600 errors into the log with: "GetCellContent(): invalid table ID
    --  2336 - table might have been destroyed already." (Where the id
    -- number changes each time.)
    -- Suggests something; not sure what.
    frame:display()
    ]]
end


-- Copy/edit of ego's function for displaying on or two rows of hotkeys,
-- with buttons for adding more keys (but only up to 2).
-- "first" is true if the first control after a category header line.
function L.displayControlRow(ftable, action_id, first)
    -- Add spacing after a prior control.
	if not first then
		local row = ftable:addRow(nil, {  })
		row[2]:setColSpan(7):createText(" ", { fontsize = 1, height = Helper.scaleY(config.standardTextHeight) / 2 - 2 * Helper.borderSize, scaling = false })
	end
    
    local action    = L.action_registry[action_id]
    local player_keys = L.player_action_keys[action_id]

    -- Fill in some ego terms, to make reusing their code easier.
    -- TODO: does functions or actions make more sense? Unclear on difference.
    local controltype = "functions"
    local code = action_id

    -- Decide how many button lines to display: one per assigned key, plus
    -- one if a key is currently being assigned, minimum of one blank line
    -- if no keys.
    local buttons = player_keys.inputs
	local numbuttons = next(buttons) and #buttons or 1
	if next(buttons) and menu.remapControl then
		if ((menu.remapControl.controltype == controltype) 
        and (menu.remapControl.controlcode == code) 
        and (menu.remapControl.oldinputtype == -1) 
        and (menu.remapControl.oldinputcode == -1)) then
			numbuttons = numbuttons + 1
		end
	end

	for i = 1, numbuttons do
		local row = ftable:addRow(true, {  })
        
        local info = player_keys.inputs[i]

        -- Get the name of an existing key, or blank.
        local keyname, keyicon = " ", nil
        if info ~= nil and info.source then
            keyname, keyicon = menu.getInputName(info.source, info.code, info.signum)
        end
        
        -- Adjust selection to this row if it would have been the next row.
        -- (Maybe occurs when cancelling a new key addition and the new key
        -- selected row is deleted?)
		if i == numbuttons then
			if row.index + 1 == menu.preselectOption then
				menu.preselectOption = row.index
			end
		end

        -- Handle preselection.
        -- Note: column 3 is key, 4 is X, 7 is radial menu (unsupported).
		if row.index == menu.preselectOption then
			ftable:setSelectedRow(row.index)
			if menu.preselectCol == 3 then
				if buttons[i] then
					ftable:setSelectedCol(3)
				end
			elseif menu.preselectCol == 4 then
				if buttons[i] then
					ftable:setSelectedCol(4)
				end
			--elseif menu.preselectCol == 7 then
			--	ftable:setSelectedCol(7)
			end
		end
        
        -- Ego terms.
		local text = keyname
        local name = action.name
        local mouseOverText = action.description
        -- Skip mouseover if a blank string.
        if mouseOverText == "" then mouseOverText = nil end
        local context = "hotkey_api"
        -- Unclear what this does.
		local isdblclick = false
        local mappable = true
        local allowmouseaxis = false
        local checklastnonkeyboard = false
        local mouseonly = false
        local mousewheelonly = false
        local mouseaxisonly = false
        local disableremove = false
        
        local oldinputtype = -1
        local oldinputcode = -1
        local oldinputsgn = 0
        local uiTriggerID = "remapcontrol1a"
        if info ~= nil then
            oldinputtype = info.source
            oldinputcode = info.code
            oldinputsgn = info.signum
            uiTriggerID = "remapcontrol1b"
        end

        -- First row has the control name.
		if i == 1 then
			row[2]:createText(name, config.standardTextProperties)
		end
		if mouseovertext then
			row[2].properties.mouseOverText = mouseovertext
		end

        -- Truncate the text to have space for the icon.
		if buttons[i] and keyicon then
			local iconwidth = C.GetTextWidth(
                " " .. keyicon, 
                config.font, 
                Helper.scaleFont(config.font, config.standardFontSize))
			text = TruncateText(text, 
                config.font, 
                Helper.scaleFont(config.font, config.standardFontSize), 
                row[3]:getWidth() - 2 * Helper.scaleX(config.standardTextOffsetX) - iconwidth)
		end
		local button = row[3]:createButton({  }):setText(text, { 
            color = buttons[i] and Color["text_normal"] or Color["text_negative"] })
		if buttons[i] and keyicon then
			button:setText2(keyicon, { halign = "right" })
		end

        -- Setup the remap call.
        -- Note: these functions complete immediately, and the remapInput
        -- call happens later after user input.
		row[3].handlers.onClick = function ()
            -- Record info into L to help know which key to map.
            L.capture_action_id = action_id
            L.capture_input_index = i
            menu.buttonControl(
                row.index, { controltype, code, 
                oldinputtype, oldinputcode, oldinputsgn, 
                3, not mappable, context, allowmouseaxis, checklastnonkeyboard, 
                mouseonly, disableremove, isdblclick, 
                mousewheelonly, mouseaxisonly })
            return
        end
		row[3].properties.uiTriggerID = uiTriggerID

		if mouseovertext then
			row[3].properties.mouseOverText = mouseovertext
		end

        -- Button to remove a key.
		row[4]:createButton({ 
            active = buttons[i] ~= nil,
            width = config.standardTextHeight, 
            mouseOverText = ReadText(1026, 2677) 
            }):setText("X", { halign = "center", x = 0 })
		if buttons[i] then
			--row[4].handlers.onClick = function () return menu.buttonRemoveControl(
            --    row.index, { controltype, code, 
            --    oldinputtype, oldinputcode, oldinputsgn, 4, not mappable, 
            --    context, allowmouseaxis, checklastnonkeyboard }) end
            row[4].handlers.onClick = function ()
                    L.RemoveControl(action_id, i, row.index, 4)
                    return
                end
		end

		-- Button to add a new key.
		if i == 1 then
			row[5]:createButton({ 
                width = config.standardTextHeight, 
                mouseOverText = ReadText(1026, 2678) 
                }):setText("+", { halign = "center", x = 0 })

			row[5].handlers.onClick = function ()
                L.capture_action_id = action_id
                -- Insert at the end of the input list.
                L.capture_input_index = #player_keys.inputs + 1
                menu.buttonAddControl(
                    -- Row of the button will be further down (this is used
                    -- to select it after the row is added).
                    row.index + (next(buttons) and numbuttons or 0), 
                    { controltype, code, -1, -1, 0, 3, 
                    not mappable, context, allowmouseaxis, nil, mouseonly })
                return
            end
		end

		-- Draw a reset button for consistency but leave innactive.
		if i == 1 then
			row[6]:createButton({ active = false, 
                width = config.standardTextHeight, 
                mouseOverText = ReadText(1026, 2679) 
                }):setIcon("menu_reset_view", {  })
			row[6].handlers.onClick = function () return end
		end

	end
end

-- Pre-7.0 version.
--function L.displayControlRow(ftable, action_id)
--
--    local action    = L.action_registry[action_id]
--    local player_keys = L.player_action_keys[action_id]
--    
--    local row = ftable:addRow(true, { })
--    
--    -- Select the row if it was selected before menu reload.
--    if row.index == menu.preselectOption then
--        ftable:setSelectedRow(row.index)
--        -- Select a column, 3 or 4, those with buttons.
--        if menu.preselectCol == 3 or menu.preselectCol == 4 then
--            ftable:setSelectedCol(menu.preselectCol)
--        end
--    end
--
--    -- Set the action title.
--    -- This is column 2, since 1 is under the back arrow.
--    row[2]:createText(action.name, config.standardTextProperties)
--    if action.description then
--        row[2].properties.mouseOverText = action.description
--    end
--    
--    -- Create the two buttons.
--    for i = 1,2 do
--        local info = player_keys.inputs[i]
--
--        -- Get the name of an existing key, or blank.
--        local keyname, keyicon = "", nil
--        if info.source then
--            keyname, keyicon = menu.getInputName(info.source, info.code, info.signum)
--        end
--
--        -- Skip the funkiness regarding truncating the text string to
--        -- make room for the icon. TODO: maybe revisit if needed.
--        
--        -- Buttons start at column 3, so offset i.
--        local col = i+2
--        local button = row[col]:createButton({ mouseOverText = action.description or "" })
--        -- Set up the text label; this applies even without a keyname since
--        -- it handles blinking _.
--        button:setText(
--            -- 'nameControl' handles label blinking when changing.
--            function () return menu.nameControl(keyname, row.index, col) end,
--            -- Can probably leave color at default; don't need 'red' logic.
--            { color = Color.text_normal })
--        -- Add the icon.
--        if keyicon then
--            button:setText2(keyicon, { halign = "right" })
--        end
--
--        -- Clicks will hand off to buttonControl.
--        row[col].handlers.onClick = function () return menu.buttonControl(
--            -- Second arg is a list with a specific ordering.
--            row.index, {
--                -- controltype; go with whatever.
--                "functions", 
--                -- controlcode; go with the action id.
--                action_id,
--                -- oldinputtype
--                info.source,
--                -- oldinputcode
--                info.code,
--                -- oldinputsgn
--                info.signum,
--                -- column
--                col,
--                -- not_mapable/nokeyboard
--                false,
--                -- control_context; put whatever.
--                "hotkey_api",
--                -- allowmouseaxis
--                false,
--            }) end
--        -- Unclear on if this is good for anything; probably not.
--        --row[col].properties.uiTriggerID = "remapcontrol1a"
--
--    end    
--end


--[[
The following functions are after buttonControl(), the function
called when a button is pressed.

At this point, most of the args fed to displayControlRow are
present in a named table at menu.remapControl.
Fields are (maybe outdated since 7.0):
{ row, col, controltype, controlcode, controlcontext, oldinputtype,
    oldinputcode, oldinputsgn, nokeyboard, allowmouseaxis}
]]
    

-- This handles player input when setting custom keys.
-- Should only be called on player keys, not ego keys, so has no link
-- back to the original remapInput.
-- May be called multiple times recursively when not receiving keyboard keys.
-- Called by ego menu.registerDirectInput().
function L.remapInput(...)

    -- Always call this; ego does it right away.
    menu.unregisterDirectInput()

    -- Code to call on any return path, except those that still listen
    -- for keys.
    -- TODO: egosoft buttonControl and buttonAddControl handle this somewhat,
    -- but not quite the same; this is maybe partly or wholly unnecesary.
    local return_func = function()
        -- Reboot the menu. All paths in ego code end with this, so it may
        -- be required to recover properly.
        -- (At least need to clear remapControl, since it being filled triggers
        -- other code, eg. trying to unregister events when the menu closes
        -- causes log errors.)
        -- For 7.0, also close out the overlay menu, else it will spam errors.
		menu.closeContextMenu()
        menu.preselectTopRow = GetTopRow(menu.optionTable)
        menu.preselectOption = menu.remapControl.row
        menu.preselectCol = menu.remapControl.col
        menu.remapControl = nil
        menu.submenuHandler(menu.currentOption)
    end

    -- Safety wrap the rest of this logic.
    local success, error = pcall(L.remapInput_wrapped, return_func, ...)
    -- On error, still aim for the good return function setup.
    if not success then
        DebugError("remapInput error: "..tostring(error))
        return_func()
    end
end

-- Inner part of remapInput, allowed to error.
function L.remapInput_wrapped(return_func, newinputtype, newinputcode, newinputsgn)

    if debug.print_keycodes then
        Lib.Print_Table({
            controlcode = menu.remapControl.controlcode,
            newinputtype = newinputtype,
            newinputcode = newinputcode,
            newinputsgn = newinputsgn,
            }, "Control remap info")
        --DebugError(string.format(
        --    "Detected remap of code '%s'; new aspects: type %s, %s, %s", 
        --    tostring(menu.remapControl.controlcode),
        --    tostring(newinputtype),
        --    tostring(newinputcode),
        --    tostring(newinputsgn)
        --    ))
        --Lib.Print_Table(menu.remapControl, "menu.remapControl")
    end


    -- Look up the matching action.
    -- Note: action_id is also in menu.remapControl.controlcode.
    local action_id = L.capture_action_id
    if action_id ~= menu.remapControl.controlcode then
        DebugError("HotkeyAPI: action_id ~= menu.remapControl.controlcode")
    end
    local action_keys = L.player_action_keys[action_id]
    -- Error if not found.
    if not action_keys then
        error("Found no action_keys matching id: "..tostring(action_id))
    end

    -- Get the index in the input list to write to (or overwrite).
    local input_index = L.capture_input_index
    if input_index == nil then
        error("input_index == nil")
    end
            
    -- 'newinputtype' will be 1 for keyboard.
    -- Since only keyboard is wanted for now, restart listening if something
    -- else arrived.
    if newinputtype ~= 1 then
        -- DebugError("Hotkey: Non-keyboard input not supported.")
        -- Note: recursive call, so it the user inputs many non-keyboard events
        -- the call stack can grow excessively; this is also how egosoft
        -- does it, so probably okay normally.
        menu.registerDirectInput()
        -- If here, a valid key was found and handled already.
        return
    end

    -- TODO: consider integrating other ego style functions for avoiding
    -- control conflicts and such.
    
    -- Note the prior key combo, if any.
    local old_input_info = action_keys.inputs[input_index]
    local old_combo = old_input_info and old_input_info.combo or ""
    local new_combo

    -- Note: ego menu behavior has "escape" cancel the selection with no change,
    -- and "delete" remove the key binding.
    -- Try to mimic that here.

    -- Check for escape.
    if newinputtype == 1 and newinputcode == 1 then
        -- Do nothing.
        return return_func()

    -- Check for "delete" on a key that was mapped.
    elseif newinputtype == 1 and newinputcode == 211 then
        -- Prepare to reset to defaults.
        newinputtype = nil
        newinputcode = nil
        newinputsgn = nil
        new_combo = ""
    else
        -- Get the new combo string.
        new_combo = string.format("code %d %d %d", newinputtype, newinputcode, newinputsgn)

        -- -Removed, updated 3.0 makes ego's version too hard to use since
        --  it uses some special escape character and icon code for modifiers.
        ---- Start with ego's key name.
        ---- TODO: probably not robust across languages.
        ---- TODO: try out GetLocalizedRawKeyName
        --local ego_key_name, icon = menu.getInputName(newinputtype, newinputcode, newinputsgn)
        --
        ---- These are uppercase and with "+" for modified keys.
        ---- Translate to the combo form: space separated lowercase.
        --new_combo = string.lower( string.gsub(ego_key_name, "+", " ") )
        --if debug.print_keynames then
        --    DebugError(string.format("Ego key %s translated to combo %s", ego_key_name, new_combo))
        --end
    end
    

    -- If the new_combo is already recorded as either of the existing inputs,
    -- and is not empty (eg. deleting binding), do nothing.
    if new_combo ~= "" then        
        local combo_exists = false
        for _, key_info in ipairs(action_keys.inputs) do
            if key_info.combo == new_combo then
                combo_exists = true
            end
        end
        if combo_exists then
            if debug.print_keynames then
                DebugError("Ignoring already recorded key combo: "..new_combo)
            end
            return return_func()
        end
    end

    if new_combo == "" then
        -- Delete the entry, if it exists.
        if old_input_info ~= nil then
            if debug.print_keynames then
                DebugError("Deleting key combo: "..old_combo)
            end
            table.remove(L.player_action_keys[action_id].inputs, input_index)
        end
    else
        -- Overwrite stored key or add to end of list.
        action_keys.inputs[input_index] = {
            combo  = new_combo, 
            code   = newinputcode, 
            source = newinputtype, 
            signum = newinputsgn }
    end
        
    -- Signal md to update if the combo changed.
    Raise_Signal("Update_Key", {
        id      = action_keys.id,
        new_key = new_combo,
        old_key = old_combo,
        })

    -- Update md to save the keys.
    -- TODO: maybe integrate into Update_Key calls.
    L.Write_Player_Keys()

    return return_func()
end


function L.RemoveControl(action_id, i, row, col)
    local input_list = L.player_action_keys[action_id].inputs
    -- Safety against removing a blank line (though removal button should
    -- be disabled in that case, so this shouldn't be needed).
    if #input_list + 1 > i then
        if debug.print_keynames then
            DebugError("Deleting key combo: "..input_list[i].combo)
        end
        
        -- Signal md to update.
        Raise_Signal("Update_Key", {
            id      = action_id,
            new_key = "",
            old_key = input_list[i].combo,
            })
            
        -- Modify the list.
        table.remove(input_list, i)
        -- Update md to save the keys.
        L.Write_Player_Keys()

        -- Code found in egosoft buttonRemoveControl.
	    menu.preselectTopRow = GetTopRow(menu.optionTable)
	    menu.preselectOption = row
	    menu.preselectCol = col
	    menu.remapControl = nil
	    menu.submenuHandler(menu.currentOption)
	    --AddUITriggeredEvent(menu.name, "remap_removed")
    end
end


---- Patch registration.
---- Unused currently.
--function L.registerDirectInput(ego_registerDirectInput)
--    -- Check for this being a custom key.
--    if menu.remapControl.controlcontext == 1000 then
--        C.DisableAutoMouseEmulation()
--        for event, func in pairs(L.input_event_handlers) do
--            RegisterEvent(event, func)
--        end
--        ListenForInput(true)
--    else
--        ego_registerDirectInput()
--    end
--end
--    
---- Patch unregistration.
---- Unused currently.
--function L.unregisterDirectInput(ego_unregisterDirectInput)
--    -- Check for this being a custom key.
--    if menu.remapControl.controlcontext == 1000 then
--        ListenForInput(false)
--        for event, func in pairs(L.input_event_handlers) do
--            UnregisterEvent(event, func)
--        end
--        C.EnableAutoMouseEmulation()
--    else
--        ego_unregisterDirectInput()
--    end
--end

Register_OnLoad_Init(Init, "extensions.sn_mod_support_apis.ui.hotkey.Interface")


--[[
Development notes.
Note: these were written before 7.0 changes, so some descriptions may be wrong.

The existing ui functions are in gameoptions.lua.
    
    config.input.controlsorder
    - Holds data on various keys
    - Subfields space, menus, firstperson
      - Nested tables have section titles, table of keys.
      - Each key entry's arg order appears to be:
        - [controltype, code, context, mouseovertext, allowmouseaxis]
        - Many keys leave fields 3-5 unused.
    - Local, so no way to add keys without direct overwrite.

    config.input.controlsorder.space[i]
    - Table, keyed partially by indices and partly by named fields.
    - .title, .mapable, [1-5]

    config.input.directInputHookDefinitions
      List of sublists like:
        {"keyboardInput", 1, 0}
        
    config.input.directInputHooks
        
    config.input.directInputHooks
    - Table of functions, one per directInputHookDefinition.
    - Functions take a keycode, and call menu.remapInput with info on what type of input.
    - One function for each input type: keyboard, mouse, occulus, vive, and subtypes.
    - Ex: function (_, keycode) menu.remapInput(entry[2], keycode, entry[3])
      
    config.input.forbiddenkeys
      Gives a couple examples of keycodes:
        [1]   = true, - Escape
        [211] = true, - Delete
        
    menu
    - Table that defines menu properties, registered with general gui.
    - Accessible through Menus global, so functions can potentially overwritten.
    - Since functions often reference locals, overwrites may not be very useful,
      as other files won't have access to those locals.
      
    menu.getInputName(source, code, signum)
      Translates a key code into a name.
      'source' is an integer which appears to represent input source (keyboard, mouse, ...)
      'signum' appears to add a "+" or "-" if used.
      
      Keyboard key names are from GetLocalizedRawKeyName(code).
      Mouse button names are from ffi.string(C.GetLocalizedRawMouseButtonName(code)).
      Others are from the text file.

      Text file has names of some key codes:
        Page 1018: mouse axes
        Page 1022: joystick buttons
        etc.

    menu.displayControls(string optionParameter)
    - Creates the whole controls tab, for one of space, menus, or first person.
    - Hardcoded for these three; don't bother adding a new category without
      substantial copy/paste monkeypatching.
    - Loops over "controls", eg. members of config.input.controlsorder.space
      - Makes a section label, eg. "Steering: Analog"
      - Calls menu.displayControlRow() for each key, passing args.
      - Has various logic to filter which controls are shown, notably based on
        the search bar, which can potentially be ignored (eg. always show any
        custom hotkeys).


    menu.displayControlRow(
            ftable, controlsgroup, controltype, code, context, 
            mouseovertext, mappable, allowmouseaxis, first, checklastnonkeyboard, 
            compassmenusupport, mouseonly, mousewheelonly, mouseaxisonly)

        Handles drawing rows of the keybind menu.
        'code' is for a specific action being mapped.
        'controlsgroup' is an index of a group in config.input.controlsorder.

        (controltype, code, context, mouseovertext) are unpacked 
        from config.input.controlsorder, often with (controltype, code) 
        filled and others nil.

        Current key texts are taken from menu.nameControl(), which is fed the
        name and may replace it with blinking "_"/"" for a key currently
        being remapped.

        Button onClick events call buttonControl (edit existing control),
        buttonAddControl (clicked "+"), buttonRemoveControl (clicked "X"),
        passing along fields used to fill in menu.remapControl.
      
      
        This will look up various data from menu.controls, which was
        set in menu.getControlsData(). This is a table of control types,
        with most being pulled from C code except for "functions"
        which is pulled from config.input.controlFunctions.

        displayControlRow will reference:
        menu.controls[controltype][code]
            .contexts
            .definingcontrol
            .actions
            .states
            .ranges

        Each "functions" entry defines a "definingcontrol" field, which
        is a reference to another controls subtable and key.
        Eg. {"states", 22} will get redirected to menu.controls["states"][22].
        This in turn is a list of "inputs", where each input
        is a list of {source, code, signum}, the current input for
        that control.

        If reusing this function, the related tables need to be updated:
        "functions" with a name and definingcontrol.
        "actions" or similar with the current recorded input, originally
        saved from md.
    
      
    menu.buttonControl(row, data)
    - Called when user clicks an input remap button.
    - data is a list with the following fields (note: maybe outdated):
      {controltype, controlcode, oldinputtype, oldinputcode, oldinputsgn, column (often set to 3 or 4), not_mapable/nokeyboard, control_context, allowmouseaxis}
    - Stores a table including data contents into menu.remapControl for lookup later.
      - Names all the args, and adds 'row'.
    - Sets menu.contextMenuMode = "directinput".
    - Calls menu.createContextMenu() to creates a popup window that shows info
      about the action (name, current key, etc.); this window is purely
      informational.
    - Calls menu.registerDirectInput() to listen for user key press and handle
      any further code/menu updates.
      
    menu.registerDirectInput(...)
    - Runs RegisterEvent on all events in config.input.directInputHookDefinitions,
      setting functions in config.input.directInputHooks as handlers.
    - Calls ListenForInput(true).
    - So, this is where it kicks off listening for a new user key press.
    - Presumably, ListenForInput sets a mode which will raise one of these
      events, eg. "keyboardInput" on a key press.

    ListenForInput(?)
      External function; unknown behavior.
      
    menu.unregisterDirectInput()
      Undoes registerDirectInput: unregisters events, calls ListenForInput(false).
      
      
    menu.remapInput(newinputtype, newinputcode, newinputsgn)
    - Has a bunch of logic for processing the key.
    - Clears conflicts, rejects disallowed keys, etc.
    - Calls menu.unregisterDirectInput(), to stop listening for new keys.
    - Calls checkInput, presumably to clear conflicts.
    - May delete a key if 211 (delete) was pressed.
      - Calls menu.removeInput() on this path.    
    - At end calls SaveInputSettings(menu.controls.actions, menu.controls.states, menu.controls.ranges).
        - SaveInputSettings is exe level.
    - Note: this is not called directly, but indirectly through menu.registerDirectInput()
      which in turn looks it up in config.input.directInputHooks, initialized
      on lua loading. Those wrapper funcs do look it up in menu, though, so
      a direct monkey patch works.
    - If an invalid key is given, this will call registerDirectInput and
      return, effectively doing recursive calls to listen for different keys
      until finding a valid one.
              
                  
    menu.removeInput()
      At end calls SaveInputSettings(menu.controls.actions, menu.controls.states, menu.controls.ranges).
      
    SaveInputSettings(?,?,?)
      External function; unknown behavior.
      Presumably this transfers current key mappings to exe side for actual
      key listening and functionality.
      
      
Keycodes:
    - The example codes for escape (1) and delete (211) don't mach up with windows keycodes.
    - However, they do match this lua file, and its linked c++ file:
      - https://github.com/lukemetz/moonstone/blob/master/src/lua/utils/keycodes.lua
      - https://github.com/wgois/OIS/blob/master/includes/OISKeyboard.h
    - Using the above, can potentially translate user keys appropriately.
    
]]