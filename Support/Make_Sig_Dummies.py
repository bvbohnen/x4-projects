'''
Creates dummy .sig files in the working extension folders.
These are normally created anyway for releases, but the local dummies
are useful when running the extensions from source using symlinks.

This doesn't need to be run often, just occasional touchup or maybe when
freshly pulling the repo.
'''

import json
from pathlib import Path
ext_dir = Path(__file__).resolve().parents[1] / 'extensions'
assert ext_dir.exists()

file_paths = []

for ext_folder in ext_dir.glob('*'):
    if not ext_folder.is_dir():
        continue

    file_paths.append(ext_folder / 'content.xml')

    # If there is a customizer log, grab it, and omit its files
    # from consideration.
    paths_to_ignore = []
    log_path = ext_folder / 'customizer_log.json'
    if log_path.exists():
        with open(log_path, 'r') as file:
            log = json.load(file)
        for path in log['file_paths_written']:
            paths_to_ignore.append(Path(path))

    # Get files in all subdirectories.
    for path in ext_folder.glob('**/*'):
        if not path.is_file():
            continue

        # Skip if already a sig file.
        if path.suffix == '.sig':
            continue

        if path in paths_to_ignore:
            continue

        # Pick out suffixes of interest.
        if path.suffix not in ['.xml']:
            continue

        file_paths.append(path)

for path in file_paths:
    if path.name == 'dockarea_arg_m_station_01.xml':
        bla = 0
    sig_path = path.parent / (path.name + '.sig')
    if not sig_path.exists():
        sig_path.write_text('')
        print('made {}'.format(sig_path))

