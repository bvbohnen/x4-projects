
import os
import sys
import re
from pathlib import Path
from collections import defaultdict
from lxml import etree

# Set up an import from the customizer for cat packing.
project_dir = Path(__file__).resolve().parents[1]
x4_customizer_dir = str(project_dir.parent / 'X4_Customizer')
if x4_customizer_dir not in sys.path:
    sys.path.append(x4_customizer_dir)
import Framework as X4_Customizer

__all__ = [
    'Release_Spec',
    ]

class Release_Spec:
    '''
    Specification for a given release.

    * root_path
      - Path to where the main files are located, eg. content.xml.
    * name
      - Name of the release; uses the root_path name if not specified.
    * is_extension
      - Bool, True if this is an extension.
    * steam
      - Bool, True if this is an extension that is intended to be on steam.
    * extension_id
      - String; if this is an extension, this is the id from the content.xml.
      - TODO
    * files
      - Dict of lists of files, where keys are category strings.
      - Categories include: lua, python, ext_cat, subst_cat, documentation,
        change_logs, misc, prior_subst_cat.
    * doc_specs
      - Dict, keyed by relative path from root to the doc file name, holding
        a list of files to include in the automated documentation generation,
        in order.
    * change_log_version
      - String, latest version from the change log.
    * change_log_notes
      - String, notes for the latest version in the change log.
    '''
    def __init__(
            self,
            root_path,
            steam = False,
            name = None,
            doc_specs = None,
            files = None,
        ):
        self.root_path = root_path.resolve()
        self.name = self.root_path.name if not name else name
        self.is_extension = self.root_path.parent.name == 'extensions'
        self.files = defaultdict(list)
        self.steam = steam

        self.doc_specs = doc_specs if doc_specs else {}
        # Touch up doc paths.
        for key, path_suffix_list in self.doc_specs.items():
            path_list = [(self.root_path / path_suffix).resolve()
                         for path_suffix in path_suffix_list]
            self.doc_specs[key] = path_list
        
        # Pack given files as misc ones.
        if files:
            for path_suffix in files:
                self.files['misc'].append((self.root_path / path_suffix).resolve())

        # Find standard files maybe not included above.
        self.Find_Standard_Files()

        # If an extension, find its general files and content info.
        self.extension_id = None
        if self.is_extension:
            self.Find_Ext_Files()
            self.Init_Ext_Info()
            
        # Fill in change log info.
        self.Parse_Change_Log()

        return


    def Find_Standard_Files(self):
        '''
        Search for standard files, eg. change_log and readme.
        '''
        readme_path = self.root_path / 'readme.md'
        if readme_path.exists():
            self.files['documentation'].append(readme_path)
        top_change_log = self.root_path / 'change_log.md'
        if top_change_log.exists():
            self.files['change_logs'].append(top_change_log)
        return
        

    def Find_Ext_Files(self):
        '''
        Search the extension's folder for files, and put them into categories.\
        '''
        files = self.files
        paths_seen = []
        content_dir = self.root_path

        # Find everything in the lua folder, lua or dll.
        for suffix in ['.lua','.dll']:
            for path in (content_dir / 'lua').glob(f'**/*{suffix}'):
                files['lua'].append(path)
        # Also include special case "lua_interface.txt" files in the top
        # folder.
        lua_interface_path = content_dir / 'lua_interface.txt'
        if lua_interface_path.exists():
            files['lua'].append(lua_interface_path)

        # Find python servers.
        for path in (content_dir / 'python').glob('**/*.py'):
            files['python'].append(path)

        # Find everything in the ui folder to pack into a subst cat.
        # Should just be xml and lua.
        # TODO: move this packing to the api mod explicitly.
        for suffix in ['.xml','.lua']:
            for path in (content_dir / 'ui').glob(f'**/*{suffix}'):
                files['subst_cat'].append(path)

        # Grab any existing subst file. Expect at most one.
        subst_cat_path = content_dir / 'subst_01.cat'
        if subst_cat_path.exists():
            subst_dat_path = content_dir / 'subst_01.dat'
            files['prior_subst_cat'].append(subst_cat_path)
            files['prior_subst_cat'].append(subst_dat_path)

        # Extended docs are in documentation. (Simple stuff is just in the readme.)
        for path in (content_dir / 'documentation').glob('**/*.md'):
            files['documentation'].append(path)

        # Change logs can be one folder down.
        for path in (content_dir / 'change_logs').glob('**/*.md'):
            files['change_logs'].append(path)

        # Find everything else in subfolders to pack into a normal cat.
        # For safety, filter to just xml for now.
        # TODO: other file types as needed.
        paths_seen = [x for sublist in files.values() for x in sublist]
        for path in content_dir.glob('**/*.xml'):
            if path in paths_seen:
                continue
            # Skip if not in a subfolder.
            if path.parent == content_dir:
                continue
            files['ext_cat'].append(path)

        # Check for content.xml.
        content_path = content_dir / 'content.xml'
        if content_path.exists():
            files['misc'].append(content_path)
            
        # Check for preview.png.
        preview_path = content_dir / 'preview.png'
        if preview_path.exists():
            files['preview'].append(preview_path)

        return
            

    def Init_Ext_Info(self):
        '''
        Loads the extension content.xml and reads some information out.
        TODO: fill out more.
        '''
        content_path = self.root_path / 'content.xml'
        if not content_path.exists():
            return

        content_root = etree.parse(str(content_path)).getroot()
        self.extension_id = content_root.get('id')
        return


    def Set_Extension_ID(self, new_id):
        '''
        Sets the content.xml id to the new id. Intended for use after
        a steam publish.
        '''
        assert self.extension_id
        assert new_id

        # Use string parsing for this, to avoid changing content test.
        content_path = self.root_path / 'content.xml'
        if not content_path.exists():
            return
        text = content_path.read_text(encoding='utf-8')
        new_text = text.replace(self.extension_id, new_id)
        content_path.write_text(new_text, encoding='utf-8')
        self.extension_id = new_id
        return


    def Parse_Change_Log(self):
        '''
        Parse and update change log data: latest version and change notes.
        '''
        # Traverse the logs, looking for ' *' lines, which will hold
        # version numbers.

        # Lines holding the latest change notes.
        change_notes = []

        # Start with a dummy empty string, eg. for simple mods that
        # don't bother with change logs and just write their content.xml
        # version directly.
        if len(self.files['change_logs']) == 0:
            if not self.is_extension:
                version = ''
            else:
                # Look up the existing version number, content encoded.
                content_version = self.Get_Content_Version()
                # Split into major/minor.
                version_major = int(content_version[:-2])
                version_minor = int(content_version[-2:])
                # Put back together into a normal string.
                version = '{}.{}'.format(version_major, version_minor)

        # If there is only one change log, its last version number is
        # the total version.
        elif len(self.files['change_logs']) == 1:
            for line in reversed(self.files['change_logs'][0].read_text().splitlines()):
                if not line.startswith('*'):
                    # Should be a change note.
                    change_notes.append(line)
                    continue
                version = line.split('*')[1].strip()
                break
            # Reverse the notes, since above loop went bottom to top.
            change_notes = [x for x in reversed(change_notes)]

        else:
            '''
            If there are multiple logs, then the joint version needs to
            consistently increment with any sub-log changes, but there is
            no specific overall version.

            Can count the number of log entries and use that in the total
            version, though that doesn't well represent major changes,
            eg. if a submodule switches from 1.x to 2.x.

            Major overall version could be the sum of the major versions
            of submodules (minus the implied 1).
            Minor versions could just be the number of log entries in
            the submodule's most recent major version.
            In this way, if a submodule switches from 1.11 to 2.0, 
            the overall major version will increment +1 and minor version
            decrement -11.

            However, the above gets a little messier when there are
            many minor version increments, as every 100 need to tick
            over to a new major version (for x4 content.xml).

            To reduce headache, just sum up all the change entries and
            add 100 to set the overall version; fancier handling can
            be done later if submodules every tick over to 2.x.
            '''
            change_entries = 0
            for change_log_path in self.files['change_logs']:

                # Note: no support for change_notes for now, since there
                # is no easy way to figure out which sub-log may have
                # had new entries.
                # TODO: maybe merge all logs into one.
                for line in reversed(change_log_path.read_text().splitlines()):
                    if line.startswith('*'):
                        change_entries += 1

            version_major = 1 + change_entries // 100
            version_minor = change_entries % 100
            version = '{}.{}'.format(version_major, version_minor)


        # Compact change notes together; one line for now, to dump on steam.
        changes = ''
        for line in change_notes:
            line = line.replace('-','').strip()
            # Add a space between the lines.
            if changes:
                changes += ' '
            changes += line

        self.change_log_version = version
        self.change_log_notes = changes
        return
    

    def Get_Version(self):
        '''
        Returns the last version number in the extension's change log,
        as a string.
        Ideally, only "x.yy" versions are present, for easy representation
        in x4. Extra suffixes will be dropped.
        '''
        return self.change_log_version


    def Get_Content_Encoded_Version(self):
        '''
        Returns the content.xml style encoding of the version, eg. a 3+
        digit integer where the lower two digits are implied to be after
        the decimal. Given as a string.
        If no version is known, returns None.
        '''
        version_str = self.Get_Version()
        if not version_str:
            return None

        # Content version needs to have 3+ digits, with the last
        #  two being sub version. This doesn't mesh well if there are
        #  3+ version sub-numbers, but can do a simple conversion of
        #  the top two version sub-numbers.
        version_split = version_str.split('.')
        # Should have at least 2 version sub-numbers, sometimes a third.
        assert len(version_split) >= 2
        # This could go awry on weird version strings, but for now just
        # assume they are always nice integers, and the second is 1-2
        # digits.
        version_major = version_split[0]
        version_minor = version_split[1].zfill(2)
        assert len(version_minor) == 2
        # Combine together.
        version = version_major + version_minor
        return version


    def _Get_Content_Version_Match(self):
        '''
        Local function to return the content.xml re match object for
        its version attribute string.

        Returns a match for the content node, and a match for
        the version node. Total string offset is based on both match offsets.
        '''
        content_path = self.root_path / 'content.xml'
        if not content_path.exists():
            return
    
        # Do text editing for this instead of using lxml; don't want
        # to mess up manual layout and such.
        # Have to explicitly set utf-8 to support translations.
        text = content_path.read_text(encoding='utf-8')

        # Get the text chunk from 'content' to 'version=".?"'.
        # This skips over the xml header version attribute.
        # Note: the version may be on a line after content.
        match_content = re.search(r'<content.*?version=".*?"', text, flags = re.DOTALL)

        # From this chunk of the string, get just the version value.
        # Use look-behind for the version=" and look-ahead for the closing ".
        # This should just give the positions of the numeric version text.
        match_version = re.search(r'(?<=version=").*?(?=")', 
                                  text[match_content.start() : ])
        return match_content, match_version


    def Get_Content_Version(self):
        '''
        Returns the version string from content.xml, as raw text.
        Does not insert the implicit decimal.
        '''
        matches = self._Get_Content_Version_Match()
        if not matches:
            return
        match_content, match_version = matches
        return match_version[0]


    def Update_Content_Version(self):
        '''
        Update an extension's content.xml file with the current version number,
        adjusted for x4 version coding. Skips if no content.xml found.
        '''
        # Get the new version to put in here.
        version = self.Get_Content_Encoded_Version()
        # If none known, skip.
        if not version:
            return
        
        matches = self._Get_Content_Version_Match()
        if not matches:
            return
        match_content, match_version = matches
        
        # Skip if the version is the same.
        current_content_version = match_version[0]
        if version == current_content_version:
            return

        content_path = self.root_path / 'content.xml'
        text = content_path.read_text(encoding='utf-8')

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
        content_path.write_text(text, encoding='utf-8')
        return



    def Path_To_Cat_Path(self, path):
        '''
        Convert a pathlib.Path into the virtual_path used in catalog files,
        eg. forward slash separated, relative to the content.xml folder.
        '''
        # These are relative to root, eg. don't want the extension folder
        # name in the path (md scripts should start with 'md', etc.).
        rel_path = Path(os.path.relpath(path, self.root_path))
        # Format should match the as_posix() form.
        return rel_path.as_posix()


    def Path_To_Lua_Require_Path(self, path):
        '''
        Convert a pathlib.Path into the internal format used in lua "require",
        eg. dot separated with no suffix, relative to the extensions folder.
        Will include the parent folder of the root_path.
        '''
        # Get the relative path to the root_path.
        rel_path = Path(os.path.relpath(path, self.root_path.parent))
        # Break into pieces: directory, then name; don't want extension.
        # Replace slashes with dots; do this as_posix for consistency.
        dir_path = rel_path.parent.as_posix().replace('/','.')
        name = rel_path.stem
        return dir_path + '.' + name


    def Path_To_Lua_Loadlib_Path(self, path):
        '''
        Convert a pathlib.Path into the internal format used in lua "loadlib",
        eg. double backslash separated, with suffix.
        '''
        # Get the relative path to the root_path.
        rel_path = Path(os.path.relpath(path, self.root_path.parent))
        # Break into pieces: directory, then name.
        # Replace slashes with \\; do this as_posix for consistency.
        dir_path = rel_path.parent.as_posix().replace('/','\\\\')
        return dir_path + '\\\\' + rel_path.name
    
    def Path_To_Python_Path(self, path):
        '''
        Convert a pathlib.Path into the internal format used in the
        pipe host api to declare python servers.
        '''
        # Get the relative path to the root_path.
        rel_path = Path(os.path.relpath(path, self.root_path.parent))
        # These have a posix style path, eg.
        # extensions/sn_mod_support_apis/python/Time_API.py
        return rel_path.as_posix()


    def Get_File_Binaries(self):
        '''
        Returns a dict holding file binary data. Keys are the desired paths,
        not necessarily the original paths, and are relative to the root_path
        parent (eg. suitable for feeding to a zip file packing).
        Binaries may be edited.

        Results will be suitable for a steam release.
        '''
        path_binaries = {}
        files = self.files
        root = self.root_path

        # Handle the easy case: not an extension.
        if not self.is_extension:
            for path in self.files['misc']:
                # No path adjustments, other than making relative.
                path_binaries[path] = path.read_bytes()

        else:
            
            # Collect lists of files to be put into the ext_01 and subst_01.
            ext_game_files   = []
            subst_game_files = []

            # Lua and python files will be renamed .txt and placed in the
            #  root dir, so they can distribute through steam.
            # This dict pairs original path with new desired path.
            lua_py_path_newpath_dict = {}
            # This dict has string replacements to perform on other text files.
            # Note: workshop upload lowercases file names, so account for that
            # below.
            string_replacement_dict = {}

            for path in files['lua'] + files['python']:

                # Set up the adjusted path.
                # This will include the names of intermediate folders between
                # the root_path and the actual lua file.
                # This isn't needed for the lua_interface.txt, which is
                # already in the top folder as txt.
                if path.name == 'lua_interface.txt':
                    new_path = path
                else:
                    new_path = root / '{}_{}.txt'.format(
                        path.relative_to(root).parent.as_posix().replace('/','_'),
                        path.stem.lower())
                    # Error if this conflicts with a lua_interface.txt file,
                    # for safety. (This could be resolved if it comes up.)
                    assert not new_path.name == 'lua_interface.txt'
                lua_py_path_newpath_dict[path] = new_path
                
                # Get the original in-text string for lua requires.
                # Note: lua_interface.txt doesn't need this conversion
                # for when it's required (which is why it exists), though
                # will still undergo replacement later for when it requires
                # the actual lua files.
                if path.suffix == '.lua':
                    # Goal is to replace "extensions.sn_simple_menu_api.lua.Custom_Options"
                    # with "extensions.sn_simple_menu_api.Custom_Options", or similar.
                    old_string = self.Path_To_Lua_Require_Path(path)
                    new_string = self.Path_To_Lua_Require_Path(new_path)
                    string_replacement_dict[old_string] = new_string

                # The dll is special, looking like:
                # ".\\extensions\\sn_named_pipes_api\\lualibs\\winpipe_64.dll"
                # This will also become a _dll.txt file, but needs different
                # string replacement.
                elif path.suffix == '.dll':
                    old_string = self.Path_To_Lua_Loadlib_Path(path)
                    new_string = self.Path_To_Lua_Loadlib_Path(new_path)
                    string_replacement_dict[old_string] = new_string

                elif path.suffix == '.py':                                           
                    old_string = self.Path_To_Python_Path(path)
                    new_string = self.Path_To_Python_Path(new_path)
                    string_replacement_dict[old_string] = new_string
    

            # Load all md xml and lua file texts, and adjust paths.
            # This dict pairs original paths with modified text.
            # TODO: maybe think about what happens if python files try
            # to cross-import; for now don't worry.
            file_text_dict = {}
            for path in files['lua'] + files['ext_cat'] + files['misc']:
                if path.suffix not in ['.lua','.xml','.txt']:
                    continue

                # Get the existing text.
                # Needs to explicitly be utf-8 else this messed up 
                # the infinity symbol in better_target_monitor.
                text = path.read_text(encoding = 'utf-8')
                # Edit paths.
                for old_string, new_string in string_replacement_dict.items():
                    text = text.replace(old_string, new_string)

                file_text_dict[path] = text


            for path in files['ext_cat']:
                # Set the catalog virtual path.
                virtual_path = self.Path_To_Cat_Path(path)

                # If text is already loaded, set up a text Misc_File, else binary.
                if path in file_text_dict:
                    game_file = X4_Customizer.File_Manager.Misc_File(
                        virtual_path = virtual_path,
                        text = file_text_dict[path])
                else:
                    game_file = X4_Customizer.File_Manager.Misc_File(
                        virtual_path = virtual_path,
                        binary = path.read_bytes())
                ext_game_files.append(game_file)


            # Subst files are in a separate list.
            for path in files['subst_cat']:
                virtual_path = self.Path_To_Cat_Path(path)

                # These will always record as binary.
                game_file = X4_Customizer.File_Manager.Misc_File(
                    virtual_path = virtual_path,
                    binary = path.read_bytes())
                subst_game_files.append(game_file)

                # If this is a lua file, also create an xpl copy.
                if path.suffix == '.lua':
                    game_file = X4_Customizer.File_Manager.Misc_File(
                        virtual_path = virtual_path.replace('.lua','.xpl'),
                        binary = path.read_bytes())
                    subst_game_files.append(game_file)


            # Collect files for cat/dat packing.
            cat_dat_paths = []
            # Offset subst based on existing subst (/2 since cat+dat recorded).
            subst_index = (len(files['prior_subst_cat']) // 2) + 1
            for game_files, cat_name in [(ext_game_files  , 'ext_01.cat'),
                                         (subst_game_files, f'subst_0{subst_index}.cat')]:
                # Skip if there are no files to pack.
                if not game_files:
                    continue

                # Set up the writer for this cat.
                # It will be created in the content.xml folder.
                # TODO: redirect to some other folder, maybe.
                cat = X4_Customizer.File_Manager.Cat_Writer.Cat_Writer(
                            cat_path = root / cat_name)
                # Add the files.
                for file in game_files:
                    cat.Add_File(file)

                # Write it.
                # TODO: some way to skip the actual write, at least for
                # cats, and for subst to skip if dat contents did
                # not change.
                cat.Write()

                # Record paths.
                cat_dat_paths.append(cat.cat_path)
                cat_dat_paths.append(cat.dat_path)


            # Finally, start gathering the actual files to include in
            # the zip, as binary data.
            # Generic files copy over directly (may be modified text).
            for path in files['misc']:
                if path in file_text_dict:
                    path_binaries[path] = file_text_dict[path].encode('utf-8')
                else:
                    path_binaries[path] = path.read_bytes()

            # Existing subst copy directly.
            for path in files['prior_subst_cat']:
                path_binaries[path] = path.read_bytes()

            # Lua/Py files copy over from their edited text, using their new path.
            for old_path, new_path in lua_py_path_newpath_dict.items():
                if old_path in file_text_dict:
                    # Stick to utf-8 for now.
                    path_binaries[new_path] = file_text_dict[old_path].encode('utf-8')
                else:
                    # Otherwise this should be the dll file.
                    path_binaries[new_path] = old_path.read_bytes()

            # TODO: maybe include readme as .txt instead of .md.
            for path in files['documentation'] + files['change_logs']:
                if (path.name.lower() == 'readme.md' 
                or  path.name.lower() == 'change_log.md'):
                    path_binaries[path.with_suffix('.txt')] = path.read_bytes()

            # Include the new cat/dat files themselves.
            for path in cat_dat_paths:
                path_binaries[path] = path.read_bytes()
            
            # Delete cat/dat files, except subst, so that the local extensions
            # continue to use loose files.
            # TODO: maybe a way to get raw binary from the cat_writer, instead
            # of it having to write the file first.
            for path in cat_dat_paths:
                if 'subst' not in path.name:
                    path.unlink()


        # Adjust the paths to be relative to the root's parent.
        # This way the zip file includes the root's folder.
        relative_path_binaries = {}
        for path, binary in path_binaries.items():

            # Get a path relative to root (removing local system pathing).
            # If the file was from outside root, eg. a compiled exe in
            # some bin folder, then just use the file name.
            if self.root_path in path.parents:
                rel_path = os.path.relpath(path, self.root_path)
            else:
                rel_path = path.name

            # Prefix with the release name.
            rel_path = os.path.join(self.name, rel_path)

            relative_path_binaries[rel_path] = binary

        return relative_path_binaries