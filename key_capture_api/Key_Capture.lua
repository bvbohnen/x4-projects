--[[
Lua side of the key capture api.
This primarily aims to interface tightly with the egosoft menu system,
to leverage existing code for allowing players to customize hotkeys.

Patches the OptionsMenu.
]]

-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    uint32_t GetMouseHUDModeOption(void);
]]

-- Imports. TODO: maybe pull from other helper extensions.
local Lib = require("extensions.key_capture_api.Library")

-- Local functions and data.
local L = {
    -- Shadow copy of the md's shortcut registry.
    shortcut_registry = {},

    -- Table of assigned keys and their shortcuts, keyed by id.
    -- This is mirrored in a player blackboard var whenever it changes.
    player_shortcut_keys = {},

    -- Wrapper functions on remapInput to be used in registering for input events.
    input_event_handlers = {},
    }


-- Proxy for the gameoptions menu, linked further below.
local menu = nil


-- Ego style config. Copying over needed consts.
local config = {
    optionsLayer = 3,
    topLevelLayer = 4,

    backarrow = "table_arrow_inv_left",
    backarrowOffsetX = 3,

    sliderCellValueColor = { r = 71, g = 136, b = 184, a = 100 },
    greySliderCellValueColor = { r = 55, g = 55, b = 55, a = 100 },

    font = "Zekton outlined",
    fontBold = "Zekton bold outlined",

    headerFontSize = 13,
    infoFontSize = 9,
    standardFontSize = 10,

    headerTextHeight = 34,
    subHeaderTextHeight = 22,
    standardTextHeight = 19,
    infoTextHeight = 16,

    headerTextOffsetX = 5,
    standardTextOffsetX = 5,
    infoTextOffsetX = 5,

    vrIntroDelay = 32,
    vrIntroFadeOutTime = 2,
}
config.headerTextProperties = {
    font = config.fontBold,
    fontsize = config.headerFontSize,
    x = config.headerTextOffsetX,
    y = 6,
    minRowHeight = config.headerTextHeight,
    titleColor = Helper.defaultSimpleBackgroundColor,
}
config.subHeaderTextProperties = {
    font = config.font,
    fontsize = config.standardFontSize,
    x = config.standardTextOffsetX,
    y = 2,
    minRowHeight = config.subHeaderTextHeight,
    halign = "center",
    titleColor = Helper.defaultSimpleBackgroundColor,
}


local function Init()

    -- MD triggered events.
    RegisterEvent("Key_Capture.Update_Shortcuts", L.Update_Shortcuts)
    RegisterEvent("Key_Capture.Update_Player_Keys", L.Read_Player_Keys)
    
    -- Cache the player component id.
    L.player_id = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    
    -- Signal to md that a reload event occurred.
    -- This will also trigger md to send over its stored list of
    -- player assigned keys.
    Lib.Raise_Signal("reloaded")
    

    -- Stop if something went wrong.
    if Menus == nil then
        error("Menus global not yet initialized")
    end
    
    -- Search the ego menu list. When this lua loads, they should all
    -- be filled in.
    for i, ego_menu in ipairs(Menus) do
        if ego_menu.name == "OptionsMenu" then
            menu = ego_menu
        end
    end
    
    -- Stop if something went wrong.
    if menu == nil then
        error("Failed to find egosoft's OptionsMenu")
    end
    
    -- Patch displayOptions.
    local ego_displayControls = menu.displayControls
    menu.displayControls = function(...)
        -- Start by building the original manu.
        -- Note that this calls frame:display().
        ego_displayControls(...)
        -- Safety call.
        local success, error = pcall(L.displayControls, ...)
        if not success then
            DebugError("displayControls error: "..tostring(error))
        end
    end
    
    -- Patch remapInput, which catches the player's new keys.
    local ego_remapInput = menu.remapInput
    menu.remapInput = function(...)
        -- Hand off to ego function if this isn't a custom key.
        if menu.remapControl.controlcontext ~= "key_capture" then
            ego_remapInput(...)
            return
        end        
        -- Safety call.
        local success, error = pcall(L.remapInput, ...)
        if not success then
            DebugError("remapInput error: "..tostring(error))
        end
    end
    
    -- TODO: replace the event registration functions which select which
    -- input types to capture.  Just want keyboard for custom controls.
    -- TODO: also need to suppress key_capture from triggering cues while
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
    
