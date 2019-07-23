# X4_Named_Pipes_API
Adds support for Windows named pipes to X4 Foundations.
X4 will act as a client, with one or more an external applications serving the pipe(s).

Version: early preview, unversioned.

Installation
------------
* Copy, or symlink, the named_pipes_api folder to the X4 Foundations extensions folder.
* Copy winapi_64.dll to X4 Foundations/ui/core/lualibs
  - A copy of this is uploaded to github, but not directly in the repo.
  - Instructions on how to compile the dll are found in named_pipes.lua.

Testing
-------
* Launch Python_Server/Test.py.
* Start up X4 and load a save.
* To test the Lua API:
  - Edit named_pipes.lua to uncomment the "Test()" function call.
  - Open the in-game chat window, and call "/reloadui".
* To test the MD API:
  - Edit md/Test_Named_Pipes.xml to uncomment "<check_value value="false"/>" in the Test_Named_Pipe cue.
  - In the chat window, call "/refreshmd".
  - Tests are set to occur periodically; wait for the next test.
* In both cases, the server Test.py needs to be restarted between tests.
* Debug messages are printed to the chat window.
* The game can be paused while reading the chat window output and refreshing the md.

API
---
* Lua API is documented in named_pipes.lua.
* MD API is documented in LIB_Named_Pipes.xml.

Acknowledgements
----------------
* Makes use of the Lua winapi bindings
  - https://github.com/stevedonovan/winapi
* X4 developed by Egosoft