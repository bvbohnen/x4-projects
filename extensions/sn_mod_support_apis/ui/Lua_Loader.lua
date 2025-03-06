--[[
Simple api for loading in mod lua files, and for accessing ui userdata.
This works around a bug in the x4 ui.xml style lua loading which fails
to initialize the globals table.

Usage is kept simple:
    When the ui reloads or a game is loaded, a ui event is raised.
    User MD code will set up a cue to trigger on this event and signal to
    lua which file to load.
    Lua will then "require" the file, effectively loading it into the game.

This lua file is itself included by modding an official ui.xml. Lua added
in this way is imported correctly into X4, though there are limited
official ui.xml files which can be modified in this way.
    

Example from MD:

    <cue name="Load_Lua_Files" instantiate="true">
    <conditions>
        <event_ui_triggered screen="'Lua_Loader'" control="'Ready'" />
    </conditions>
    <actions>
        <raise_lua_event name="'Lua_Loader.Load'" 
            param="'extensions.sn_named_pipes_api.Named_Pipes'"/>
    </actions>
    </cue>
  
Here, the cue name can be anything, and the param is the specific
path to the lua file to load, without extension.
The file extension may be ".lua" or ".txt", where the latter may be
needed to distribute lua files through steam workshop.
The lua file needs to be loose, not packed in a cat/dat.

When a loading is complete, a message is printed to the debuglog, and
a ui signal is raised. The "control" field will be "Loaded " followed
by the original file_path. This can be used to set up loading
dependencies, so that one lua file only loads after a prior one.

Example dependency condition:

    <conditions>
        <event_ui_triggered screen="'Lua_Loader'" 
            control="'Loaded extensions.sn_named_pipes_api.Named_Pipes'" />
    </conditions>
    

This api also provides for saving data into the uidata.xml file.
All such saved data is in the __MOD_USERDATA global table.
Each individual mod should add a unique key to this table, and save its
data under that key. Nested tables are supported.
Care should be used in the top level key, to avoid cross-mod conflicts.

To enable early loading of the Userdata handler, this will also support
an early ready signal, which resolves before the normal ready.
- On reloadui or md signalling Priority_Signal, send Priority_Ready.
- Next frame, md cues which listen to this may signal to load their lua.
- Md side will see Priority_Ready, and send Signal.
- Back end of frame, priority lua files load, and api signals standard Ready.
- Next frame, md cues which listen to Ready may signal to load their lua.

TODO: allow for more md arguments, including specifying dependendencies
which are resolved at this level (eg. store and delay the require until
all dependencies are met).
]]

Lua_Loader = {}

local modules = {

}

local function Send_Priority_Ready()
    --DebugError("LUA Loader API: Signalling 'Lua_Loader, Priority_Ready'")
    -- Send a ui signal, telling all md cues to rerun.
    AddUITriggeredEvent("Lua_Loader", "Priority_Ready")
end

local function Send_Ready()
    --DebugError("LUA Loader API: Signalling 'Lua_Loader, Ready'")
    -- Send a ui signal, telling all md cues to rerun.
    AddUITriggeredEvent("Lua_Loader", "Ready")
end

local function IsWhitelistedInProtectedUI(name)
    return name == "ffi" or name == "utf8"
end

local function IsReserved(name)
    return name ~= nil and type(name) == "string" and (name == "bit" or name == "Color" or name == "coroutine" or name == "debug" or name == "ffi" or name == "math" or name == "Matrix" or name == "package" or name == "Rotation" or name == "string" or name == "table" or name == "utf8" or name == "Vector" or name == "_G" or string.find(name, "^jit%."))
end

local function Lua_Loader_Require_Helper(name, methodName, requestorName)
    if type(name) ~= "string" then
        error("Invalid call to "..methodName..". Given name must be a string but is '"..type(name).."''")
    end
    if requestorName ~= nil and type(requestorName) ~= "string" then
        error("Invalid call to "..methodName..". Given requestorName must be nil or a string but is '"..type(requestorName).."''")
    end

    local module = modules[name]
    if module == nil then
        return false
    end

    local status = module.status

    if status ~= "defined" then
        if status == "executing" then
            if requestorName == nil and type(requestorName) == "string" then
                error("Invalid call to "..methodName..". Cyclical dependency detected in '"..requestorName.."' and '"..name.."''")
            end
        elseif status == "faulted" then
            error("Failed to require the module '"..name.."' as it encountered an error whilst being defined.\n"..module.exports)
        end

        error("Invalid call to "..methodName..". Required module whilst is was being defined '"..name.."''")
    end

    local moduleInit = module.init

    return true,module.exports,module.init
end

