
# TODO: generic import suitable to dynamicly imported modules.
# TODO: x4 model using Pipe_Client (can take/edit from Old/Test.py).
from ..Classes import Pipe_Server, Pipe_Client

def main():
    '''
    Entry function for this server.
    In this test, the server acts as a memory.
    X4 writes using: "write:[key]data"
    X4 reads using : "read:[key]"

    Example:
        "write:[food]bard" stores "bard" at "food"
        "read:[food]"      returns "bard" to x4
    '''
    # Set up the pipe and connect to x4.
    pipe = Pipe_Server('x4_pipe')

    # TODO: set up python reference client model.

    # Wait for client.
    pipe.Connect()
    
    # These will be read/write transactions to a data table, stored here.
    data_store = {}

    # Loop ends on getting a 'close' command.
    close_requested = False
    while not close_requested:
                
        # Get the next control message.
        message = pipe.Read()
        print('Received: ' + message)

        # Testing: delay on processing write.
        # Used originally to let multiple x4 writes queue up, potentially
        # hitting a full buffer.
        if 0:
            print('Pausing for a moment...')
            time.sleep(0.5)

        # Handle based on prefix, write or read.
        if message.startswith('write:'):
            # Expected format is:
            #  write:[key]value
            # (Or possibly a chain of keys? just one for now)
            key, value = message.split(':')[1].split(']')
            # Pull out the starting bracket.
            key = key[1:]
            # Save.
            data_store[key] = value

        elif message.startswith('read:'):
            # Expected format is:
            #  read:[key]
            key = message.split(':')[1]
            key = key[1:-1]

            if key not in data_store:
                response = 'error: {} not found'.format(key)
            else:
                response = data_store[key]

            # Pipe the response back.
            # Note: data is binary in the pipe, but treated as string in lua,
            # plus lua apparently has no integers (just doubles), but does have
            # string pack/unpack functions.
            # Anyway, it is easiest to make strings canonical for this, for now.
            # TODO: consider passing some sort of format specifier so the
            #  data can be recast in the lua.
            # Optionally do a read timeout test, which doesn't return data.
            timeout_test = 0
            if timeout_test:
                print('Suppressing read return; testing timeout.')
            else:
                pipe.Write(response)
                print('Returned: ' + response)

        elif message == 'close':
            # Close the pipe/server when requested.
            close_requested = True

        else:
            print('Unexpected message type')

    return