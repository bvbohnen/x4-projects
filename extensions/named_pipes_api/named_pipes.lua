--[[
Support for communicating through windows named pipes with
an external process.

The external process will be responsible for serving pipes.
X4 will act purely as a client.


Reading:
	Start with a trigger:
	
		<raise_lua_event name="'pipeRead'" param="'<pipe_name>'"/>
		
	Capture completion with a new subcue (don't instantiate if already inside
	an instance), conditioned on response signal:
	
		<event_object_signalled 
			object="player.galaxy" 
			param="'pipeRead_complete_<pipe_name>'"/>
		
	The returned value will be in "event.param2":
	
		<set_value name="$pipe_read_value" exact="event.param2" />
		
	<pipe_name> should be replaced with the full path name of the pipe
	being connected to. Example: "\\.\pipe\x4_pipe", with doubled backslashes
	as needed for escapes in the string creation.
	
	If the read fails due to a closed pipe, a return signal will still be sent,
	but param2 will contain 'ERROR'.
	
	
Writing:
	The message to be sent will be suffixed to the pipe_name, separated
	by a semicolon.
	
		<raise_lua_event name="'pipeWrite'" param="'<pipe_name>;message'"/>	
			
	For now, no signal is raised on write completion, success or failure.
	
	
Check if pipes open:
	Test if the pipe is open in a similar way to reading:
	
		<raise_lua_event name="'pipeCheck'" param="'<pipe_name>'" />
	
		<event_object_signalled 
			object="player.galaxy" 
			param="'pipeCheck_complete'"/>
			
	In this case, event.param2 holds true if the pipe appears to be
	succesfully opened, false if not. Note that this does not robustly
	test the pipe.
		
	

TODO:
	Flesh out, make robust, etc. etc.
	
	Think about how to deal with reloads and /reloadui events when
	io read requests are active.  Game reloads should toss out leftover
	read responses, but UI reloads should keep servicing them, and
	game saves in the middle of a read request will need a way to
	know to resend the request upon reloading.
	This can be pushed to the MD api, which naturally is able to save state.
	
	
Note:
	The external pipe names are (with extra lua escape slashes):
		"\\\\.\\pipe\\x4input"  (\\.\pipe\x4_input)
		"\\\\.\\pipe\\x4output" (\\.\pipe\x4_output)
]]


-- Generic required ffi.
local ffi = require("ffi")
local C = ffi.C


-- This will use winapi
--  https://github.com/stevedonovan/winapi
-- Goal is to use named pipes, which are more desirable anyway than file io.
-- Notes on compiling winapi to a dll are further below.
local winapi = require("winapi")


-- Forward declarations of functions.
-- (Does redeclaring them local further below break things? TODO)
local Init
local Handle_pipeRead
local Handle_pipeWrite
local Handle_pipeCheck

--local Handle_Read_Responses

local Raise_Signal
local Open_Pipe
local _Write_Pipe_Raw
local Write_Pipe
local _Read_Pipe_Raw
local Read_Pipe
local Test


-- Match the style of egosoft lua, with a private table containing
-- static variables.
-- For safety, most higher level state (transmit buffers and such) will
-- be kept at the MD level, to be recorded in saved games.
local private = {
	-- Pipe objects, generally live while the link is set up.
	-- Keys are the basic pipe names sent from the MD side, with full path
	-- extension.
	-- Entries are non-existent or nil for closed pipes (all pipes are
	-- closed/non-existent on a ui reload or save game reload).
	pipes = { },

	-- If a failed access is allowed one retry.
	-- On a retry attempt, this flag should be cleared.
	retry_allowed = false,
	}

-- Removed; buffering logic pulled out of lua and put in MD.
-- TODO: consider if this should be re-added.
--[[
-- List definition, taken from https://www.lua.org/pil/11.4.html
-- Names modified somewhat for fifo behavior.
-- TODO: make more object oriented, once better understanding lua.
FIFO = {}
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

-- Returns true if fifo is empty, else false.
function FIFO.Is_Empty (fifo)
  empty = fifo.first > fifo.last
  return empty
end
]]

-- Handle any initial setup.
function Init()
	-- Connect the events to the matching functions.
	RegisterEvent("pipeRead", Handle_pipeRead)
	RegisterEvent("pipeWrite", Handle_pipeWrite)
	RegisterEvent("pipeCheck", Handle_pipeCheck)
		
