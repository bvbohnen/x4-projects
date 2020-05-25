'''
This script will set up the modified exe.
This only needs to be done once for a series of perf profiles.
Note: if using steam, the modified exe will be named something like
"x4.mod.exe", but needs to be renamed to "x4.exe" to launch through
steam (back up the original and restore it when done).
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


def Run():
    '''
    Setup the customized exe.
    '''
    # Load settings from the ini file(s).
    # Defaults are in settings_defaults.ini
    # User overrides are in settings.ini (may or may not exist).
    config = configparser.ConfigParser()
    config.read([this_dir/'config_defaults.ini', this_dir/'config.ini'])
    
    # Set the path to the X4 installation folder and exe file.
    if config['General']['x4_path']:
        Settings(path_to_x4_folder = config['General']['x4_path'])
    if config['General']['x4_exe_name']:
        Settings(X4_exe_name = 'X4.exe')

    Remove_Sig_Errors()
    High_Precision_Systemtime()
    Write_Modified_Binaries()

Run()