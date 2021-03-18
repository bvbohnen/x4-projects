
import sys
from lxml import etree
from lxml.etree import Element
from pathlib import Path
this_dir = Path(__file__).resolve().parent

# Set up the customizer import.
project_dir = this_dir.parents[1]
x4_customizer_dir = str(project_dir.parent / 'X4_Customizer')
if x4_customizer_dir not in sys.path:
    sys.path.append(x4_customizer_dir)
        
# Import all transform functions.
from Plugins import *
from Framework import Transform_Wrapper, Load_File, Load_Files, Get_All_Indexed_Files

Settings(
    # Set the path to the X4 installation folder.
    path_to_x4_folder   = r'D:\Games\Steam\SteamApps\common\X4 Foundations',
    # Generate the extension here.
    path_to_output_folder = this_dir.parent,
    extension_name = this_dir.name,
    developer = True,
    )

'''
Note:
    Cpu affinity can maybe be set for X4 to select ever-other core for a perf bump.
    The measurements below were done without such a setting.
    In a quick affinity test on 20k ships save:
    (note: some of this may be drift in the game, since no reloads were done)
        - 0/1/2/3/4/5/6/7: 39 fps  (default)
        - 1/3/5/7: 38 fps
        - 0/1: 18 fps  (verifies perf can tank, at least)
        - 0/1/2: 26 fps
        - 0/1/2/3/4: 36 fps
        - 5/7: 25 fps
        - 3/5/7: 31 fps
        - 1/3/5/7: 35 fps
        - 0/1/2/3/4/5/6/7: 37 fps
        - 0/2/4/6: 37 fps
    Could be luck based, but the above doesn't find any benefit, just
    detriment, to restricting cores.

Note:
    Cpu min performance state can be changed in windows power options
    advanced settings.
    Balanced profile sets this to 5%, max perf sets it to 100%.
    In quick test, 20k ships save, maybe with factories messed up by removal
    of sector scaling:
        5% min cpu:  49.2 fps
        100% min cpu: 49.5 fps
    Basically, no difference.

TODO:
    Try disabling high performance timer, noted to help with some games.
    Also try setting disabledynamictick.
    https://www.reddit.com/r/Guildwars2/comments/hmqi76/psa_there_is_a_possibility_that_guild_wars_2_will/

High performance timer test:
    Using dense empire test save from forums.
    To see if currently on, can check Divice Manager/System Devices,
    or can check cmd (as admin) ""bcdedit /enum" and look for 
    "useplatformclock".
    To disable, can try disabling in device manager, or maybe 
    "bcdedit /deletevalue useplatformclock" on cmd, altenratively 
    "bcdedit /set useplatformclock false".
    Turn back on in bcd with "bcdedit /set useplatformclock true".

TODO:
    Maybe increase 1ms waits, on the reasoning that they cant fire faster than
    a frame delay, and if the game is supposed to operate correctly down 
    around ~30 fps, then the minimum wait should be ~30 ms (to reduce
    excessive script load). May have side effects in cases when 1ms wait is
    meant to just be a 1 frame delay for cue timings or similar, though.
'''

# Note: can try testing with this removed from command line:
#  -logfile debuglog.txt -debug general


@Transform_Wrapper()
def Remove_Debug(empty_diffs = 1):
    '''
    Delete debug_to_text nodes from md and aiscript files.

    * empty_diffs
      - Bool, set True to generate diff files but with no changes, useful
        for reloading a save so that game still sees the diff files.
        
    Result: over 60 second of fps smoothing, after waiting for it to stabalize,
    ignoring first loaded game (that has ~25% higher fps than reloads):
    - without command line logging enabled: no notable difference.
    - with logging enabled: 15.7 to 17.2 fps (+10%).
    - There is reload-to-reload variation, though, so not certain.
    TODO: retest using fresh game restarts.
    '''
    aiscript_files = Load_Files('aiscripts/*.xml')
    md_files       = Load_Files('md/*.xml')
    
    for game_file in aiscript_files + md_files:
        xml_root = game_file.Get_Root()

        changed = False
        for tag in ['debug_text', 'debug_to_file']:
            debug_nodes = xml_root.xpath(".//{}".format(tag))
            if not debug_nodes:
                continue

            changed = True
            if empty_diffs:
                continue

            for node in debug_nodes:
                # Remove it from its parent.
                node.getparent().remove(node)

        # In some cases a do_if wrapped a debug_text, and can be safely
        # removed as well if it has no other children.
        # The do_if may be followed by do_else that also wrapped debug,
        # so try to work backwards.
        for tag in ['do_else', 'do_elseif', 'do_if']:
            do_nodes = xml_root.xpath(".//{}".format(tag))
            if not do_nodes:
                continue
            
            changed = True
            if empty_diffs:
                continue

            # Loop backwards, so do_elseif pops from back to front.
            # (Not likely to catch anything, but maybe.)
            for node in reversed(do_nodes):
                # Check for children.
                if list(node):
                    continue
                # Check that the next sibling isn't do_else_if or else.
                follower = node.getnext()
                if follower != None and follower.tag in ['do_elseif','do_else']:
                    continue
                # Should be safe to delete.
                node.getparent().remove(node)

        if changed:
            # Commit changes right away; don't bother delaying for errors.
            game_file.Update_Root(xml_root)
    return


