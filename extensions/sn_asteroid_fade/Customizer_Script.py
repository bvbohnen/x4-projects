
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
from Framework import Get_Indexed_File, Get_All_Indexed_Files, Get_Asset_Files_By_Class

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
            
            
    
    # Handle the specs for when asteroids draw, by size.
    lodvalues_file = Load_File('libraries/region_lodvalues.xml')
    lodvalues_root = lodvalues_file.Get_Root()

    # Change the xxl distance; needs to be <200km (original 250km) for
    # lighting to work. Make even closer, based on zone vis distance.
    # Reduce the component spawning range on xxl asteroids, since it prevents
    # them from displaying when their zone isn't visible.
    # Closest observed pop-in is 42km, so 40km may be mostly safe, but
    # can also drop to 30km like other asteroids.
    # TODO: consider asteroid size, as surface several km from center.
    for distance_node in lodvalues_root.xpath('./distances/distance'):
        if float(distance_node.get('render')) > 200000:
            distance_node.set('component'  , '30000')
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
    for game_file, xml_root in game_file_xml_roots.items():
        game_file.Update_Root(xml_root)

    return


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
        
        TODO: including camera angle somehow? Maybe compute from the
        cam and object xyz but based on angle? 
            angles = sin((cam.x - obj.x) / (cam.z - obj.z)) + sin((cam.y - obj.y) / (cam.z - obj.z))
            Tweak this based on:
                - Distance; reduced angle between pixels at longer distance.
                - Resolution; reduced angle between pixels at higher res.
                - Round to roughly matching up to pixel density.

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
            # Works decently, though dither tracks with camera rotation.
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


# Run the transform.
Fadein_Asteroids()
Write_To_Extension(skip_content = True)



