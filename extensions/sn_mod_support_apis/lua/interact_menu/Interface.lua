
--[[
Module for adding new context menu actions.
Note: not dependent on the simple menu flow directly, except for
some library functions.

menu.showInteractMenu()
- Sets up the component, or selected objects.
- Fills menu state data from call params (processed elsewhere?).
- Calls menu.display()

menu.onShowMenu()
- Also sets up the component, or selected objects.
- Has more logic for setting up menu state data, eg. filling a default
  selectedplayerships.
- Calls menu.display()

menu.display()
- Records mouse position (not used anywhere?)
- Calls menu.prepareActions() 
- Calls menu.draw()
- Can potentially intercept and delay this one frame to get md responses.
- Note: don't just delay this by a frame, since an onUpdate can fire before
  display() is called, causing problems.
- Could possibly delay this while suppressing onUpdate.

menu.draw()
- Sets up widget stuff.
- Records menu.mouseOutBox, used in update function to close the menu if the
  mouse is outside the box.

menu.onUpdate()
- Checks menu.mouseOutBox.
- Calls menu.prepareActions() if player activity changed (eg. a scan completed)
- Calls menu.draw() if things have changed.
- Note: to suppress onUpdate, note that when the menu showMenuCallback kicks
  off in Helper, onUpdate is recorded into a wrapper function, so an extra
  wrapper will need to be created here and manipulated for its internal
  call to menu.onUpdate. Further, Helper.interactMenuCallbacks.update is
  another link to menu.onUpdate, which also needs switching.
    
menu.prepareActions() 
- Bunch of logic for different possible actions.
- Standard action list obtained externally from:
    - C.GetCompSlotPlayerActions(buf, n, menu.componentSlot)
    - Action list depends on target component?
- Makes many conditional calls to insertInteractionContent() 
    to register the actions.
- Can be followed with adding new actions.
- Returns "anydisplayed", true if there are any menu entries.
            
        
insertInteractionContent(section, entry)
    Appears to register a new action.
    * section
        String, matching a section name in config.sections
        Eg:
            main
            player_interaction
            selected_orders
            playersquad_orders
            etc.
    * entry
        Table with some subfields.
        * type
            - String, often called actiontype, eg. "teleport", "upgrade", etc.
            - When loading predefined orders from C ffi, type names are used
              to select which section to use.
            - Gets set to the widget uiTriggerID, which will cause a ui
              event of this name when the widget is clicked.
            - Can leave as nil to prevent excess ui events, particularly to
              avoid an accidental collision to existing ui listeners.
        * text
            - String, display text
            - Icons appear to be added using a special text term:
              - "\27[<icon name>]"
        * text2
            - String, right side text?
        * helpOverlayID
            - String, unique gui id?  Never seems to be used.
        * helpOverlayText
            - String, often blank
        * helpOverlayHighlightOnly
            - Bool, often true
        * script
            - Lua function callback, no input args.
            - Often given as a "menu.button..." function in this lue module.
        * hidetarget
            - Bool, often true
            - TODO: what is this? useful?
        * active
            - Lua function, returns bool?
            - Greys it out if unnactive, maybe?
            - No smooth and easy way to hook into this dynamically from md.
        * mouseOverText
            - String

Notes on subsections:
    Sections are defined in the local config table, and sometimes have
    subsections.
    Each action is assigned a section, recorded into menu.actions[section] lists.
    Subsections are shown if they have actions recorded, or are forced to
    show by being added to a "menu.forced[section] = name" table of names.

    Since config is static, there is no good way to create new subsections.
    New actions should use existing sections.

Some menu state data of interest:
* componentSlot.component
  - Raw component UniverseID, the target of the menu.
* connection, componentSlot.connection
  - Some string?; not used anywhere obvious.
* selectedplayerships
  - List of player owned ships selected, explicit or implicit.
  - Converted components (ConvertStringTo64Bit out).
  - When empty for onShowMenu, fills with the player's ship (piloted or
    occupying).
* selectedplayerdeployables, selectedotherobjects
  - Lists
  - Converted components
* mode
  - Either nil or "shipconsole".
  - Only set up by onShowMenu.
* isdockedship
  - Either nil or true/false.
  - Only set by onShowMenu when mode == "shipconsole"
* construction
  - Construction object.  Has attributes: inprogress, component, macro, id.
  - Cancel action operates on id against the componentSlot.component.
* mission
  - ID of a mission already active.
* missionoffer
  - ID of a mission offer.
* componentOrder
  - Order object, generally using a menu.componentOrder.queueidx value.
* subordinategroup
  - Appears to be an integer 1-24 matching a wing number.
  - Used directly look up text entry on page 20401 (greek letters).
* offsetcomponent
  - UniverseID Sector (or something else), a reference position in space?
* offset
  - UIPosRot, relative offset from offsetcomponent.
* componentMissions
  - List of mission ids.
* playerSquad
  - Just a list populated with subordinates of the player ship.
  - MD can recreate this if needed.
]]