end


-- Handle md requests to update the shortcut registry.
-- Reads data from a player blackboard var.
function L.Update_Shortcuts()
    -- Args are attached to the player component object.
    local md_table = GetNPCBlackboard(L.player_id, "$key_capture_shortcuts")

    -- Note: md may have sent several of these events on the same frame,
    -- in which case the blackboard var has just the args for the latest
    -- event, and later events processed will get nil.
    -- Skip those nil cases.
    if not md_table then return end
    L.shortcut_registry = md_table

    -- Clear the md var by writing nil.
    SetNPCBlackboard(L.player_id, "$key_capture_shortcuts", nil)
    
    Lib.Print_Table(L.shortcut_registry, "Update_Shortcuts shortcut_registry")
end

-- Read in the stored list of player shortcut keys.
-- Generally md will send this on init.
function L.Read_Player_Keys()
    -- Args are attached to the player component object.
    local md_table = GetNPCBlackboard(L.player_id, "$key_capture_player_keys_from_md")
    -- This shouldn't get getting nil values since the md init is
    -- sent just once, but play it safe.
    if not md_table then return end
    L.player_shortcut_keys = md_table

    -- Clear the md var by writing nil.
    SetNPCBlackboard(L.player_id, "$key_capture_player_keys_from_md", nil)
    
    Lib.Print_Table(L.player_shortcut_keys, "Read_Player_Keys player_shortcut_keys")
end

-- Write to the list of player shortcut keys to be stored in md.
-- This could be integrated into remapInput, but kept separate for now.
function L.Write_Player_Keys()
    -- Args are attached to the player component object.
    SetNPCBlackboard(L.player_id, "$key_capture_player_keys_from_lua", L.player_shortcut_keys)
    Lib.Raise_Signal("Store_Player_Keys")
    
    Lib.Print_Table(L.player_shortcut_keys, "Write_Player_Keys player_shortcut_keys")
end



