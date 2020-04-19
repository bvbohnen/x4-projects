
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
def Annotate_Script_Names(empty_diffs = 0):
    '''
    For every ai script, annotate the pilot entity with the name
    of the script running.
    '''
    aiscript_files = Load_Files('aiscripts/*.xml')
    
    for game_file in aiscript_files:
        xml_root = game_file.Get_Root()

        # Do this on every blocking action command.
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

                # Version of script name with the line number.
                # Can only do this for blocking elements that have a line.
                if node.sourceline:
                    name_line = "'${} {}'".format(game_file.name.replace('.xml',''), node.sourceline)

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
                            <do_if value="not this.$script_line_counts?">
                              <set_value name="this.$script_line_counts" exact="table[]"/>
                            </do_if>'''),
                        # Can accumulate a long time, so use a float or long int.
                        etree.fromstring('''
                            <do_if value="not this.$script_line_counts.{FIELD}?">
                              <set_value name="this.$script_line_counts.{FIELD}" exact="0.0"/>
                            </do_if>'''.replace('FIELD', name_line)),
                        etree.fromstring(('''
                            <set_value name="this.$script_line_counts.{FIELD}" operation="add"/>'''
                            ).replace('FIELD', name_line)),
                    ]
                    for record_node in record_group:
                        node.addprevious(record_node)


        if changed:
            # Commit changes right away; don't bother delaying for errors.
            game_file.Update_Root(xml_root)
    return



# Run the transform.
Remove_Debug()
Annotate_Script_Names()
Write_To_Extension(skip_content = True)
