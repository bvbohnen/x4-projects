--[[
Library functions to be shared across apis.
]]

-- Table to hold lib functions.
local L = {}

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

    -- TODO: look into syntax like:
    -- left, right = string.match(this_string, "(.+)"..separator.."(.+)")

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



-- FIFO definition, largely lifted from https://www.lua.org/pil/11.4.html
-- Adjusted for pure fifo behavior.
-- TODO: change to act as methods.
local FIFO = {}
L.FIFO = FIFO

function FIFO.new ()
  return {first = 0, last = -1}
end    

function FIFO.Write (fifo, value)
  local last = fifo.last + 1
  fifo.last = last
  fifo[last] = value
end

function FIFO.Read (fifo)
  local first = fifo.first
  if first > fifo.last then error("fifo is empty") end
  local value = fifo[first]
  fifo[first] = nil
  fifo.first = first + 1
  return value
end

-- Return the next Read value of the fifo, without removal.
function FIFO.Next (fifo)
  local first = fifo.first
  if first > fifo.last then error("fifo is empty") end
  return fifo[first]
end

-- Returns true if fifo is empty, else false.
function FIFO.Is_Empty (fifo)
  return fifo.first > fifo.last
end


return L