-- Patch to add custom keys to the control remap menu.
function L.displayControls (optionParameter)
    --DebugError("GameOptions.displayControls() called")


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
    -- TODO: could maybe also do menu.optionTable.
    local ftable
    for i=1,#frame.content do
        if frame.content[i].type == "table" then
            ftable = frame.content[i]
        end
    end
    if ftable == nil then
        error("Failed to find gameoptions menu main ftable")
    end
        
    -- Add a nice title.
    local row = ftable:addRow(false, { bgColor = Helper.color.transparent })
    row[2]:setColSpan(3):createText("Extensions", config.subHeaderTextProperties)

    --[[ 
    Notes on displayControlRow indirect inputs:

    This will look up various data from menu.controls, which was
    set in menu.getControlsData(). This is a table of control types,
    with most being pulled from C code except for "functions"
    which is pulled from config.input.controlFunctions.

    displayControlRow will reference:
    menu.controls[controltype][code]
        .name
        .contexts
        .definingcontrol

    'controltype' needs to be "functions" else displayControlRow will
    try to read the name from config, where it isn't available.

    Each "functions" entry defines a "definingcontrol" field, which
    is a reference to another controls subtable and key.
    Eg. {"states", 22} will get redirected to menu.controls["states"][22].
    This in turn is a list of "inputs" (up to 2), where each input
    is a list of {source, code, signum}, the current input for
    that control.

    Custom controls need to be added to "functions" to be able to
    give their name, as well as to 
    ]]
    --Lib.Print_Table(menu.controls, "menu.controls")

    -- Prune out old custom keys.
    for _, field in ipairs({"actions","functions"}) do
        -- Use reverse iteration, to delete entries from the back.
        for i = #menu.controls[field], 1, -1 do
            -- Note: unlike normal lua tables, there appear to be gaps
            --  in ego's tables, though the # arg still gives a high
            --  number (perhaps explicit 'n' field filled in).
            -- Skip nil entries.
            if menu.controls[field][i] and menu.controls[field][i].from_key_capture then
                menu.controls[field][i] = nil
            end
        end
    end

    -- Error check.
    if not L.shortcut_registry then
        DebugError("shortcut_registry is nil")
        return
    end
        
    -- Set up the custom shortcuts.
    -- TODO: ordering.
    for id, shortcut in pairs(L.shortcut_registry) do

        -- If there is no entry for player keys yet, make one.
        if not L.player_shortcut_keys[shortcut.id] then
            L.player_shortcut_keys[shortcut.id] = {
                -- Repetition of id, in case it is ever useful.
                id = shortcut.id,
                -- List of inputs.
                -- Note: unused entries are elsewhere {-1,-1,0}, though that
                -- led to problems when tried.  All nil works okay.
                inputs = {
                    [1] = {combo  = "", code = nil, source = nil, signum = nil},
                    [2] = {combo  = "", code = nil, source = nil, signum = nil},
                }
            }
        end

        -- Hand off to custom function.
        L.displayControlRow(ftable, shortcut.id)

        --[[ Removed; below used ego's displayControlRow and made a mess.

        -- Note: ego uses a "code" or "controlcode" to track which key is
        -- which. These match up to an index in the menu.controls[] tables.
        -- But this can be replaced with the shortcut id for the custom
        -- handling.
        local code = shortcut.id


        menu.controls["functions"][code] = {
            ["name"] = shortcut.name, 
            -- This redirects to one of the other subtables of menu.controls.
            ["definingcontrol"] = {"actions", code}, 
            -- Maybe just have "actions" match the above keycode.
            ["actions"] = { code }, 
            ["states"] = {}, 
            ["ranges"] = {},
            -- Custom context.
            ["contexts"] = "key_capture",
            -- Extra field to identify added keys.
            ["from_key_capture"] = true,
            }

        -- Add a new "action" to define the current keys.
        menu.controls["actions"][code] = {["from_key_capture"] = true}
        -- Fill with stored player keys, in menu column order.
        for i = 1,2 do
            local info = L.player_shortcut_keys[shortcut.id].inputs[i]
            menu.controls["actions"][code][i] = {info.source, info.code, info.signum}
        end
            
        -- Call the function to add the new key.
        local isdoubleclickmode = C.GetMouseHUDModeOption() == 2
        menu.displayControlRow(
            -- ftable
            ftable,
            -- controlsgroup; matches index of controls subtable, but unused.
            -- 11+ is free for space; just pick something.
            20,
            -- controltype; "actions" "functions" or "state".
            -- Needs to be "functions" for name lookup to work.
            "functions",
            -- code; int, these appear meant to match up to the c++ side.
            -- Stock codes go up to 300ish.
            -- In practice, all the ego code that assumes this is an int should
            -- be bypassed, so can use the shortcut id instead.
            code,
            -- context; nil/int/table, not used anyway since this is read
            -- from ego_controls[].contexts.
            "key_capture",
            -- mouseovertext
            shortcut.description,
            -- mapable
            true,
            -- isdoubleclickmode; looked up in C function.
            isdoubleclickmode,
            -- allowmouseaxis; don't support this for now.
            false )
            ]]
    end
            
    -- Need to re-display.
    -- TODO: stress test for problems.
    -- In practice, this causes log warning spam display() done directly, since
    -- the display() function builds a whole new frame, but the old frame's
    -- scripts weren't cleared out.
    -- Manually do the script clear first.
    -- (Unlike clearDataForRefresh, this call just removes scripts,
    -- not existing widget descriptors.)
    Helper.removeAllWidgetScripts(menu, config.optionsLayer)
    frame:display()
end


