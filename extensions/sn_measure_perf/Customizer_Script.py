
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
from Framework import Transform_Wrapper, Load_File, Load_Files

Settings(
    # Set the path to the X4 installation folder.
    path_to_x4_folder   = r'C:\Steam\SteamApps\common\X4 Foundations',
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
'''

# Note: can try testing with this removed from command line:
#  -logfile debuglog.txt -debug general

time_format = '%Y-%j-%H-%M-%S'

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


def Get_First_Source_Line(node):
    'Returns a sourceline int, or empty string, the first for a node.'
    return node.sourceline if node.sourceline else ''

def Get_Last_Source_Line(node):
    '''
    Returns a sourceline int, or empty string, the last for a node or children.
    This will handle, eg. do_all nodes with many children.
    '''
    sourceline = None
    for subnode in node.iter():
        if subnode.sourceline and (not sourceline or subnode.sourceline > sourceline):
            sourceline = subnode.sourceline
    return str(sourceline) if sourceline else ''


def Insert_Timestamp(
        section_name,
        location_name,
        path_bound,
        node,
        op,
    ):
    '''
    Inserts a new timestamp node, a raise_lua_event sending player.systemtime.

    * section_name
      - String declaring the file and possibly the section of interest.
      - Time deltas for paths will only be collected in matching section_names.
      - The section shouldn't have un-annotated entry or exit points, except
        to immediately evaluated subfunctions (libs).
    * location_name
      - Descriptive name of the location, typically including line number.
    * path_bound 
      - One of "entry"/"mid"/"exit", based on if this is known to start
        or exit a section, with mid points optional.
    * node
      - Element to act as the base for the annocation insertion.
    * op
      - One of "before"/"after"/"firstchild"/"lastchild", where to insert
        the annotation.
    * new_node
      - Created new node, inserted, provided for any debug reference.
    '''
    # Signal lua, appending the time of the event.
    new_node = etree.fromstring(f''' <raise_lua_event 
        name  = "'Measure_Perf.Record_Event'"
        param = "'{section_name},{location_name},{path_bound},' + player.systemtime.{{'{time_format}'}} "
        />''')

    # Handle insertion.
    if op == 'before':
        node.addprevious(new_node)
    elif op == 'after':
        node.addnext(new_node)
        # addnext moves the tail, and hence node_id; fix it here.
        if new_node.tail != None:
            node.tail = new_node.tail
            new_node.tail = None
    elif op == 'firstchild':
        node.insert(0, new_node)
    elif op == 'lastchild':
        node.append(new_node)
    assert new_node.tail == None
    return



# -Removed; switching to detailed timestamp profiler.
#@Transform_Wrapper()
#def Annotate_AI_Scripts(empty_diffs = 0):
#    '''
#    For every ai script, annotate the pilot entity with the name
#    of the script running.
#    '''
#    aiscript_files = Load_Files('aiscripts/*.xml')
#    
#    for game_file in aiscript_files:
#        xml_root = game_file.Get_Root()
#
#        # Do this on every blocking action command.
#        # TODO: for perf profile, also should get script entry/exit,
#        # interrupts, etc.
#        changed = False
#        for tag in [
#            'dock_masstraffic_drone',
#            'execute_custom_trade',
#            'execute_trade',
#            'move_approach_path',
#            'move_docking',
#            'move_undocking',
#            'move_gate',
#            'move_navmesh',
#            'move_strafe',
#            'move_target_points',
#            'move_waypoints',
#            'move_to',
#            'detach_from_masstraffic',
#            'wait_for_prev_script',
#            'wait',
#            ]:
#            nodes = xml_root.xpath(".//{}".format(tag))
#            if not nodes:
#                continue
#
#            changed = True
#            if empty_diffs:
#                continue
#
#            for node in nodes:
#
#                # Before the wait, write to the pilot the file name.
#                script_name = etree.Element('set_value', 
#                    name = 'this.$script_name', 
#                    # File name, in extra quotes.
#                    exact = "'{}'".format(game_file.name.replace('.xml','')))
#                node.addprevious(script_name)
#
#                # Blocking action may be of interest.
#                element_name = etree.Element('set_value', 
#                    name = 'this.$element_name',
#                    exact = "'{}'".format(tag))
#                node.addprevious(element_name)
#
#                # Version of script name with the line number, and node tag.
#                # Can only do this for blocking elements that have a line.
#                if node.sourceline:
#                    name_line = "'${} {} {}'".format(
#                        game_file.name.replace('.xml',''),
#                        # lxml starts at 2?
#                        node.sourceline,
#                        tag)
#
#                    script_line_node = etree.Element('set_value', 
#                        name = 'this.$script_line_name', 
#                        # File name, in extra quotes, followed by line.
#                        exact = name_line)
#                    node.addprevious(script_line_node)
#
#                    # More complicated: set the pilot to count how many
#                    # times each script/line block was reached.
#                    # This is likely to better represent hot code that just
#                    # the number of ai ships sitting on some blocking action.
#                    record_group = [
#                        etree.fromstring('''
#                            <do_if value="not this.$script_line_hits?">
#                              <set_value name="this.$script_line_hits" exact="table[]"/>
#                            </do_if>'''),
#                        # Can accumulate a long time, so use a float or long int.
#                        etree.fromstring('''
#                            <do_if value="not this.$script_line_hits.{FIELD}?">
#                              <set_value name="this.$script_line_hits.{FIELD}" exact="0"/>
#                            </do_if>'''.replace('FIELD', name_line)),
#                        etree.fromstring(('''
#                            <set_value name="this.$script_line_hits.{FIELD}" operation="add"/>'''
#                            ).replace('FIELD', name_line)),
#                    ]
#                    for record_node in record_group:
#                        node.addprevious(record_node)
#
#
#        if changed:
#            # Commit changes right away; don't bother delaying for errors.
#            game_file.Update_Root(xml_root)
#    return


@Transform_Wrapper()
def Annotate_AI_Scripts(empty_diffs = 0):
    '''
    For every ai script, add timestamps at entry, exit, and blocking nodes.
    Test result: ego ai scripts take ~6% of computation, at least for
    the bodies, with a vanilla 10hr save. Condition checks not captured.
    '''
    aiscript_files = Load_Files('aiscripts/*.xml')
    #aiscript_files = [Load_File('aiscripts/masstraffic.watchdog.xml')]
    
    for game_file in aiscript_files:
        xml_root = game_file.Get_Root()
        file_name = game_file.name.replace('.xml','')
        
        if not empty_diffs:
            # All normal blocking nodes (return to this script when done).
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
                'run_script',
                'run_order_script',
                'wait_for_prev_script',
                'wait',
                ]:
                nodes = xml_root.xpath(".//{}".format(tag))
                if not nodes:
                    continue

                # All of these nodes need timestamps on both sides.
                for node in nodes:
                    # Pick out the entry/exit lines for annotation.
                    # (Do these nodes even have children?  Maybe; be safe.)
                    first_line = Get_First_Source_Line(node)
                    last_line  = Get_Last_Source_Line(node)

                    # Above the node exits a path; below the node enters a path.
                    Insert_Timestamp(
                        f'ai.{file_name}', 
                        f'{node.tag} {first_line}', 
                        'exit', node, 'before')
                    Insert_Timestamp(
                        f'ai.{file_name}', 
                        f'{node.tag} {last_line}', 
                        'entry' , node, 'after')
                

            # Special exit points.
            # Script can hard-return with a return node.
            for tag in ['return']:
                nodes = xml_root.xpath(".//{}".format(tag))
                if not nodes:
                    continue

                # Just timestamp the visit.
                for node in nodes:
                    first_line = Get_First_Source_Line(node)
                    Insert_Timestamp(
                        f'ai.{file_name}', 
                        f'{node.tag} {first_line}', 
                        'exit', node, 'before')


            # TODO:
            # Possible mid points:
            # -label
            # -resume
            # 

            # Blocks of actions can show up in:
            # -attention (one actions child)
            # -libraries (multiple actions children possible, each named)
            # -interrupts (may or may not have an actions block)
            # -handler (one block of actions, no name on this or handler)
            # -on_attentionchange (in theory; no examples seen)
            # Of these, all but libraries should start/end paths.
        
            # init blocks also have actions, though not labelled as such.
            # on_abort is similar.
            for tag in ['actions','init','on_abort']:
                nodes = xml_root.xpath(f'.//{tag}')

                for node in nodes:
                    # Skip if empty.
                    if len(node) == 0:
                        continue

                    # Skip if action parent is a libary.
                    # TODO: look into if libs can have blocking actions; if not,
                    # can set these up with a separate category name.
                    if tag == 'actions' and node.getparent().tag == 'library':
                        continue

                    # Pick out the entry/exit lines for annotation.
                    first_line = Get_First_Source_Line(node[0])
                    last_line  = Get_Last_Source_Line(node[-1])

                    Insert_Timestamp(
                        f'ai.{file_name}', 
                        f'{node.tag} entry {first_line}', 
                        'entry', node, 'firstchild')
                    Insert_Timestamp(
                        f'ai.{file_name}', 
                        f'{node.tag} exit {last_line}', 
                        'exit' , node, 'lastchild')

        game_file.Update_Root(xml_root)
    return


