'''
Main entry function for the overall python based server.
This will load in individual pipe sub-servers and run their threads.

Initial version just runs a test server.
'''

# Setup include path to this package.
import sys
from pathlib import Path
home_path = Path(__file__).resolve().parents[1]
if str(home_path) not in sys.path:
    sys.path.append(str(home_path))
    
from Python_Server.Servers import Test1
from Python_Server.Servers import Send_Keys
from Python_Server.Classes import Server_Thread


# TODO: any interesting argparsing.
def Main():
    '''
    '''
    # TODO: dynamically load in server modules from extensions.
    # Need to check which extensions are enabled/disabled, and determine
    # what the protocol will be for file naming.

    # Start all server threads.
    # Just a test for now.
    threads = [
        Server_Thread(Test1.main),
        Server_Thread(Send_Keys.main),
    ]
    # Wait for them all to finish.
    for thread in threads:
        thread.Join()
    return

if __name__ == '__main__':
    Main()

