
-- Table holding lib functions to be returned.
local L = {}


-- Shared function to raise a named galaxy signal with an optional
-- return value.
function L.Raise_Signal(name, return_value)
    -- Clumsy way to lookup the galaxy.
    -- local player = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
    -- local galaxy = GetComponentData(player, "galaxyid" )
    -- SignalObject( galaxy, name, return_value)
    
    -- Switching to AddUITriggeredEvent
    -- This will give the return_value in event.param3
    -- Use <event_ui_triggered screen="'Named_Pipes'" control="'<name>'" />
    AddUITriggeredEvent("Named_Pipes", name, return_value)
end



-- Split a string on the first semicolon.
-- Note: works on the MD passed arrays of characters.
-- Returns two substrings.
function L.Split_String(this_string)

    -- Get the position of the separator.
    local position = string.find(this_string, ";")
    if position == nil then
        -- Debug error printout gets a nicer log heading.
        DebugError("No ';' separator found in: "..tostring(this_string))
        -- Hard error.
        error("Bad separator")
    end

    -- Split into pre- and post- separator strings.
    local left  = string.sub(this_string, 0, position -1)
    local right = string.sub(this_string, position +1)
    
    return left, right
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