-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef uint64_t UniverseID;
    bool IsUnit(UniverseID controllableid);
    UniverseID GetPlayerOccupiedShipID(void);
    UniverseID GetPlayerControlledShipID(void);
    UniverseID GetPlayerContainerID(void); 
    typedef struct {
        const char* missionName;
        const char* missionDescription;
        int difficulty;
        int upkeepalertlevel;
        const char* threadType;
        const char* mainType;
        const char* subType;
        const char* subTypeName;
        const char* faction;
        int64_t reward;
        const char* rewardText;
        size_t numBriefingObjectives;
        int activeBriefingStep;
        const char* opposingFaction;
        const char* license;
        float timeLeft;
        double duration;
        bool abortable;
        bool hasObjective;
        UniverseID associatedComponent;
        UniverseID threadMissionID;
    } MissionDetails;
    MissionDetails GetMissionIDDetails(uint64_t missionid);
]]

-- Use local debug flags.
-- Note: rely on the simple_menu_api lib functions.
local debugger = {
    verbose = false,
}
local Lib = require("extensions.sn_mod_support_apis.lua.Library")
local Time = require("extensions.sn_mod_support_apis.lua.time.Interface")



-- Table of locals.
local L = {
    settings = {
        -- Extension option setting to disable these hooks, for safety.
        disabled = false,
    },

    -- Component of the player.
    player_id = nil,

    -- Flag indicating if a menu display is currently being delayed
    -- by a frame.
    delaying_menu = false,

    -- List of queued command args.
    queued_args = {},

    -- Table of custom actions, keyed by id.
    -- Old style: perpetual actions loaded at startup.
    static_actions = {},
    -- New style: one-use actions sent on menu open.
    temp_actions = {},

    -- Lists of ids, order in which action ids were declared.
    static_actions_order = {},
    temp_actions_order = {},

    -- Current table of target object flags.
    flags = nil,
}

-- Convenience link to the egosoft interact menu.
local menu

function L.Init()
    
    -- MD triggered events.
    RegisterEvent("Interact_Menu.Process_Command", L.Handle_Process_Command)
    
    -- Signal to md that a reload event occurred.
    AddUITriggeredEvent("Interact_Menu_API", "reloaded")

    -- Cache the player component id.
    L.player_id = ConvertStringTo64Bit(tostring(C.GetPlayerID()))

    L.Init_Patch_Menu()
end


-- Extract blackboard args.
function L.Get_Next_Args()

    -- If the list of queued args is empty, grab more from md.
    if #L.queued_args == 0 then
    
        -- Args are attached to the player component object.
        local args_list = GetNPCBlackboard(L.player_id, "$interact_menu_args")
        
        -- Loop over it and move entries to the queue.
        for i, v in ipairs(args_list) do
            table.insert(L.queued_args, v)
        end
        
        -- Clear the md var by writing nil.
        SetNPCBlackboard(L.player_id, "$interact_menu_args", nil)
    end
    
    -- Pop the first table entry.
    local args = table.remove(L.queued_args, 1)

    return args
