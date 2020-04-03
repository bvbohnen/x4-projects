--[[
    Wrapper for various text lookups from the t files, using ReadText.
    Standardizes the text names for code management, and maybe even speeds
    up lookups (probably negligible impact).
]]

-- Standard page for new text.
local new = 68537

-- Read from page and t entry, with safety fallback if not found.
local function readtext (page, id)
    local text = ReadText(page, id)
    if text == nil then
        text = "["..page..","..id.."]"
    end
    return text
end

local T = {

extensions        = readtext(1001, 2697),
extension_options = readtext( new, 1000),

}

return T