@Transform_Wrapper()
def Tweak_Escorts(empty_diffs = 0):
    '''
    Adjust escort scripts to fire less often.
    Test result: negligible difference (5% at most, probably noise).
    '''
    game_file = Load_File('aiscripts/order.fight.escort.xml')
    xml_root = game_file.Get_Root()
    '''
    These scripts run far more often than anything else, specifically
    hitting a 500 ms wait then doing a move_to_position, even when
    out of visibility.
    Can try increasing the wait to eg. 5s.

    Results:
    - New game, 0.4x sector size, 3x job ships, flying 300 km above trinity
      sanctum in warrior start ship, pointing toward the sector center.
    - Driver set to adaptive power, adaptive vsync (60 fps cap).
    - Game restart between tests, other major programs shut down (no firefox).
    - With change: 37.3 fps, escort wait+move at 20% of aiscript hits.
    - Without change: 41.3 fps, escort wait_move at 40% of aiscript hits.
    - Retest change: 42.8 fps
    - Retest no change: 40.8 fps
    - Retest change: 43.1
    Around a 2 fps boost, or 5%.
    '''
    if not empty_diffs:
        wait_node = xml_root.find('./attention[@min="unknown"]/actions/wait[@exact="500ms"]')
        wait_node.set('exact', '5s')
    game_file.Update_Root(xml_root)
    return


@Transform_Wrapper()
def Delete_Faction_Logic(empty_diffs = 0):
    '''
    Clears out faction logic cues entirely.
    Test result: no change.
    '''
    '''
    Testing using same setup as above (eg. 3x jobs):
    - Baseline: 43.4 fps
    - Changed: 45.8 fps
    '''
    md_files = Load_Files('md/faction*.xml')
    
    for game_file in md_files:
        xml_root = game_file.Get_Root()

        # Do this on every cue and library, top level.
        changed = False
        for tag in ['cue', 'library']:
            nodes = xml_root.xpath("./cues/{}".format(tag))
            if not nodes:
                continue

            changed = True
            if empty_diffs:
                continue

            for node in nodes:
                # Delete this node.
                node.getparent().remove(node)

        if changed:
            # Commit changes right away; don't bother delaying for errors.
            game_file.Update_Root(xml_root)

    return



@Transform_Wrapper()
def Remove_Moves(empty_diffs = 0):
    '''
    Replace all move commands with waits.
    '''
    '''
    Test on 20k ships save above trinity sanctum.
    without edit: 32 fps
    with edit   : 45->~60 fps (gradually climbing over time)~
    '''
    aiscript_files = Load_Files('aiscripts/*.xml')
    #aiscript_files = [Load_File('aiscripts/order.fight.escort.xml')]
    
    for game_file in aiscript_files:
        xml_root = game_file.Get_Root()
        file_name = game_file.name.replace('.xml','')
        
        if not empty_diffs:
            # All moves.
            for tag in [
                'move_approach_path',
                'move_docking',
                'move_undocking',
                'move_gate',
                'move_navmesh',
                'move_strafe',
                'move_target_points',
                'move_waypoints',
                'move_to',
                ]:
                nodes = xml_root.xpath(".//{}".format(tag))
                if not nodes:
                    continue

                for node in nodes:
                    # Create a wait node, of some significant duration.
                    wait = Element('wait', exact='30s')
                    node.getparent().replace(node, wait)
                    assert not wait.tail
                    
        game_file.Update_Root(xml_root)
                    
    return



