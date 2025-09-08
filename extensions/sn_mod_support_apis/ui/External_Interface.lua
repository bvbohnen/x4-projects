--[[
Lightweight lua wrapper on some exported api functions.
Other extensions using these lua apis can access them using:
`apis = require("extensions.sn_mod_support_apis.lua_interface")`
The path will be maintained between github development files and steam style
release files.
]]

local L = {}
L.Library = require("extensions.sn_mod_support_apis.ui.Library")
L.Pipes   = require("extensions.sn_mod_support_apis.ui.named_pipes.Pipes")
L.Time    = require("extensions.sn_mod_support_apis.ui.time.Interface")

-- Use the path from pre-7.5 for consistency.
Register_Require_Response("extensions.sn_mod_support_apis.lua_interface", L)
return L