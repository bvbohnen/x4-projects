# X4 Named Pipes
Adds support for Windows named pipes to X4 Foundations, in support of inter-process communication.
X4 will act as a client, with one or more an external applications serving the pipe(s).
The initial use of pipes is for the key capture api, allowing custom hotkeys in X4.

### Organization

This project is organized into three parts:

* Named Pipes API
  - X4 extension for interfacing with pipes and a host python server.
* X4 Python Pipe Server
  - Python host which dynamically loads py server modules from extensions.
* Win Pipe API
  - C code for generating a lua compatible dll that wraps key Windows pipe functions.
  - A precompiled dll is included in X4_Files.

Additional Readme files are located in their corresponding directories.
Secondary parts of this repository include test X4 extensions for the above, and python code for generating releases.

### Dependencies
* https://github.com/bvbohnen/x4-lua-loader-api.git
* Python 3.6+
  - pywin32 package (python -m pip install pywin32)


### Installation

* Basic install
  - Grab zip files from the Releases page, for wanted components.
    - Named_Pipes_API requires Lua_Loader_API.
    - X4_Python_Pipe_Server needed to service pipes.
      - This can be placed anywhere convenient.
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
  - Possibly edit Test_Key_Capture.xml line ~18 to enable a basic test that prints select keys to the chat window.
    - This step may be changed at some point.

