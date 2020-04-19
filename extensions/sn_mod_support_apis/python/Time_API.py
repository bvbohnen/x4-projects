'''
Python side of the time api.
This provides actual realtime timer support, which will work within
a single frame (which is otherwise not possible with X4's internal
timer).
'''
from X4_Python_Pipe_Server import Pipe_Server, Pipe_Client
import time
import threading

# Name of the pipe to use.
pipe_name = 'x4_time'

# Flag to do a test run with the pipe client handled in python instead
# of x4.
test_python_client = 0


def main(args):
    '''
    Entry function for this server.
    Protocol: x4 sends some request, pipe server responds (or not) based
    on command.  The pipe server will never send messages on its own.
    '''
    # Enable test mode if requested.
    if args['test']:
        global test_python_client
        test_python_client = True

    # Set up the pipe and connect to x4.
    pipe = Pipe_Server(pipe_name)
        
    # For python testing, kick off a client thread.
    if test_python_client:
        # Set up the reader in another thread.
        reader_thread = threading.Thread(target = Pipe_Client_Test)
        reader_thread.start()

    # Wait for client.
    pipe.Connect()

    # Var to hold the last tic time.
    last_tic = 0
           

    while 1:        
        # Blocking wait for a message from x4.
        message = pipe.Read()

        if test_python_client:
            print(pipe_name + ' server got: ' + message)

        # React based on command.
        if message == 'ping':
            # Ignore any setup pings.
            pass

        elif message == 'get':
            # Return current time.
            pipe.Write(time.perf_counter())

        elif message == 'tic':
            # Record current time in prep for toc.
            last_tic = time.perf_counter()

        elif message == 'toc':
            # Return time since the tic.
            pipe.Write(time.perf_counter() - last_tic)

        else:
            print('Error:' + pipe_name + ' unrecognized command: ' + message)
                        
        # TODO: maybe use time.sleep(?) for a bit if ever switching to
        # non-blocking reads.
    return


def Pipe_Client_Test():
    '''
    Function to mimic the x4 client.
    '''
    pipe = Pipe_Client(pipe_name)

    # Run a number of tests, to see how time values progress.
    for _ in range(5):

        # Send commands.
        for command in ['ping', 'get', 'tic', 'toc']:
            pipe.Write(command)

        # Capture and print responses.
        for _ in range(2):
            response = pipe.Read()
            print(pipe_name + ' client got: ' + response)

    return