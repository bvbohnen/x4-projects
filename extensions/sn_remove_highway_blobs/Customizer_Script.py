
import sys
from copy import deepcopy
from lxml import etree
from pathlib import Path
this_dir = Path(__file__).resolve().parent

# Set up the customizer import.
project_dir = this_dir.parents[1]
x4_customizer_dir = str(project_dir.parent / 'X4_Customizer')
if x4_customizer_dir not in sys.path:
    sys.path.append(x4_customizer_dir)
        
# Import all transform functions.
from Plugins import *
from Framework import Transform_Wrapper, Load_File, File_System

Settings(
    # Set the path to the X4 installation folder.
    path_to_x4_folder   = r'C:\Steam\SteamApps\common\X4 Foundations',
    # Generate the extension here.
    path_to_output_folder = this_dir.parent,
    extension_name = this_dir.name,
    )

Transform_Wrapper()
def Remove_Highway_Blobs():
    highway_file = Load_File('libraries/highwayconfigurations.xml')
    xml_root = highway_file.Get_Root()

    '''
    Set the config for superhighways:
      <blockerconfiguration ref="super_hw_blocker_config" />
    to
      <blockerconfiguration ref="empty_blocker_config" />

    TODO: maybe play around with other highway properties, eg. the
    blur effect, any ad signs (are they here?), mass traffic.
    '''
    superhighway_node = xml_root.find('./configurations/configuration[@id="defaultsuperhighwayconfiguration"]')
    blocker_node = superhighway_node.find('./blockerconfiguration')
    blocker_node.set('ref', 'empty_blocker_config')
    highway_file.Update_Root(xml_root)

# Run the transform.
Remove_Highway_Blobs()
Write_To_Extension(skip_content = True)
