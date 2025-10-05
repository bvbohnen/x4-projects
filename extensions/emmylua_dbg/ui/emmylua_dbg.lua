

local function Init()
    package.cpath = package.cpath .. ";c:/Users/Brent/.vscode/extensions/tangzx.emmylua-0.9.29-win32-x64/debugger/emmy/windows/x64/?.dll"
    local dbg = require("emmy_core")
    dbg.tcpListen("localhost", 9966)
end

Register_OnLoad_Init(Init)