@Transform_Wrapper()
def Simpler_Moves(empty_diffs = 0):
    '''
    Change all moves to use a linear flight model.
    '''
    '''
    Test on 20k ships save above trinity sanctum.
    without edit: 32 fps (reusing above)
    with edit   : 30.5 fps (probably in the noise).
    No real difference.
    '''
    
    '''
    Unitrader suggestion:
    "<set_flight_control_model object="this.ship" flightcontrolmodel="flightcontrolmodel.linear"/> 
    before every movement command (and remove all @forcesteering if present)"
    '''

    aiscript_files = Load_Files('aiscripts/*.xml')
    #aiscript_files = [Load_File('aiscripts/order.fight.escort.xml')]
    
    for game_file in aiscript_files:
        xml_root = game_file.Get_Root()
        file_name = game_file.name.replace('.xml','')
        
        if not empty_diffs:
            # All moves.
            for tag in [
                'move_approach_path',
                'move_docking',
                'move_undocking',
                'move_gate',
                'move_navmesh',
                'move_strafe',
                'move_target_points',
                'move_waypoints',
                'move_to',
                ]:
                nodes = xml_root.xpath(".//{}".format(tag))
                if not nodes:
                    continue

                for node in nodes:
                    # Prepend with the set_flight_control_model.
                    flight_node = Element(
                        'set_flight_control_model', 
                        object = "this.ship",
                        flightcontrolmodel = "flightcontrolmodel.linear")
                    node.set('forcesteering', 'false')
                    node.addprevious(flight_node)
                    assert not flight_node.tail
                    
        game_file.Update_Root(xml_root)
                    
    return




# Note: moved to customizer, with more polish.
@Transform_Wrapper()
def Increase_Waits(multiplier = 10, filter = '*', empty_diffs = 0):
    '''
    Multiply the duration of all wait statements.

    * multiplier
      - Float, factor to increase wait times by.
    * filter
      - String, possibly with wildcards, matching names of ai scripts to
        modify; default is plain '*' to match all aiscripts.
    '''
    '''
    Test on 20k ships save above trinity sanctum.
    without edit   : 32 fps (reusing above; may be low?)
    with 10x       : 50 fps (immediate benefit)
    just trade 10x : 37 fps
    with 2x        : 46 fps

    Success!  (idea: can also scale wait by if seta is active)
    '''
    
    # Just ai scripts; md has no load.
    aiscript_files = Load_Files(f'aiscripts/{filter}.xml')
    #aiscript_files = [Load_File('aiscripts/order.fight.escort.xml')]
    
    for game_file in aiscript_files:
        xml_root = game_file.Get_Root()
        file_name = game_file.name.replace('.xml','')
        
        if not empty_diffs:
            nodes = xml_root.xpath(".//wait")
            if not nodes:
                continue

            for node in nodes:
                for attr in ['min','max','exact']:
                    orig = node.get(attr)
                    if orig:
                        # Wrap the old value or expression, and multiply.
                        node.set(attr, f'({node.get(attr)})*{multiplier}')
                    
        game_file.Update_Root(xml_root)
                    
    return


@Transform_Wrapper()
def Decrease_Radar(empty_diffs = 0):
    '''
    Reduce radar ranges, to reduce some compute load for npc ships.
    '''
    '''
    Test on 20k ships save above trinity sanctum.
    5/4    : 35 fps   (50km)
    1/1    : 37 fps   (40km, vanilla, fresh retest)
    3/4    : 39 fps   (30km, same as x3 triplex)
    1/2    : 42 fps   (20km, same as x3 duplex)
    1/4    : 46 fps   (10km, probably too short)

    TODO: small ships 20k, large ships 30k, very large 40k?
    '''
    game_file = Load_File('libraries/defaults.xml')
    xml_root = game_file.Get_Root()

    for node in xml_root.xpath('.//radar'):
        range = node.get('range')
        if range:
            range = float(range)
            node.set('range', str(range * 2/4))
    game_file.Update_Root(xml_root)
    return

