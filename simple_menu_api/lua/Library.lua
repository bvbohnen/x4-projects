--[[
    Misc functions split off into a library file.
    Mostly string or table processing.
]]

-- Table to hold lib functions.
local L = {}


-- Signalling results from lua to md.
-- Takes the row,col of the activated widget, and an optional new value
-- for that widget.
-- TODO: think about this more.
function L.Raise_Signal(name, value)
    AddUITriggeredEvent("Simple_Menu", name, value)
end

-- Table of lua's pattern characters that have special meaning.
-- These need to be escaped for string.find.
-- Can check a separator based on table key; values are dummies.
local lua_pattern_special_chars = {
    ["("]=0, [")"]=0, ["."]=0, ["%"]=0, ["+"]=0, ["-"]=0, 
    ["*"]=0, ["?"]=0, ["["]=0, ["^"]=0, ["$"]=0,
}

-- Split a string on the first separator.
-- Note: works on the MD passed arrays of characters.
-- Returns two substrings, left and right of the sep.
function L.Split_String(this_string, separator)

    -- Get the position of the separator.
    -- Warning: lua is kinda dumb and has its own patterning rules, which
    -- came up with '.' matched anything.
    -- Need to escape with "%" in these cases, though can't use it for
    -- alphanumeric (else it can become some other special code).
    if lua_pattern_special_chars[separator] then
        separator = "%" .. separator
    end
   
    local position = string.find(this_string, separator)
    if position == nil then
        error("Bad separator")
    end

    -- Split into pre- and post- separator strings.
    -- TODO: should start point be at 1?  0 seems to work fine.
    local left  = string.sub(this_string, 0, position -1)
    local right = string.sub(this_string, position +1)
    return left, right
end

-- Split a string as many times as possible.
-- Returns a list of substrings.
function L.Split_String_Multi(this_string, separator)
    substrings = {}
    
    -- Early return for empty string.
    if this_string == "" then
        return substrings
    end
    
    -- Use Split_String to iteratively break apart the args in a loop.
    local remainder = this_string
    local left, right
    
    -- Loop until Split_String fails to find the separator.
    local success = true
    while success do
    
        -- pcall will error and set sucess=false if no separators remaining.
        success, left, right = pcall(L.Split_String, remainder, separator)
        
        -- On success, the next substring is in left.
        -- On failure, the final substring is still in remainder.
        local substring
        if success then
            substring = left
            remainder = right
        else
            substring = remainder
        end
        
        -- Add to the running list.
        table.insert(substrings, substring)
    end
    return substrings
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
  d : optional default
  t : string type, only needed for casting (eg. if not string).
If a name is missing from user args, the default is added to 'args'.
 If the default is the "nil" string, nothing is added.
 If the default is nil, it is treated as non-optional.
Type is "str" or "int"; the latter will get converted to a number.
If the original arg is a string "nil" or "null", it will be converted
 to nil, prior to checking if optional and filling a default.
 
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


-- Replace any arg value that references a Helper const with the actual
-- value, recursively through subtables.
function L.Replace_Helper_Args(args)
    local prefix = "Helper."
    for k, v in pairs(args) do

        -- Look for strings that start with "Helper."
        if type(v) == "string" and string.sub(v, 1, #prefix) == prefix then

            -- Split on the dots.
            local fields = L.Split_String_Multi(v, ".")

            -- Approach will get to start with Helper, and progress through
            -- its fields downward.
            local temp = Helper

            -- Loop over all after the first (skipping Helper)
            for i = 2, #fields do
                if temp then
                    temp = temp[fields[i]]
                end
            end

            -- Error message if ran into nil.
            if not temp then
                DebugError("Simple Menu: Failed lookup of helper const: "..v)
            end

            -- Put it back.
            args[k] = temp

        -- Recurse into subtables.
        elseif type(v) == "table" then
            L.Replace_Helper_Args(v)
        end
    end
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

-- Update the left table with contents of the right one, overwriting
-- when needed. Any subtables are similarly updated (not directly
-- overwritten). Tables in right should always match to tables or nil in left.
-- Returns early if right side is nil.
function L.Table_Update(left, right)
    -- Similar to above, but with blind overwrites.
    if not right then return end
    for k, v in pairs(right) do
        -- Check for left having a table (right should as well).
        if type(left[k]) == "table" then
            -- Error if right is not a table or nil.
            if type(v) ~= "table" then
                DebugError("Table_Update table type mismatch at "..tostring(k))
            end
            L.Table_Update(left[k], v)
        else
            -- Direct write (maybe overwrite).
            left[k] = v
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


-- Print a table's contents to the log.
-- Optionally give the table a name.
-- TODO: maybe recursive.
-- Note: in practice, DebugError is limited to 8192 characters, so this
-- will try to break up long prints.
function L.Print_Table(itable, name)
    if not name then name = "" end
    -- Construct a string with newlines between table entries.
    -- Start with header.
    local str = "Table "..name.." contents:\n"
    local line

    for k,v in pairs(itable) do
        line = "["..k.."] = "..tostring(v).." ("..type(v)..")\n"
        -- If this line will put the str over 8192, do an early str dump
        -- first.
        if #line + #str >= 8192 then
            DebugError(str)
            -- Restart the str.
            str = line
        else
            -- Append to running str.
            str = str .. line
        end
    end
    DebugError(str)
end


-- Chained table lookup, using a series of key names.
-- If any key fails, returns nil.
-- 'itable' is the top level table.
-- 'keys' is a list of string or int keys, processed from index 0 up.
-- If keys is empty, the itable is returned.
function L.Multilevel_Table_Lookup(itable, keys)
    if #keys == 0 then
        return itable
    end
    local temp = itable
    for i = 1, #keys do
        -- Dig in one level.
        temp = temp[keys[i]]
        -- If nil, quick return.
        if temp == nil then
            return nil
        end
    end
    return temp
end


-- Function to take a slice of a list (table ordered from 1 and up).
function L.Slice_List(itable, start, stop)
    local otable = {}
    for i = start, stop do
        -- Stop early if ran out of table content.
        if itable[i] == nil then
            return otable
        end
        -- Else copy over one entry.
        table.insert(otable, itable[i])
    end
    return otable
end


return L