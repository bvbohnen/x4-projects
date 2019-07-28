'''
Test which will capture select keyboard key presses, and will
signal them to x4 accordingly, to be bound x4-side to MD cues.

Pending development.
'''

from ..Classes import Pipe

def main():
    '''
    Entry function for this server.
    '''
    # Set up the pipe and connect to x4.
    pipe = Pipe('x4_keys')

    # TODO: pick keys to capture, how to send to x4 (keynames? actions?),
    # how to buffer, how to avoid stale items in buffer (eg. buffer
    # isn't serviced when game is paused, so don't overflow and maybe
    # try to prune old presses), etc.

    return