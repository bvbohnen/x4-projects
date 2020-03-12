'''
X4 runtime pipe server.
This will aim to handle communication with the game: sending commands and
reading back responses.

Initial version is mostly for testing stuff.
'''

#-Removed linkup to the x4 customizer for git release.
'''
# Set up the path to the customizer framework.
def _Init():
    import sys
    from pathlib import Path
    parent_dir = Path('.').resolve().parents[1]
    if str(parent_dir) not in sys.path:
        sys.path.append(str(parent_dir))
_Init()
'''

# Make available the pipes for easy import into dynamically loaded modules.
from .Classes import Pipe_Server, Pipe_Client
