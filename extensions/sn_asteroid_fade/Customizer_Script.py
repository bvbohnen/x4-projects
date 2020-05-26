
import sys
from pathlib import Path
this_dir = Path(__file__).resolve().parent
from collections import defaultdict
from copy import deepcopy
from lxml import etree

# Set up the customizer import.
project_dir = this_dir.parents[1]
x4_customizer_dir = str(project_dir.parent / 'X4_Customizer')
if x4_customizer_dir not in sys.path:
    sys.path.append(x4_customizer_dir)
        
# Import all transform functions.
from Plugins import *
from Framework import Transform_Wrapper, Load_File, Load_Files
from Framework import Get_All_Indexed_Files, Get_Asset_Files_By_Class

# Binary patching support.
from Plugins.Transforms.Support import Binary_Patch
from Plugins.Transforms.Support import String_To_Hex_String
from Plugins.Transforms.Support import Apply_Binary_Patch
from Plugins.Transforms.Support import Apply_Binary_Patch_Group


Settings(
    # Set the path to the X4 installation folder.
    path_to_x4_folder   = r'C:\Steam\SteamApps\common\X4 Foundations',
    # Generate the extension here.
    path_to_output_folder = this_dir.parent,
    extension_name = this_dir.name,
    developer = True,
    )

@Transform_Wrapper()
def Patch_Asteroid_Shader(empty_diffs = 0):
    'Edit asteroid shader to support transparency.'    
    '''
    The asteroid shader, and ogl file linking to v/vh/etc., doesn't normally
    support camera fade. However, fading rules are in the common.v file,
    and fade parameters can be added to the shaer ogl.
    Note: ogl is xml format.
    '''
    # TODO: other shaders?
    # If an xl roid, it also uses P1_complex_surface ?

    shader_ogl_file = Load_File('shadergl/high_spec/p1_asteroid.ogl')
    xml_root = shader_ogl_file.Get_Root()
    properties = xml_root.find('./properties')

    # Add defines for the camera distance and fade.
    # Put these at the top, with other defines (maybe doesn't matter).
    for field in ['ABSOLUTE_CAMERA_FADE_DISTANCE', 'FADING_HARDCODED']:#'FADING_CAMERA_FADE_RANGE']:
        property = etree.Element('define', name = field, value = '/*def*/')
        properties.insert(0, property)
        assert property.tail == None

    # Give dummy default values; hopefully the definition is enough.
    # These can go at the end.
    for field, value in [('camera_fade_range_start', '1000.0'), 
                         ('camera_fade_range_stop' , '270000.0')]:
        property = etree.Element('float', name = field, value = value)
        properties.append(property)
        assert property.tail == None
    shader_ogl_file.Update_Root(xml_root)


    # Need to update the .f file that holds the actual shader logic.
    # (The above just sets up common code to define IO_Fade.)
    shader_f_file = Load_File('shadergl/shaders/p1/high/asteroid.f')
    # Do raw text editing on this.
    text = shader_f_file.Get_Text()
    new_text = text

    # Why are there two OUT_Color settings, second a dummy?
    # The DEFERRED_OUTPUT macro, if used, overwrites OUT_Color.
    # TODO: introducing a syntax error makes asteroids stop drawing with
    # no log error. But other attempts to change results had no effect.
    
    #new_text = new_text.replace(
    #    'OUT_Color = half4(finalColor.rgb, ColorBaseDiffuse.a * F_alphascale);',
    #    'ColorBaseDiffuse.rgb = ColorBaseDiffuse.rgb * 0.5;\n'
    #    'ColorBaseDiffuse.a = ColorBaseDiffuse.a * 0.5;\n'
    #    'OUT_Color = half4(finalColor.rgb, ColorBaseDiffuse.a * F_alphascale);'
    #    )
    #new_text = new_text.replace(
    #    'OUT_Color = half4(finalColor.rgb, ColorBaseDiffuse.a * F_alphascale);',
    #    'OUT_Color = half4(finalColor.rgb, ColorBaseDiffuse.a * F_alphascale);')
    #new_text = new_text.replace(
    #    'OUT_Color = half4(1, 0, 0, 1);',
    #    'OUT_Color = half4(1, 0, 0, 1 * IO_Fade);')
    #new_text = new_text.replace(
    #    'DEFERRED_OUTPUT(Normal.xyz, ColorBaseDiffuse.rgb, MetalnessVal, SmoothnessVal, ColorGlow.rgb+fade_val*U_color_emissive.rgb);',
    #    'DEFERRED_OUTPUT(Normal.xyz, ColorBaseDiffuse.rgb * IO_Fade, MetalnessVal, SmoothnessVal, ColorGlow.rgb * IO_Fade + fade_val * U_color_emissive.rgb * IO_Fade);')

    # This does something.
    # - makes the asteroid reflect the background, with no particular
    #   color of its own.
    #new_code = 'OUT_Color = half4(1.0, 1.0, 1.0, 1.0);'

    # This does nothing.
    #new_code = 'OUT_Color.a *= 0.1;'
    
    # This does nothing.
    #new_code = 'OUT_Color.a = 0.1;\n  OUT_Color.rgb *= 0.1;'
    
    # Makes the asteroid invisible, but still has collision.
    #new_code = 'OUT_Color.a = 0;\n  OUT_Color.rgb = 0;'
    
    # This does nothing.
    #new_code = 'OUT_Color.a = ColorBaseDiffuse.a * F_alphascale * 0.5;'
    
    # This does nothing.
    #new_code = 'OUT_Color.a = saturate(ColorBaseDiffuse.a * F_alphascale) * 0.1;'
    
    # This does nothing.
    #new_code = 'OUT_Color.a = 0;'
    
    # Makes the asteroid invisible.
    #new_code = 'OUT_Color.rgb = 0;'
    
    # This does nothing.
    #new_code = 'OUT_Color.rgb *= 0.1;'
    
    # Makes the asteroid invisible.
    #new_code = 'OUT_Color.rgb = 1;\n  OUT_Color.a = 0;'
    
    # This does nothing.
    #new_code = 'OUT_Color.rgb *= 0.00001f;\n  OUT_Color.a = 0;'
    
    # This does nothing.
    #new_code = 'OUT_Color = vec4(OUT_Color.rgb, 0.0f);'
    
    # Partially reflective-ish.
    #new_code = 'OUT_Color.rgb = vec3(0.5, 0.5, 0.5);'
    
    # Darkish bland hue.
    #new_code = 'OUT_Color = half4(0.0, 0.0, 0.0, 0.5);'    
    # As above.
    #new_code = 'OUT_Color = half4(0.0, 0.0, 0.0, 0.0);'

    # Black asteroids, and red glowy bits gone. So color1/color2 in use.
    #new_code = 'OUT_Color = half4(0.0, 0.0, 0.0, 0.0);\n OUT_Color1 = vec4(0);\n OUT_Color2 = vec4(0);'
    
    # Makes the asteroid invisible.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0);',
    #    'OUT_Color1 = vec4(0);', 
    #    'OUT_Color2 = vec4(0);', 
    #    'OUT_Color3 = vec4(0);', 
    #    'OUT_Color4 = vec4(0);', 
    #    'OUT_Color5 = vec4(0);',])
    
    # Makes the asteroid invisible.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0, 0, 0, 1);',
    #    'OUT_Color1 = vec4(0, 0, 0, 1);', 
    #    'OUT_Color2 = vec4(0, 0, 0, 1);', 
    #    'OUT_Color3 = vec4(0, 0, 0, 1);', 
    #    'OUT_Color4 = vec4(0, 0, 0, 1);', 
    #    'OUT_Color5 = vec4(0, 0, 0, 1);',])
    
    # Asteroids are a muted greyish bland color.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0, 0, 0, 1);',
    #    'OUT_Color1 = vec4(0, 0, 0, 1);', 
    #    'OUT_Color2 = vec4(0, 0, 0, 1);', 
    #    ])
    
    # Asteroids are extremely white.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(1);',
    #    'OUT_Color1 = vec4(1);', 
    #    'OUT_Color2 = vec4(1);', 
    #    ])
    
    # Asteroids are extremely white.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(1,1,1,0.5);',
    #    'OUT_Color1 = vec4(1,1,1,0.5);', 
    #    'OUT_Color2 = vec4(1,1,1,0.5);', 
    #    ])
    
    # Asteroids are extremely white.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(1,1,1,0.0);',
    #    'OUT_Color1 = vec4(1,1,1,0.0);', 
    #    'OUT_Color2 = vec4(1,1,1,0.0);', 
    #    ])
    
    # Asteroids are black (still not transparent).
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0);',
    #    'OUT_Color1 = vec4(0);', 
    #    'OUT_Color2 = vec4(0);', 
    #    ])
    
    # Reflective
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(1);',
    #    'OUT_Color1 = vec4(0);', 
    #    'OUT_Color2 = vec4(0);', 
    #    ])
    
    # Darkly reflective
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(1,1,1,0);',
    #    'OUT_Color1 = vec4(0);', 
    #    'OUT_Color2 = vec4(0);', 
    #    ])
    
    # Asteroids are black
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0);',
    #    'OUT_Color1 = vec4(1);', 
    #    'OUT_Color2 = vec4(0);', 
    #    ])
    
    # Asteroids are white.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0);',
    #    'OUT_Color1 = vec4(0);', 
    #    'OUT_Color2 = vec4(1);', 
    #    ])
    
    # Asteroids are white.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0);',
    #    'OUT_Color1 = vec4(0);', 
    #    'OUT_Color2 = vec4(1,1,1,0);', 
    #    ])
    
    # Asteroids are white.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0);',
    #    'OUT_Color1 = vec4(0);', 
    #    'OUT_Color2 = vec4(1,1,1,0);', 
    #    'OUT_Color3 = vec4(1,1,1,0);', 
    #    ])
    
    # Asteroids are white.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0);',
    #    'OUT_Color1 = vec4(0);', 
    #    'OUT_Color2 = vec4(1,1,1,0);', 
    #    'OUT_Color3 = vec4(0);', 
    #    'OUT_Color4 = vec4(0);', 
    #    ])
    
    # Asteroids are white.
    #new_code = '\n'.join([
    #    'OUT_Color  = half4(0);',
    #    'OUT_Color1 = vec4(0);', 
    #    'OUT_Color2 = vec4(1,1,1,0);', 
    #    'OUT_Color3 = vec4(0);', 
    #    'OUT_Color4 = vec4(0);', 
    #    'OUT_Color5 = vec4(0);', 
    #    ])

    '''
    Observations:
    - Errors lead to transparency.
    - color   appears to control reflectivity
      - Full reflectivity means base color is fully suppressed.
      - Reflection is some low res alternate skybox, and does have a sun.
      - Depending on angle, reflection can blend nicely, or can really stand
        out, expecially with sun reflection.
    - color.a does nothing
    - color1  does nothing?
    - color2  appears to control the actual asteroid color.
    - color2.a does nothing?
    - color3+ does nothing?
    '''

    # TODO: figure this out.
    
    # Replace a late commented line, overriding out_color.
    new_text = new_text.replace(
        '//	OUT_Color = half4(Occl.xxx, 1.0);',	
        new_code,
        )
    shader_f_file.Set_Text(new_text)

    # TODO: complex_surface.f


    return


