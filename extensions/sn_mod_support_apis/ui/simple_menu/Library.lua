--[[
    Misc functions split off into a library file.
    Mostly string or table processing.
]]

-- Table to hold lib functions.
local L = {}

-- Include stuff from the shared library.
local Lib_shared = require("extensions.sn_mod_support_apis.ui.Library")
Lib_shared.Table_Update(L, Lib_shared)


-- Signalling results from lua to md.
-- Takes the row,col of the activated widget, and an optional new value
-- for that widget.
-- TODO: think about this more.
function L.Raise_Signal(name, value)
    AddUITriggeredEvent("Simple_Menu", name, value)
end


-- Take an arg string and convert to a table.
function L.Tabulate_Args(arg_string)
    local args = {}    
    -- Start with a full split on semicolons.
    local named_args = L.Split_String_Multi(arg_string, ";")
    -- Loop over each named arg.
    for i = 1, #named_args do
        -- Split the named arg on comma.
        local key, value = L.Split_String(named_args[i], ",")
        -- Keys have a prefixed $ due to md dumbness; remove it here.
        key = string.sub(key, 2, -1)
        args[key] = value
    end
    return args    
end


-- Function to remove $ prefixes from MD keys.
-- Recursively calls itself for subtables.
function L.Clean_MD_Keys( in_table )
    -- Loop over table entries.
    for key, value in pairs(in_table) do
        -- Slice the key, starting at 2nd character to end.
        local new_key = string.sub(key, 2, -1)
        -- Delete old, replace with new.
        in_table[key] = nil
        in_table[new_key] = value
        
        -- If the value is a table as well, give it the same treatment.
        if type(value) == "table" then
            L.Clean_MD_Keys(value)
        end
    end
end

--[[ 
Handle validation of arguments, filling in defaults.
'args' is a table with the named user provided arguments.
'arg_specs' is a list of subtables with fields:
  n : string, name
  d : optional default or literal "nil"
  t : string type, only needed for casting (eg. if not string).
If a name is missing from user args, the default is added to 'args'.
 If the default is the "nil" string, nothing is added.
 If the default is nil, it is treated as non-optional.
If argtype is "int", converts the value to a number.
If argtype is "boolean", converts 1 to true and 0 to false.
 
TODO: maybe support dynamic code execution for complex args that want
 to use lua data (eg. Helper.viewWidth for window size adjustment sliders),
 using loadstring(). This is probably a bit niche, though.
 
]]
function L.Validate_Args(args, arg_specs)
    -- Loop over the arg_specs list.
    for i = 1, #arg_specs do 
        local name    = arg_specs[i].n
        local default = arg_specs[i].d
        local argtype = arg_specs[i].t
        
        -- In lua, if a name is missing from args its lookup will be nil.
        if args[name] == nil then
            -- Error if no default available.
            if default == nil then
                -- Treat as non-recoverable, with hard error instead of DebugError.
                error("Args missing non-optional field: "..name)
            -- Do nothing if default is explicitly nil; this leaves the arg
            -- as nil for later uses.
            elseif default == "nil" then
            else
                -- Use the default.
                args[name] = default
            end
        else
            -- Number casting.
            -- TODO: maybe round ints, but for now floats are fine.
            if argtype == "int" then
                args[name] = tonumber(args[name])
            elseif argtype == "boolean" then
                -- MD transferred false as 0, true as 1. Both of these
                -- lua counts as true, so handle manually.
                -- Only check 0/1, so this is safe against a prior call
                -- already having converted to bool.
                if args[name] == 0 then
                    args[name] = false
                elseif args[name] == 1 then
                    args[name] = true
                end
            end
        end        
    end
end


-- Replace any arg value that references a global table const with the actual
-- value, recursively through subtables.
-- Reused for Helper and Color tables.
function _Replace_Global_Args(args, prefix, ref_table)
    for k, v in pairs(args) do

        -- Look for strings that start with "Helper."
        if type(v) == "string" and string.sub(v, 1, #prefix) == prefix then
            --DebugError("Unpacking const arg ref "..v)

            -- Split on the dots.
            local fields = L.Split_String_Multi(v, ".")

            -- Approach will get to start with the table, and progress through
            -- its fields downward.
            local temp = ref_table

            -- Loop over all after the first (skipping ref_table).
            for i = 2, #fields do
                if temp then
                    temp = temp[fields[i]]
                end
            end

            -- Error message if ran into nil (but false is okay).
            if temp == nil then
                DebugError("Simple Menu: Failed lookup of "..prefix.." const: "..v)
            end

            -- Put it back.
            args[k] = temp

        -- Recurse into subtables to find nested globals.
        elseif type(v) == "table" then
            _Replace_Global_Args(v, prefix, ref_table)
        end
    end
end

-- Replace any arg value that references a Helper const with the actual
-- value, recursively through subtables.
function L.Replace_Helper_Args(args)
    _Replace_Global_Args(args, "Helper.", Helper)
end


-- Replace any arg value that references a Color const with the actual
-- value, recursively through subtables.
function L.Replace_Color_Args(args)
    _Replace_Global_Args(args, "Color.", Color)
end


-- Returns a filtered version of the input table, keeping only those keys
-- that are in the 'filter' list of strings.
-- Returns early if filter is nil.
function L.Filter_Table(in_table, filter)
    local out_table = {}
    if not filter then return in_table end
    -- Can just do a direct transfer; nil's take care of missing keys.
    for i, field in ipairs(filter) do
        out_table[field] = in_table[field]
    end
    return out_table
end


-- Update the first table with entries from the second table, except where
-- there is a conflict. Works recursively on subtables.
-- Returns early if right side is nil.
function L.Fill_Defaults(left, right)
    if not right then return end
    for k, v in pairs(right) do
        if left[k] == nil then
            left[k] = v
        elseif type(left[k]) == "table" and type(v) == "table" then
            L.Fill_Defaults(left[k], v)
        end
    end
end

-- Update the first table with entries from the second where the entry is
--  a subtable, and the first table contains an entry already for the field.
-- The goal is that subtables (referred to as complex properties) will get
--  defaults filled in for unused fields, while the top level table will
--  be left alone (ego's backend can handle that already).
function L.Fill_Complex_Defaults(left, right)
    if not right then return end
    for k, v in pairs(right) do
        -- Check for both having tables.
        if type(left[k]) == "table" and type(v) == "table" then
            -- Hand off to the normal default filler function.
            L.Fill_Defaults(left[k], v)
        end
    end
end


-- Cast any non-bool args to bool.
-- If the default is a boolean and the main table has a 0/1 in that spot,
-- it will be converted to a corresponding bool false/true; this done to
-- cleanup md failure to transfer bools properly.
function L.Fix_Bool_Args(args, defaults)
    if not defaults then return end
    for k, v in pairs(defaults) do
        if type(v) == "boolean" then
            -- Swap 0/1 to false/true. Does nothing if already bool.
            if args[k] == 0 then
                args[k] = false
            elseif args[k] == 1 then
                args[k] = true
            end
        -- Recursively handle subtables.
        elseif type(args[k]) == "table" and type(v) == "table" then
            L.Fix_Bool_Args(args[k], v)
        end
    end
end


Register_Require_Response("extensions.sn_mod_support_apis.ui.simple_menu.Library", L)
return L