
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
from Framework import Transform_Wrapper, Load_File, Load_Files, File_System, XML_File, Text_File
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
    

    Note: in testing, other users of these shaders tend to error,
    apparently tracing back to the V_cameraposition or IO_world_pos
    values (at a guess), which even when not executed still cause a problem.

        It is possible the other ogl spec files do not have corresponding
        defines for the above values to be present.

        Possible fixes:
        - Duplicate all shaders being edited, link their ogl to the
            unique versions, so original ogl/shader files are unchanged.
        - Modify other ogl files to define whatever is needed to ensure
            these variables are available.
        - Modify the common header to ensure this vars are available.
        - Regenerate these vars here (if possible).
    '''
    # From ogl files, get their fragment shader names.
    shader_f_names = []

    # Go through ogl files and uniquify/modify them.
    for shader_name in shader_names:
        shader_ogl_file = Load_File(f'shadergl/high_spec/{shader_name}')
        # Skip empty files.
        if shader_ogl_file.load_error:
            continue

        # Copy out the root.
        xml_root = shader_ogl_file.Get_Root()

        # Grab the fragment shader name.
        shader_node = xml_root.find('./shader[@type="fragment"]')
        shader_f_name = shader_node.get('name')
        # Record it.
        if shader_f_name not in shader_f_names:
            shader_f_names.append(shader_f_name)
        # Uniquify it.
        shader_f_name = shader_f_name.replace('.f','_faded.f')
        shader_node.set('name', shader_f_name)

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
        # Note: These default values are not expected to ever be used.
        for field, value in [('ast_camera_fade_range_start', '19900000.0'),
                             ('ast_camera_fade_range_stop' , '20000000.0')]: 
            property = etree.Element('float', name = field, value = value)
            properties.append(property)
            assert property.tail == None


        # Generate a new file for the new shader spec.
        File_System.Add_File(XML_File(
            virtual_path = shader_ogl_file.virtual_path.replace('.ogl', '_faded.ogl'),
            xml_root = xml_root,
            modified = True))
        #shader_ogl_file.Update_Root(xml_root)



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


        Note: dithering on rotating asteroids creates a shimmer effect,
        as lighter or darker areas of the asteroid rotate into display pixels.
        Further, since dither is calculated by distance, and different points
        on the asteroid are at different distances, the pixels shown are
        also moving around (since asteroid isn't perfectly round).

            To mitigate shimmer, also adjust the object coloring.
            A couple options:
            - Dim to black. This is similar to some alpha examples. Would work
              well on a dark background (common in space).
            - Average to the asteroid base color. This would require specifically
              setting the base color for each asteroid type (brown for ore,
              blueish for ice, etc.). Avoids a black->blueish transition on ice.
              May look worse against a dark backdrop (eg. one blue/white pixel).

            This code will go with generic color dimming for now.
            Result: seems to help, though not perfect.


        Further shimmer mitigation is possible by reducing volatility of
        the camera depth.
            In reading, it doesn't appear pixel/fragment shaders normally
            support distance to the original object, only to their
            particular point on the surface.

            But, if the cam distance (or computed alpha) is rounded off, it
            will create somewhat more stable bins.  There would still be
            a problem when the asteroid surface moves from one bin to another,
            but most of the shimmer should be reduced.

            Rounding the fade factor is probably more robust than cam distance.
            Eg. fade = floor(fade * 100) / 100

            Result: somewhat works, but makes the pixel selection pattern
            really obvious. Where (dist.x+dist.y) is used, gets diagonal
            lines of drawn pixels.


        Cull pixel selection
            This has a problem with creating obvious patterns.
            Cull x < cuttoff || y < cuttoff:
            - Get mesh of dark lines (culled points).
            Cull x < cuttoff && y < cuttoff:
            - Get mesh of shown lines (non-culled points).
            Cull x + y < cuttoff
            - Get diagonal lines.

            TODO: what is a good culling formula that spreads out the points,
            both when mostly faded (first few points shown) and when mostly
            shown (last few points culled).
            
            Patterns are most obvious when zooming in, but can be somewhat
            seen by leaning forward, or identified when turning the camera.

        
        Reverse-shimmer is a somewhat different problem where eg. a blue/white
        ice asteroid that is mostly drawn will have some black background 
        pixels shimmering around and standing out.
           
            This could be addressed by fading in with two steps:
            - Dither region, where more pixels are drawn, all black.
            - Color region, where pixels adjusted from black to wanted color.
            
            Such an approach would also address other shimmer problems above,
            with the caveat that it might be even more sensitive to the
            overall background color (black is good, otherwise bad).

            Note: small asteroids drawing in front of already-visible larger
            asteroids would cause this background discrepency, eg. a small
            ice chunk starts dithering in black pixels when a large ice
            asteroid behind it is blue/white.

            For now, ignore this problem, as solutions are potentially worse.

        TODO: adjust for viewport width (or whatever it was called), so that
        zoomed in views see more of the asteroid draw (reducing obviousness
        of the dither effect when using a zoom hotkey).


        '''
        # Pick number of fade stepping bins, used to reduce shimmer.
        # Should be few enough that steppings don't stand out visually.
        num_bins = 20
    
        # Copy over the IO_Fade calculation from the common.v, and
        # do any customization. This also allows unique var names, to
        # avoid stepping on existing fade variables (eg. IO_fade).
        # Note: ast_fade is live through the function in testmode, so give
        # it a name likely to be unique.
        new_code = f'''
            float ast_cameradistance = abs(distance(V_cameraposition.xyz, IO_world_pos.xyz));
            float ast_faderange = U_ast_camera_fade_range_stop - U_ast_camera_fade_range_start;
            float ast_fade = 1.0 - clamp(abs(ast_cameradistance) - U_ast_camera_fade_range_start, 0.0, ast_faderange) / ast_faderange;
            ast_fade = round(ast_fade * {num_bins:.1f}) / {num_bins:.1f};
        '''
        # Add in the discard check if not in test mode.
        # Want to avoid diagonal patterns (x+y) in favor of a better scatter.
        if not testmode:
            #new_code += '''
            #    if( fract((gl_FragCoord.x + gl_FragCoord.y) * ast_fade) >= ast_fade)
            #        discard;
            #    '''

            # Make a 2-wide vector for this. Note: vulkan doesn't seem to
            # support something from documentation checked (sqrt? bvec?
            # greaterThanEqual?), so expand out the comparison.
            # Want to keep x/y crossing points, so discard unwanted x and y
            # (OR the check).
            #new_code += '''
            #    if (ast_fade < 0.999){
            #        float ast_fade_sqrt = sqrt(ast_fade);
            #        vec2 ast_factions = fract(gl_FragCoord.xy * ast_fade_sqrt);
            #        if( ast_factions.x >= ast_fade_sqrt || ast_factions.y >= ast_fade_sqrt)
            #            discard;
            #    }
            #    '''

            # Better idea: use the fragment xyz, so the discard pattern doesnt
            # follow the camera angle when turned.
            # If the coordinate is a noisy float (eg. not 2.00000), can use
            # its deep fractional part as a sort of random value.
            # Result: looks good on a still object, but asteroid rotation
            # creates shimmier, so reject.
            #new_code += '''
            #    if (ast_fade < 0.999){
            #        float psuedo_rand = fract((IO_world_pos.x + IO_world_pos.y + IO_world_pos.z) * 16.0);
            #        if( psuedo_rand >= ast_fade)
            #            discard;
            #    }
            #    '''
                
            # Try to create a random value from the screen xy position.
            # Note: quick reading indicates gpu sin/cos is just 1 cycle.
            # Example of randomizer calculation here:
            # https://stackoverflow.com/questions/4200224/random-noise-functions-for-glsl
            new_code += '''
                if (ast_fade < 0.999){
                    float psuedo_rand = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898,78.233))) * 43758.5453);
                    if( psuedo_rand >= ast_fade)
                        discard;
                }
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

        # When not in test mode, dim the asteroid final color.
        # TODO: does this work for all shaders, eg. color in out_color2?
        # Or perhaps can all color fields (eg. reflectivity) be dimmed
        # equally without impact?
        # Makes everything green tinted?
        if not testmode:
            new_code = '''
                OUT_Color  = OUT_Color  * ast_fade;
                OUT_Color1 = OUT_Color1 * ast_fade;
                OUT_Color2 = OUT_Color2 * ast_fade;
                '''
            
        # Replace a late commented line, overriding out_color.
        # TODO: more robust way to catch close of main.
        ref_line = '}'
        new_text = (new_code + ref_line).join(new_text.rsplit(ref_line, 1))

        
        # Uniquify the file.
        File_System.Add_File(Text_File(
            virtual_path = shader_f_file.virtual_path.replace('.f','_faded.f'),
            text = new_text,
            modified = True
            ))
        
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
            
    '''
    Some asteroids appear in groups, all at once, 50km-100km out (varying
    per asteroid in the group). This appears to trace back to zone culling:
    https://forum.egosoft.com/viewtopic.php?t=418286
    Note: this says stations are excepted from zone culling.

    Only xxl asteroids appear to be afflicted. Smaller asteroids draw even
    when further away than the pop-in xxl asteroids.
    Observed pop-in has been as close as 42km, as far as >100km.

    In component files, the main difference is xxl connections have
    an extra "cluster_l_detail" tag.
    Test removal result: no change in game, even with a new game.
    Grepping around, this connection might just be used in cluster_29.xml
    which has some hardcoded asteroid locations.

    In defaults.xml is a zone entry, with a visibility distance definition
    of 25km. In testing, bumping this to 100km made an asteroid that popped
    up 42km away instead be visible out to 163km (where it is still plenty
    large on screen).
    Can bump this value way way up.
    TODO: turn down the region_lodvalues or the dbglodrule_asteroidxl in
    renderparam_library distance for large asteroids, to offset their
    extra visibility from zones.
    '''
    #for component in component_nodes.values():
    #    for connection in component.xpath('./connections/connection'):
    #        tags = connection.get('tags')
    #        for tag in ['cluster_l_detail']:
    #            # Unclear on if single-vs-double spacing matters, but this
    #            # removal may have double spaces leftover, so clean them up.   
    #            tags = tags.replace(tag, '').replace('  ',' ')            
    #        connection.set('tags', tags)

    # Edit the defaults.xml zone visibility distance.
    defaults_file = Load_File('libraries/defaults.xml')
    defaults_root = defaults_file.Get_Root()
    vis_node = defaults_root.find('./dataset[@class="zone"]/properties/visible')
    vis_node.set('distance', '500000')
    
    # Handle the specs for when asteroids draw, by size.
    lodvalues_file = Load_File('libraries/region_lodvalues.xml')
    lodvalues_root = lodvalues_file.Get_Root()

    # Change the xxl distance; needs to be <200km (original 250km) for
    # lighting to work.
    for distance_node in lodvalues_root.xpath('./distances/distance'):
        if float(distance_node.get('render')) > 200000:
            distance_node.set('component'  , '198000')
            distance_node.set('render'     , '198000')
            distance_node.set('calculation', '200000')

    # Read out the show distances and size cuttoffs.
    minsize_renderdists ={}
    for distance_node in lodvalues_root.xpath('./distances/distance'):
        min_size = float(distance_node.get('minobjectsize'))
        render_dist = float(distance_node.get('render'))
        minsize_renderdists[min_size] = render_dist


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
            for type, prop_name, value in [
                ('Float', 'ast_camera_fade_range_start', f'{fade_start:.0f}'),
                ('Float', 'ast_camera_fade_range_stop',  f'{fade_end:.0f}'),
                ]:

                # Check if there is already a matching property.
                property = material.find(f'./properties/property[@name="{prop_name}"]')
                # If not found, add it.
                if property == None:
                    property = etree.Element(
                        'property', type = type, name = prop_name)
                    properties = material.find('./properties')
                    properties.append(property)
                    assert property.tail == None

                # Set or update the value.
                property.set('value', value)


    # Collect from all materials the shaders used, and uniquify their
    # names. Patch_Shader_Files will create the new ones.
    shader_names = []
    for materials in asteroid_materials.values():
        for material in materials:
            mat_shader_name = material.get('shader')
            # Actual file names use ogl instead of fx extension.
            shader_name = mat_shader_name.replace('.fx','.ogl')
            if shader_name not in shader_names:
                shader_names.append(shader_name)
            material.set('shader', mat_shader_name.replace('.fx', '_faded.fx'))

    # Send them over for updating.
    Patch_Shader_Files(shader_names)


    # Put back the modified materials and asteroids.
    material_file.Update_Root(material_root)
    lodvalues_file.Update_Root(lodvalues_root)
    defaults_file.Update_Root(defaults_root)
    for game_file, xml_root in game_file_xml_roots.items():
        game_file.Update_Root(xml_root)

    return


# Run the transform.
#Fadein_Asteroids()
Write_To_Extension(skip_content = True)
