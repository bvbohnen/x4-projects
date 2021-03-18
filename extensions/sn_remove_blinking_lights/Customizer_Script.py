
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
from Framework import Transform_Wrapper, Load_File, File_System

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
def Remove_Blinking_Ship_Lights():
    '''
    Removes the blinking lights from ships.
    '''

    '''
    Of interest are the omni nodes that contain animations for blinking.

    Example:    
    ' <omni name="XU Omni091" shadow="0" r="255" g="0" b="0" range="2" shadowrange="2" lighteffect="1" trigger="1" intensity="1" specularintensity="1">
    '   <lightanimations>
    '     <lightanimation name="intensity" controller="linear_float">
    '       <key frame="0" value="1"/>
    '       <key frame="4" value="1"/>
    '       <key frame="5" value="0"/>
    '       <key frame="9" value="0"/>
    '       <key frame="10" value="1"/>
    '       <key frame="14" value="1"/>
    '       <key frame="15" value="0"/>
    '       <key frame="64" value="0"/>
    '       <key frame="65" value="1"/>
    '       <key frame="69" value="1"/>
    '       <key frame="70" value="0"/>
    '       <key frame="100" value="0"/>
    '     </lightanimation>
    '   </lightanimations>
    '   <offset>
    '     <position x="-7.476295" y="-0.733321" z="-5.032233"/>
    '   </offset>
    ' </omni>

    Can do a general search for such nodes.
    Note: the blinking rate seems to be similar but not quite the same
    between ships, at least the animation key count can differ (12, 13, etc.).

    Check for "anim_poslights" in the parent part name, though
    this is not consistent across ships (eg. "anim_poslights_left"), but
    adds some safety against accidental removal of other components.

    Note: just removing the omni nodes has no effect, for whatever reason,
    but removing the entire connection node housing them is effective.
    (Removing the part also didn't work.)

    Update: the split medium miners define the anim_poslights part, but
    without accomponying omni lights, and yet still blink.
    Assuming the lights are defined elsewhere, removing the anim_poslights
    connection should turn off blinking.
    
    TODO: in 3.2 connection names were changed on some ships, which throws
    off diff patches which xpath to the connection node by name. Index would
    also fail in this case. Both are in danger of matching the wrong
    connection, which could cause fundumental problems if stored in a save,
    eg. disconnected components (losing shields/whatever).
    How can the xpath creator be induced to use a child node/attribute
    when removing a parent node?
    (Workaround might be to match tags, though no promises on that being safe.)
    '''
    ship_files  = File_System.Get_All_Indexed_Files('components','ship_*')

    # Test with just a kestrel
    #ship_files = [Load_File('assets/units/size_s/ship_tel_s_scout_01.xml')]

    for game_file in ship_files:
        xml_root = game_file.Get_Root()

        modified = False

        # Find the connection that has a uv_animation.
        for conn in xml_root.xpath(".//connection[parts/part/uv_animations/uv_animation]"):
            
            # Check the part name for anim_poslights (or a variation).
            parts = conn.xpath('./parts/part')
            # Expecting just one part.
            if len(parts) > 1:
                print('Error: multiple parts matched in {}, skipping'.format(game_file.virtual_path))
            part_name = parts[0].get('name')
            if 'anim_poslights' not in part_name:
                continue

            # Remove it from its parent.
            conn.getparent().remove(conn)
            modified = True

        if modified:
            # Commit changes right away; don't bother delaying for errors.
            game_file.Update_Root(xml_root)
            # Encourage a better xpath match rule.
            game_file.Add_Forced_Xpath_Attributes('parts/part/@name')
    return


# Run the transform.
Remove_Blinking_Ship_Lights()
Write_To_Extension(skip_content = True)
