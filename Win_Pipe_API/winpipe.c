/*
Lua wrapping for select win32 api functions:
    open_pipe
    file.write
    file.read
    file.close
    GetLastError

This is based on the lua winapi module from:
https://github.com/stevedonovan/winapi
Original mit license is located at the bottom of this file.

Changes mostly consist of removal of nearly all of the api, minus
the necessary pipe related functions, tweaking pipe mode, adding
error code export.
New comments (not part of winapi) start with "//--".
*/

#define WINDOWS_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>
#ifdef __GNUC__
#include <winable.h> /* GNU GCC specific */
#endif

#include <winerror.h>

#define FILE_BUFF_SIZE 2048


#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#ifdef WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT
#endif
#if LUA_VERSION_NUM > 501
#define lua_objlen lua_rawlen
#endif


//-- Most of the winapi wutils header/c file isn't needed.
//-- Just copy over the necessary bits.
//#include "wutils.h"
typedef int Ref;

/// push a error message.
// @param L the state
// @param msg a message string
// @return 2; `nil` and the message on the stack
// @function push_error_msg
int push_error_msg(lua_State *L, const char *msg) {
    lua_pushnil(L);
    lua_pushstring(L, msg);
    return 2;
}

const char *last_error(int err) {
    static char errbuff[256];
    int sz;
    if (err == 0) {
        err = GetLastError();
    }
    sz = FormatMessage(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL, err,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), // Default language
        errbuff, 256, NULL
    );
    errbuff[sz - 2] = '\0'; // strip the \r\n
    return errbuff;
}

/// push the last Windows error.
// @param L the state
// @return 2; 'nil' and the message
// @function push_error
int push_error(lua_State *L) {
    return push_error_msg(L, last_error(0));
}

/// release a reference to a Lua value.
// @param L the state
// @param ref the reference
// @function release_ref
void release_ref(lua_State *L, Ref ref) {
    luaL_unref(L, LUA_REGISTRYINDEX, ref);
}

//--end of wutils sourced code


// These functions are all run in background threads, and a little bit of poor man's
// OOP helps here. This is the base struct for describing threads with callbacks,
// which may have an associated buffer and handle.

#define callback_data_ \
  HANDLE handle; \
  lua_State *L; \
  Ref callback; \
  char *buf; \
  int bufsz;

typedef struct {
    callback_data_
} LuaCallback, *PLuaCallback;

//--Removed; only used in pipe serving.
//LuaCallback *lcb_callback(void *lcb, lua_State *L, int idx) {
//  LuaCallback *data;
//  if (lcb == NULL) {
//    lcb = malloc(sizeof(LuaCallback));
//  }
//  data = (LuaCallback*) lcb;
//  data->L = L;
//  data->callback = make_ref(L,idx);
//  data->buf = NULL;
//  data->handle = NULL;
//  return data;
//}

//BOOL lcb_call(void *data, int idx, Str text, int flags) {
//  LuaCallback *lcb = (LuaCallback*)data;
//  return call_lua(lcb->L,lcb->callback,idx,text,flags);
//}

void lcb_allocate_buffer(void *data, int size) {
    LuaCallback *lcb = (LuaCallback*)data;
    lcb->buf = malloc(size);
    lcb->bufsz = size;
}

void lcb_free(void *data) {
    LuaCallback *lcb = (LuaCallback*)data;
    if (!lcb) return;
    if (lcb->buf) {
        free(lcb->buf);
        lcb->buf = NULL;
    }
    if (lcb->handle) {
        CloseHandle(lcb->handle);
        lcb->handle = NULL;
    }
    release_ref(lcb->L, lcb->callback);
}

#define lcb_buf(data) ((LuaCallback *)data)->buf
#define lcb_bufsz(data) ((LuaCallback *)data)->bufsz
#define lcb_handle(data) ((LuaCallback *)data)->handle

/// this represents a raw Windows file handle.
// The write handle may be distinct from the read handle.
// @type File

typedef struct {
    callback_data_
    HANDLE hWrite;
} File;



#define File_MT "File"

File * File_arg(lua_State *L, int idx) {
    File *this = (File *)luaL_checkudata(L, idx, File_MT);
    luaL_argcheck(L, this != NULL, idx, "File expected");
    return this;
}

static void File_ctor(lua_State *L, File *this, HANDLE hread, HANDLE hwrite);

static int push_new_File(lua_State *L, HANDLE hread, HANDLE hwrite) {
    File *this = (File *)lua_newuserdata(L, sizeof(File));
    luaL_getmetatable(L, File_MT);
    lua_setmetatable(L, -2);
    File_ctor(L, this, hread, hwrite);
    return 1;
}


