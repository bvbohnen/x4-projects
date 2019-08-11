# X4 Named Pipes
Adds support for Windows named pipes to X4 Foundations, in support of inter-process communication.
X4 will act as a client, with one or more an external applications serving the pipe(s).
The initial use of pipes is for the key capture api, allowing custom hotkeys in X4.

### Organization

Due to the somewhat modular nature of components of this project, this has been split into five primary parts:

* Named Pipes API
  - X4 extension for interfacing with pipes and a host python server.
* X4 Python Pipe Server
  - Python host which dynamically loads py server modules from extensions.
* Key Capture API
  - X4 extension for registering keys or combos to callback cues, with a python server module to handle input capture.
* Lua Loader API
  - X4 extension with basic support for loading lua files.
* Win Pipe API
  - C code for generating a lua compatible dll that wraps key Windows pipe functions.
  - A precompiled dll is included with Named Pipes.

Additional Readme files are located in their corresponding directories.
Secondary parts of this repository include test X4 extensions for the above, and python code for generating releases.


### Installation

* Basic install
  - Grab zip files from the Releases page, for wanted components.
    - Named_Pipes_API requires Lua_Loader_API.
    - Key_Capture_API requires Named_Pipes_API.
      - The above zip files extract to the X4 directory.
    - X4_Python_Pipe_Server needed to service pipes.
      - This can be placed anywhere convenient.
  - Running the python server requires:
    - Python 3.6+
    - pywin32 package (part of the Anaconda distribution already)
    - pynput package (for Key Capture API)
    - Packages can be installed from command the line:
      - python -m pip install pywin32
      - python -m pip install pynput
  - The python server may be started before or after loading X4.
    - From command line: "python X4_Python_Pipe_Server/Main.py"
    - If started while a game is running, it may take a few seconds before a connection is made.
 
* Developer install
  - Python requirements are the same as above.
  - Clone or copy the git repo.
  - Symlink the extension folders of interest to the X4 Foundations extensions folder.
    - Command line example:
      - mklink /J "%X4_PATH%\extensions\named_pipes_api" "%REPO_PATH%\X4_Files\extensions\named_pipes_api"
  - Copy or symlink the winpipe_64.dll to X4 Foundations/ui/core/lualibs
    - Optionally compile the Win_Pipe_API project in Visual Studio (2017) to obtain a fresh winpipe_64.dll.
  - Edit Test_Key_Capture.xml line ~18 to enable a basic test that prints select keys to the chat window.