end

-- Process a command sent from md.
function L.Handle_Process_Command(_, param)
    local args = L.Get_Next_Args()
    
    if debugger.verbose then
        Lib.Print_Table(args, "Command_Args")
    end

    -- Process command.
    -- Old version, perpetual action with flag checks.
    if args.command == "Register_Action" then
        -- If not seen yet, record the id ordering.
        if L.static_actions[args.id] == nil then
            table.insert(L.static_actions_order, args.id)
        end
        L.static_actions[args.id] = args

    -- New version, single-use action.
    elseif args.command == "Add_Action" then
        -- If not seen yet, record the id ordering.
        if L.temp_actions[args.id] == nil then
            table.insert(L.temp_actions_order, args.id)
        end
        L.temp_actions[args.id] = args

    -- Update fields of an existing action.
    elseif args.command == "Update_Action" then

        -- Check temp and static actions.
        local action = nil
        if L.temp_actions[args.id] ~= nil then
            action = L.temp_actions[args.id]
        elseif L.static_actions[args.id] ~= nil then
            action = L.static_actions[args.id]
        else
            DebugError("Interact API: Update_Action has unmatched id: "..tostring(args.id))
        end

        -- Copy over fields.
        for field, value in pairs(args) do
            -- Skip the id (though should be harmless to modify).
            if field ~= "id" then
                action[field] = value
            end
        end

    -- Change any settings. If name doesn't match a setting, it will
    -- be recorded but just not used.
    elseif args.command == "Update_Settings" then
        -- Convert 0 to false.
        local value = args.value
        if value == 0 then value = false end
        L.settings[args.setting] = value
    else
        DebugError("Interact API: Unrecognized command: "..tostring(args.command))
    end
end


