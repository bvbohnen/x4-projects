
import sys
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
from Framework import Transform_Wrapper, Load_File, Load_Files

Settings(
    # Set the path to the X4 installation folder.
    path_to_x4_folder   = r'C:\Steam\SteamApps\common\X4 Foundations',
    # Generate the extension here.
    path_to_output_folder = this_dir.parent,
    extension_name = this_dir.name,
    developer = True,
    )

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
def Annotate_AI_Scripts(empty_diffs = 0):
    '''
    For every ai script, annotate the pilot entity with the name
    of the script running.
    '''
    aiscript_files = Load_Files('aiscripts/*.xml')
    
    for game_file in aiscript_files:
        xml_root = game_file.Get_Root()

        # Do this on every blocking action command.
        # TODO: for perf profile, also should get script entry/exit,
        # interrupts, etc.
        changed = False
        for tag in [
            'dock_masstraffic_drone',
            'execute_custom_trade',
            'execute_trade',
            'move_approach_path',
            'move_docking',
            'move_undocking',
            'move_gate',
            'move_navmesh',
            'move_strafe',
            'move_target_points',
            'move_waypoints',
            'move_to',
            'detach_from_masstraffic',
            'wait_for_prev_script',
            'wait',
            ]:
            nodes = xml_root.xpath(".//{}".format(tag))
            if not nodes:
                continue

            changed = True
            if empty_diffs:
                continue

            for node in nodes:

                # Before the wait, write to the pilot the file name.
                script_name = etree.Element('set_value', 
                    name = 'this.$script_name', 
                    # File name, in extra quotes.
                    exact = "'{}'".format(game_file.name.replace('.xml','')))
                node.addprevious(script_name)

                # Blocking action may be of interest.
                element_name = etree.Element('set_value', 
                    name = 'this.$element_name',
                    exact = "'{}'".format(tag))
                node.addprevious(element_name)

                # Version of script name with the line number, and node tag.
                # Can only do this for blocking elements that have a line.
                if node.sourceline:
                    name_line = "'${} {} {}'".format(
                        game_file.name.replace('.xml',''),
                        # lxml starts at 2?
                        node.sourceline,
                        tag)

                    script_line_node = etree.Element('set_value', 
                        name = 'this.$script_line_name', 
                        # File name, in extra quotes, followed by line.
                        exact = name_line)
                    node.addprevious(script_line_node)

                    # More complicated: set the pilot to count how many
                    # times each script/line block was reached.
                    # This is likely to better represent hot code that just
                    # the number of ai ships sitting on some blocking action.
                    record_group = [
                        etree.fromstring('''
                            <do_if value="not this.$script_line_hits?">
                              <set_value name="this.$script_line_hits" exact="table[]"/>
                            </do_if>'''),
                        # Can accumulate a long time, so use a float or long int.
                        etree.fromstring('''
                            <do_if value="not this.$script_line_hits.{FIELD}?">
                              <set_value name="this.$script_line_hits.{FIELD}" exact="0"/>
                            </do_if>'''.replace('FIELD', name_line)),
                        etree.fromstring(('''
                            <set_value name="this.$script_line_hits.{FIELD}" operation="add"/>'''
                            ).replace('FIELD', name_line)),
                    ]
                    for record_node in record_group:
                        node.addprevious(record_node)


        if changed:
            # Commit changes right away; don't bother delaying for errors.
            game_file.Update_Root(xml_root)
    return

def Get_Source_Line(node):
    'Returns a sourceline int, or empty string.'
    return node.sourceline if node.sourceline else ''

