--[[
Lightweight lua wrapper on some exported api functions.
Other extensions using these lua apis should 'require' this file, as its
path will be maintained between github development files and steam style
release files.
]]

Lua_Loader.define("extensions.sn_better_target_monitor.lua_interface",function(require)
	-- TODO: Need to determine if we need to Init this
	return require("extensions.sn_better_target_monitor.lua.Target_Monitor")
end)