end

-- Shared function to raise a named galaxy signal with an optional
-- return value.
function Raise_Signal(name, return_value)
	-- Clumsy way to lookup the galaxy.
	local player = ConvertStringTo64Bit(tostring(C.GetPlayerID()))
	local galaxy = GetComponentData(player, "galaxyid" )
	SignalObject( galaxy, name, return_value)
end


-- Check if a pipe is currently open, and if not, try to open it.
-- An error will be raised if the pipe opening failed.
-- Note: if the pipe was open, but the server shut down and restarted,
-- the call to this function will look like the pipe is good when it
-- will actually fail the first access.
-- As such, if the pipe is already open, a retry_allowed flag will be
-- set, so that the first access that fails can close the pipe and
-- try to reopen it.
function Open_Pipe(pipe_name)

	-- If the name isn't present, try to open it.
	if private.pipes[pipe_name] == nil then
		private.pipes[pipe_name] = winapi.open_pipe(pipe_name)
		
		-- If the entry is still nil, the open failed.
		if private.pipes[pipe_name] == nil then
			-- TODO: maybe print an error to the chat window, but the concern
			-- is that scripts will keep attempting to access the pipe and
			-- will spam error messages.
			-- A simple error description is used for the Test function.
			error("open_pipe returned nil for "..pipe_name)
		end
			
		-- Announce to the server that x4 just connected.
		-- private.pipes[pipe_name]:write('connected\n')
		
		-- Debug print.
		CallEventScripts("directChatMessageReceived", pipe_name..";Pipe connected in lua")
	else
		-- Since no real testing done, allow one retry if an access fails.
		private.retry_allowed = true
	end
	
	-- TODO: test the pipe.
	-- Ideal would be an echo, sent to the server and bounced back,
	--  but the problem is that that would add delay, and the check should
	--  ideally occur on every test. Also, it may cause a data ordering
	--  problem when the user requests a read.
	-- For now, just hope things work out if the file opened, and check for
	--  errors in the Read/Write functions.

	-- TODO: how to change pipe mode?  winapi appears to forget to
	-- expose SetNamedPipeHandleState, which means these pipes are
	-- in byte mode and not message mode. For writes this doesn't
	-- matter (server reads as messages, eg. individual write accesses),
	-- but for reading it needs a way to distinguish multiple reads
	-- that may have been pipelined.
	-- Test this, think of ideas, maybe need to parse read bytes or
	-- else only allow one read request at a time in flight (or send
	-- multiple read reqs but ack each response, so server knows when
	-- to move to next response).
	-- Alternatively, modify winapi to open pipes in message mode,
	-- or (more complicated) to expose SetNamedPipeHandleState.
	-- Aternatively, protocol can presend how many bytes are in a message,
	-- and the other end access just that many bytes.
	
end

-- Close a pipe.
-- Call this when any pipe error is caught, for some cleanup.
function Close_Pipe(pipe_name)
	-- Do a safe close() attempt, ignoring errors.
	pcall(function () private.pipes[pipe_name].close() end)
	-- Clear the link to hard-kill the pipe.
	private.pipes[pipe_name] = nil
end


-- Support function for pipe writing.
-- This will throw errors, and does no error handling.
-- Could also be anonymous, but that apparently has performance problems in lua.
function _Write_Pipe_Raw(pipe_name, message)
	-- Open the pipe if needed. Let errors carry upward.
	Open_Pipe(pipe_name)
	
	-- Send the write request on the output pipe.
	-- Presumably this returns the number of bytes actually written, so
	-- assume a 0 means an error.
	local result = private.pipes[pipe_name]:write(message)
	if result == 0 then
		CallEventScripts("directChatMessageReceived", pipe_name..";0 bytes written")
		error("writing ("..message..") to pipe ("..pipe_name..") returned 0 bytes written")
	end
end

-- Write to a pipe, with error handling.
-- Returns 1 on success, 0 on error.
function Write_Pipe(pipe_name, message)
	-- _Write_Pipe_Raw(pipe_name, message) --Testing
	local success = pcall(_Write_Pipe_Raw, pipe_name, message)
	
	if success then
		-- Debug print.
		CallEventScripts("directChatMessageReceived", pipe_name..";Wrote: "..message)
	else
		-- Close the pipe out.
		Close_Pipe(pipe_name)
		-- Debug print.
		CallEventScripts("directChatMessageReceived", pipe_name..";Write error")

		-- Retry, if allowed.
		if private.retry_allowed then
			CallEventScripts("directChatMessageReceived", pipe_name..";Retrying write...")
			private.retry_allowed = false
			-- Call self; this should not enter a infinite loop since the
			-- retry flag will not be reset (since it only gets set when
			-- a pipe was open, but it is now closed).
			Write_Pipe(pipe_name, message)
		end
	end
