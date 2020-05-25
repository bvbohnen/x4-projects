X4 Script Profiler

MD and AI scripts can be profiled to help determine their impact on x4
performance.

Requirements:
- X4 Customizer python source code (eg. clone the git repo)
- Python 3.6+ with lxml package (and maybe a couple others)
- Windows 8 or newer
- Mod Support APIs extension
- This extension

Setup steps:
- Open config_defatults.ini to view settings.
- Optionally, create config.ini for custom settings, or edit defaults directly.
- Set up the path to the X4 installation either in the Customizer or ini file.

- Edit the X4_Python_Pipe_Server permissions.json file to allow this extension.
  Eg. add a line with: "sn_script_profiler": true,