@Transform_Wrapper()
def Annotate_MD_Scripts(empty_diffs = 0):
    '''
    For every md script, add performance measuring nodes.
    Test result: ego md only uses ~0.5% of the compute time, so
    not of particular potential for optimization.
    This may vary with other setups or extensions.
    '''
    '''
    Basic idea:
    - At various points, gather a time sample.
    - Pass samples to lua.
    - Separate lua script computes time deltas between points, sums
      path delays and hits (and hits at gather points), etc.
    '''
    # TODO: maybe include extension files in general.
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
            first_line = Get_First_Source_Line(actions_node[0])
            last_line  = Get_Last_Source_Line(actions_node[-1])

            # Entry/exit redundant for now, but will differ for
            # specific nodes.
            Insert_Timestamp(f'md.{file_name}.{cue_name}', f'entry {first_line}', 'entry', actions_node, 'firstchild')
            Insert_Timestamp(f'md.{file_name}.{cue_name}', f'exit {last_line}'  , 'exit' , actions_node, 'lastchild')
                

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


def Test_Time_Deformatter():
    '''
    Runs a test on the deformatting routine for formatted time values,
    primarily focused on getting leap year handling correct.
    Test result: success.
    '''
    from datetime import datetime
    start = datetime(1970,1,1)
    for base_year in range(1970, 3000):

        # Get a reference.
        date = datetime(base_year, 1, 1)
        ref_seconds = (date - start).total_seconds()
        # Also represent as hours/days for debug comparison.
        ref_hours = ref_seconds / 3600
        ref_days  = ref_hours / 24
        ref_leap_years = ref_days % 365
        ref_years = base_year - 1970

        # Construct the string.
        time_str = date.strftime(time_format)

        # Run manual decoding.
        year_str, day_str, hour_str, min_str, sec_str = time_str.split('-')

        year = int(year_str)
        years = year - 1970

        # Leap years start in 1972. This means the first leap has passed
        # in 1973 (since want to know an extra day was missed).
        # Can offset by +1, divide by 4, so first leap is at (3+1).
        leap_years = (years + 1) // 4
        # Every 100 years is a skipped leap, except every 400 years which
        # retain the leap.
        # Only check this past 2000, to avoid dealing with negatives.
        if year > 2000:
            # Start by removing the 100 entries. First occurrence at 2001,
            # so offset +(100-31)=69.
            leap_years -= (years + 69) // 100
            # Undo every 400, first occurrence also at 2001, so offset +369.
            leap_years += (years + 369) // 400

        # Continue with simple stuff.
        # Day counter starts at 1, so adjust that back.
        days  = (int(day_str) - 1) + 365 * years + leap_years
        hours = int(hour_str) + 24 * days
        mins = int(min_str) + 60 * hours
        secs = int(sec_str) + 60 * mins
        
        assert leap_years == ref_leap_years
        assert days == ref_days
        assert hours == ref_hours
        assert secs == ref_seconds

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


# TODO: mysterial found (and mewosmith reported) that stations never forget
# targets, and get an ever expanding list of targets they constantly
# search through.  Find such cases, fix them, check difference.

# Run the transform.
#Tweak_Escorts()
#Remove_Debug()
#Delete_Faction_Logic()

# Profiling related. Note: causes some slowdown for timestamp gather.
#Test_Time_Deformatter()
#Annotate_AI_Scripts()
#Annotate_MD_Scripts()

#Remove_Moves()
#Simpler_Moves()
#Increase_Waits(multiplier = 10)
#Decrease_Radar()

# Just ai waits.
#Increase_Waits(filter = '*trade.*')

# Smaller wait multiplier.
#Increase_Waits(multiplier = 2)

Write_To_Extension(skip_content = True)
