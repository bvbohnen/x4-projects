# X4_Named_Pipes_API
Adds support for Windows named pipes to X4 Foundations, in support ofinter-process communication.
X4 will act as a client, with one or more an external applications serving the pipe(s).

Installation
------------
* Copy, or symlink, the named_pipes_api folder to the X4 Foundations extensions folder.
* Copy winpipe_64.dll to X4 Foundations/ui/core/lualibs
  - Optionally compile using visual studio and the Win_Pipe_API project.

Testing
-------
* Launch Python_Server/Test.py.
* Start up X4 and load a save.
* To test the Lua API:
  - Edit named_pipes.lua to uncomment the "Test()" function call.
  - Open the in-game chat window, and call "/reloadui".
* To test the MD API:
  - Edit md/Test_Named_Pipes.xml to uncomment "<check_value value="false"/>"
    in the Test_Named_Pipe cue.
  - In the chat window, call "/refreshmd".
  - Tests are set to occur periodically; wait for the next test.
* In both cases, the server Test.py needs to be restarted between tests,
  unless the 'close' command is removed from the test lua/md code.
* Debug messages are printed to the chat window.
* The game can be paused while reading the chat window output and
  refreshing the md.

API
---
* Lua API is documented in named_pipes.lua, and is primarily for internal use.
* MD API is documented in LIB_Named_Pipes.xml.

Pitfalls
--------
* No testing yet performed on save/reload behavior when expecting a pipe read.
* Reads are currently blocking; the server should respond in a timely manner,
  ideally withing 1-2 game frames.
