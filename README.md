# X4 Named Pipes API

Adds support for Windows named pipes to X4 Foundations.
Named pipes are OS level psuedo-files which support inter-process communication.
Pipes avoid the overhead of disk access from normal files (eg. debug logs), and are bidirectional.
X4 will act as a client, with one or more an external applications serving the pipes.

There are three components to this API:
 * A low level lua plugin and corresponding dll for pipe access.
 * An MD wrapper that interfaces between the lua and MD pipe users.
 * A default, optional Python external pipe host server.

### Requirements

* Lua Loader API extension
  - https://github.com/bvbohnen/x4-lua-loader-api
* Time API extension
  - https://github.com/bvbohnen/x4-time-api
* Optionally, Simple Menu API
  - https://github.com/bvbohnen/x4-simple-menu-api
* Optionally, Python 3.6+ with the pywin32 package.
  - Only needed if running the pipe server from python source code.
  - An executable is provided as an alternative.
  - The pywin32 package is part of the Anaconda distribution of python by default.

### Installation

* Place the named_pipes_api folder in extensions, as with normal mods.
* Place winpipe64.dll in ui\core\lualibs.
* Place the X4_Python_Pipe_Server (exe or py) anywhere convenient.
  - Run this pipe server alongside X4.

### Components

* MD Pipe API

  This api is found in Named_Pipes.xml, and allows MD code to read or write pipes.

* MD Server API

  This api is found in Pipe_Server_Host, and allows MD code to register a python module with the host server.
  The host (if running) will dynamically import the custom module.
  Such modules may be distributed with extensions.

* Lua Pipe API

  The lower level support for X4 to use named pipes is located in Named_Pipes.lua.
  Basic pipe usage can ignore this level in favor of the MD api.
  Advanced usage may want to use this api directly.

* Winpipe dll API

  The pipes themselves are accessed through a dll which wraps key Windows functions.
  This dll is limited to only what is needed: opening a pipe client, reading/writing/closing it, and error checking.
  If desired, the dll may be compiled freshly from source on github.