-- Patch the egosoft menu to insert custom actions.
function L.Init_Patch_Menu()

    -- Look up the menu, store in this module's local.
    menu = Lib.Get_Egosoft_Menu("InteractMenu")


    -- Wrap onUpdate, so it can be suppressed. Note that Helper will link
    -- to this when the menu showMenuCallback kicks off, which is fine
    -- with this style of wrapping. (Temporary wraps wouldn't work so well.)
    -- Note: onUpdate wants to check if the mouse is over the menu,
    -- but the menu box isn't known while delayed (not until draw() finishes).
    -- Note: onUpdate will get called 1-2 times before the frame delay
    -- completes, due to event order alignment (and that onUpdate fires
    -- on the same frame the menu display() was called, needlessly).
    local ego_onUpdate = menu.onUpdate
    menu.onUpdate = function(...)
        if not L.delaying_menu then
            ego_onUpdate(...)
        end
    end
    -- Also update Helpers dedicated link to the interactmenu properties.
    Helper.interactMenuCallbacks.update = menu.onUpdate

    -- Do the same for a couple others.
    -- Note: these could just be suppressed to a select display() call,
    -- but doing it this way is a little easier to recover on an error
    -- since it doesn't risk leaving the menu attached to dummy functions.
    local ego_draw = menu.draw
    menu.draw = function(...)
        if not L.delaying_menu then
            ego_draw(...)
        end
    end

    -- Removed; temp printout used during some debugging.
    --local ego_insertInteractionContent = menu.insertInteractionContent
    --menu.insertInteractionContent = function(name, entry, ...)
    --    DebugError("insertInteractionContent("..name..", "..tostring(entry.text)..")")
    --    ego_insertInteractionContent(name, entry, ...)
    --end

    -- Patch prepareActions to slot in the custom function afterward.
    local ego_prepareActions = menu.prepareActions
    menu.prepareActions = function (...)
        if not L.delaying_menu then
            -- Run the standard setup first.
            -- Return arg added in 4.10b5 (will be nil on pre-beta branch).
            local hasanydisplayed = ego_prepareActions(...)

            -- Safety call to add in the new actions.
            if not L.settings.disabled then
                local success, has_added_actions_or_error = pcall(L.Add_Actions, ...)
                if not success then
                    DebugError("Interact API prepareActions error: "..tostring(has_added_actions_or_error))
                elseif has_added_actions_or_error then
                    hasanydisplayed = true
                end
            end
            return hasanydisplayed
        else
            -- Act as if the menu will have something to display, so it
            -- doesn't get closed early (checked in the display() func).
            return true
        end
    end
    
    -- Patch the initial display.
    local ego_display = menu.display
    menu.display = function(...)

        -- If disabled in options (as a safety against breaking), just pass
        -- through the call.
        if L.settings.disabled then
            -- Ensure this flag is false, to be safe.
            L.delaying_menu = false
            ego_display(...)

        else
            -- Flag that display is active, to suppress some functions.
            L.delaying_menu = true

            -- Run the display function; prepareActions and draw will
            -- be suppressed. This will basically record the mouse position
            -- and fill in texts.
            ego_display(...)

            -- Request actions from md; this reads texts from above.
            local success, error = pcall(L.Signal_MD_Get_Actions)
            if not success then
                DebugError("Interact API error in Signal_MD_Get_Actions: "..tostring(error))
            end

            -- Delay one frame, so md can respond.
            Time.Set_Frame_Alarm('options_menu_delay', 1, L.Delayed_Draw)
        end
    end

end

-- 1-frame delayed menu draw.
function L.Delayed_Draw()
    -- Stop suppressing some functions.
    L.delaying_menu = false

    -- Run the suppressed functions.
    -- Note: if a C function fails, prepareActions will silently die and
    -- not return, so draw() will not be called, and the onUpdate function
    -- will throw errors due to missing mouse position data.
    menu.prepareActions()
    menu.draw()
end

-- Function called when a menu is first opened.
-- Tells md to load actions for the target.
function L.Signal_MD_Get_Actions()
    local ret_table = {

        -- The specific object selected.
        -- Note: maybe be null (0); led md deal with that case.
        object          = ConvertStringTo64Bit(tostring(menu.componentSlot.component)),
        
        -- If this is a ship console.
        isshipconsole = menu.mode == "shipconsole",
        isdockedship  = menu.isdockedship == true,

        -- Ensure these have false values if nil.
        showPlayerInteractions = menu.showPlayerInteractions or false,
        hasPlayerShipPilot     = menu.hasPlayerShipPilot or false,

        -- Multiple player ships could be selected, presumably
        -- including the above component.
        -- This list appears to already be convertedComponents,
        -- so can return directly.
        selectedplayerships       = menu.selectedplayerships,
        selectedplayerdeployables = menu.selectedplayerdeployables,
        selectedotherobjects      = menu.selectedotherobjects,

        -- Various text snippets might be useful.
        texts = menu.texts,

        -- These components are polished further below.
        offsetcomponent = menu.offsetcomponent,
        -- For construtions, try just passing the component itself? TODO
        construction = menu.construction and menu.construction.component,

        -- Only the order queueidx (or nil).
        order_queueidx = menu.componentOrder and menu.componentOrder.queueidx,

        -- Int 1-24 (or nil) greek letter index.
        subordinategroup = menu.subordinategroup,
        
        -- Note: mission ids are cdata objects (ULL), which the AddUITriggeredEvent
        -- function will error on ("Cannot convert table value '(null)' to ScriptValue").
        -- Handle conversions further below.
        mission = menu.mission,
        missionoffer = menu.missionoffer,
        componentMissions = menu.componentMissions,

        -- Manually convert positions (expand here, repack in md).
        offset = menu.offset and {
            x = menu.offset.x, y = menu.offset.y, z = menu.offset.z},
    }
    
    -- -Removed; made no difference to the mission id value.
    ---- Missions are a bit odd, giving a mission id, but MD-side missions
    ---- are attached to cues and always accessed through those cues.
    --for _, field in ipairs({"mission","missionoffer"}) do
    --    if menu[field] then
    --        -- Makes no difference?
    --        local missiondetails = C.GetMissionIDDetails(menu[field])
    --        ret_table[field] = missiondetails.associatedComponent
    --    end
    --end

    -- Convert some components, if they exist.
    for _, field in ipairs({"offsetcomponent","construction"}) do --,"mission","missionoffer"
        -- Convert component, suppressing if 0 (hide from md).
        ret_table[field] = (ret_table[field] and ret_table[field] > 0 
                        and ConvertStringTo64Bit(tostring(ret_table[field])))
    end

    -- For texts convenience, since often targetbasename and targetshortname
    -- are selected together (former if available, else latter), create a 
    -- unified term here.
    ret_table.texts.targetBaseOrShortName = menu.texts.targetBaseName or menu.texts.targetShortName

    -- Convert cdata to something that AddUITriggeredEvent can handle.
    -- For now, just use strings.
    -- TODO: maybe cast to numbers, but lua doubles can lose precision
    -- from 64-bit ints.
    -- This will just check the top layer and one level of table nesting,
    -- which should catch all missionid entries.
    for field, value in pairs(ret_table) do
        -- Nested table handling
        if type(value) == "table" then
            -- For safety, always make sure this ret_table value is a
            -- different table from the one from the menu (to avoid
            -- messing up menu data) if cdata is being replaced.
            local convert = false
            for subfield, subvalue in pairs(value) do
                if type(subvalue) == "cdata" then
                    convert = true
                    break
                end
            end
            if convert then
                -- Copy elements to the new table, converting on the
                -- cdata ones (probably all, but be safe).
                local new_table = {}
                ret_table[field] = new_table
                for subfield, subvalue in pairs(value) do
                    if type(subvalue) == "cdata" then
                        new_table[subfield] = tostring(subvalue)
                    else
                        new_table[subfield] = subvalue
                    end
                end
            end
        else
            if type(value) == "cdata" then
                ret_table[field] = tostring(value)
            end
        end
    end
    
    -- Note: info gets printed out md-side, so this is somewhat redundant.
    --if debugger.verbose then
    --    Lib.Print_Table(ret_table, "interact_menu_params")
    --    if ret_table.componentMissions ~= nil then
    --        Lib.Print_Table(ret_table.componentMissions, "componentMissions")
    --    end
    --    Lib.Print_Table(ret_table.texts, "texts")
    --end

    -- Package up menu into into a table, and signal to md.
    -- Note: will give a (null) conversion error on cdata objects in ret_table.
    AddUITriggeredEvent("Interact_Menu_API", "onDisplay", ret_table)

    -- Clear any prior recorded temp actions.
    L.temp_actions = {}
    L.temp_actions_order = {}
end


-- Injected code which adds new action entries to the menu.
-- Gets called when menu opened, and when refreshed.
function L.Add_Actions()
    -- Most actions filter based on this flag check, but not all.
    -- TODO: consider if this should be filtered or not.
    --if not menu.showPlayerInteractions then return end

    local convertedComponent = ConvertStringTo64Bit(tostring(menu.componentSlot.component))

    -- Flag set true if any actions are added, to be merged with the egosoft
    -- hasanydisplayed flag.
    local has_added_actions = false

    -- Update object flags.
    L.Update_Flags(menu.componentSlot.component)

    -- Pick actions to show.
    -- Ordering will place static ones first, then temp ones.
    local action_specs = {}

    -- Static actions, with filtering.
    for _, id in ipairs(L.static_actions_order) do
        local action = L.static_actions[id]
        -- Skip disabled actions.
        if action.disabled == 1 then
        -- Skip if flag check fails.
        elseif not L.Check_Flags(action) then
        else
            table.insert(action_specs, action)
        end
    end
    -- All temp actions; should have been filtered md-side.
    for _, id in ipairs(L.temp_actions_order) do
        local action = L.temp_actions[id]
        table.insert(action_specs, action)
    end

    -- pcall the handler for each individual action, so one bad
    -- action doesn't suppress all others.
    for _, action in ipairs(action_specs) do
        local success, error = pcall(L.Process_Action, action)
        if not success then
            DebugError("Interact API error in Process_Action: "..tostring(error))
        else
            has_added_actions = true
        end
    end

    return has_added_actions
end

-- Process a single action. This should be pcalled for safety.
function L.Process_Action(action)
    -- Table of generic data to return to the call.
    -- Reduced down to just id currently.
    local ret_table = {
        id = action.id,
    }

    -- Set up the text name, with icon.
    -- Note: attempting to pass over "\27[icon]" text straight from
    -- md ran into problems with the \27 becoming some error character,
    -- so icon strings are built here instead.
    local text = ''
    if action.icon and type(action.icon) == "string" then
        text = "\27["..action.icon.."] "
    end
    text = text .. action.text

    -- Set up the mouseover, also with icon support.
    local mouseover = nil
    if action.mouseover then
        mouseover = ''
        if action.mouseover_icon and type(action.mouseover_icon) == "string" then
            mouseover = "\27["..action.mouseover_icon.."] "
        end
        mouseover = mouseover .. action.mouseover
    end

    -- To enable dynamic "active" status updates, a wrapper function will
    -- be used to look up the active flag each refresh.
    -- TODO: this would also need a hook into the menu code to force a
    -- widget refresh (since that is when "active" flags are checked).
    --local active_check_func = function()
    --end
    -- Determine if active (eg. not greyed out).
    -- If not specified, defaults true.
    local active = true
    if action.active == false or action.active == 0 then 
        active = false
    end

    -- Make a new entry.
    menu.insertInteractionContent(
        action.section, { 
        -- Leave type undefined; don't need a ui event on click.
        type = nil, 
        text = text, 
        text2 = action.text2,

        -- TODO: is this needed or useful?
        helpOverlayID = "interactmenu_"..action.id,
        helpOverlayText = "", 
        helpOverlayHighlightOnly = true,

        script = function () 
            return L.Interact_Callback(action.keep_open, ret_table) 
            end, 

        active = active, 
        mouseOverText = mouseover })        
end

-- Convert a value to a boolean true/false.
-- Treats 0 as false.
-- Ensures nil entries are false (eg. don't get deleted from table).
local function tobool(value)
    if value and value ~= 0 then 
        return true 
    else 
        return false 
    end
end

-- Returns a table of flag values (true/false) that can be referenced by
-- user actions to determine when they show.
-- Note: mostly depricated in favor of md-side checks.
function L.Update_Flags(component)

    -- Note: it is unclear when component, component64, and convertedComponent
    -- should be used; just trying to match ego code in each instance.

    local component = menu.componentSlot.component
    --local component64 = ConvertIDTo64Bit(component) -- Errors
    local convertedComponent = ConvertStringTo64Bit(tostring(component))

    local flags = {}

    -- Verify the component still exists (get occasional log messages
    -- if not). Also, this is 0 when eg. opening a menu on a mission.
    if convertedComponent > 0 then

        -- Component class checks.
        for key, name in pairs({
            class_controllable = "controllable",
            class_destructible = "destructible",
            class_gate         = "gate", 
            class_ship         = "ship", 
            class_station      = "station",
        }) do
            -- Note: C.IsComponentClass returns 0 for false, so needs cleanup.
            flags[key] = tobool(C.IsComponentClass(component, name))
        end

        -- Component data checks.
        -- TODO: more complicated logic, eg. shiptype and purpose comparisons
        -- to different possibilities.
        for key, name in pairs({
            is_dock        = "isdock",
            is_deployable  = "isdeployable",
            is_enemy       = "isenemy",
            is_playerowned = "isplayerowned", 
        }) do
            flags[key] = tobool(GetComponentData(convertedComponent, name))
        end

        -- Special flags inherited from the menu.
        for key, name in pairs({
            show_PlayerInteractions = "showPlayerInteractions", 
            has_PlayerShipPilot     = "hasPlayerShipPilot",
        }) do
            flags[name] = tobool(menu.showPlayerInteractions)
        end

        -- Misc stuff.
        flags["is_operational"]         = tobool(IsComponentOperational(convertedComponent))
        -- TODO: IsUnit tosses failed-to-retrieve-controllable log messages
        -- sometimes; maybe figure out how to suppress.
        --flags["is_unit"]                = tobool(C.IsUnit(convertedComponent))
        flags["have_selectedplayerships"] = #menu.selectedplayerships > 0
        flags["has_pilot"]              = GetComponentData(convertedComponent, "assignedpilot") ~= nil
        flags["in_playersquad"]         = tobool(menu.playerSquad[convertedComponent])


        -- Player related flags.
        local player_occupied_ship = ConvertStringTo64Bit(tostring(C.GetPlayerOccupiedShipID()))
        local player_piloted_ship  = ConvertStringTo64Bit(tostring(C.GetPlayerControlledShipID()))
        local playercontainer      = ConvertStringTo64Bit(tostring(C.GetPlayerContainerID()))

        flags["is_playeroccupiedship"]  = player_occupied_ship == convertedComponent
        flags["player_is_piloting"]     = player_piloted_ship > 0

        -- Do stuff with player component checks.
        -- Side note: ego code checks playercontainer ~= 0 ahead of the conversion
        -- to a proper 64Bit value (as done above), and hence might always
        -- evaluated true (since it is a special C type), based on early
        -- testing with the player_is_piloting check which used the C type
        -- as well (ULL). Though something else could have been wrong there.
        -- TODO: maybe check if this check is useful.
        if playercontainer ~= 0 then
            -- TODO: check if player location is dockable, etc.
        end


        -- For every flag, also offer the negated version.
        -- Do in two steps; can't modify the original table in the loop without
        -- new entries showing up in the same loop (eg. multiple ~~~flags).
        local negated_flags = {}
        for key, value in pairs(flags) do
            negated_flags["~"..key] = not value
        end
        for key, value in pairs(negated_flags) do
            flags[key] = value
        end
    
        if debugger.verbose then
            -- Debug printout.
            Lib.Print_Table(flags, "flags")
        end
    end

    L.flags = flags
end


-- Check an action against the current flags
-- Note: mostly depricated in favor of md-side checks.
function L.Check_Flags(action, flags)

    if debugger.verbose then
        Lib.Print_Table(action.enabled_conditions, "enabled_conditions")
    end
    
    if debugger.verbose then
        Lib.Print_Table(action.disabled_conditions, "disabled_conditions")
    end

    -- If there are requirements, check those.
    if #action.enabled_conditions ~= 0 then
        local match_found = false
        -- Only need one to match.
        for i, flag in ipairs(action.enabled_conditions) do
            if L.flags[flag] then
                match_found = true
                break
            end
        end
        -- If no match, failure.
        if not match_found then 
            if debugger.verbose then
                DebugError("Interact API: Enable condition not matched for action "..action.id)
            end
            return false 
        end
    end

    -- If there are blacklisted flags, check those.
    if #action.disabled_conditions ~= 0 then
        -- Failure on any match.
        for i, flag in ipairs(action.disabled_conditions) do
            if L.flags[flag_req] then
                if debugger.verbose then
                    DebugError("Interact API: Disable condition matched for action "..action.id)
                end
                return false
            end
        end
    end

    -- If here, should be good to go.
    return true
end


-- Handle callbacks when the player selects the action.
function L.Interact_Callback(keep_open, ret_table)

    if debugger.verbose then
        --Lib.Print_Table(ret_table, "ret_table")
        DebugError("Interact API: selected custom action: "..tostring(ret_table.id))
        CallEventScripts("directChatMessageReceived", "InteractMenu;lua action: "..ret_table.id)
    end

    -- Signal md with the component/object.
    AddUITriggeredEvent("Interact_Menu_API", "Selected", ret_table)

    -- Close the context menu.
    -- Note: md may have sent over 'false' as 0.
    if not keep_open or keep_open == 0 then
        menu.onCloseElement("close")
    end
end


L.Init()