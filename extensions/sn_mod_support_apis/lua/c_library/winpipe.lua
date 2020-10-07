--[[
Wrapper for loading the winpipe dll file.

X4 would normally look for dll files only in "ui/core/lualibs/?_64.dll",
as defined in package.cpath. To load a dll from an extension folder, some
extra effort is needed.

Using require():
    "require" on a dll will attempt to call a function named "luaopen_<path>",
    where the path is the arg given to require.
    As a result, require() cannot easily be used with complex paths; instead
    a path search rule needs to be added with the specific directory.

    This is somewhat clumsy due to polluting the cpath rule set.

Using loadlib():
    This takes the path and name of the entry function, returns the
    entry (init) function, which needs to be called to set up the library.
    Note: this doesn't implicitly record the imported module like require()
    does, so any future loadlib() calls do a fresh import, but that should
    be fine.

A clean way to support require() is to create a wrapper lua file which
handles the loadlib() call, but can be found by the require() search paths.
This is recommended by the lua documentation:
    https://www.lua.org/pil/8.2.html

This is that wrapper.
]]

-- Ignore the require() style for now.
--package.cpath = package.cpath .. ";.\\extensions\\named_pipes_api\\lualibs\\?_64.dll"
--local winpipe = require("winpipe")

-- Check if this is running on Windows.
-- First character in package.config is the separator, which
-- is backslash on windows.
if package.config:sub(1,1) == "\\" then

    -- Note: as of x4 3.3 hotfix 1 (beta), the jit and lua dll are changed
    -- such that the winpipe dll doesn't work between versions.
    -- (Older winpipe crashes 3.3hf1, while a newer winpipe just doesnt work
    -- in pre-patch versions.)
    -- Both winpipe dlls are included for now, but one needs to be selected
    -- based on the game version.

    -- Note: cannot use jit to check the estimated game version, since it
    -- cannot be required/imported here.
    --local jit = require("jit")
    --DebugError("jit version: "..tostring(jit.version_num))

    -- The GetVersionString() command returns "3.30 (406216)" in the pre-hotfix
    -- game. Can check for this build code to select which dll to load.
    -- Newer versions will have a different build code, even the beta.
    if string.find(GetVersionString(), "406216") then
        -- <= 3.3 release dll.
        return package.loadlib(
            ".\\extensions\\sn_mod_support_apis\\lua\\c_library\\winpipe_64_pre3p3hf1.dll", 
            "luaopen_winpipe")()
    else
        -- 3.3 hf1 dll.
        return package.loadlib(
            ".\\extensions\\sn_mod_support_apis\\lua\\c_library\\winpipe_64.dll", 
            "luaopen_winpipe")()
    end
end