# TODO: remove; moved to separate extension.
@Transform_Wrapper()
def Decrease_Fog(empty_diffs = 0):
    '''
    Try methods of reducing fog impact on fps.
    '''
    '''
    Test in heart of acrymony fog cloud, cockpit hidden.
    Baseline: 9.5fps
    Fog removed: 91 fps

    Note:
        heart of acrynomy uses fog_outside_set1_whiteblue which uses
        p1fogs.fog_04_alpha_dim.

    Attempt 1:
        Edit the material draw distance to reduce it.
        Fog fades in at 45-55km normally.
        Can reduce way down, eg. 10-15km, to see if that reduces the number
        of fog effects drawn.

        Result: no noticeable fps change (maybe +0.25).

    Attempt 2:
        Switch texture to a transparent one; maybe no load?

        Result: still 9.5, fog is white, but much more opaque and with
        obvious texture boundaries (so uglier).
        
    Attempt 3:
        Delete the fog component file connection to the material entry.

        Result: 91 fps.  Success, but no fog left.
        
    Attempt 4:
        Reduce density of the region. Heart of acrymony is notably density 1
        where most fog effects are much lower density.

        Result: 
            0.3:  fps
            0.2:  fps
            0.1:  fps

    Attempt ?:
        TODO
        Swap in cheaper fog material files?
    '''
    # These didnt help.
    if 0:
        material_file = Load_File('libraries/material_library.xml')
        xml_root = material_file.Get_Root()

        fade_distance_mult = 0.2
    
        # Search all materials.
        # TODO: maybe pick selective fogs that are the most expensive.
        for node in xml_root.xpath('.//material'):
            # Skip anything without fog in the name.
            if 'fog_' not in node.get('name'):
                continue

            # Edit the fades.
            if 0:
                for attr in [
                    'camera_fade_range_far_start', 
                    # Why is this sometimes end and sometimes stop?
                    'camera_fade_range_far_end',
                    'camera_fade_range_far_stop']:
                    # Find the param.
                    property = node.find(f'./properties/property[@name="{attr}"]')
                    if property == None:
                        continue
                    value = float(property.get('value'))
                    # Reduce it.
                    # TODO: maybe dont reduce stuff already close range.
                    new_value = value * fade_distance_mult
                    property.set('value', f'{new_value:.1f}')
            
            if 0:
                # Change all bitmaps to use assets\textures\fx\transparent_diff
                for bitmap in node.xpath("./properties/property[@type='BitMap']"):
                    bitmap.set('value', r'assets\textures\fx\transparent_diff')
            
        material_file.Update_Root(xml_root)

    # Great, but removes all fog.
    if 0:
        # Look up fog components.
        for game_file in Get_All_Indexed_Files('components', 'fog_outside_*'):
            xml_root = game_file.Get_Root()
            # Find the connections with the materials (probably just one).
            for conn in xml_root.xpath('./component/connections/connection[.//material]'):
                conn.getparent().remove(conn)
            game_file.Update_Root(xml_root)

    if 1:
        game_file = Load_File('libraries/region_definitions.xml')
        xml_root = game_file.Get_Root()

        # Different scalings are possible.
        # This will try to somewhat preserve relative fog amounts.

        for positional in xml_root.xpath('.//positional'):
            # Skip non-fog
            if not positional.get('ref').startswith('fog_outside_'):
                continue
            # Density is between 0 and 1.
            density = float(positional.get('densityfactor'))

            # Rescale. Dont touch below 10%.
            if 0:
                if density < 0.1:
                    continue
                diff = density - 0.1
                new_diff = diff / 4
                new_density = new_diff + 0.1
            if 0:
                new_density = ((density * 100)**0.5) / 100
            if 0:
                # In case density was >1, add some safety here, capping
                # at -80%.
                reduction_factor = min(0.8, 0.8 * density)
                new_density = density *(1 - reduction_factor)
            if 1:
                max_size = 0.0
                if density < max_size:
                    continue
                new_density = max_size

            positional.set('densityfactor', f'{new_density:.4f}')

        game_file.Update_Root(xml_root)

    return


# TODO: mysterial found (and mewosmith reported) that stations never forget
# targets, and get an ever expanding list of targets they constantly
# search through.  Find such cases, fix them, check difference.

# Run the transform.
#Tweak_Escorts()
#Remove_Debug()
#Delete_Faction_Logic()

#Remove_Moves()
#Simpler_Moves()
#Increase_Waits(multiplier = 10)
#Decrease_Radar()

# Just ai waits.
#Increase_Waits(filter = '*trade.*')

# Smaller wait multiplier.
#Increase_Waits(multiplier = 2)

#Decrease_Fog()

Write_To_Extension(skip_content = True)