@Transform_Wrapper()
def Annotate_MD_Scripts(empty_diffs = 0):
    '''
    For every md script, add performance measuring nodes.
    '''
    '''
    Basic idea:
    - At various points, gather a time sample.
    - Pass samples to lua.
    - Separate lua script computes time deltas between points, sums
      path delays and hits (and hits at gather points), etc.
    - Need to 
    '''
    md_files = Load_Files('md/*.xml')
    
    for game_file in md_files:
        xml_root = game_file.Get_Root()

        file_name = game_file.name.replace('.xml','')

        # Gather a list of sample points.
        # These will be tuples of 
        # (section_name, location_name, path_bound "entry"/"mid"/"exit", node, 
        #  "before"/"after"/"firstchild"/"lastchild").
        # Where section_name should have the file_name, and a suffix
        # for the cue/lib involved, so that timers can be matched up
        # across lib calls from a cue.
        sample_points = []
        
        # Entering/exiting any action block. Include cue/lib name.
        actions_nodes = xml_root.xpath('.//actions')
        for actions_node in actions_nodes:
            cue_name = actions_node.getparent().get('name')

            # Skip if empty.
            if len(actions_node) == 0:
                continue

            # Pick out the entry/exit lines for annotation.
            first_line = Get_Source_Line(actions_node[0])
            last_line  = Get_Source_Line(actions_node[-1])

            sample_points+= [
                # Entry/exit redundant for now, but will differ for
                # specific nodes.
                (f'md.{file_name}.{cue_name}', f'entry {first_line}', 'entry', actions_node, 'firstchild'),
                (f'md.{file_name}.{cue_name}', f'exit {last_line}'  , 'exit' , actions_node, 'lastchild'),
                ]

        # TODO: if/else forks/joins.

        for section_name, location_name, path_bound, node, op in sample_points:

            # Signal lua, appending the time of the event.
            new_node = etree.fromstring(f''' <raise_lua_event 
                name  = "'Measure_Perf.Record_Event'"
                param = "'{section_name},{location_name},{path_bound}' + player.systemtime.{{'%G-%j-%H-%M-%S'}} "
                />''')

            # Handle insertion.
            if op == 'before':
                node.addprevious(new_node)
            elif op == 'after':
                node.addnext(new_node)
            elif op == 'firstchild':
                node.insert(0, new_node)
            elif op == 'lastchild':
                node.append(new_node)

        # -Removed, old style just counted visits, with no timing.
        ## Do this on every cue and library, including nestings.
        ## TODO: also flag every major control flow fork/join, eg. inside
        ## each do_if/else path and just after join.
        #changed = False
        #for tag in ['cue', 'library']:
        #    nodes = xml_root.xpath(".//{}".format(tag))
        #    if not nodes:
        #        continue
        #
        #    changed = True
        #    if empty_diffs:
        #        continue
        #
        #    for node in nodes:
        #
        #        # This doesn't really need to know sourceline, but include
        #        # it if handy.
        #        if node.sourceline:
        #            line_num = node.sourceline
        #        else:
        #            # In this case, it is likely from a diff patch.
        #            line_num = ''
        #
        #        # Include: file name, cue/lib name, line.
        #        # Update: gets too cluttered; just do file and cue/lib name.
        #        name_line = "'${} {}'".format(
        #            game_file.name.replace('.xml',''), 
        #            #tag,
        #            node.get('name'),
        #            #node.sourceline,
        #            )
        #
        #        # Need to add subcues to actions.
        #        actions = node.find('./actions')
        #        # If there are no actions for some reason, eg. it is
        #        # the parent of some child cues, then skip.
        #        if actions == None:
        #            continue
        #
        #        # Set up the counter.
        #        record_group = [
        #            etree.fromstring('''
        #                <do_if value="not md.SN_Measure_Perf.Globals.$md_cue_hits?">
        #                    <set_value name="md.SN_Measure_Perf.Globals.$md_cue_hits" exact="table[]"/>
        #                </do_if>'''),
        #            # Can accumulate a long time, so use a float or long int.
        #            etree.fromstring('''
        #                <do_if value="not md.SN_Measure_Perf.Globals.$md_cue_hits.{FIELD}?">
        #                    <set_value name="md.SN_Measure_Perf.Globals.$md_cue_hits.{FIELD}" exact="0"/>
        #                </do_if>'''.replace('FIELD', name_line)),
        #            etree.fromstring(('''
        #                <set_value name="md.SN_Measure_Perf.Globals.$md_cue_hits.{FIELD}" operation="add"/>'''
        #                ).replace('FIELD', name_line)),
        #        ]
        #        for record_node in record_group:
        #            actions.append(record_node)

        # Commit changes right away; don't bother delaying for errors.
        game_file.Update_Root(xml_root)
    return


@Transform_Wrapper()
def Tweak_Escorts(empty_diffs = 0):
    '''
    Adjust escort scripts to fire less often.
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

# TODO:
# - Change factionlogic.EvaluateForceStrength to just return basic 1 values.
# - Change delays on various faction logic cue loops, eg. 10s to 1 minute.

# Run the transform.
#Tweak_Escorts()
#Remove_Debug()
#Annotate_AI_Scripts()
Annotate_MD_Scripts()
#Delete_Faction_Logic()

Write_To_Extension(skip_content = True)
