'''
Support for generating documentation readmes for the extensions.

Extracts from decorated lua block comments and xml comments.

TODO: maybe develop this out further.
'''

from pathlib import Path
from lxml import etree
from collections import OrderedDict
import sys
from itertools import chain
import Version

this_dir = Path(__file__).parent

# Set up an import from the customizer for some text processing.
x4_customizer_dir = this_dir.parents[1] / 'X4_Customizer'
sys.path.append(str(x4_customizer_dir))
from Framework.Make_Documentation import Merge_Lines, Get_BB_Text


def Run():
    Make_Lua_Loader_Doc()
    Make_Key_Capture_Doc()
    Make_Named_Pipes_Doc()
    return


def Make_Lua_Loader_Doc():
    '''
    Document lua_loader_api.
    '''
    ext_dir = this_dir / 'extensions' / 'lua_loader_api'
    
    # Get the existing version string.
    current_version = Version.Get_Version(ext_dir)

    # Run the update function on the content.xml.
    Version.Update_Content_Version(ext_dir)

    # The readme is all hand written for now.

    # Set up the bbcode version.
    Make_BB_Code(ext_dir, header_lines = [
        r'Download: [url]https://github.com/bvbohnen/X4_Named_Pipes_API/releases[/url]',
        '',
        ])
    return


def Make_Named_Pipes_Doc():
    '''
    Document named_pipes_api.
    '''
    ext_dir = this_dir / 'extensions' / 'named_pipes_api'
    doc_path = ext_dir / 'Readme.md'
    doc_lines = []
        
    # Get the existing version string.
    current_version = Version.Get_Version(ext_dir)

    # Run the update function on the content.xml.
    Version.Update_Content_Version(ext_dir)

    # Grab the manually written part of the readme to append to.
    doc_lines = (ext_dir / 'readme_intro.md').read_text().splitlines()
    # TODO: insert version number into title

    # The MD pipe api.
    doc_lines += Get_XML_Cue_Text(ext_dir / 'md' / 'Named_Pipes.xml')
    
    # The MD server api.
    doc_lines += Get_XML_Cue_Text(ext_dir / 'md' / 'Pipe_Server_Host.xml')

    # The Lua pipe api.
    doc_lines += Get_Lua_Text(ext_dir / 'Named_Pipes.lua')
    
    with open(doc_path, 'w') as file:
        file.write('\n'.join(doc_lines))

    # Set up the bbcode version.
    Make_BB_Code(ext_dir)
    return


def Make_Key_Capture_Doc():
    '''
    Document key_capture_api.
    '''
    ext_dir = this_dir / 'extensions' / 'key_capture_api'
    doc_path = ext_dir / 'Readme.md'
    doc_lines = []
    
    # Get the existing version string.
    current_version = Version.Get_Version(ext_dir)

    # Run the update function on the content.xml.
    Version.Update_Content_Version(ext_dir)

    # Grab the manually written part of the readme to append to.
    doc_lines = (ext_dir / 'readme_intro.md').read_text().splitlines()
    # TODO: insert version number into title
    
    # Add the api cues.
    doc_lines += Get_XML_Cue_Text(ext_dir / 'md' / 'Key_Capture.xml')

    with open(doc_path, 'w') as file:
        file.write('\n'.join(doc_lines))

    # Set up the bbcode version.
    Make_BB_Code(ext_dir)
    return


def Sections_To_Lines(doc_text_dict):
    '''
    Converts a dict of {section label: text} to a list of text lines,
    with labelling and formatting applied.
    Expects the input to start with a 'title', then 'overview', then
    a series of names of cues or functions.
    '''
    # Transfer to annotated/indented lines.
    functions_started = False
    title = ''
    ret_text_lines = []
    for key, text in doc_text_dict.items():
        
        # Extract the title and continue; this isn't printed directly.
        if key == 'title':
            title = text.strip()
            continue

        # Header gets an 'overview' label.
        if key == 'overview':
            ret_text_lines += ['', '### {} Overview'.format(title), '']
            indent = ''

        # Lua functions are in one lump, like overview.
        elif key == 'functions':
            ret_text_lines += ['', '### {} Functions'.format(title), '']
            indent = ''

        # Otherwise these are md cues.
        else:
            indent = '  '
            # Stick a label line when starting the function section.
            if not functions_started:
                functions_started = True
                ret_text_lines += ['', '### {} Cues'.format(title), '']
            # Bullet the function name.
            ret_text_lines.append('* {}'.format(key))
            
        # Process the text a bit.
        text = Merge_Lines(text)

        # Add indents to functions, and break into convenient lines.
        text_lines = [indent + line for line in text.splitlines()]
        # Record for output.
        ret_text_lines += text_lines

    return ret_text_lines


