--[[
Lua interface between md and the chat window.
Primary goal is to intercept chat text and pass it back to md, with some
string parsing to break apart command arguments.

Notes on integrating with the chat window:
- All functions and data in chatwindow.lua are local.
- View.registerMenu is called with the onChatWindowCreated function, though
  this is done before mod lua can intercept it.
- View.menus can be used to access the onChatWindowCreated function.
- onChatWindowCreated attaches the onCommandBarDeactivated function to the
  editbox widget deactivation (eg. <enter>) using SetScript.
- If onChatWindowCreated is called before modded lua can run, then it cannot
  be intercepted, but this case can be detected using View.hasMenu and
  corrected.

TODO:
- Add text coloring support, similar to stock menu.
- Mimic the egosoft style of handling messages (eg. red color, ; separated and
  putting first term in brackets).
- Easy way to enable/disable for debug purposes.
- pcalls and such for better error handling.
- Detect wordwrap and plan around it to avoid text going outside the table.
- Find a way to suppress the ego ExecuteDebugCommand
]]

-- FFI stuff.
local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    void SetEditBoxText(const int editboxid, const char* text);
]]

-- Imports.
local Lib = require("extensions.sn_mod_support_apis.ui.Library")
local Time = require("extensions.sn_mod_support_apis.ui.time.Interface")
local T = require("extensions.sn_mod_support_apis.ui.Text")

-- Copy of ego config terms of interest.
local config = {
    maxOutputLines = 8,
    textColor = {
        ["command"]       = "#FFFFFFFF", -- white
        ["directMessage"] = "#FFFF2B2B", -- bright red
        ["otherMessage"]  = "#FFF2F200", -- yellow
        ["ownMessage"]    = "#FF1B893C", -- dark green
        ["serverMessage"] = "#FFAE02AE"  -- bright purple
    },
}

local L = {
    -- The original egosoft callback function on menu creation.
    ego_onChatWindowCreated = nil,

    -- List of recorded text lines entered.
    text_lines = {},

    -- The editbox widget.
    edit_box = nil,
    -- The text table widget. Has only one cell.
    text_table = nil,

    -- If this code should control the text display.
    control_text = true,

    -- Shortened commands that users may give.
    short_commands = {
        rui = "reloadui",
        rai = "refreshai",
        rmd = "refreshmd",
    },
}

-- Signalling results from lua to md.
-- args is nil or a list of space separated strings.
function L.Raise_Signal(name, args)
    AddUITriggeredEvent("Chat_Window_API", name, args)
end


function L.Init()
    RegisterEvent("Chat_Window_API.Print", L.onPrint)
    -- Also listen to the normal event, for compatability.
    RegisterEvent("directChatMessageReceived", L.onPrint)
    

    -- The window could already have been created, or have yet to be created.
    -- Aim to handle both cases.
    -- Intercepting View.registerMenu to listen for new chat windows.
    local ego_registerMenu = View.registerMenu
    View.registerMenu = function(id, ...)
        -- Let View do the initial setup.
        ego_registerMenu(id, ...)
        -- Use shared code to search for the chat window.
        if id == "chatWindow" then
            L.Patch_New_Menu()
        end
    end

    -- The chat window might already be set up in View, so always run
    -- this once, to find an exiting menu.
    L.Patch_New_Menu()

end

-- Search View for the chatWindow and patch it if found.
function L.Patch_New_Menu()
    local chat_menu = nil
    for i, menu in ipairs(View.menus) do
        if menu.id == "chatWindow" then
            chat_menu = menu
            break
        end
    end

    -- If not found, this may be the init call with no shown window, so skip.
    if chat_menu == nil then
        return
    end

    -- Intercept the creation callback.
    L.ego_onChatWindowCreated = chat_menu.callback
    chat_menu.callback = L.onChatWindowCreated

    -- Check if the chat window is already open.
    if View.hasMenu({chatWindow = true}) then
        -- Update it; triggers onChatWindowCreated callback linked above.
        View.updateMenu(chat_menu)
    end
end