-- Copy/edit of ego's function for displaying a control row of text
-- and two buttons.
-- Attempts to reuse ego's function were a mess.
function L.displayControlRow(ftable, shortcut_id)

    local shortcut    = L.shortcut_registry[shortcut_id]
    local player_keys = L.player_shortcut_keys[shortcut_id]
    
    local row = ftable:addRow(true, { bgColor = Helper.color.transparent })
    
    -- Select the row if it was selected before menu reload.
    if row.index == menu.preselectOption then
        ftable:setSelectedRow(row.index)
        -- Select a column, 3 or 4, those with buttons.
        if menu.preselectCol == 3 or menu.preselectCol == 4 then
            ftable:setSelectedCol(menu.preselectCol)
        end
    end

    -- Set the shortcut title.
    -- This is column 2, since 1 is under the back arrow.
    row[2]:createText(shortcut.name, config.standardTextProperties)
    if shortcut.description then
        row[2].properties.mouseOverText = shortcut.description
    end
    
    -- Create the two buttons.
    for i = 1,2 do
        local info = player_keys.inputs[i]

        -- Get the name of an existing key, or blank.
        local keyname, keyicon = "", nil
        if info.source then
            keyname, keyicon = menu.getInputName(info.source, info.code, info.signum)
        end

        -- Skip the funkiness regarding truncating the text string to
        -- make room for the icon. TODO: maybe revisit if needed.
        
        -- Buttons start at column 3, so offset i.
        local col = i+2
        local button = row[col]:createButton({ mouseOverText = shortcut.description or "" })
        -- Set up the text label; this applies even without a keyname since
        -- it handles blinking _.
        button:setText(
            -- 'nameControl' handles label blinking when changing.
            function () return menu.nameControl(keyname, row.index, col) end,
            -- Can probably leave color at default; don't need 'red' logic.
            { color = Helper.color.white })
        -- Add the icon.
        if keyicon then
            button:setText2(keyicon, { halign = "right" })
        end

        -- Clicks will hand off to buttonControl.
        row[col].handlers.onClick = function () return menu.buttonControl(
            -- Second arg is a list with a specific ordering.
            row.index, {
                -- controltype; go with whatever.
                "functions", 
                -- controlcode; go with the shortcut id.
                shortcut_id,
                -- oldinputtype
                info.source,
                -- oldinputcode
                info.code,
                -- oldinputsgn
                info.signum,
                -- column
                col,
                -- not_mapable/nokeyboard
                false,
                -- control_context; put whatever.
                "key_capture",
                -- allowmouseaxis
                false,
            }) end
        -- Unclear on if this is good for anything; probably not.
        --row[col].properties.uiTriggerID = "remapcontrol1a"

    end    
end


--[[
The following functions are after buttonControl(), the function
called when a button is pressed.

At this point, most of the args fed to displayControlRow are
present in a named table at menu.remapControl.
Fields are:
{ row, col, controltype, controlcode, controlcontext, oldinputtype,
    oldinputcode, oldinputsgn, nokeyboard, allowmouseaxis}
]]
    