end


-- Read a pipe, possibly throwing an error.
function _Read_Pipe_Raw(pipe_name)
	-- Open the pipe if needed. Let errors carry upward.
	Open_Pipe(pipe_name)
	
	-- Read in whatever is in the pipe.
	-- Apparently this either returns text, or [nil, error]
	-- In lua, the error term will be nil if not returned.
	-- TODO: apparently this is unbuffered and reads whatever is there;
	--  look into this and think how to fix.
	-- TODO: non-blocking read.
	local message, this_error = private.pipes[pipe_name]:read()
	if this_error ~= nil then
		error()
	end
	return message
end

-- Read a pipe safely, closing it on error.
-- Returns the message, or 'ERROR'.
function Read_Pipe(pipe_name)
	local success, message = pcall(_Read_Pipe_Raw, pipe_name)
	
	if success then
		-- Debug print.
		CallEventScripts("directChatMessageReceived", pipe_name..";Read: "..message)
	else
		-- Close the pipe out.
		Close_Pipe(pipe_name)
		-- Switch to an error message for upstream.
		message = "ERROR"
		-- Debug print.
		CallEventScripts("directChatMessageReceived", pipe_name..";Read error")
		
		-- Retry, if allowed.
		if private.retry_allowed then
			CallEventScripts("directChatMessageReceived", pipe_name..";Retrying read...")
			private.retry_allowed = false
			message = Read_Pipe(pipe_name)
		end
	end
	
	return message
end



-- MD interface: check if a pipe is connected.
function Handle_pipeCheck(pipe_name)
	local success = pcall(Open_Pipe, pipe_name)
	Raise_Signal('pipeCheck_complete', success)
end


-- MD interface: write to a pipe.
-- Since lua events take one arg, it has to have both the pipe name
-- and the message to write, semicolon separated.
function Handle_pipeWrite(_, pipe_name_with_value)

	-- Get the position of the separator.
	local position = string.find(pipe_name_with_value, ";")
	if position == nil then
		-- TODO: error in message construction.
	end

	-- Split into pre- and post- separator strings.
	local pipe_name = string.sub(pipe_name_with_value, 0, position -1)
	local message   = string.sub(pipe_name_with_value, position +1)
	
	-- Hand off to the writer.
	Write_Pipe(pipe_name, message)
	
	-- TODO: maybe a response for success/failure.
end


-- MD interface: read a message from a pipe.
function Handle_pipeRead(_, pipe_name)

	-- TODO: play around with SetScript("onUpdate", Handle_Queues_Reads),
	-- sticking wanted reads in a queue to be checked each cycle and
	-- serviced as they come in.
	-- If this is the first item to be added to the response fifo, turn on the
	-- response handler.
	-- if FIFO.Is_Empty(read_request_fifo) then
	-- 	CallEventScripts("directChatMessageReceived", "pipe;Registering Handle_Read_Responses")
	-- 	SetScript("onUpdate", Handle_Read_Responses)
	-- end
		
	-- Hand off to the reader.
	local message = Read_Pipe(pipe_name)
	
	-- Return, suffixing the signal name with the pipe_name.
	Raise_Signal('pipeRead_complete_'..pipe_name, message)		
end


-- Service to process read requests.
-- Runs every cycle while a read is active, checking pipes for a response.
-- TODO: set this up once non-blocking reads are implemented.
--[[
function Handle_Read_Responses()

	-- Loop over queued requests.
	
	-- Try to service this request.
	
	-- If succesful, remove from the queue, and signal with the result.
	
	-- If the queue is empty, disconnect this function.
	-- RemoveScript("onUpdate", Handle_Read_Responses)

end
]]



-- TODO:
-- Polish up the interface: open pipes in background, occasionally check
--  if the python side closed/reopened/etc., add functions/events for
--  reading and writing the pipes; use separate pipes for each directly;
--  handshake if necessary (though that can be MD level), etc.


