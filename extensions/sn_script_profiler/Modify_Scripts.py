'''
This python script will use the X4 Customizer to set up the md and ai scripts
for profiling.  Automatically generates suitable diff patches.

The X4 Customizer is assumed to be 3 directories up in a X4_Customizer folder.

To tune behavior, see settings.json.
'''

import sys
from lxml import etree
from lxml.etree import Element
from pathlib import Path
import configparser
this_file = Path(__file__).resolve()
this_dir = this_file.parent

# When run directly, set up the customizer import.
if __name__ == '__main__':
    # Set up the customizer import.
    project_dir = this_file.parents[2]
    x4_customizer_dir = str(project_dir.parent / 'X4_Customizer')
    if x4_customizer_dir not in sys.path:
        sys.path.append(x4_customizer_dir)

        
# Import all transform functions.
from Plugins import *
from Framework import Transform_Wrapper, Load_File, Load_Files

# The systime print format to use.
time_format = '%Y-%j-%H-%M-%S'


def Run():
    '''
    Setup the customized scripts.
    '''
    # Load settings from the ini file(s).
    # Defaults are in settings_defaults.ini
    # User overrides are in settings.ini (may or may not exist).
    config = configparser.ConfigParser()
    config.read([this_dir/'config_defaults.ini', this_dir/'config.ini'])

    # Set customizer settings.
    Settings(
        # Generate the extension here.
        path_to_output_folder = this_dir.parent,
        extension_name = this_dir.name,
        developer = True, )

    # Set the path to the X4 installation folder.
    if config['General']['x4_path']:
        Settings(path_to_x4_folder = config['General']['x4_path'])

    # Evaluate the patterns to collect all files.
    game_files = []
    for field, pattern in config['Scripts'].items():

        # Make sure the pattern ends in xml.
        if not pattern.endswith('.xml'):
            pattern += '.xml'

        # Filter out duplicates (generally not expected, but can happen).
        for file in Load_Files(pattern):
            if file not in game_files:
                game_files.append(file)

    # Separate into aiscript and md files.
    ai_files = []
    md_files = []
    for file in game_files:
        path = file.virtual_path
        if '/' not in path:
            continue
        folder = path.split('/')[-2]
        if folder == 'aiscripts':
            ai_files.append(file)
        elif folder == 'md':
            md_files.append(file)
            
    # Hand off to helper functions.
    Annotate_Scripts(ai_files, style = 'ai')
    Annotate_Scripts(md_files, style = 'md')

    # Ensure any extensions being modified are set as dependencies.
    Update_Content_XML_Dependencies()
    Write_To_Extension(skip_content = True)
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
        name  = "'Script_Profiler.Record_Event'"
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


def Get_MD_Block_Name(node):
    '''
    For md xml nodes, return their parent cue or lib name.
    '''
    # Search parents upward until a match.
    test_node = node.getparent()
    while 1:
        if test_node.tag in ['cue', 'library']:
            return test_node.get('name')
        test_node = test_node.getparent()
        if test_node == None:
            return ''


