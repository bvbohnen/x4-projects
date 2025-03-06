Lua_Loader.define("extensions.sn_better_target_monitor.lua.Target_Monitor",function(require)
--[[
Lua side of performance profiling.
]]

local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
]]

-- Inherited lua stuff from support apis.
local Lib   = require("extensions.sn_mod_support_apis.lua_interface").Library

-- Table of local functions and data.
local L = {}
    

function Init()

    -- Test: how many times can a lua-md-lua signal bounce in a frame?
    RegisterEvent("Measure_Perf.Bounce_Test", L.Bounce_Test)
    -- Kick off the test, so many bounces.
    -- Test result: 1 frame of delay going from lua to md (no delay md to lua).
    -- Comment out now that test is done.
    --AddUITriggeredEvent("Measure_Perf", "Bounce_Test", 10)

end

function L.Bounce_Test(_, count)
    DebugError("bounce "..count.." at "..GetCurTime())
    if count ~= 0 then
        AddUITriggeredEvent("Measure_Perf", "Bounce_Test", count - 1)
    end
end




--[[
    Testing an idea:
    If opened conversations from md call to lua immediately, and not in
    a delay until after the cue completes, then they can be used to do
    direct lua function calls. Which would in turn allow for getting
    a high performance counter (with dll plugin) back to the script level.

    MD will use open_menu on the "CallLua" menu. Register it here.

    Test results:
        md open_menu appears to simply raise a lua event.
        When in lua a menu is registerd, Helper will attach a custom
        showMenuCallback function, and register this function to be
        called on the "show<menu_name>" event.
        As such, md open_menu is seemingly equivelent to raising a lua event.

        open_menu: dead end.

    Other things to try:
        uipositionlookup
            Returns conversation highlighted option, 1-6.
            Quick glance finds nothing for this in lua.
        add_player_choice
            ?


    NotifyOnX
        Lua global functions, which are used in low level ui contracts
        that also listen to a similarly named event.
        In testing, such contracts need a NotifyX for their event
        registration to work and get callbacks, but these still have
        a delay on the callback.
        Testing with opening/closing a converstation, listening to
        the conversationFinished event with NotifyOnConversationFinished.

    Results:
        All attempts below failed to trigger until after the md actions
        completed.

]]
--local Lib = require("extensions.sn_mod_support_apis.lua.simple_menu.Library")

--[[
local menu = {
    -- Name of the menu used in registration. Should be unique.
    name = "CallLua",
    -- How often the menu refreshes?
    updateInterval = 0.1,
    -- The main frame, named to match ego code.
    infoFrame = nil,
}

local function Menu_Init()
    -- Register menu; uses its name.
    Menus = Menus or {}
    table.insert(Menus, menu)
    if Helper then
        Helper.registerMenu(menu)
    end
end
Menu_Init()

-- TODO: how to avoid closing existing menus?
function menu.onShowMenu()
    DebugError("CallLua onShowMenu triggered")

    ----Lib.Print_Table(args, "menu_open_args")
    --local player_id = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    --
    ---- Look at what md sent.
    --local arg = GetNPCBlackboard(player_id, "$call_lua_arg")
    --DebugError("CallLua onShowMenu got arg: "..tostring(arg))
    --SetNPCBlackboard(player_id, "$call_lua_arg", nil)
    --
    --
    ---- Write something to the blackboard.
    --SetNPCBlackboard(player_id, "$call_lua_response", 'lua_hello')
    ---- Do nothing further (eg. no frame display).

    -- System thinks this menu is now open; force close it.
    Helper.closeMenu(menu, "close")
end
]]

-- Try out NotifyOnStartDialog.
--[[
local function startDialog(data, time)
    DebugError("Caught startDialog")
end

local function conversationFinished(data, time)
    DebugError("Caught conversationFinished")
end

local function Test_Init()
    DebugError("Creating contract and registering events.")
    local scene           = getElement("Scene")
    local contract        = getElement("UIContract", scene)
    registerForEvent("startDialog", contract, startDialog)
    registerForEvent("conversationFinished", contract, conversationFinished)
    NotifyOnStartDialog(contract)
    NotifyOnConversationFinished(contract)
end
Test_Init()
]]



return nil,Init
)