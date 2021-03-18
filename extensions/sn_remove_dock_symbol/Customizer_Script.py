
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
    path_to_x4_folder   = r'D:\Games\Steam\SteamApps\common\X4 Foundations',
    # Generate the extension here.
    path_to_output_folder = this_dir.parent,
    extension_name = this_dir.name,
    developer = True,
    )


# Create a custom transform.
# (Could also skip the transform packing if not wanting error detection.)
@Transform_Wrapper()
def Remove_Dock_Symbol():
    '''
    Removes the red dock symbol from small docks.
    '''

    '''
    These are present in the dockingbay_arg_s_01* files.
    These connect to the material:
    <material id="1" ref="p1effects.p1_holograph_dockingbay_noentry"/>
    This happens twice, once in a part named "fx_NE_base" (remove part),
    and once as a part named "fx_NE_dots" (can remove this whole connection,
    since it is a child of fx_NE_base).

    Can either delete the connection (was done originally), or modify
    the material. Go with the latter, as a better catch-all and safe
    against game version changes.

    See remove_dirty_glass for comments on this, but in short, test
    changes with game restarts, and swap bitmaps to be transparent.

    Test result:
    - Only the dots were removed; the solid part of the symbol remains.

    '''
    if 0:
        # Material edits. Failed to fully remove the symbol.
        material_file = Load_File('libraries/material_library.xml')
        xml_root = material_file.Get_Root()
    
        for mat_name in [
            'p1_holograph_dockingbay_noentry',
            ]:
            mat_node = xml_root.xpath(".//material[@name='{}']".format(mat_name))
            assert len(mat_node) == 1
            mat_node = mat_node[0]

            # Change all bitmaps to use assets\textures\fx\transparent_diff
            for bitmap in mat_node.xpath("./properties/property[@type='BitMap']"):
                bitmap.set('value', r'assets\textures\fx\transparent_diff')

        material_file.Update_Root(xml_root)

    if 1:
        # Direct connection edits.
        dock_files = Load_Files('*dockingbay_arg_*.xml')

        for game_file in dock_files:
            xml_root = game_file.Get_Root()

            # Remove fx_NE_base part.
            results = xml_root.xpath(".//parts/part[@name='fx_NE_base']")
            if not results:
                continue
            for part in results:
                # Remove it from its parent.
                part.getparent().remove(part)


            # Remove fx_NE_dots parent connection.
            results = xml_root.xpath(".//connection[parts/part/@name='fx_NE_dots']")
            for conn in results:
                # Remove it from its parent.
                conn.getparent().remove(conn)

            # Commit changes right away; don't bother delaying for errors.
            game_file.Update_Root(xml_root)
            # Encourage a better xpath match rule.
            game_file.Add_Forced_Xpath_Attributes("name,parts/part/@name='fx_NE_dots'")

    return


# Run the transform.
Remove_Dock_Symbol()
Write_To_Extension(skip_content = True)
