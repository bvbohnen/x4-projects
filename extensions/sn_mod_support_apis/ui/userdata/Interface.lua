Lua_Loader.define("extensions.sn_mod_support_apis.lua.userdata.Interface",function(require)
--[[
    Support for accessing userdata from uidata.xml, stored in the
    __MOD_USERDATA global table.

    For each function, the first key of the keylist should be unique
    to a given modder, to avoid conflicts with other mods.

    A reference to this user data will be stored in a player blackboard var,
    for convenient access from md.
]]
-- Set up any used ffi functions.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef uint64_t UniverseID;
    UniverseID GetPlayerID(void);
]]

-- Default table holding generic mod data saved to the uidata.xml file.
__MOD_USERDATA = __MOD_USERDATA or {}

local Lib = require("extensions.sn_mod_support_apis.lua.Library")

-- Local functions/data.
local L = {
    player_id = nil,
}

function L.Init()
    -- Initial copy of userdata to the md blackboard.
    local player_id = ConvertStringTo64Bit(tostring(ffi.C.GetPlayerID()))

    if player_id == 0 then
        player_id = nil
    end

    L.player_id = player_id

    -- If userdata is empty, and the player blackboard has data, then leave
    -- it in place, as a minor safety against the game deleting userdata,
    -- utilizing data from the savegame as a backup.
    if next(__MOD_USERDATA) == nil then
        -- Look up what the md has stored.
        local md_userdata = GetNPCBlackboard(player_id, "$__MOD_USERDATA")
        -- If something, copy it back.
        if md_userdata ~= nil then
            __MOD_USERDATA = md_userdata
        end
    end
    --DebugError("Copying __MOD_USERDATA to player blackboard")
    SetNPCBlackboard(player_id, "$__MOD_USERDATA", __MOD_USERDATA)

    -- Listen for md Userdata update signal.
    RegisterEvent("Userdata.Update", L.Userdata_Update)

    -- Signal md that userdata is ready.
    AddUITriggeredEvent("Userdata", "Ready")
end

-- Updates requested by md will be done in two calls for param passing,
-- first call passing owner, second passing key (or nil).
-- This will trigger the matching entry in the blackboard var to be copied
-- over to the userdata (a safe way to update without impacting other
-- tables that lua may be using).
local owner
function L.Userdata_Update(_, param)
    -- First call stores owner.
    if owner == nil then
        owner = param
    else
        -- Second call gets key.
        local key = param
        -- Look up the data from the blackboard.
        local md_userdata = GetNPCBlackboard(L.player_id, "$__MOD_USERDATA")
        --DebugError("Attempting to update from md userdata["..tostring(owner).."]["..tostring(key).."]")
        local value = md_userdata[owner]
        if key ~= nil then
            value = value[key]
        end
        -- Write to the local version.
        L.Write_Userdata(owner, key, value)
        -- Clear the owner arg.
        owner = nil
    end
end

-- Function for reading user data that was saved.
-- Arg1: owner name (string), unique to a given modder/mod.
-- Arg2: optional key (string or number), a subfield to access in the owner table.
-- If no key given, returns the full owner table.
-- Returns nil on a failed lookup.
-- Note: if a table is returned, edits to its contents will change userdata,
-- but will not be visible to md without explicitly calling Write_Userdata.
function L.Read_Userdata(owner, key)
    -- TODO: validate string owner/key (or nil key).
    -- Check for the owner being missing.
    if __MOD_USERDATA[owner] == nil then
        return
    end
    -- If a key given, look it up and return (maybe nil).
    if key ~= nil then
        return __MOD_USERDATA[owner][key]
    end
    -- Else return the owner data.
    return __MOD_USERDATA[owner]
end

-- Function for writing user data to be saved.
-- Arg1: owner name (string), unique to a given modder/mod.
-- Arg2: key (string or number), a subfield to access in the owner table.
-- Arg3 (or arg2 with no key): value to be written.
-- If the value is nil, the key (or owner) entry will be removed.
function L.Write_Userdata(owner, key, value)
    -- TODO: validate string owner/key (or nil key).
    if key ~= nil then
        -- Init an owner table if not yet present.
        if __MOD_USERDATA[owner] == nil then
            __MOD_USERDATA[owner] = {}
        end
        __MOD_USERDATA[owner][key] = value
    else
        __MOD_USERDATA[owner] = value
    end
    -- TODO: maybe update the blackboard with these changes, if lua and md
    -- will support sharing the same fields. For now assume they are separate.
    --SetNPCBlackboard(L.player_id, "$__MOD_USERDATA", __MOD_USERDATA)
end

local exports = {
    Read_Userdata = L.Read_Userdata,
    Write_Userdata = L.Write_Userdata,
}
return exports, L.Init

end)