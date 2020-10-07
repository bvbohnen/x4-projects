
Win_Pipe_API
------------

Lua plugin which offers support for windows named pipe clients.

This dll project is originally adapted from winapi for lua, and heavily
modified to cut out unused parts (nearly all) of that api.

Notes on compilation:
* This should always be compiled in 64-bit release mode.
* Various compilation/linking options are done in the VS project properties.
* The output file is named winpipe.dll and placed at the default VS
  output folder.


Dependencies:
1) Lua 5.1 headers.
   https://www.lua.org/source/5.1/
   They will be placed in: Win_Pipe_API/lua

2) Lua 5.1 lib file, matching the X4 shipped dll.
   This will be placed in Win_Pipe_API/lua/lua51_64.lib.

   For safety, this may be generated from the dll shipped with X4:
   - Grab the lua51_64.dll from the x4 folder
   - Using VS2017, open the developer command prompt in x64 mode.
     On Win7 this required adding a command line parameter:
     %comspec% /k "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64
   - Convert this dll into a lib file using bat file from:
     https://stackoverflow.com/questions/9946322/how-to-generate-an-import-library-lib-file-from-a-dll
   
   Note: X4 patch 3.3 hf1 beta modified the lua dll. Supporting both pre-patch and post-patch dlls is done manually, with the current setup using the latest dll->lib, but the older one is available under an alternate name (needs manual lib rename to compile it).

     

History of moving from winapi batch file to VS IDE compilation:

  The original source used a bat file build script to compile and link,
  using largely default flags. Below is the key piece of code (minus some paths):

    set CFLAGS= /O1 /DPSAPI_VERSION=1  /I"%LUA_DIR%\include"
    cl /nologo -c %CFLAGS% winapi.c
    cl /nologo -c %CFLAGS% wutils.c
    link /nologo winapi.obj wutils.obj /EXPORT:luaopen_winapi  /LIBPATH:"%LUA_DIR%" msvcrt.lib kernel32.lib user32.lib psapi.lib advapi32.lib shell32.lib  Mpr.lib lua51_64.lib  /DLL /OUT:winapi.dll

  The above is run in the 64-bit version of the developer command prompt.

  When compiling in VS IDE, by default many more flags are added.
  Here are some notes on changes made from the default VS project while
  trying to get the dll to compile correctly (eg. load into x4 and have
  its functions work, which takes more than just getting a dll):

  * Project set for Release/x64.
  * Disabled precompiled headers.
  * Added the lua headers on additional include paths.
  * Added extra libs to the linker references.
  * Turned off SDL checks (complaints about depricated functions).
  * At this point the dll compiles, but when loaded into the game its
    open_pipe function returns nil.
  * Added /DPSAPI_VERSION=1 to cl command line options.
    There was no obvious way to do this from the ui list of defines.
  * Added /EXPORT:luaopen_winapi to the linker command line options.
  * Adjusted warnings from W3 down to W1, the cl default.
    Aim is to get a closer match to the warnings from the bat file.
  * Changed character set from unicode to undefined.
  * At this point, there is a close match in the compile output log between
    the vs ide and the dev command prompt batch file.
  * The resulting dll loads into x4 correctly and passes initial tests.