@Transform_Wrapper()
def Fadein_Asteroids(empty_diffs = 0):
    '''
    Uniquify asteroid materials, and set fade-in rules to match when they
    first start drawing, for a smoother fade-in period.
    '''
    '''
    Asteroids are selected from their component files, often with multiple
    variations of the same size category (eg. large, medium, etc.).
    Size is defined in the component as part of the connection to a material.

    Different sizes asteroids often share the same material entry.
    Asteroid appearance rules are set by region_lodvalues.xml, which defines
    when the asteroid spawns and (slightly closer) when it starts drawing
    based on asteroid size.

    Asteroid material refs in the xml are dummies; the actual material is
    defined in the xmf binary, which needs a binary patch.
    Uniquified materials will use names of the same length, for easy patching.
    '''

    # Only need to read lodvalues.
    lodvalues_file = Load_File('libraries/region_lodvalues.xml')
    lodvalues_root = lodvalues_file.Get_Root_Readonly()

    # Read out the show distances and size cuttoffs.
    minsize_renderdists ={}
    for distance_node in lodvalues_root.xpath('./distances/distance'):
        min_size = float(distance_node.get('minobjectsize'))
        render_dist = float(distance_node.get('render'))
        minsize_renderdists[min_size] = render_dist


    # Gather all of the asteroid components.
    # TODO: maybe reuse the database stuff for this.
    for pattern in ['env_ast_*', 'asteroid_*']:
        # Load the files first.
        Get_All_Indexed_Files('components',pattern)
    # Filter for asteroids.
    asteroid_files = Get_Asset_Files_By_Class('components', 'asteroid')

    # Dict of (game file : xml root), for writeback later.
    game_file_xml_roots = {x : x.Get_Root() for x in asteroid_files}
    

    # Extract component xml nodes to work with, indexed by name.
    component_nodes = {}
    for xml_root in game_file_xml_roots.values():
        # Loop over the components (probably just one).
        for component in xml_root.xpath('./component'):
            if component.get('class') != 'asteroid':
                continue
            ast_name = component.get('name')
            component_nodes[ast_name] = component


    # Match up asteroids with their materials used, prepping to uniquify.
    # Dict matching material names to asteroids using it.
    # Note: 168 asteroids use 19 materials.
    mat_asteroid_dict = defaultdict(list)

    for component in component_nodes.values():
        # An asteroid may use more than one material.
        mats = []
        for material in component.xpath('.//material'):
            mat_name = material.get('ref')
            # Ignore duplicates (fairly common).
            if mat_name not in mats:
                mats.append(mat_name)

        for mat in mats:
            mat_asteroid_dict[mat].append(component)
            

    # Pull up the materials file.
    material_file = Load_File('libraries/material_library.xml')
    material_root = material_file.Get_Root()

    # Gather materials for each asteroid, uniquifying as needed.
    asteroid_materials = defaultdict(list)
    # Names of all materials by collection, used to ensure uniqueness
    # of generated names.
    collection_names = defaultdict(set)

    # Note: loading of the xmf files can be slow if done individually for
    # each asteroid, due to pattern searches.
    # Do a single xmf lod pattern search here, organized by folder name.
    # Try to limit to expected folder names, else this is really slow.
    xmf_folder_files = defaultdict(list)
    for xmf_file in Load_Files('*/asteroids/*lod*.xmf'):
        folder = xmf_file.virtual_path.rsplit('/',1)[0]
        xmf_folder_files[folder].append(xmf_file)

    for mat_ref, asteroids in mat_asteroid_dict.items():

        # Break the mat_name into a collection and proper name, since
        # the components use <collection>.<mat>
        collection_name, mat_name = mat_ref.split('.',1)
        
        # To do binary edits safely, ensure the new name is the same
        # length as the old. Adjusting just the last character isn't quite
        # enough in the worst case that needs >30, so swap the last two
        # characters for a number.
        numbers = '0123456789'
        suffixes = []
        for char0 in numbers:
            for char1 in numbers:
                suffixes.append(char0 + char1)

        # If the collection isn't checked for names yet, check it now.
        if collection_name not in collection_names:
            for mat_node in material_root.xpath(f'./collection[@name="{collection_name}"]/material'):
                collection_names[collection_name].add(mat_node.get('name'))

        material = material_root.find(f'./collection[@name="{collection_name}"]/material[@name="{mat_name}"]')
        # Should always be found.
        assert material != None

        # If just one asteroid user, no duplication needed.
        if len(asteroids) == 1:
            asteroid_materials[asteroids[0]].append(material)
            continue

        # Otherwise, make duplicates for each asteroid.
        # (Don't bother reusing the original entry for now.)
        for i, asteroid in enumerate(asteroids):

            mat_copy = deepcopy(material)
            mat_copy.tail = None

            # Give a new, unique name.
            old_name = mat_copy.get('name')
            # Replace the last 2 characters until unique (probably first try
            # will work, except when it is the same as the existing last chars).
            while suffixes:
                char_pair = suffixes.pop(0)
                new_name = old_name[0:-2] + char_pair
                if new_name not in collection_names[collection_name]:
                    collection_names[collection_name].add(new_name)
                    break
            # Don't expect to ever run out of suffixes.
            assert suffixes
            # Ensure same length.
            assert len(old_name) == len(new_name)

            #print(f'copying {old_name} -> {new_name}')
            mat_copy.set('name', new_name)

            # Insert back into the library.
            material.addnext(mat_copy)
            # Screw around with messed up tails.
            if mat_copy.tail != None:
                material.tail = mat_copy.tail
                mat_copy.tail = None


            # Update the asteroid to use this material.
            asteroid_materials[asteroid].append(mat_copy)

            # Updating the xml doesn't actually matter in practice, since the
            # game reads from xmf lod values. But do it anyway.
            old_ref_name = collection_name + '.' + old_name
            new_ref_name = collection_name + '.' + new_name
            for material_ref in asteroid.xpath(f'.//material[@ref="{old_ref_name}"]'):
                material_ref.set('ref', new_ref_name)

            # Look up the xmf lod binaries.
            # These have the old ref name as a string packed with the binary.
            # The data is in a folder, defined in the component.
            # These use backslashes; convert to forward.
            geometry_folder = asteroid.find('./source').get('geometry').replace('\\','/')

            # Lod files appear to have the name form <prefix>lod<#>.xmf.
            lod_files = xmf_folder_files[geometry_folder]
            assert lod_files

            for lod_file in lod_files:
                print(f'Binary patching {lod_file.virtual_path}')

                # Make a binary edit path, looking to replace the old name
                # with the new name.
                patch = Binary_Patch(
                    file = lod_file.virtual_path,
                    # Convert the strings to hex, each character becoming
                    # two hex digits. These are null terminated in xmf.
                    # (Prevents eg. ast_ore_01 also matching ast_ore_01_frac.)
                    ref_code = String_To_Hex_String(old_ref_name) + '00',
                    new_code = String_To_Hex_String(new_ref_name) + '00',
                    expected_matches = [0,1],
                    )
                # Try the patch; if successful it will tag the file
                # as modified.
                if not Apply_Binary_Patch(patch):
                    # Some mismatch; just breakpoint to look at it.
                    bla = 0


    # Now with all materials being unique, check the asteroid sizes against
    # lodvalues, and update their material fade distances.
    for asteroid, materials in asteroid_materials.items():

        # Determine the asteroid size, based on its max dimension.
        ast_size = 0
        size_max_node = asteroid.find('.//size/max')
        for attr in ['x','y','z']:
            dim = size_max_node.get(attr)
            assert dim != None
            dim = float(dim)
            if dim > ast_size:
                ast_size = dim

        # Determine the render distance, based on largest matching rule.
        # Loop goes from largest to smallest; break on first match.
        render_dist = None
        for minsize, dist in sorted(minsize_renderdists.items(), reverse = True):
            if ast_size >= minsize:
                render_dist = dist
                break

        # Fade should end at render_dist, start somewhat closer.
        # How much closer is harder to define, but vanilla files are
        # often around 20%.
        fade_end = render_dist
        # Test: set really close to see if fade even works.
        fade_start = min(1000, render_dist * 0.8)
        
        # Apply these to the material properties.
        for material in materials:
            for prop_name, value in [
                ('camera_fade_range_start', fade_start),
                ('camera_fade_range_stop', fade_end),
                # Keep trying stuff to see any ingame effect.
                #('camera_fade_range_far_stop', fade_end),
                #('camera_fade_range_near_start', 10),
                #('camera_fade_range_near_end', 1000),
                #('angle_fade', 0.1),                
                #('angle_fade_speed', 1.0),
                #('angle_fade_offset', 0.0),
                
                # Note: these bitmap changes do update in game, even
                # if fade seems broken.
                #('diffuse_map',       r"assets\textures\environments\asteroids\icepattern_02_new_diff"),
                #('smooth_map',        r"assets\textures\environments\asteroids\icepattern_02_smooth"),
                #('normal_map',        r"assets\textures\environments\asteroids\ast_holeypattern_01_bump"),
                #('normal_detail_map', r"assets\textures\environments\asteroids\icepattern_bump"),
                #('color_glow_map',    r"assets\textures\environments\asteroids\icepattern_02_new_diff"),
                
                ]:

                # Check if there is already a matching property.
                property = material.find(f'./properties/property[@name="{prop_name}"]')
                # If not found, add it.
                if property == None:
                    property = etree.Element('property', 
                                             type = 'Float' if not isinstance(value, str) else 'BitMap', 
                                             name = prop_name)
                    properties = material.find('./properties')
                    properties.append(property)
                    assert property.tail == None

                # Update the value.
                if not isinstance(value, str):
                    value = f'{value:.0f}'
                property.set('value', value)


    material_file.Update_Root(material_root)
    for game_file, xml_root in game_file_xml_roots.items():
        game_file.Update_Root(xml_root)

    return


# Run the transform.
Patch_Asteroid_Shader()
#Fadein_Asteroids()
Write_To_Extension(skip_content = True)