-- TODO: return some table of exported functions, if wanting others to
-- use this in their lua. (If the import system pathing gets figured out.)

-- Finalize with initial setup.
Init()

-- TODO: consider exporting functions for other lua modules.


-- Small test function.
-- Only run this if the external named pipes are set up and ready.
-- This will do a test write, then a test read.
-- Note: when logging to the chat window, it was noticed that sometimes
--  the window doesn't display the latest activity, and needs to be
--  closed/reopened to see all messages.
function Test()
	local pipe_name = "\\\\.\\pipe\\x4_pipe"
	CallEventScripts("directChatMessageReceived", "pipes;Starting pipe test on "..pipe_name)
	Open_Pipe(pipe_name)
	Write_Pipe(pipe_name, "write:[test1]5")
	Write_Pipe(pipe_name, "read:[test1]")
	local message = Read_Pipe(pipe_name)
end

-- Uncomment this to run the test. Used during development.
--Test()


--[[
Notes on compiling winapi on windows using VS2017:
- Grab the lua 5.1 binaries (exe); lua5_1_4_Win64_bin
- Grab the /include headers from lua-5.1.4_Win64_dll12_lib or lua-5.1.4_Win64_vc12_lib
  These headers appear the same.
  Ignore the dll/lib files.
- Grab the lua51_64.dll from the x4 folder
- Using VS2017, open the developer command prompt in x64 mode.
  For this, I created a new shortcut with the arch arg:
  %comspec% /k "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64
- Convert this dll into a lib file using technique from:
  https://stackoverflow.com/questions/9946322/how-to-generate-an-import-library-lib-file-from-a-dll
  The bat file on that page works well; run in the dev prompt.
- Get the winapi-master git repo
- Edit the winapi build-msvc.bat file to update paths.
  Eg. use "lua51_64.lib" obtained above.
- Run it; hopefully it has no errors, though I did get a warning about default libs.
- Name the dll winapi_64.dll (x4 appends the _64) and place it in ui/core/lualibs
]]

--[[
A couple old, quick winapi tests.

-- Launching the calculator works!
-- winapi.shell_exec('open','calc.exe')

-- Match this name to what was opened python-side.
-- Result: test succesfully sent message to python.
local pipe = winapi.open_pipe("\\\\.\\pipe\\x4pipe")
pipe:write 'hello\n'
pipe:close()
]]


-- Old ffi related notes/attempts:
--
-- Testing using ffi for file access, since x4 doesn't include the io library.
-- One possibility (maybe overly complex):
-- 	https://github.com/luapower/stdio/blob/master/stdio.lua
--
-- Simpler example:
--  https://stackoverflow.com/questions/30585574/write-to-file-using-lua-ffi
-- Above failed to find fopen/etc.
--
-- New approach: 
-- Get C ffi functions from: https://github.com/jmckaskill/luaffi
-- Download lua 5.1 binary (exe)
-- Grab X4 lua dll; obtain lib file using:
--  https://stackoverflow.com/questions/9946322/how-to-generate-an-import-library-lib-file-from-a-dll
-- Edit bat file: change paths, comment out "/I"msvc"" or else comment the bool header to not define _Bool.
--  (VS2017 already defined _Bool as bool, causing errors.)
--  (Also change the output target from ffi.dll to something else.)
-- Put this dll in x4/ui/core/lualibs
-- Require it here
-- ???
-- profit
-- Result: sorta success, though the luaffi only has limited functionality
--  and nothing for opening/closing files, just stuff for writing them.
--  Hence, the "fopen" still fails to be found.
--
--
-- ffi.cdef[[
-- typedef struct {
--   char *fpos;
--   void *base;
--   unsigned short handle;
--   short flags;
--   short unget;
--   unsigned long alloc;
--   unsigned short buffincrement;
-- } FILE;
-- 
-- FILE *fopen(const char *filename, const char *mode);
-- int fprintf(FILE *stream, const char *format, ...);
-- int fclose(FILE *stream);
-- ]]
-- -- Apparently ffi.load goes after the cdef?
-- local clib = ffi.load("C:\\Steam\\steamapps\\common\\X4 Foundations\\ui\\core\\lualibs\\ffi_c.dll")
-- 
-- local f = C.fopen("ffi_test.txt", "a+")
-- C.fprintf(f, "Hello World")
-- C.fclose(f)