static void File_ctor(lua_State *L, File *this, HANDLE hread, HANDLE hwrite) {
    lcb_handle(this) = hread;
    this->hWrite = hwrite;
    this->L = L;
    lcb_allocate_buffer(this, FILE_BUFF_SIZE);
}

/// write to a file.
// @param s text
// @return number of bytes written.
// @function write
static int l_File_write(lua_State *L) {
    File *this = File_arg(L, 1);
    const char *s = luaL_checklstring(L, 2, NULL);
    DWORD bytesWrote;
    //--Explicit Dword cast to make warning go away.
    WriteFile(this->hWrite, s, (DWORD)lua_objlen(L, 2), &bytesWrote, NULL);
    lua_pushinteger(L, bytesWrote);
    return 1;
}

static BOOL raw_read(File *this) {
    DWORD bytesRead = 0;
    BOOL res = ReadFile(lcb_handle(this), lcb_buf(this), lcb_bufsz(this), &bytesRead, NULL);
    lcb_buf(this)[bytesRead] = '\0';
    return res && bytesRead;
}

/// read from a file.
// Please note that this is not buffered, and you will have to
// split into lines, etc yourself.
// @return text if successful, nil plus error otherwise.
// @function read
static int l_File_read(lua_State *L) {
    File *this = File_arg(L, 1);
    if (raw_read(this)) {
        lua_pushstring(L, lcb_buf(this));
        return 1;
    }
    else {
        return push_error(L);
    }
}


//--For access to an empty pipe in non-blocking mode, ReadFile will return
//  an error, and GetLastError should be ERROR_IO_PENDING.
//  To support this, expose GetLastError without formatting.
//  Update: microsoft documentation is wrong or incomplete; non-blocking
//  reads actually return ERROR_NO_DATA, not mentioned in docs.
static int l_GetLastError(lua_State *L) {
    // Grab the current error code.
    int err = GetLastError();
    lua_pushinteger(L, err);
    return 1;
}


//--removed; depends on threads, and may not work with pipes, as
//  they are only documented for use with ReadFile.
//static void file_reader (File *this) { // background reader thread
//  int n;
//  do {
//    n = raw_read(this);
//    // empty buffer is passed at end - we can discard the callback then.
//    lcb_call (this,0,lcb_buf(this),n == 0 ? DISCARD : 0);
//  } while (n);
//}
//
///// asynchronous read.
//// @param callback function that will receive each chunk of text
//// as it comes in.
//// @return @{Thread}
//// @function read_async
//static int l_File_read_async(lua_State *L) {
//  File *this = File_arg(L,1);
//  int callback = 2;
//  this->callback = make_ref(L,callback);
//  return lcb_new_thread((TCB)&file_reader,this);
//}

static int l_File_close(lua_State *L) {
    File *this = File_arg(L, 1);
    //-- Adding check for hWrite being not null.
    if (this->hWrite && this->hWrite != lcb_handle(this)){
        CloseHandle(this->hWrite);
        // --Similar to __gc below, for safety make sure the handle is null.
        this->hWrite = NULL;
    }
    lcb_free(this);
    return 0;
}

// -- The autocalled garbage collection will clear the char* memory section
// set up in lcb_allocate_buffer with malloc.
static int l_File___gc(lua_State *L) {
    File *this = File_arg(L, 1);
    //-- Adding check for buf being not null.
    if (this->buf) {
        free(this->buf);
        // -- Shouldn't this set buf to NULL?
        // Adding it in, in an attempt to fix a crash when garbage collecting
        // files and trying to call :close to close their handle.
        // (It didn't help, but leaving in anyway.)
        this->buf = NULL;
    }
    return 0;
}

static const struct luaL_Reg File_methods[] = {
    {"write",l_File_write},
    {"read",l_File_read},
    //{"read_async",l_File_read_async},
    {"close",l_File_close},
    {"__gc",l_File___gc},
    {NULL, NULL}  /* sentinel */
};

static void File_register(lua_State *L) {
    luaL_newmetatable(L, File_MT);
#if LUA_VERSION_NUM > 501
    luaL_setfuncs(L, File_methods, 0);
#else
    luaL_register(L, NULL, File_methods);
#endif
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}


