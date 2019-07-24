'''
Pack the extension and winpipe_64.dll into a zip folder for release,
suitable for unpacking to the X4 directory.

TODO
'''

from pathlib import Path
import os
import re
import zipfile
import Change_Log

this_dir = Path(__file__).parent

def Make_Release():
    # TODO: consider cat packing the extension files, using x4 customizer.


    # Get a list of paths to files to zip up.
    file_paths = []
    # (Most) Everything from extensions.
    for file in (this_dir / 'extensions').glob('**/*'):
        # Skip folders.
        if file.is_dir():
            continue
        file_paths.append(file)
    # The dll.
    file_paths.append(this_dir / 'ui'/'core'/'lualibs'/'winpipe_64.dll')
    
    # Edit the content.xml with the latest version.
    Update_Content_Version()    

    # Create a new zip file.
    # TODO: update code from customizer.
    # Put this in the top level directory.
    version_name = 'X4_Named_Pipes_API_v{}'.format(Change_Log.Get_Version())
    zip_path = this_dir.parent / (version_name + '.zip')
    # Optionally open it with compression.
    if False:
        zip_file = zipfile.ZipFile(zip_path, 'w')
    else:
        zip_file = zipfile.ZipFile(
            zip_path, 'w',
            # Can try out different zip algorithms, though from a really
            # brief search it seems lzma is the newest and strongest.
            # Result: seems to work well, dropping the ~90M qt version
            # down to ~25M.
            # Note: LZMA is the 7-zip format, not native to windows.
            #compression = zipfile.ZIP_LZMA,
            # Deflate is the most commonly supported format.
            # With max compression, this is ~36M, so still kinda okay.
            compression = zipfile.ZIP_DEFLATED,
            # Compression level only matters for bzip2 and deflated.
            compresslevel = 9 # 9 is max for deflated
            )

    # Add all files to the zip, with an extra nesting folder to
    # that the files don't sprawl out when unpacked.
    for path in file_paths:
        zip_file.write(
            # Give a full path.
            path,
            # Give an alternate internal path and name.
            # This will be relative to the top dir.
            # Note: relpath seems to bugger up if the directories match,
            #  returning a blank instead of the file name.
            arcname = os.path.join(version_name, os.path.relpath(path, this_dir))
            )

    # Close the zip; this needs to be explicit, according to the
    #  documenation.
    zip_file.close()

    print('Release written to {}'.format(zip_path))

    return


def Update_Content_Version():
    '''
    Update the content.xml file with the current version number,
    adjusted for x4 version coding.
    '''
    # Get the new version to put in here.
    # Code copied from x4 customizer:
    #
    # Content version needs to have 3+ digits, with the last
    #  two being sub version. This doesn't mesh will with
    #  the version in the Change_Log, but can do a simple conversion of
    #  the top two version numbers.
    version_split = Change_Log.Get_Version().split('.')
    # Should have at least 2 version numbers, sometimes a third.
    assert len(version_split) >= 2
    # This could go awry on weird version strings, but for now just assume
    # they are always nice integers, and the second is 1-2 digits.
    version_major = version_split[0]
    version_minor = version_split[1].zfill(2)
    assert len(version_minor) == 2
    # Combine together.
    version = version_major + version_minor


    # Do text editing for this instead of using lxml; don't want
    # to mess up manual layout and such.
    content_xml_path = this_dir / 'extensions'/'named_pipes_api'/'content.xml'
    with open(content_xml_path, 'r') as file:
        text = file.read()

    # Get the text chunk from 'content' to 'version=".?"'.
    # This skips over the xml header version attribute.
    match_content = re.search(r'<content.*?version=".*?"', text)

    # From this chunk of the string, get just the version value.
    # Use look-behind for the version=" and look-ahead for the closing ".
    # This should just give the positions of the numeric version text.
    match_version = re.search(r'(?<=version=").*?(?=")', 
                              text[match_content.start() : ])

    # Do a text replacement.
    # Compute the position to begin.
    # Note: .end() gives the spot after the last matched character.
    version_start = match_content.start() + match_version.start()
    version_end   = match_content.start() + match_version.end()
    # Use slicing to replace.
    text = text[ : version_start] + version + text[version_end : ]

    with open(content_xml_path, 'w') as file:
        file.write(text)

    return


if __name__ == '__main__':
    Make_Release()
