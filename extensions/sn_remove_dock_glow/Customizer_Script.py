
import sys
from pathlib import Path
this_dir = Path(__file__).resolve().parent

# Set up the customizer import.
project_dir = this_dir.parents[1]
x4_customizer_dir = str(project_dir.parent / 'X4_Customizer')
if x4_customizer_dir not in sys.path:
    sys.path.append(x4_customizer_dir)
        
# Import all transform functions.
from Plugins import *
from Framework import Transform_Wrapper, Load_File, Load_Files

Settings(
    # Set the path to the X4 installation folder.
    path_to_x4_folder   = r'C:\Steam\SteamApps\common\X4 Foundations',
    # Generate the extension here.
    path_to_output_folder = this_dir.parent,
    extension_name = this_dir.name,
    developer = True,
    )


# Create a custom transform.
# (Could also skip the transform packing if not wanting error detection.)
@Transform_Wrapper()
def Remove_Dock_Glow():
    '''
    Removes the glow effect from station docks.
    '''

    '''
    Of interest are the connections that define the parts for the fx glow/haze.
    Examples:
        ' <connection name="Connection04" tags="part detail_xl nocollision fx  ">
        '   ...
        '   <parts>
        '     <part name="fx_haze">
        '   ...
    and
        ' <connection name="Connection02" tags="part detail_l nocollision fx  ">
        '   ...
        '   <parts>
        '     <part name="fx_glow">

    In testing:
        Glow is the giant blue ball effect.
        Haze is a greyish fog close to the platform.
    Remove just glow.

    '''
    # Find every "dockarea" file.
    dock_files = Load_Files('*dockarea_arg_m_station*.xml')

    for game_file in dock_files:
        xml_root = game_file.Get_Root()

        results = xml_root.xpath(".//connection[parts/part/@name='fx_glow']")
        if not results:
            continue

        for conn in results:
            # Remove it from its parent.
            conn.getparent().remove(conn)        

        # Commit changes right away; don't bother delaying for errors.
        game_file.Update_Root(xml_root)
        # Encourage a better xpath match rule.
        game_file.Add_Forced_Xpath_Attributes("parts/part/@name='fx_glow'")
    return


# Run the transform.
Remove_Dock_Glow()
Write_To_Extension(skip_content = True)