# TODO: remove this fluff.
def Tests(component_nodes, lodvalues_root):
    '''
    Bunch of tests from trying to figure out why xxl asteroids were popping
    out with their zone visibility.
    '''
    # TODO: split off this test logic into another function.
    '''
    Some asteroids appear in groups, all at once, 40km-100km+ out (varying
    per asteroid in the group). This appears to trace back to zone culling:
    https://forum.egosoft.com/viewtopic.php?t=418286
    Note: this says stations are excepted from zone culling.
    In testing, this is verified: when visible such asteroids are "visible"
    attension; on disappearing they are "adjacentzone".

    Only xxl (maybe xl?) asteroids appear to be afflicted. Smaller asteroids
    draw even when further away than the pop-in xxl asteroids.
    Observed pop-in has been as close as 42km, as far as >100km.

    Note: targetting a random largish asteroid and flying away, it stays
    in "visible" attention well past not being rendered, until 125.7km
    away it drops into "adjacentzone".

    Note: "env_ast_ore_xs_01" and "xu_asteroid" are in the exe, but not 
    other asteroids, and no other insightful "asteroid" or "ast" strings found.
    This suggests the xl->zone connection isn't completely hardcoded, and
    changing the name of the xl asteroid won't help.

    Note: env_ast_crystal_xl_01 is also rather large, and doesn't have the
    zone popping problem.
    Eg. ore xl has size 1277 and pops; crystal xl has size 1390 and doesn't.
    TODO: maybe look into this further.
    When env_ast_crystal_xl_01 is fading, it can be in the "adjacentzone"
    attention, eg. it still has a zone owner but isn't getting culled
    with the zone.

    Note on save file:
        Using trinity sanctum warrior start (Cluster_47_macro).
        Asteroids are listed as zone connections.
        Zones observer all use a "tempzone" macro.

        <component class="zone" macro="tempzone" connection="sector"
          <connection connection="asteroids">
            <component class="asteroid" macro="env_ast_ore_xxl_01_macro" ...

        Three ore asteroids observed:
            env_ast_ore_xxl_01_macro
            env_ast_ore_xl_01_macro
            env_ast_ore_l_01_macro (and other numbers)
            (not medium)

        Many tempzones have just env_ast_ore_xxl_01_macro, suggesting it is
        indeed the one that remains statically out to further distances,
        other rocks getting spawned only when closer.
        Nothing notable is in the save for asteroids, just location, rotation,
        and ore amount.

    Note on trinity sanctum 7:
        Has three region defs in clusters.xml:
            region_bigasteroids
            region_cluster_47_sector_001
            region_cluster_47_sector_001b
        region_bigasteroids uses groups from regionobjectgroups, and is the
        only one responsible for the silicon xl asteroids.
        Ore xl and xxl asteroids can spawn from any of the regions.

    Note on xmf:
        Swapping the env_ast_crystal_xl_01 xmf model/lod files over top
        of the env_ast_ore_xl_01 ones had no benefit: an ore asteroid
        would pop out when surrounding/further silicon asteroids (with
        the same model) would continue to display.
            
        In short, the xmf has nothing to do with this behavior.
    '''
    '''
    In component files, the main difference is xxl connections have
    an extra "cluster_l_detail" tag.

    Test removal result: no change in game, even with a new game (tried twice).
    Grepping around, this connection might just be used in cluster_29.xml
    (Hatikvah) which has some hardcoded asteroid locations.
    '''
    if 0:
        for component in component_nodes.values():
            for connection in component.xpath('./connections/connection'):
                tags = connection.get('tags')
                for tag in ['cluster_l_detail']:
                    # Unclear on if single-vs-double spacing matters, but this
                    # removal may have double spaces leftover, so clean them up.   
                    tags = tags.replace(tag, '').replace('  ',' ')            
                connection.set('tags', tags)


    '''
    In defaults.xml is a zone entry, with a visibility distance definition
    of 25km. In testing, bumping this to 100km made an asteroid that popped
    up 42km away instead be visible out to 163km (where it is still plenty
    large on screen).
    Can bump this value way way up.  250km should safely load all
    wanted asteroids.

    Test result: success.
    However, this causes ships to be in "visible" attention much further away,
    with a related performance impact with many ships in a system.
    Note: objects are only lit out to 200km, so asteroids should be limited
    to less than that distance.

    TODO: how does the min dist to visible asteroid related to zone distance?

    TODO: better solution.

    '''
    zone_xl_distance = 200000
    if 0:
        # Edit the defaults.xml zone visibility distance.
        # - Works, but impacts ai scripts, so seek another solution.
        defaults_file = Load_File('libraries/defaults.xml')
        defaults_root = defaults_file.Get_Root()
        vis_node = defaults_root.find('./dataset[@class="zone"]/properties/visible')
        vis_node.set('distance', str(zone_xl_distance))
        defaults_file.Update_Root(defaults_root)
        

    '''
    Alternatively, try adding tags to l/xl asteroids that might allow
    display further out.  Stations display further and include such
    tags.

    Test result: adding detail_xl and/or forceoutline made no difference.
    '''
    if 0:
        for component in component_nodes.values():
            # Find connections with material children.
            for connection in component.xpath('./connections/connection[.//material]'):
                tags = connection.get('tags')
                for tag in ['detail_xl', 'forceoutline']:
                    if tag not in tags:  
                        tags = f'{tags} {tag}'.replace('  ',' ')
                        connection.set('tags', tags)
        

    '''
    Perhaps the selection of asteroids culling with zones is made by
    the highest renderparam_library entry. Try:
    a) Up the draw distance of the second/third entries, verify they are
       not zone culled.
    b) Add a new, higher radius rule that no asteroids match, to act as a dummy.
    c) If b fails, change radius on current highest rule, and use the second
       highest to cover the largest two groups of asteroids.

    Test results:
    a) 200k draw distance on second two tiers (166000, 82000) do show up much
       farther than the xxl asteroid zone.
    b) No change using a new 10000 size node.
    c) No change swapping highest rule to 10000 size. Nor for highest 2 sizes.
       Note: verified the xl roids are going in the lower render group (eg.
       fading in instead of popping, just at ~80 km).

    '''
    if 0:
        for distance_node in lodvalues_root.xpath('./distances/distance'):
        # Verified second two tiers aren't attached to the zone.
            if distance_node.get('calculation') == '166000':
                distance_node.set('component'  , '30000')
                distance_node.set('render'     , '198000')
                distance_node.set('calculation', '200000')
            if distance_node.get('calculation') == '82000':
                distance_node.set('component'  , '30000')
                distance_node.set('render'     , '198000')
                distance_node.set('calculation', '200000')

    # Add a new higher tier.  Result: doesn't help.
    if 0:
        new_lod = etree.Element(
            'distance', 
            minobjectsize="10000",
            component="300000",
            render="300000",
            calculation="320000",
            chunksize="256" )
        lodvalues_root.find('./distances').insert(0, new_lod)

    # Edit the existing highest tier to larger size. Result: doesn't help.
    if 0:
        lodvalues_root.find('./distances/distance[@minobjectsize="2500"]').set('minobjectsize', '10000')
        
    # As above, but highest two tiers. Result: doesn't help.
    if 0:
        lodvalues_root.find('./distances/distance[@minobjectsize="2500"]').set('minobjectsize', '10000')
        lodvalues_root.find('./distances/distance[@minobjectsize="1000"]').set('minobjectsize', '9000')
        

    '''
    Perhaps the zone attachment is based on the component size (since there
    isn't much else to go on).  Edit sizing and see.

    Note: this seems to affect edge of screen culling, such that a rock
    vanishes when still partly visible. Not ideal.
    
    Note: Makes it much harder to get targets; even clicking up close often fails.

    Test result: asteroid distributions feel rather different, but still
    has the popping problem on xl rocks.  Xxl rocks not observed spawning
    at all, though.
    (Tested on new game.)
    '''
    if 0:
        # Force to 500 max.
        for asteroid in component_nodes.values():
            for size_node in asteroid.xpath('.//size'):
                max_node = size_node.find('./max')
                for attr in max_node.attrib:
                    if float(max_node.get(attr)) > 500:
                        max_node.set(attr, '500')
        # For this test, make sure the "smaller" asteroids still have a good
        # visibility range to verify.  120km should do.
        distance_node = lodvalues_root.find('./distances/distance[@minobjectsize="500"]')
        distance_node.set('component'  , '30000')
        distance_node.set('render'     , '118000')
        distance_node.set('calculation', '120000')

    '''
    In the region definitions, the xl/xxl roids are given an extra term,
    lodrule="asteroidxl", missing from large roids.
    Perhaps removing this rule from the region def would help.

    The rule itself is in renderparam_library as dbglodrule_asteroidxl
    with a very high range, and dbglodrule_asteroids = 0.  The latter
    might also be part of the issue.

    a) Try setting the sizecontrib to 80, same as normal asteroid.
        Result: no change on loaded save.
    b) Try removing lodrule from region defs.
        Result: no change on loaded save. no change on new game.
    c) Try changing other properties, eg. range.
        Result: no change.
    '''
    if 0:
        renderparam_file = Load_File('libraries/renderparam_library.xml')
        renderparam_root = renderparam_file.Get_Root()
        renderparam_root.find('.//rule[@name="dbglodrule_asteroidxl"]').set('sizecontrib', '80')
        renderparam_file.Update_Root(renderparam_root)

    if 0:
        region_defs_file = Load_File('libraries/region_definitions.xml')
        region_defs_root = region_defs_file.Get_Root()
        for asteroid_node in region_defs_root.xpath('.//asteroid[@lodrule="asteroidxl"]'):
            del(asteroid_node.attrib['lodrule'])
        region_defs_file.Update_Root(region_defs_root)
        
    if 0:
        renderparam_file = Load_File('libraries/renderparam_library.xml')
        renderparam_root = renderparam_file.Get_Root()
        renderparam_root.find('.//rule[@name="dbglodrule_asteroidxl"]').set('range', '35000')
        renderparam_root.find('.//rule[@name="dbglodrule_asteroidxl"]').set('sizecontrib', '80')
        renderparam_file.Update_Root(renderparam_root)
        
    '''
    It is possible that region_definitions which use grouprefs to
    regionobjectgroups are not culled, while those using direct macro refs
    are culled.  As a quick test, try changing the xxl direct ref asteroids
    with grouprefs to asteroid_ore_xxl.

    Result: still pop, no difference.
    Note: test below finds that the xxl pop-in asteroids are coming from
    the grouprefs of region_bigasteroids anyway.
    '''
    if 0:
        region_defs_file = Load_File('libraries/region_definitions.xml')
        region_defs_root = region_defs_file.Get_Root()
        for asteroid_node in region_defs_root.xpath('.//asteroid[@ref="env_ast_ore_xxl_01_macro"]'):
            # Skip if not an ore asteroid, since the groupref is for ore.
            if asteroid_node.get('resources') != 'ore':
                continue
            del(asteroid_node.attrib['ref'])
            asteroid_node.set('groupref', 'asteroid_ore_xxl')
        region_defs_file.Update_Root(region_defs_root)
        
    '''
    If it is ore specifically that the game messes up, and not silicon, can
    swap asteroid regions over to silicon and see what happens.

    Test results:
        No change if just switching to silicon in region_definitions; large
        "ore" asteroids still have ore, not silicon.
        No pop-in change when switching regionobjectgroups to silicon, though
        it does indeed swap the xxl ore asteroids over to containing silicon.
    '''
    if 0:
        region_defs_file = Load_File('libraries/region_definitions.xml')
        region_defs_root = region_defs_file.Get_Root()
        for asteroid_node in region_defs_root.xpath('.//asteroid[@resources="ore"]'):
            asteroid_node.set('resources', 'silicon')
        region_defs_file.Update_Root(region_defs_root)
        
        region_groups_file = Load_File('libraries/regionobjectgroups.xml')
        region_groups_root = region_groups_file.Get_Root()
        for group in region_groups_root.xpath('.//group[@resource="ore"]'):
            group.set('resource', 'silicon')
        region_groups_file.Update_Root(region_groups_root)
        
    '''
    If the specific asteroid macro/component names are handled specially in
    the exe (maybe after hashing, so hard to find as strings?), perhaps
    creating new copies with different names would work out better.

    Note: test with a new game, since a save will ref the old macro/component.

    Test result: still pop-in, with the new macro being used, when just
    changing the name to suffix with _copy.

    Test of "crystal" style name:  env_ast_crystal_l_01_xxl(_macro): still
    pops in.

    (Tested on new game)
    This indicates the naming is not the problem.
    '''
    if 0:
        # Create copies of the xxl macro and component files.
        component_file = Get_Indexed_File('components', 'env_ast_ore_xxl_01')
        macro_file     = Get_Indexed_File('macros', 'env_ast_ore_xxl_01_macro')
        component_copy = component_file.Copy(component_file.virtual_path.replace('env_ast_ore_xxl_01.xml','env_ast_crystal_l_01_xxl.xml'))
        macro_copy     = macro_file    .Copy(macro_file    .virtual_path.replace('env_ast_ore_xxl_01_macro.xml','env_ast_crystal_l_01_xxl_macro.xml'))
        File_System.Add_File(component_copy)
        File_System.Add_File(macro_copy)

        # Swap out names internally.
        xml_root = component_copy.Get_Root()
        xml_root.find('./component').set('name', 'env_ast_crystal_l_01_xxl')
        component_copy.Update_Root(xml_root)

        xml_root = macro_copy.Get_Root()
        xml_root.find('./macro').set('name', 'env_ast_crystal_l_01_xxl_macro')
        # Swap the macro to component link.
        xml_root.find('./macro/component').set('ref', 'env_ast_crystal_l_01_xxl')
        macro_copy.Update_Root(xml_root)


        # Add to index files.
        component_index = Load_File('index/components.xml')
        xml_root = component_index.Get_Root()
        start_id = xml_root.tail
        new_node = etree.Element('entry', 
            name = 'env_ast_crystal_l_01_xxl', 
            value = 'extensions\\sn_asteroid_fade\\' + component_copy.Get_Index_Path())
        xml_root.append(new_node)
        assert new_node.tail == None
        assert xml_root.tail == start_id
        component_index.Update_Root(xml_root)
        
        macro_index     = Load_File('index/macros.xml')
        xml_root = macro_index.Get_Root()
        xml_root.append(etree.Element('entry', 
            name = 'env_ast_crystal_l_01_xxl_macro', 
            value = 'extensions\\sn_asteroid_fade\\' + macro_copy.Get_Index_Path()))
        macro_index.Update_Root(xml_root)

        # Replace refs to the original macro with the new one.
        region_defs_file = Load_File('libraries/region_definitions.xml')
        region_defs_root = region_defs_file.Get_Root()
        for asteroid_node in region_defs_root.xpath('.//asteroid[@ref="env_ast_ore_xxl_01_macro"]'):
            asteroid_node.set('ref', 'env_ast_crystal_l_01_xxl_macro')
        region_defs_file.Update_Root(region_defs_root)
        
        region_groups_file = Load_File('libraries/regionobjectgroups.xml')
        region_groups_root = region_groups_file.Get_Root()
        for select in region_groups_root.xpath('.//select[@macro="env_ast_ore_xxl_01_macro"]'):
            select.set('macro', 'env_ast_crystal_l_01_xxl_macro')
        region_groups_file.Update_Root(region_groups_root)
        

    '''
    Try making the ore xl files look more and more like the crystal xl files.
    
    Point the ore xl macro file at the crystal xl component and drop.

    Result: model changed in game, still pops in, in reloaded save.
    Try new game: still pops.
    
    Result: test pointless due to targeted-object-pops issue.
    Go back to focusing on env_ast_ore_xxl_01_macro.
    '''
    if 0:
        # Edit the ore xl macro to point to the crystal component and drops.
        # Note: macros aren't edited elsewhere, so can update here.
        ore_macro = Get_Indexed_File('macros', 'env_ast_ore_xl_01_macro')
        xml_root = ore_macro.Get_Root()
        xml_root.find('./macro/component').set('ref', 'env_ast_crystal_xl_01')
        xml_root.find('.//drop').set('ref', 'asteroid_crystal_xl')
        ore_macro.Update_Root(xml_root)
        
    '''
    As above, but swap the xxl ore to xl ore.

    Result:
        Existing save: xxl asteroids use the smaller xl model, but still pop 
        as a group.
        New save: xxl asteroids don't spawn at all (verified by save xml search).
    '''
    if 0:
        ore_macro = Get_Indexed_File('macros', 'env_ast_ore_xxl_01_macro')
        xml_root = ore_macro.Get_Root()
        xml_root.find('./macro/component').set('ref', 'env_ast_ore_xl_01')
        ore_macro.Update_Root(xml_root)

    '''
    Try swapping the crystal and ore macros in the region files, to see what
    happens.

    Test result:
        env_ast_ore_xl_01_macro contains silicon, and fades out properly.
        env_ast_crystal_xl_01_macro contains ore, and also fades properly.

        What does this mean?

    Test just swapping region_definitions refs:
        env_ast_ore_xl_01_macro with ore pops in.  or fade in?
        New observation: in a clump of 3 env_ast_ore_xl_01_macro ore roids,
        the one targetted pops in, which the 2 not targetted fade in, and
        if the target is removed them all 3 fade in.

    Behavior changes if a target is on the asteroid? Though prior observations
    have seen targetted asteroids fade in, so this isn't consistent.

    This calls into question some prior test observations.

    Result: test pointless due to targeted-object-pops issue.
    Go back to focusing on env_ast_ore_xxl_01_macro.
    '''
    if 0:
        # Replace refs to the original macro with the new one.
        region_defs_file = Load_File('libraries/region_definitions.xml')
        region_defs_root = region_defs_file.Get_Root()
        for node in region_defs_root.xpath('.//asteroid'):
            if node.get('ref') == 'env_ast_ore_xl_01_macro':
                node.set('ref', 'env_ast_crystal_xl_01_macro')
            elif node.get('ref') == 'env_ast_crystal_xl_01_macro':
                node.set('ref', 'env_ast_ore_xl_01_macro')
        region_defs_file.Update_Root(region_defs_root)        
    if 0:
        region_groups_file = Load_File('libraries/regionobjectgroups.xml')
        region_groups_root = region_groups_file.Get_Root()
        for node in region_groups_root.xpath('.//select'):
            if node.get('macro') == 'env_ast_ore_xl_01_macro':
                node.set('macro', 'env_ast_crystal_xl_01_macro')
            elif node.get('macro') == 'env_ast_crystal_xl_01_macro':
                node.set('macro', 'env_ast_ore_xl_01_macro')
        region_groups_file.Update_Root(region_groups_root)
        
    '''
    Try the same, but swapping xxl ore for xl ore, and xl ore to crystal (to
    get it out of the way).

    Result: ore_xxl (as ore_xl_01) doesn't spawn at all (not seen in save).
    '''
    if 0:
        # Replace refs to the original macro with the new one.
        region_defs_file = Load_File('libraries/region_definitions.xml')
        region_defs_root = region_defs_file.Get_Root()
        for node in region_defs_root.xpath('.//asteroid'):
            if node.get('ref') == 'env_ast_ore_xl_01_macro':
                node.set('ref', 'env_ast_crystal_xl_01_macro')
            elif node.get('ref') == 'env_ast_ore_xxl_01_macro':
                node.set('ref', 'env_ast_ore_xl_01_macro')
        region_defs_file.Update_Root(region_defs_root)        
    if 0:
        region_groups_file = Load_File('libraries/regionobjectgroups.xml')
        region_groups_root = region_groups_file.Get_Root()
        for node in region_groups_root.xpath('.//select'):
            if node.get('macro') == 'env_ast_ore_xl_01_macro':
                node.set('macro', 'env_ast_crystal_xl_01_macro')
            elif node.get('macro') == 'env_ast_ore_xxl_01_macro':
                node.set('macro', 'env_ast_ore_xl_01_macro')
        region_groups_file.Update_Root(region_groups_root)
        

    '''
    Try adding a hidden=true attribute to the xxl connections.

    Result: asteroids go invisible once getting close enough to target them.
    '''
    if 0:
        ore_macro = Get_Indexed_File('macros', 'env_ast_ore_xxl_01_macro')
        xml_root = ore_macro.Get_Root()
        for node in xml_root.xpath('./macro/connections/connection'):
            node.set('hidden', 'true')
        ore_macro.Update_Root(xml_root)
        
        for asteroid in component_nodes.values():
            if asteroid.get('name') == 'env_ast_ore_xxl_01':
                for node in asteroid.xpath('./connections/connection'):
                    node.set('hidden', 'true')
                    
    '''
    Try adding <map visible="0" /> element to the properties of the macro.

    Result: xxl still pops, still targetable, but no icon on the map
    '''
    if 0:
        ore_macro = Get_Indexed_File('macros', 'env_ast_ore_xxl_01_macro')
        xml_root = ore_macro.Get_Root()
        xml_root.find('./macro/properties').append(etree.Element(
            'map', visible='0'))
        ore_macro.Update_Root(xml_root)

        
    '''
    The xxl asteroids have a much higher "component" range (250km) than
    others in the render_lodvalues. If this determines targetability,
    and targetability relates to if the asteroid is culled, can tweak
    this to fix the problem.

    Test result:
    - Loaded save, no difference on test asteroids, though a newly spawned
      xxl (3.2 beta bug generates extra asteroids each save) wasn't culled.
    - New game: xxl asteroids display out to full lod distance, except
      when targeted and flown away from (similar to xl observations).

    Success.  This means the issue is with asteroids that have a component
    active in the game, which then get culled by zone visibility, but
    those without a component display to full range.
    Loading a save, asteroids with components retain components, or else
    something weird was up with those tests.
    An asteroid targeted retains its component as long as target is active.
    '''
    # Reduce component range of the largest size.
    if 0:
        lodvalues_root.find('./distances/distance[@minobjectsize="2500"]').set('component', '30000')
        
    return