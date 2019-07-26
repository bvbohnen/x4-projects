'''
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
  - Added Make_Release for zip file generation with the X4 files.
* 0.3
  - Refined behavior of api on connection errors and game reloads.
  - Rewrote lua api to support non-blocking access, with support for
    queueing multiple requests.  Winpipe updated accordingly.
  - Rewrote md api, compressing code, removing unused stubs.
  - Timeouts are a work in progress, and are disabled by default.
'''

def Get_Version():
    '''
    Returns the highest version number in the change log,
    as a string, eg. '3.4.1'.
    '''
    # Traverse the docstring, looking for ' *' lines, and keep recording
    #  strings as they are seen.
    version = ''
    for line in __doc__.splitlines():
        if not line.startswith('*'):
            continue
        version = line.split('*')[1].strip()
    return version
