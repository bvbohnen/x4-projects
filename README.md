# X4 Named Pipes API (and Key Capture API)
Adds support for Windows named pipes to X4 Foundations, in support ofinter-process communication.
X4 will act as a client, with one or more an external applications serving the pipe(s).

The initial use of pipes is for the key capture api.
This allows MD scripts to register a key or key combination with a cue to be called when pressed by the player.


Installation
------------
* Basic API install
  - Grab the latest release, unpack into the X4 Foundations folder.
  - This may lag significantly behind the latest work during active development.
* Developer/test install
  - Clone or copy the git repo.
  - Symlink the named_pipes_api folder to the X4 Foundations extensions folder.
  - Optionally symlink the key_capture_api as well.
  - Copy or symlink the winpipe_64.dll to X4 Foundations/ui/core/lualibs
    - Optionally compile the Win_Pipe_API project in Visual Studio (2017) to
    obtain a fresh winpipe_64.dll.
  - If running the test Python server, obtain Python 3 and install the pywin32 package.
    - Anaconda Python has pywin32 installed already.
    - For key capture, this also needs the pynput package.

Dev Testing
-----------
* Launch Python_Server/Main.py.
* Start up X4 and load a save.
* To test the Lua API:
  - Edit named_pipes.lua to uncomment the "Test()" function call.
  - Edit the private variable table to turn on debug, to chat window or log.
  - Open the in-game chat window, and call "/reloadui".
* To test the MD named pipe API:
  - Edit Test_Named_Pipes.xml to uncomment "<check_value value="false"/>"
    in the Test_Named_Pipe cue conditions.
  - In the chat window, call "/refreshmd".
  - Tests are set to occur periodically; wait for the next test.
* To test the MD key capture API:
  - Edit Test_Key_Capture.xml as above.
  - Optionally change the key/combos being captured.
  - When keys pressed, their codes should print to the chat window.
* The game can be paused while reading the chat window output and
  refreshing the lua or md, though md tests require an unpause.

API
---
* Lua API is documented in named_pipes.lua, and is primarily for internal use.
* MD API is documented in LIB_Named_Pipes.xml and LIB_Key_Capture.xml.
