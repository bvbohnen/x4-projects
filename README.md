# X4 Named Pipes API
Adds support for Windows named pipes to X4 Foundations, in support ofinter-process communication.
X4 will act as a client, with one or more an external applications serving the pipe(s).

Installation
------------
* Basic API install
  - Grab the latest release, unpack into the X4 Foundations folder.
* Developer/test install
  - Clone or copy the git repo.
  - Symlink the named_pipes_api folder to the X4 Foundations extensions folder.
  - Copy or symlink the winpipe_64.dll to X4 Foundations/ui/core/lualibs
    - Optionally compile the Win_Pipe_API project in Visual Studio (2017) to
    obtain a fresh winpipe_64.dll.
  - If running the test Python server, obtain Python 3 and install the pywin32 package.
    - Anaconda Python has pywin32 installed already.

Dev Testing
-----------
* Launch Python_Server/Test.py.
* Start up X4 and load a save.
* To test the Lua API:
  - Edit named_pipes.lua to uncomment the "Test()" function call.
  - Open the in-game chat window, and call "/reloadui".
* To test the MD API:
  - Edit md/Test_Named_Pipes.xml to uncomment "<check_value value="false"/>"
    in the Test_Named_Pipe cue conditions.
  - In the chat window, call "/refreshmd".
  - Tests are set to occur periodically; wait for the next test.
* In both cases, the server Test.py needs to be restarted between tests.
  - This could be changed by removing the 'close' command from the
    test lua or md code.
* Debug messages are printed to the chat window.
* The game can be paused while reading the chat window output and
  refreshing the lua or md, though md tests require an unpause.

API
---
* Lua API is documented in named_pipes.lua, and is primarily for internal use.
* MD API is documented in LIB_Named_Pipes.xml.

Pitfalls
--------
* No testing yet performed on save/reload behavior when expecting a pipe read.
* Reads are currently blocking; the server should respond in a timely manner,
  ideally within ~20 ms, and needs to send enough data to satisfy all reads.
