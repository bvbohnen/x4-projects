
Change Log

* 0.1
  - Initial release.
  - Used the lua winapi module, compiled against x4 lua, to access windows
    named pipes.
  - Functional versions of lua and md apis in place, with light test code.
* 0.2
  - Rewrote winapi into winpipe, using only open_pipe and related file
    read/write/close functions.  Reduces dll size and improves security.
  - Switched client pipes into messaging mode, and verified pipelined reads
    are received correctly.
* 0.3
  - Refined behavior of api on connection errors and game reloads.
  - Rewrote lua api to support non-blocking access, with support for
    queueing multiple requests.  Winpipe updated accordingly.
  - Rewrote md api, compressing code, removing unused stubs.
  - Timeouts are a work in progress, and are disabled by default.
* 0.4
  - Timeouts working, plus some general debug and refinement.
* 0.5
  - Added workaround for lua garbage collection not closing pipe files.
  - General debug.
* 0.6
  - Slight debug to prevent excess garbage collection on pipes.
  - Reorganization of python test server setup, for scalability to
    running user provided subservers, and to support auto-restart
    when x4 reloads.
* 0.8
  - Added Pipe_Server_Lib.
  - Overhauled python server to work with the above.
* 0.9
  - Added the Server_Reader library function which handles connecting
    to and continually reading a pipe, and updated Pipe_Server_Lib.
* 0.9.1
  - Minor tweaks.
* 0.10
  - Added status report menu using simple menu api.
* 0.11
  - Switch to the Time API setting time between reconnect pings while the game is paused.
* 0.12
  - Exposed lua api to other lua modules.
* 0.12.1
  - More graceful shutdown if a pipe server is already running.