def Get_XML_Cue_Text(xml_path):
    '''
    Returns a list of lines holding the documentation extracted
    from a decorated MD xml file.
    '''
    # OrderedDict, keyed by cue name, hold the extracted text lines.
    # Special entries for title and overview.
    doc_text_dict = OrderedDict()

    # Read the xml and pick out the cues.
    tree = etree.parse(str(xml_path))
    root = tree.xpath('/*')[0]
    cues = tree.xpath('/*/cues')[0]

    # Stride through comments/cues in the list.
    # Looking for decorated comments.
    for node in chain(root.iterchildren(), cues.iterchildren()):

        # Skip non-comments.
        # Kinda awkward how lxml checks this (isinstance doesn't work).
        if node.tag is not etree.Comment:
            continue

        # Handle title declarations.
        if '@doc-title' in node.text:
            label = 'title'
            text = node.text.replace('@doc-title','')
        # Text blocks are either overview or cue.
        elif '@doc-overview' in node.text:
            label = 'overview'
            text = node.text.replace('@doc-overview','')
        elif '@doc-cue' in node.text:
            label = node.getnext().get('name')
            text = node.text.replace('@doc-cue','')
        else:
            # Unwanted comment; skip.
            continue

        # Record it.
        doc_text_dict[label] = text
               
    # Process into lines and return.
    return Sections_To_Lines(doc_text_dict)


def Get_Lua_Text(lua_path):
    '''
    Extract documentation text from a decorated lua file.
    '''
    text = lua_path.read_text()
    ret_text_lines = []

    # Extract non-indented comments.
    # TODO: maybe regex this.
    comment_blocks = []
    lua_lines = text.splitlines()
    i = 0
    while i < len(lua_lines):
        this_line = lua_lines[i]

        if this_line.startswith('--[['):
            # Scan until the closing ]].
            these_lines = []

            # Record the first line.
            these_lines.append(this_line.replace('--[[',''))
            i += 1

            # Only search to the end of the doc.
            while i < len(lua_lines):
                next_line = lua_lines[i]
                if next_line.startswith(']]'):
                    # Found the last line; skip it.
                    break
                these_lines.append(next_line)
                i += 1

            comment_blocks.append('\n'.join(these_lines))
            
        # Check single-line comments after block comments, to avoid 
        # -- confusion.
        elif this_line.startswith('--'):
            comment_blocks.append(this_line.replace('--',''))

        # Always one increment per loop.
        i += 1
        

    # Title to put on label lines.
    # Starts blank, filled by decorator.
    title = ''
    
    # OrderedDict, keyed by function name, hold the extracted text lines.
    # Special entries for title and overview.
    doc_text_dict = OrderedDict()

    # Go through the comments looking for decorators.
    for comment in comment_blocks:
        
        # Handle title declarations.
        if '@doc-title' in comment:
            label = 'title'
            text = comment.replace('@doc-title','')
        # Text blocks are either overview or cue.
        elif '@doc-overview' in comment:
            label = 'overview'
            text = comment.replace('@doc-overview','')
        # For now, all functions are lumped together in one comment.
        elif '@doc-functions' in comment:
            label = 'functions'
            text = comment.replace('@doc-functions','')
        else:
            # Unwanted comment; skip.
            continue
        
        # Record it.
        doc_text_dict[label] = text
               
    # Process into lines and return.
    return Sections_To_Lines(doc_text_dict)


def Make_BB_Code(ext_dir, header_lines = []):
    '''
    Turn the ext_dir's readme into a bbcode txt file.
    Output is placed in the release folder.
    '''
    release_dir = this_dir.parent / 'Release'
    if not release_dir.exists():
        release_dir.mkdir()

    # Grab the readme contents.
    doc_lines = (ext_dir / 'Readme.md').read_text().splitlines()
    # Generate a bbcode version, prefixing with custom header.
    bb_lines = header_lines + Get_BB_Text(doc_lines)
    (release_dir / (ext_dir.name + '_bb_readme.txt')).write_text('\n'.join(bb_lines))
    return


if __name__ == '__main__':
    Run()

