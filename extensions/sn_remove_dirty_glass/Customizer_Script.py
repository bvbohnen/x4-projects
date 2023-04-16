
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
    path_to_x4_folder   = r'D:\Games\Steam\SteamApps\common\X4 Foundations',
    # Generate the extension here.
    path_to_output_folder = this_dir.parent,
    extension_name = this_dir.name,
    # Note: with the way x4 loads extensions, the material library
    # p1_effects collection can occur multiple times (base, split dlc,
    # maybe other dlc), and the extensions will end up with their nodes
    # ordered first, such that an attempt to modify the base p1_effects
    # will use an xpath index that depends on extensions loaded.
    # This can break for users without the same dlcs as when the xpath was
    # constructed.
    # For better compatability, guide the xpath generator to include a
    # child node check for picking with p1_effects node to include, so
    # it doesn't use an index.
    #forced_xpath_attributes = "material/@name='p1_window_trim_01'",
    # Alternativly, use // syntax to shorten xpaths.
    shorten_xpaths = True,
    )


# Create a custom transform.
# (Could also skip the transform packing if not wanting error detection.)
@Transform_Wrapper()
def Clean_Dirty_Glass():
    '''
    Cleans the dirty glass on ship windows.
    '''
    '''
    It looks like the common element in window dirt is the material, eg.:
    '<connection name="Connection21" tags="part nocollision iklink detail_s " parent="anim_cockpit_frame">
    '  ...
    '  <parts>
    '    <part name="detail_xl_glass_inside_dirt">
    '      <lods>
    '        <lod index="0">
    '          <materials>
    '            <material id="1" ref="p1effects.p1_window_trim_01"/>

    ' <connection name="Connection62" tags="part detail_s forceoutline noshadowcaster platformcollision ">
    '   ...
    '   <parts>
    '     <part name="fx_glass_inside">
    '       <lods>
    '         <lod index="0">
    '           <materials>
    '             <material id="1" ref="p1.cockpit_glass_inside_01"/>
    

    The "dirt" in the name is not consistent.
    "p1effects.p1_window_trim_01" may be consistent; it is common in the
    ships sampled.
    Or is the trim just the outside of the window?  Unclear.


    Testing:
        p1effects.p1_window_trim_01
            Haze removed from the edges of the window, around the model
            cockpit frame.
        p1.cockpit_glass_inside_01
            Haze removed from most of the window.
            There is an awkward cuttoff high on the screen where haze reappears.
            May remove some collision? Can seem to walk into the window a bit.
        p1.cockpit_glass_outside_02
            Haze removed from high part of the window, not main part.
        arcp1.cp1_modes
            No change noticed.

    If all haze removed, there is no collision for the window, and the player
    can fall out of the ship.


    Note: removing just the material node from the connection didn't
    have any effect; needed to remove the whole connection.
    
    Suggested to try replacing material with p1effects.p1_chair_ui.
    Maybe try dummy.transparent instead.
    Results: neither had any effect (even with a restart).
    In discussion with others, the material itself may be defined as part
    of the model, and only relies on the connection being present.

    Ultimately, solved below with edit to materials library instead.
    '''
    #ship_macro_files = File_System.Get_All_Indexed_Files('macros','ship_*')
    #ship_files  = File_System.Get_All_Indexed_Files('components','ship_*')

    # Test with the gorgon.
    #ship_files = [Load_File('assets/units/size_m/ship_par_m_frigate_01.xml')]
    #ship_files = []

    #for game_file in ship_files:
    #    xml_root = game_file.Get_Root()
    #    
    #    for mat_name in [
    #        #'p1effects.p1_window_trim_01',
    #        #'p1.cockpit_glass_inside_01',
    #        #'p1.cockpit_glass_outside_02',
    #        #'arcp1.cp1_modes',
    #    ]:
    #    
    #        results = xml_root.xpath(
    #            ".//connection[parts/part/lods/lod/materials/material/@ref='{}']".format(mat_name))
    #        if not results:
    #            continue
    #
    #        for conn in results:
    #
    #            mat = conn.find('./parts/part/lods/lod/materials/material')
    #            # Try removing the mat link.
    #            #mat.getparent().remove(mat)
    #            # Try editing the mat link.
    #            mat.set('ref', 'dummy.transparent')
    #
    #            # Remove it from its parent.
    #            #conn.getparent().remove(conn)
    #
    #    # Commit changes right away; don't bother delaying for errors.
    #    game_file.Update_Root(xml_root)

    '''
    With advice from others looking at the model, there is a reference
    to the cockpit_glass_inside_02 material. Perhaps this can be
    handled by editing the materials.xml to play with that.

    ' <material name="cockpit_glass_inside_02" shader="p1_glass.fx" blendmode="ALPHA8_SINGLE" preview="none" priority="-1">
    '   <properties>
    '     <!--property type="Color" name="diffuse_color" r="200" g="200" b="200" a="100" value="(color 1 1 2)" /-->
    '     <property type="BitMap" name="diffuse_map" value="assets\textures\fx\ships_cockpit_glass_inside_02_diff" />
    '     <property type="BitMap" name="smooth_map" value="assets\textures\fx\ships_cockpit_glass_inside_02_spec" />
    '     <property type="BitMap" name="specular_map" value="assets\textures\fx\ships_cockpit_glass_inside_02_spec" />
    '     <property type="BitMap" name="normal_map" value="assets\textures\fx\ships_cockpit_glass_inside_02_normal" />
    '     <property type="Float" name="normalStr" value="1.0" />
    '     <property type="Float" name="environmentStr" value="0.1" />
    '     <property type="Float" name="envi_lightStr" value="0.40" />
    '     <property type="Float" name="smoothness" value="0.2" />
    '     <property type="Float" name="metalness" value="0.0" />
    '     <property type="Float" name="specularStr" value="0.1" />
    '   </properties>
    ' </material>
    
    Note: in testing, mat lib diff patches only evaluate at game start,
    so need to restart between changes.
    (Test was to delete the p1 collection, turning the game purple; game
    stayed purple after undoing the diff patch deletion and reloading
    the save.)

    Tests:
        Removing material nodes
            Purple textures.
        Removing the bitmaps
            Generic white or grey coloring.
        Maybe try replacing it with the data from dummy.transparent?
            Textures replaced with the custom nuke icon spammed out
            around the trim, and central window is a stretched out
            and red-shifted copy.
            Why??
        Try replacing with p1effects.p1_chair_ui.
            Get a random texture tiled out again, some purplish paranid
            looking keyboard like thing?
        Try adding/changing attributes to look for some way to add transparency.
            No noticed effects for properties tried.
        Remove just the normal bitmap.
            No noticed effect.
        Change all bitmaps to use assets\textures\fx\transparent_diff
            Success!

    Note: removing the outside glass texture means there is no
    apparent cockpit glass when viewed from outside. So try to leave
    the outside glass intact.

    Update: 5.0 beta changed cockpit_glass_inside_01, notably adding
    diffuse_detail and normal_detail to the diffuse/normal/smooth maps.
    - Setting these all as transparent_diff now has the effect of making
    the whole cockpit a hazy white.
    - Setting just diffuse/normal/smooth transparent, and not details,
    has the effect of the entire cockpit having the dirty effect
    (as opposed to it being based on light sources and view angle).
    - Setting the "...Str" values to 0 appears to work (these are new
    in 5.0).
    '''
    
    if 1:
        material_file = Load_File('libraries/material_library.xml')
        xml_root = material_file.Get_Root()

        #dummy_node = xml_root.find(".//material[@name='transparent']")
        #dummy_node = xml_root.find(".//material[@name='p1_chair_ui']")

        ## New properties to add.
        #propeties = [
        #    etree.fromstring('<property type="Float" name="diffuseStr" value="1.0" />'),
        #    etree.fromstring('<property type="Float" name="color_dirtStr" value="0.0" />'),
        #    etree.fromstring('<property type="Float" name="translucency"  value="0.0" />'),
        #    etree.fromstring('<property type="Float" name="trans_scale"   value="0.0" />'),
        #    etree.fromstring('<property type="Color" name="diffuse_color" r="200" g="200" b="200" a="0" value="(color 1 1 2)" />'),
        #    ]

        for mat_name in [
            'cockpit_glass_inside_01',

            # 02 version only used on an argon bridge, and seems less
            # developed.
            'cockpit_glass_inside_02',

            #'cockpit_glass_outside_01',
            #'cockpit_glass_outside_02',
            'p1_window_trim_01',
            'p1_window_trim_02', # Only used in a couple l/xl bridges.
            # p1_window_trim_03  - diffuse map added in 3.10hf1b1, no mat entry yet.
            ]:
            mat_node = xml_root.xpath(".//material[@name='{}']".format(mat_name))
            assert len(mat_node) == 1
            mat_node = mat_node[0]

            # Removing bitmaps - failure, saturated colors
            #for bitmap in mat_node.xpath("./properties/property[@type='BitMap']"):
            #    bitmap.getparent().remove(bitmap)
                
            # Removing mat node - failure, purple error
            #mat_node.getparent().remove(mat_node)

            # Replacing with transparent node copy.
            # Note: deepcopy here doesn't traverse up to the parent.
            # - failure, grabs random textures to fill in.
            #new_node = deepcopy(dummy_node)
            #new_node.set('name', mat_node.get('name'))
            #mat_node.addnext(new_node)
            #mat_node.getparent().remove(mat_node)

            ## Try adding extra properties as children.
            #for property in propeties:
            #    new_prop = deepcopy(property)
            #    # If one already exists, delete the old one.
            #    old_props = mat_node.xpath("./properties/property[@name='{}']".format(new_prop.get('name')))
            #    for old_prop in old_props:
            #        old_prop.getparent().remove(old_prop)
            #    # Append the new one.
            #    mat_node.append(new_prop)

            # Remove the normal bitmap only. - no effect
            #for bitmap in mat_node.xpath("./properties/property[@name='normal_map']"):
            #    bitmap.getparent().remove(bitmap)

            # Change all bitmaps to use assets\textures\fx\transparent_diff
            # As of 5.0 beta, this no longer works; makes the entire mat
            # hazy white. (This remains true if the below color alpha
            # change is also applied.)
            # This is still needed to support pre-5.0 versions.
            # -Removed
            #for bitmap in mat_node.xpath("./properties/property[@type='BitMap']"):
            #    bitmap.set('value', r'assets\textures\fx\transparent_diff')

            # Try changing the Color alpha to clear instead of 255.
            # -no effect
            #for color in mat_node.xpath("./properties/property[@type='Color']"):
            #    color.set('a', '0')

            # Try changing the "...Str" values (strength?) to 0.
            # Note: non-0 Str values are new in 5.0.
            for color in mat_node.xpath("./properties/property[@type='Float']"):
                if color.get('name').endswith('Str'):
                    color.set('value', '0')

        material_file.Update_Root(xml_root)

    return


# Run the transform.
Clean_Dirty_Glass()
Write_To_Extension(skip_content = True)