@Transform_Wrapper()
def Annotate_Scripts(files, style):
    '''
    For every ai script, add timestamps at entry, exit, and blocking nodes.

    Note: while libraries can potentially be called directly without the
    caller being full interrupted, they will be treated as fully separate
    blocks, since ai libraries may have blocking actions and not return
    right away, and md libraries may be used as cue templates and not
    just as include_actions calls.
    '''
    # All normal blocking nodes (return to this script when done), and
    # places where scope moves to a different action block with its
    # own start/end.
    # These will get wrapped with an exit point before, entry point after.
    if style == 'ai':
        interrupts = [
            # Blocking actions (explicitly tagged)
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

            # The following are not tagged as blocking, but do cause control
            # flow change or similar.
            # Created orders appear to run right away.
            'create_order',
            # May not block, but starts a new action block.
            'include_interrupt_actions',
            'run_interrupt_script',
            # This command suggests it will exit an interrupt block to
            # go to a label. Unclear in documentation, but it may have a
            # delay before continuing at the label, so treat as blocking.
            'abort_called_scripts',
            # Since labels can be jumped to, possible after a delay from
            # abort_called_scripts, can be extra safe by treating all labels
            # as potential entry points (and hence set as exit points for
            # the prior path).
            'label',
            # This means resumes also need to be treated as path endpoints.
            'resume',
        ]
    else:
        # TODO: alternative to sticking endpoints on these, instead set a
        # global flag that suppresses path start/end in the callees.
        interrupts = [
            'include_actions',
            'run_actions',
            'signal_cue_instantly',
            # Signalling objects will also instantly activate cues listening
            # to that object being signalled.
            'signal_objects',
            ]
        
    for game_file in files:
        xml_root = game_file.Get_Root()
        file_name = game_file.name.replace('.xml','')

        for tag in interrupts:
            nodes = xml_root.xpath(".//{}".format(tag))
            if not nodes:
                continue

            # All of these nodes need timestamps on both sides.
            for node in nodes:

                # Pick out the entry/exit lines for annotation.
                # (Do these nodes even have children?  Maybe; be safe.)
                first_line = Get_First_Source_Line(node)
                last_line  = Get_Last_Source_Line(node)

                # Note: if this node is inside a do_any block, cannot easily
                # slot in timestamps. Either timestampe the parent do_any,
                # which can lead to other do_any children going unmeasured, or
                # nest this node in a do_all, transfer any weight property
                # to the do_all, and put the timestamping inside the do_all.
                if node.getparent().tag == 'do_any':
                    do_all = Element('do_all')
                    if node.get('weight'):
                        do_all.set('weight', node.get('weight'))
                        del(node.attrib['weight'])
                    node.getparent().replace(node, do_all)
                    do_all.append(node)
                    assert do_all.tail == None
                    # Switch to the do_all for further logic.
                    node = do_all

                # For md, get the parent cue/lib name to add to
                # the location.
                block_name = ''
                if style == 'md':
                    block_name = Get_MD_Block_Name(node)
                    if block_name:
                        block_name += ' '

                # Above the node exits a path; below the node enters a path.
                # TODO: add {block_name} to the section name, once confident
                # that it won't lead to accidents on missing entry/exit points,
                # for a cleaner printout.
                Insert_Timestamp(
                    f'{style}.{file_name}', 
                    f'{block_name}{node.tag} exit {first_line}',
                    'exit', node, 'before')
                Insert_Timestamp(
                    f'{style}.{file_name}', 
                    f'{block_name}{node.tag} entry {last_line}', 
                    'entry' , node, 'after')
                

        # Special exit points; aiscript only.
        # Script can hard-return with a return node.
        for tag in ['return']:
            nodes = xml_root.xpath(".//{}".format(tag))
            if not nodes:
                continue

            # Just timestamp the visit.
            for node in nodes:
                first_line = Get_First_Source_Line(node)
                Insert_Timestamp(
                    f'{style}.{file_name}', 
                    f'{node.tag} exit {first_line}', 
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
        
        # "init" blocks also have actions, though not labelled as such.
        # "on_abort" is similar.
        for tag in ['actions','init','on_abort']:
            nodes = xml_root.xpath(f'.//{tag}')

            for node in nodes:
                # Skip if empty.
                if len(node) == 0:
                    continue

                # Pick out the entry/exit lines for annotation.
                first_line = Get_First_Source_Line(node[0])
                last_line  = Get_Last_Source_Line(node[-1])
                
                # For md, get the parent cue/lib name to add to
                # the location.
                block_name = ''
                if style == 'md':
                    block_name = Get_MD_Block_Name(node)
                    if block_name:
                        block_name += ' '
                        
                # TODO: add {block_name} to the section name.
                Insert_Timestamp(
                    f'{style}.{file_name}', 
                    f'{block_name}{node.tag} entry {first_line}', 
                    'entry', node, 'firstchild')
                Insert_Timestamp(
                    f'{style}.{file_name}', 
                    f'{block_name}{node.tag} exit {last_line}', 
                    'exit' , node, 'lastchild')


        # Cleanup pass to clear out cases where path entry/exit points are
        # right next to each other.
        nodes_to_delete = []
        for node in xml_root.xpath('''.//raise_lua_event[@name="'Script_Profiler.Record_Event'"]'''):

            # Look for entry followed by exit.
            if ',entry,' not in node.get('param'):
                continue

            next_node = node.getnext()

            if (next_node == None
            or next_node.tag != 'raise_lua_event'
            or next_node.get('name') != "'Script_Profiler.Record_Event'"
            or ',exit,' not in next_node.get('param')):
                continue

            # Entry before exit should always be redundant.
            nodes_to_delete.append(node)
            nodes_to_delete.append(next_node)

        for node in nodes_to_delete:
            node.getparent().remove(node)

        game_file.Update_Root(xml_root)
    return


#@Transform_Wrapper()
#def Annotate_MD_Scripts(files, empty_diffs = 0):
#    '''
#    For every md script, add performance measuring nodes.
#    '''
#    for game_file in files:
#        xml_root = game_file.Get_Root()
#        file_name = game_file.name.replace('.xml','')
#
#        # Gather a list of sample points.
#        # These will be tuples of 
#        # (section_name, location_name, path_bound "entry"/"mid"/"exit", node, 
#        #  "before"/"after"/"firstchild"/"lastchild").
#        # Where section_name should have the file_name, and a suffix
#        # for the cue/lib involved, so that timers can be matched up
#        # across lib calls from a cue.
#        sample_points = []
#        
#        # Entering/exiting any action block. Include cue/lib name.
#        # TODO: maybe stop/start measurement sections around include_actions
#        # and signal_cue_instantly points, or otherwise think of a way to
#        # identify when a cue is signalled instantly (eg. a nested call) to
#        # omit it from being double counted when summing all time spent
#        # in scripts.
#        actions_nodes = xml_root.xpath('.//actions')
#        for actions_node in actions_nodes:
#            cue_name = actions_node.getparent().get('name')
#
#            # Skip if empty.
#            if len(actions_node) == 0:
#                continue
#
#            # Pick out the entry/exit lines for annotation.
#            first_line = Get_First_Source_Line(actions_node[0])
#            last_line  = Get_Last_Source_Line(actions_node[-1])
#
#            # Entry/exit redundant for now, but will differ for
#            # specific nodes.
#            Insert_Timestamp(f'md.{file_name}.{cue_name}', f'entry {first_line}', 'entry', actions_node, 'firstchild')
#            Insert_Timestamp(f'md.{file_name}.{cue_name}', f'exit {last_line}'  , 'exit' , actions_node, 'lastchild')
#
#        # Commit changes right away; don't bother delaying for errors.
#        game_file.Update_Root(xml_root)
#    return


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

# Run this script.
Run()