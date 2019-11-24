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
]]

-- Ignore the require() style for now.
--package.cpath = package.cpath .. ";.\\extensions\\named_pipes_api\\lualibs\\?_64.dll"
--local winpipe = require("winpipe")

return package.loadlib(
    ".\\extensions\\named_pipes_api\\lualibs\\winpipe_64.dll", 
    "luaopen_winpipe")()