local function on_Load_Lua_File(_, file_path)
    -- First look for our modules
    local success,exports,init = Lua_Loader_Require_Helper(file_path, "Lua_Loader.Load")

    if success then
        if init ~= nil and type(init) == "function" then
            init()
        end
    else
        local localPackage = package
        local packagePath = nil

        -- When Protected UI is enabled it seems that the `package` global is nil, but we want the actual error from require as it might be something else.
        if localPackage ~= nil then
            local packagePath = localPackage.path

            local customPackagePath = "?.txt"
            ---- Removing the debug message; if a user really wants to know,
            ---- they can listen to the ui event.
            --DebugError("LUA Loader API: loading "..file_path..", package path:"..customPackagePath)

            -- Since lua files cannot be distributed with steam workshop stuff,
            -- but txt can, use a trick to change the package search path to
            -- also look for txt files (which can be put on steam).
            -- This is done on every load, since the package.path was observed to
            -- get reset after Init runs (noticed in x4 3.3hf1).
            localPackage.path = customPackagePath
        end
    
        success, exports = pcall(baseRequire, file_path)

        -- Restore package.path to the original value
        if localPackage ~= nil then
            localPackage.path = packagePath
        elseif not IsWhitelistedInProtectedUI(name) and success and exports == nil then
            local protectedUIError = "require(\""..file_path.."\") : Only whitelisted modules are allowed in Protected UI Mode."
            DebugError("If you see the following error, then a lua file for a mod has filed to load:\n"..protectedUIError.."\n\nIf you're confident about the source of ALL of your mods then you will need to disable Protected UI Mode for this mod to function.\n\nAdvice for mod developers: You need to load your mod via 'ui.xml' and update your lua files to using Lua_Loader.define(\""..file_path.."\", function(require)\n    ...\nend)")
        end

        if not success then
            error(exports)
        end

        -- Removing the debug message; if a user really wants to know,
        -- they can listen to the ui event.
        --DebugError("LUA Loader API: loaded "..file_path..", package path:"..customPackagePath)

        -- Generic signal that the load completed, for use when there
        -- are inter-lua dependencies (to control loading order).
    end

    AddUITriggeredEvent("Lua_Loader", "Loaded "..file_path)
end

local function Init()
    --DebugError("LUA Loader API: Running Init()")
    -- Hook up an md->lua signal.
    RegisterEvent("Lua_Loader.Load", on_Load_Lua_File)
    
    -- Listen to md side timing on when to send Ready signals.
    -- Priority ready is triggered on game start/load.
    RegisterEvent("Lua_Loader.Send_Priority_Ready", Send_Priority_Ready)
    RegisterEvent("Lua_Loader.Send_Ready", Send_Ready)

    -- Also call the function once on ui reload itself, to catch /reloadui
    -- commands while the md is running.
    -- Only triggers priority ready; md will then signal Send_Ready for
    -- the second part.
    Send_Priority_Ready()
end

Lua_Loader.IsReserved = IsReserved
Lua_Loader.IsWhitelistedInProtectedUI = IsWhitelistedInProtectedUI

function Lua_Loader.require(name)
    local success,exports,init = Lua_Loader_Require_Helper(name, "Lua_Loader.require()")

    if init == nil then
        init = function()
        end
    end

    return success,exports,init
end

local baseRequire = require
require = function(name)
    local success,exports,init = Lua_Loader_Require_Helper(name, "Lua_Loader.require()")
    
    if not success then
        return baseRequire(name)
    end

    if init ~= nil and type(init) == "function" then
        init()
    end

    return exports
end

function Lua_Loader.define(name, moduleFunction)
    if type(name) ~= "string" then
        error("Invalid call to Lua_Loader.define(). Given name must be a string but is '"..type(name).."''")
    end
    if type(moduleFunction) ~= "function" then
        error("Invalid call to Lua_Loader.define(). Given moduleFunction must be a function but is '"..type(moduleFunction).."''")
    end

    local module = modules[name]

    if module ~= nil then
        DebugError("Redefining the module '"..name.."'")
    elseif package ~= nil then
        if IsReserved(name) then
            DebugError("Redefining the build-in module '"..name.."'")
        end
    elseif IsWhitelistedInProtectedUI(name) then
        DebugError("Redefining the build-in module '"..name.."'")
    end
    
    module = {
        status = "executing",
        exports = nil,
        init = nil,
    }

    modules[name] = module

    local ambientName = name

    local dependencies = nil
    local moduleFunctionRan = false

    local function moduleRequire(name)
        if moduleFunctionRan then
            error("Invalid call to require() function in Lua_Loader.define(function(require). Call to moduleRequire method outside of define in '"..ambientName.."''")
        end

        local success,exports,init = Lua_Loader_Require_Helper(name, "require() function in Lua_Loader.define(function(require)", ambientName)

        if not success then
            return baseRequire(name)
        end

        if module.status == "executing" and init ~= nil and type(init) == "function" then
            dependencies = dependencies or {}
            table.insert(dependencies, init)
        end

        return exports,init
    end

    local success, exports, initFunction = pcall(moduleFunction, moduleRequire)
    
    -- Prevent future 'require' from attempting to update the dependency list.
    module.status = "executed"

    if not success then
        module.status = "faulted"
        module.exports = exports
        error("Failed to define module '"..name.."' due because of the following error: "..exports)
    end

    if initFunction ~= nil and type(initFunction) ~= "function" then
        local err = "Invalid call to Lua_Loader.define(). Second return must be nil or the init function but is '"..type(initFunction).."''"
        module.status = "faulted"
        module.exports = err
        error("Failed to define module '"..name.."' due because of the following error: "..err)
    end

    local init = nil

    if type(initFunction) == "function" or dependencies ~= nil then
        local initialized = false

        init = function()
            if not initialized then
                if dependencies ~= nil then
                    for _, dependencyInit in ipairs(dependencies) do
                        dependencyInit()
                    end
                end
                if initFunction ~= nil and type(initFunction) == "function" then
                    initFunction()
                end
                initialized = true
            end
        end
    end

    module.exports = exports
    module.init = init
    module.status = "defined"

    return exports,init
end

-- This script kicks everything off, so we actually need to run its init now.
Init()
