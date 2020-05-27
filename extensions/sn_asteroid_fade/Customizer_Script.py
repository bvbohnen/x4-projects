
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


def Patch_Shader_Files(shader_names, testmode = False):
    '''
    Edit asteroid shader to support transparency.

    * shader_names
       - Names of shader ogl files to edit.
    * testmode
      - Sets asteroid color to white when unfaded, black when fully faded,
        for testing purposes.
    '''    
    '''
    The asteroid shader, and ogl file linking to v/vh/etc., doesn't normally
    support camera fade. However, fading rules are in the common.v file,
    and fade parameters can be added to the shaer ogl.
    Note: ogl is xml format.

    Note:
    .v : vertex shader
    .f : fragment shader (most logic is here)

    Read shaders from the materials edited.
    For now, here is a list of used materials:
        p1_asteroid
        p1_complex_surface
        xu_asteroid
        xu_asteroid_glow
        p1_complex_surface_translucent  (crystals; maybe skip)
        xu_glass (maybe skip?)
        xu_distortion
        xu_surface_layered

    Note: multiple ogl files can link to the same f shader file.
    Ensure a) that each shader file is modified once, and b) that each ogl
    file using a shader is also modified to fill in fade range defaults.

    Note: some ogl files are empty; skip them (will have load_error flagged).

    TODO: maybe be more restrictive on f files edited; probably only 2 or 3
    actually matter (not glass/crystal stuff).
    '''
    # From ogl files, get their fragment shaders.
    shader_f_names = []
    for shader_name in shader_names:
        shader_ogl_file = Load_File(f'shadergl/high_spec/{shader_name}')
        # Skip empty files.
        if shader_ogl_file.load_error:
            continue
        xml_root = shader_ogl_file.Get_Root_Readonly()
        shader_f_name = xml_root.find('./shader[@type="fragment"]').get('name')
        if shader_f_name not in shader_f_names:
            shader_f_names.append(shader_f_name)


    # Search all ogl files using these shaders.
    # Edit them to insert default fade params.
    for shader_ogl_file in Load_Files(f'shadergl/high_spec/*.ogl'):
        if shader_ogl_file.load_error:
            continue
        xml_root = shader_ogl_file.Get_Root()

        # Skip if not using one of the shaders.
        shader_f_name = xml_root.find('./shader[@type="fragment"]').get('name')
        if shader_f_name not in shader_f_names:
            continue

        # Want to add to the properties list.
        properties = xml_root.find('./properties')

        # -Removed; these defines don't seem to work, and may be undesirable
        # anyway since they might conflict with existing logic/defines,
        # eg. doubling up fade multipliers.
        # Add defines for the camera distance and fade.
        # Put these at the top, with other defines (maybe doesn't matter).
        #for field in ['ABSOLUTE_CAMERA_FADE_DISTANCE', 'FADING_CAMERA_FADE_RANGE']:
        #    property = etree.Element('define', name = field, value = '/*def*/')
        #    properties.insert(0, property)
        #    assert property.tail == None

        # The fade calculation will use these properties.
        # Assign them initial defaults in the shader (which also covers possible
        # cases where the shader is used by materials that weren't customized).
        # Defaults should be lenient; edited shaders might get used in
        # planets and such.
        # Try out custom names, for safety; eg. "ast_" prefix
        for field, value in [('ast_camera_fade_range_start', '19900000.0'), 
                             ('ast_camera_fade_range_stop' , '20000000.0')]:
            property = etree.Element('float', name = field, value = value)
            properties.append(property)
            assert property.tail == None

        # Modify the file right away.
        shader_ogl_file.Update_Root(xml_root)



    # Need to update the .f file that holds the actual shader logic.
    for shader_f_name in shader_f_names:
        shader_f_file = Load_File(f'shadergl/shaders/{shader_f_name}')
        # Do raw text editing on this.
        text = shader_f_file.Get_Text()
        new_text = text
    
        '''
        Various attempts were made to access proper transparency through
        the alpha channel, but none worked.
        Observations:
        - Out_color controls reflectivity (using low-res alt backdrop).
        - Out_color2 controls actual color.
        - Vulkan lookups suggest transparency might depend on an alpha channel,
          and would be super expensive to compute anyway.

        Instead, use a dithering approach, showing more pixels as it gets closer.
        Can use the "discard" command to throw away a fragment.

        gl_FragCoord gives the screen pixel coordinates of the fragment.
        Vanilla code divides by V_viewportpixelsize to get a Percentage coordinate,
        but that should be unnecessary.

        Want to identify every 1/alpha'th pixel.
        Eg. alpha 0.5, want every 2nd pixel.
            v * a = pix_selected + fraction
            If this just rolled over, pick this pixel.
            if( fract(v*a) >= a) discard;
            If a == 1, fract will always be 0, 0 >= 1, so discards none.
            If a == 0, fract will always be 0, 0 >= 0, so discards all.
        '''
    
        # Copy over the IO_Fade calculation from the common.v file, since it
        # apparently doesn't get included properly.
        # TODO: recheck this; IO_Fade is available, though appears to be 0.
        # Note: ast_fade is live through the function in testmode, so give
        # it a name likely to be unique.
        new_code = '''
            float ast_cameradistance = abs(distance(V_cameraposition.xyz, IO_world_pos.xyz));
            float ast_faderange = U_ast_camera_fade_range_stop - U_ast_camera_fade_range_start;
            float ast_fade = 1.0 - clamp(abs(ast_cameradistance) - U_ast_camera_fade_range_start, 0.0, ast_faderange) / ast_faderange;

        '''
        # Add in the discard check if not in test mode.
        if not testmode:
            new_code += '''
                if( fract((gl_FragCoord.x + gl_FragCoord.y) * ast_fade) >= ast_fade)
                    discard;
                '''
        # Replace a line near the start of main, for fast discard (maybe slightly
        # more performant).
        # TODO: make the ref line more robust.
        ref_line = 'main()\n{'
        assert new_text.count(ref_line) == 1
        new_text = new_text.replace(ref_line, ref_line + new_code)
    

        # In test mode, shortcut the ast_fade to the asteroid color.
        # Close asteroids will be white, far away black (ideally).
        # This overwrites the normal asteroid output result.
        if testmode:
            new_code = '''
                OUT_Color  = half4(0);
                OUT_Color1 = vec4(0);
                OUT_Color2 = vec4(ast_fade,ast_fade,ast_fade,0); 
                '''
            
            # Replace a late commented line, overriding out_color.
            # TODO: more robust way to catch close of main.
            ref_line = '}'
            #new_text = new_text.replace(ref_line, ref_line + new_code)
            new_text = (new_code + ref_line).join(new_text.rsplit(ref_line, 1))

        shader_f_file.Set_Text(new_text)
        
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
        # often around 20%, and even a small amount would be enough to
        # offset pop-in.
        # Note: render_dist is for the asteroid center point when it shows
        # up, but camera distance is per-pixel and will be closer, so have
        # fade end a little sooner. Go with 1% for now.
        fade_end   = render_dist * 0.99
        fade_start = render_dist * 0.8
        
        # Apply these to the material properties.
        for material in materials:
            for prop_name, value in [
                ('ast_camera_fade_range_start', fade_start),
                ('ast_camera_fade_range_stop', fade_end),                
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

    # Collect from all materials the shaders used.
    shader_names = []
    for materials in asteroid_materials.values():
        for material in materials:
            shader_name = material.get('shader').replace('.fx','.ogl')
            if shader_name not in shader_names:
                shader_names.append(shader_name)

    # Send them over for updating.
    Patch_Shader_Files(shader_names)

    material_file.Update_Root(material_root)
    for game_file, xml_root in game_file_xml_roots.items():
        game_file.Update_Root(xml_root)

    return


# Run the transform.
Fadein_Asteroids()
Write_To_Extension(skip_content = True)