//--Removing the pipe server stuff; only want client.
//#define PSIZE 512
//
//typedef struct {
//  callback_data_
//  const char *pipename;
//} PipeServerParms;
//
//static void pipe_server_thread(PipeServerParms *parms) {
//  while (1) {
//    BOOL connected;
//    HANDLE hPipe = CreateNamedPipe(
//      parms->pipename,             // pipe named
//      PIPE_ACCESS_DUPLEX,       // read/write access
//      PIPE_WAIT,                // blocking mode
//      255,
//      PSIZE,                  // output buffer size
//      PSIZE,                  // input buffer size
//      0,                        // client time-out
//      NULL);                    // default security attribute
//
//    if (hPipe == INVALID_HANDLE_VALUE) {
//      // could not create named pipe - callback is passed nil, err msg.
//      lua_pushnil(parms->L);
//      lcb_call(parms,-1,last_error(0),REF_IDX | DISCARD);
//      return;
//    }
//    // Wait for the client to connect; if it succeeds,
//    // the function returns a nonzero value. If the function
//    // returns zero, GetLastError returns ERROR_PIPE_CONNECTED.
//
//    connected = ConnectNamedPipe(hPipe, NULL) ?
//         TRUE : (GetLastError() == ERROR_PIPE_CONNECTED);
//
//    if (connected) {
//      push_new_File(parms->L,hPipe,hPipe);
//      lcb_call(parms,-1,0,REF_IDX); // pass it a new File reference
//    } else {
//      CloseHandle(hPipe);
//    }
//  }
//}

/// Dealing with named pipes.
// @section Pipes

/// open a pipe for reading and writing.
// @param pipename the pipename (default is "\\\\.\\pipe\\luawinapi")
// @function open_pipe
static int l_open_pipe(lua_State *L) {
    const char *pipename = luaL_optlstring(L, 1, "\\\\.\\pipe\\luawinapi", NULL);
    HANDLE hPipe = CreateFile(
        pipename,
        GENERIC_READ |  // read and write access
        GENERIC_WRITE,
        0,              // no sharing
        NULL,           // default security attributes
        OPEN_EXISTING,  // opens existing pipe
        0,              // default attributes
        NULL);          // no template file
    if (hPipe == INVALID_HANDLE_VALUE) {
        return push_error(L);
    }
    else {
        //--Modify the named pipe to change its access mode for X4.
        //--Since it requires LPDWORD input, a pointer to DWORD, set the
        //  mode first then pass it in.
        DWORD mode = PIPE_READMODE_MESSAGE | PIPE_NOWAIT;
        SetNamedPipeHandleState(
            hPipe,
            //--lpMode
            &mode,
            //--Other args are null for pipe client on same comp as server.
            NULL,
            NULL
        );
        return push_new_File(L, hPipe, hPipe);
    }
}

//--Removing pipe creation
///// create a named pipe server.
//// This goes into a background loop, and accepts client connections.
//// For each new connection, the callback will be called with a File
//// object for reading and writing to the client.
//// @param callback a function that will be passed a File object
//// @param pipename Must be of the form \\.\pipe\name, defaults to
//// \\.\pipe\luawinapi.
//// @return @{Thread}.
//// @function make_pipe_server
//static int l_make_pipe_server(lua_State *L) {
//  int callback = 1;
//  const char *pipename = luaL_optlstring(L,2,"\\\\.\\pipe\\luawinapi",NULL);
//  PipeServerParms *psp = (PipeServerParms*)malloc(sizeof(PipeServerParms));
//  lcb_callback(psp,L,callback);
//  psp->pipename = pipename;
//  return lcb_new_thread((TCB)&pipe_server_thread,psp);
//}



static const luaL_Reg winpipe_funs[] = {
    //--Adding GetLastError function.
    {"GetLastError",l_GetLastError},
    {"open_pipe",l_open_pipe},
    {NULL,NULL}
};

EXPORT int luaopen_winpipe(lua_State *L) {
    #if LUA_VERSION_NUM > 501
        lua_newtable(L);
        luaL_setfuncs(L, winpipe_funs, 0);
        lua_pushvalue(L, -1);
        lua_setglobal(L, "winpipe");
    #else
        luaL_register(L, "winpipe", winpipe_funs);
    #endif

    File_register(L);

    //--Error code constants.
    lua_pushinteger(L, ERROR_IO_PENDING); lua_setfield(L, -2, "ERROR_IO_PENDING");
    lua_pushinteger(L, ERROR_NO_DATA); lua_setfield(L, -2, "ERROR_NO_DATA");
    
    return 1;
}



//-- Original winapi license:
/*****************************************************************************
winapi License
-----------
Copyright (C) 2011 Steve Donovan.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*****************************************************************************/