-- On creation, link to the window widgets, and set a callback editbox script.
function L.onChatWindowCreated(frames)
    -- Run the original setup function to connect its onHideChatWindow
    -- and other links.
    L.ego_onChatWindowCreated(frames)

    -- Copy some of the setup code to record widgets.
    local children = table.pack(GetChildren(frames[1]))
    L.edit_box = GetCellContent(children[2], 1, 1)
    L.text_table  = children[1]

    -- Set the callback script. This is called in addition to the
    -- egosoft onCommandBarDeactivated callback, but should be called after.
    SetScript(L.edit_box, "onEditBoxDeactivated", L.onCommandBarDeactivated)

    -- Overwrite the standard inintial window text (may have stuff if this
    -- isn't the first time shown).
    L.rebuildWindowOutput()
end


-- Process edit box text when user presses <enter> on it.
function L.onCommandBarDeactivated(_, text, _, wasConfirmed)
    -- Skip if deactivated without confirmation (eg. <enter>).
    if not wasConfirmed then return end
    L.Process_Text(text)
end

function L.Process_Text(text)
    -- Skip empty text.
    if text == "" then return end

    --DebugError("Chatwindow saw text: " .. text)
    
    if L.control_text then
        -- Clear the edit box.
        C.SetEditBoxText(L.edit_box, "")
    end

    -- Space separate terms.
    local terms = Lib.Split_String_Multi(text, " ")

    -- If double+ spacing was used, some of these terms are empty.
    -- Trim empty terms here.
    local terms_trimmed = {}
    for i, term in ipairs(terms) do
        if term ~= "" then
            table.insert(terms_trimmed, term)
        end
    end
    terms = terms_trimmed

    -- If there are no terms (eg. user entered just spaces), ignore.
    if #terms == 0 then return end

    -- Echo this back to ai/md scope.
    L.Raise_Signal("text_entered", {terms = terms, text = text})
    
    if L.control_text then
        L.Add_Line(text)

        -- Do some egosoft style processing.
        -- This looks for a starting "/" for backend commands, and passes along
        -- any potential parameters (not currently used in any actual commands).
        if string.sub(terms[1], 1, 1) == "/" then
            -- Remove the "/" from the command.
            local command = string.sub(terms[1], 2, #terms[1])

            -- Pack all remaining terms as a single parameter string.
            local param = ""
            if #terms > 1 then
                for i = 2, #terms do
                    param = param .. " " .. terms[i]
                end
            end

            -- Special short commands.
            if L.short_commands[command] ~= nil then
                command = L.short_commands[command]
                -- Hand off to backend for /refreshmd and similar.
                -- Note: don't do this for the normal full command, since the
                -- ego code will also check this string and run the command.
                -- TODO: suppress the ego ExecuteDebugCommand and always do
                -- it here, so the log doesn't have an unknown command error.
                ExecuteDebugCommand(command, param)
            end
        

            -- Signal the command specifically, for user script convenience.
            -- This way md scripts can detect /refreshmd, ai /refreshai.
            -- These signals should be processed on the next frame, so
            -- the script refresh will be complete.
            if command == "refreshmd" or command == "refreshai" then
                L.Raise_Signal(command)
            end
        end
    end
end


-- Add a line to the text table.
-- Line will be formatted, and may be broken into multiple lines by word wrap.
-- Oldest lines will be removed, past the textbox line limit.
function L.Add_Line(line)

    -- Format the line; expect to maybe get newlines back.
    -- TODO: think about this. Also consider if original text has newlines.
    local f_line = line

    -- Split and add to existing text lines.
    local sublines = Lib.Split_String_Multi(f_line, "\n")
    for i, subline in ipairs(sublines) do
        table.insert(L.text_lines, subline)
    end

    -- Remove older entries.
    if #L.text_lines > config.maxOutputLines then
        local new_text_lines = {}
        for i = #L.text_lines - config.maxOutputLines + 1, #L.text_lines do
            table.insert(new_text_lines, L.text_lines[i])
        end
        L.text_lines = new_text_lines
    end

    -- Update the text window.
    L.rebuildWindowOutput()
end

-- Print a line sent from md.
function L.onPrint(_, text)
    -- Ignore if not controlling the text.
    if not L.control_text then return end
    L.Add_Line(text)
end


-- On each update, do a fresh rebuild of the window text.
-- This works somewhat differently than the ego code, aiming to fix an ego
-- problem when text wordwraps (in ego code causes it to print outside/below
-- the text window).
function L.rebuildWindowOutput()

    -- Skip if the table isn't set up yet.
    if L.text_table == nil then return end

    -- Merge the lines into one string.
    local text = ""
    for i, line in ipairs(L.text_lines) do
        text = text .. "\n" .. line
    end

    -- Jump a couple hoops to update the table cell. Copy/edit of ego code.
    local contentDescriptor = CreateFontString(text, "left", 255, 255, 255, 100, "Zekton", 10, true, 0, 0, 160)
    local success = SetCellContent(L.text_table, contentDescriptor, 1, 1)
    if not success then
        DebugError("ChatWindow error - failed to update output.")
    end
    ReleaseDescriptor(contentDescriptor)
end

-- Removed. TODO: overhaul for changes made in 6.0+.
--L.Init()