
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


@Transform_Wrapper()
def Decrease_Fog(empty_diffs = 0):
    '''
    Reduce fog density to increase fps.
    '''
    '''
    Test in heart of acrymony fog cloud, cockpit hidden, which has
    baseline density of 1.0 using p1fogs.fog_04_alpha_dim material.

    1.0: 8.5 fps
    0.5: 15
    0.3: 25
    0.2: 51
    0.1: 72
    0.0: 95

    Since 51 fps is decently playable, aim for an 80% reduction at 1.0 fog.
    To keep relative fog amounts sorted, all fogs will be scaled, but by
    a reduced % at lower base densities.

    Note: high yield ore/silicon region has 2.0 density.

    Idea 1:
        new_density = density * (1 - 0.8 * density)
        1.0 -> 0.2
        0.5 -> 0.3
        Reject, doesn't maintain ordering.

    Idea 2:
        new_density = density * (1 - 0.8 * (density^0.25))
        1.0 -> 0.2
        0.5 -> 0.16
        0.2 -> 0.09
        Stringer reduction below 0.1 than wanted.

    Idea 3:
        if density < 0.1: new_density = density
        else = (d-0.1) * (1 - 0.9 * ((d-0.1)^0.10)) + 0.1
        Linear below 0.1
        Pretty smooth 0.1 to 1.0 (goes up to ~0.2).

    Update: X4 4.0 changes to volumetric fog. While defined similarly,
    densityfactors are a bit odd, sometimes being the same as the old
    commented out fog entries, other times being 1/10th. Also, these
    new entries add a "multiplier" term of unclear intent.
    Highest observed vf densities are:
        1x 1.0 (heart of acrimony), mult 0.05
        1x 0.7, mult 1.0
        1x 0.6, undef
        2x 0.5, mult 0.15, undef
        6x 0.3, mult 1.0, undef
    Note: xsd indicates undefined mult is 0, though could be wrong as it
    is unfinished for vf.

    TODO: revisit; fog perf in 4.0 is much improved, but maybe need to test
    with AA turned on.

    Note: discontinuing this mod for now.
    '''
    game_file = Load_File('libraries/region_definitions.xml')
    xml_root = game_file.Get_Root()

    # Different scalings are possible.
    # This will try to somewhat preserve relative fog amounts.

    # Note: in X4 3.3, fog was part of a "positional" node with an
    # attribute "ref='fog_outside_...' term. In X4 4.0 this has changed
    # to be "volumetricfog" nodes.
    #for positional in xml_root.xpath('.//positional'):
    #    # Skip non-fog
    #    if not positional.get('ref').startswith('fog_outside_'):
    #        continue
    for positional in xml_root.xpath('.//volumetricfog'):

        # Density is between 0 and 1.
        density = float(positional.get('densityfactor'))

        if density < 0.1:
            continue

        # Preserve the lower 0.1.
        d = density - 0.1
        # Get the reduction factor; limit to 0.9.
        reduction = min(0.9, 0.9 * (d ** 0.10))
        # Scale it.
        d = d * (1 - reduction)
        # Add 0.1 back in.
        new_density = d + 0.1

        #print(f'{density:0.2f} -> {new_density:0.2f}')

        positional.set('densityfactor', f'{new_density:.4f}')

    # Testing a fix for second contact 2 fog cutting out.
    # Note: tests failed to help. TODO: move this off to a testing mod.
    if 0:
        # Try removing the minnoise from the region.
        second_contact_region =  xml_root.find('./region[@name="region_cluster_13_sector_001"]')
        second_contact_region.set('minnoisevalue', '0')
        # The above doesnt prevent cutout. Try the falloff values.
        for step in second_contact_region.xpath('./falloff/lateral/step'):
            if step.get('value') == '0.0':
                step.set('value', '0.1')
        for step in second_contact_region.xpath('./falloff/radial/step'):
            if step.get('value') == '0.0':
                step.set('value', '0.1')

    game_file.Update_Root(xml_root)

    return


# Run the transform.
Decrease_Fog()
Write_To_Extension(skip_content = True)
