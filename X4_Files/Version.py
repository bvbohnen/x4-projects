import re

def Get_Version(ext_path):
    '''
    Returns the last version number in the extension's change log,
    as a string, eg. '3.4.1'.
    Ideally, only "x.yy" versions are present, for easy representation
    in x4.
    '''

    # Traverse the log, looking for ' *' lines, and keep recording
    #  strings as they are seen.
    version = ''
    for line in (ext_path / 'change_log.md').read_text().splitlines():
        if not line.startswith('*'):
            continue
        version = line.split('*')[1].strip()
    return version


def Update_Content_Version(ext_path):
    '''
    Update an extension's content.xml file with the current version number,
    adjusted for x4 version coding.
    '''
    # Get the new version to put in here.
    # Code copied from x4 customizer, with slight adjustment.
    version_raw = Get_Version(ext_path)
    
    # Content version needs to have 3+ digits, with the last
    #  two being sub version. This doesn't mesh well if there are
    #  3+ version sub-numbers, but can do a simple conversion of
    #  the top two version sub-numbers.
    version_split = version_raw.split('.')
    # Should have at least 2 version sub-numbers, sometimes a third.
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
    content_xml_path = ext_path/'content.xml'
    text = content_xml_path.read_text()

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

    # Overwrite the file.
    # TODO: maybe skip this if the existing version matches the
    # updated one, to reduce redundant file writes.
    content_xml_path.write_text(text)

    return
