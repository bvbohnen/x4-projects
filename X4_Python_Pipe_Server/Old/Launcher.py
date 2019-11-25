'''
Support for launching X4 from python.
Not heavily used in current tests.
This was mostly a testbed for trying to connect to stdio pipes, and is
pending some cleanup.
'''

import sys
import subprocess
from pathlib import Path
import time

def Launch_Game():
    '''
    Launch X4 and return a subprocess.Popen object.
    '''
    
    # Note: direct exe call gets intercepted by Steam and the process
    #  dies right away (within 50ms) before steam relaunches.
    # https://stackoverflow.com/questions/50848226/running-stardew-valley-from-python-on-windows
    # Possible workaround:
    #exe_path = Path('C:\Steam\steamapps\common\X4 Foundations\X4.exe')
    #exe_path = Path(r'C:\Steam\Steam.exe')
    # This is the launcher used by generated actions.
    #exe_path = 'steam://rungameid/392160'

    # List of command line args to include.
    # TODO: think of how to pass to steam quietly.
    # Keep these around for now, in case a no-steam exe shows up.
    args = [
        # General intro skip.
        '-skipintro',
        # Capture generic debug to a log file.
        '-logfile debuglog.txt',
        # Enable special script based logging.
        '-scriptlogfiles',
        ]

    start_time = time.time()
    print('Starting subprocess...')

    # Create the prompt as a subprocess.
    process = subprocess.Popen(
        # Send the exe path, followed by arguments, as a list.
        #[str(exe_path), *args],
        # Skip args for now; assume they are set in steam (and it complains
        # anyway if extra args given).
        'start steam://run/392160',
        # Use single-line buffering.
        bufsize = 1, #Used for sync message solution.
        # Make subprocess open 'pipe' objects to cmd's stdin and stdout, which
        #  are used later with .communicate.
        stdin = subprocess.PIPE,
        # stdout = subprocess.PIPE, # Temp disable
        # stderr = subprocess.STDOUT, # Temp disable
        stdout = None,        
        stderr = None,
        # Make sure the returned data has newlines recognized in it.
        universal_newlines = True,
        # Maybe open in a shell, to avoid dumping everything to the python
        #  console window.
        # TODO: check if this helps.
        shell = True
        )

    return process


def Runtime_IO_Handler(process):
    '''
    The primary function for interfacing with the game IO at runtime.
    TODO: split this off as an separate thread, so it can handle any game
    responses while other compute occurs.
    For now, this test version will be the only thing running.
    '''

    # Test: time how long before the process gets killed by steam.
    start_time = time.time()

    # Check if there is a return code, indicated the process finished.
    # This is None if the process is running.
    while process.poll() == None:
        # Wait a moment.
        time.sleep(0.01)

    print('Process returned after {} seconds with code {}'.format(
        time.time() - start_time,
        process.poll()
    ))
    
    # Capture any generic problems with try/except.
    try:        
        # Quick input test: just send one item for the lua to try to capture.
        process.stdin.write('hello\n')
    
        if 0:
            # Read the output messages.
            # Iterating on stdout will return one line per iteration,
            #  waiting until a line is ready, stopping when the process ends.
            for line in process.stdout:

                # TODO: handlers for any special messages, to be distinguished
                #  from normal game stdout (if any) in some way.

                # Reprint the line to the python output.
                # Squash newline for nicer printing.
                if line.endswith('\n'):
                    line = line[0:-1]
                Print(line)

    except Exception as this_exception:
        # Stop the process if anything went wrong.
        process.kill()
        # Reraise the exception to catch at the console or in VS.
        raise this_exception

    return



if __name__ == '__main__':
    process = Launch_Game()
    #-Removed; the stdio tests never worked out.
    #Runtime_IO_Handler(process)