-- This handles player input when setting custom keys.
-- Should only be called on player keys, not ego keys, so has no link
-- back to the original remapInput.
function L.remapInput(...)

    -- Always call this; ego does it right away.
    menu.unregisterDirectInput()

    -- Code to call on any return path, except those that still listen
    -- for keys.
    local return_func = function()
        -- Reboot the menu. All paths in ego code end with this, so it may
        -- be required to recover properly.
        -- (At least need to clear remapControl, since it being filled triggers
        -- other code, eg. trying to unregister events when the menu closes
        -- causes log errors.)
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

    DebugError(string.format(
        "Detected remap of code '%s'; new aspects: %s, %s, %s", 
        tostring(menu.remapControl.controlcode),
        tostring(newinputtype),
        tostring(newinputcode),
        tostring(newinputsgn)
        ))
    Lib.Print_Table(menu.remapControl, "menu.remapControl")


    -- Look up the matching shortcut.
    local shortcut_keys = L.player_shortcut_keys[menu.remapControl.controlcode]
    -- Error if not found.
    if not shortcut_keys then
        error("Found no shortcut_keys matching id: "..tostring(menu.remapControl.controlcode))
    end

            
    -- 'newinputtype' will be 1 for keyboard.
    -- Since only keyboard is wanted for now, restart listening if something
    -- else arrived.
    if newinputtype ~= 1 then
        -- DebugError("Key Capture: Non-keyboard input not supported.")
        menu.registerDirectInput()
        -- Normal return; keep listener going.
        return
    end

    -- TODO: consider integrating other ego style functions for avoiding
    -- control conflicts and such.
    
    -- Use col (3 or 4) to know which index to replace (1 or 2).
    -- Try to make this a little safe against patches adding columns.
    local input_index
    if menu.remapControl.col <= 3 then
        input_index = 1
    else
        input_index = 2
    end
    
    -- Note the prior key combo.
    local old_combo = shortcut_keys.inputs[input_index].combo
    local new_combo

    -- Check for "delete" on a key that was mapped.
    -- (oldinputcode == -1 means it wasn't mapped.)
    if newinputtype == 1 and newinputcode == 211 then
        newinputtype = nil
        newinputcode = nil
        newinputsgn = nil
        new_combo = ""
    else
        -- Get the new combo string.
        -- Start with ego's key name.
        -- TODO: probably not robust across languages.
        local ego_key_name, icon = menu.getInputName(newinputtype, newinputcode, newinputsgn)

        -- These are uppercase and with "+" for modified keys.
        -- Translate to the combo form: space separated lowercase.
        new_combo = string.lower( string.gsub(ego_key_name, "+", " ") )
    end
    
    DebugError(string.format("Ego key %s translated to combo %s", ego_key_name, new_combo))

    -- If the new_combo is already recorded as either of the existing inputs,
    -- do nothing.
    if shortcut_keys.inputs[1].combo == new_combo or shortcut_keys.inputs[2].combo == new_combo then
        DebugError("Ignoring already recorded key combo: "..new_combo)
        return return_func()
    end

    -- Overwrite stored key.
    shortcut_keys.inputs[input_index] = {
        combo  = new_combo, 
        code   = newinputcode, 
        source = newinputtype, 
        signum = newinputsgn }
        
    -- Signal lua to update if the combo changed.
    Lib.Raise_Signal("Update_Key", {
        id      = shortcut_keys.id,
        new_key = new_combo,
        old_key = old_combo,
        })

    -- Update the md to save the keys.
    -- TODO: maybe integrate into Update_Key calls.
    L.Write_Player_Keys()

    return return_func()
end


-- Patch registration.
-- Unused currently.
function L.registerDirectInput(ego_registerDirectInput)
    -- Check for this being a custom key.
    if menu.remapControl.controlcontext == 1000 then
        C.DisableAutoMouseEmulation()
        for event, func in pairs(L.input_event_handlers) do
            RegisterEvent(event, func)
        end
        ListenForInput(true)
    else
        ego_registerDirectInput()
    end
end
    
-- Patch unregistration.
-- Unused currently.
function L.unregisterDirectInput(ego_unregisterDirectInput)
    -- Check for this being a custom key.
    if menu.remapControl.controlcontext == 1000 then
        ListenForInput(false)
        for event, func in pairs(L.input_event_handlers) do
            UnregisterEvent(event, func)
        end
        C.EnableAutoMouseEmulation()
    else
        ego_unregisterDirectInput()
    end
end


Init()


--[[
Development notes:

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


    menu.displayControlRow(ftable, controlsgroup, controltype, code, context, mouseovertext, mapable, isdoubleclickmode, allowmouseaxis)
        Handles drawing one row of the keybind menu.
        'code' is for a specific function being mapped.

        (controlsgroup, controltype, code, context, mouseovertext) are unpacked from config.input.controlsorder,
        often with (controlsgroup, controltype) filled and others nil.

        Current key texts are taken from menu.nameControl(), which is fed the
        name and may replace it with blinking "_"/"" for a key currently
        being remapped.

        Button onClick events call menu.buttonControl() which triggers the
        remapping.
      
      
        This will look up various data from menu.controls, which was
        set in menu.getControlsData(). This is a table of control types,
        with most being pulled from C code except for "functions"
        which is pulled from config.input.controlFunctions.

        displayControlRow will reference:
        menu.controls[controltype][code]
            .name
            .contexts
            .definingcontrol

        'controltype' needs to be "functions" else displayControlRow will
        try to read the name from config, where it isn't available.

        Each "functions" entry defines a "definingcontrol" field, which
        is a reference to another controls subtable and key.
        Eg. {"states", 22} will get redirected to menu.controls["states"][22].
        This in turn is a list of "inputs" (up to 2), where each input
        is a list of {source, code, signum}, the current input for
        that control.

        If reusing this function, the related tables need to be updated:
        "functions" with a name and definingcontrol.
        "actions" or similar with the current recorded input, originally
        saved from md.
    
      
    menu.buttonControl(row_index, data_table)
    - Called when user clicks an input remap button.
    - data_table is a list with the following fields:
      {controltype, controlcode, oldinputtype, oldinputcode, oldinputsgn, column (often set to 3 or 4), not_mapable/nokeyboard, control_context, allowmouseaxis}
    - Stores a table including data_table contents into menu.remapControl for lookup later.
      - Names all the args, and adds 'row'.
    - Sets up info for blinking button during remapping.
    - Calls menu.registerDirectInput() to listen for user key press.
      
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
    
    
Possibly adding new keys:
    a) monkeypatch menu.displayControls.
      - Run the normal version first; this ends in frame:display() (worrisome).
      - Add a custom section title.
      - Call menu.displayControlRow() for each new key, matching args.
    b) patch menu.remapInput to catch user assignments.
]]