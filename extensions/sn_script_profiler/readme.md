X4 Script Profiler
------------------

Add support for profiling MD and AI scripts to help determine their impact
on x4 performance.

## Requirements:
* X4 Customizer v1.22+ (python) or v1.23.1+ (exe)
* Windows 8 or 10
* Mod Support APIs extension
* Python pipe server v1.4+
* This extension

## Setup
The following sections go through setting up the profiler.

#### Settings ini
* Open config_defaults.ini to view settings.
  - Otionally, create config.ini for custom settings, or edit defaults directly.
  - A custom config.ini file will not be overwritten by updates to the script profiler extension.
  - Only changed or new values need to be in the custom config.ini.
* Setup the ini to select which scripts will be profiled, eg. vanilla scripts (default on), all extensions, specific extensions, md and/or ai, etc.
* Set up the path to the X4 installation either in the Customizer or ini file.
  - If you used the customizer previously, its path should already be set up.
* Edit the X4_Python_Pipe_Server permissions.json file to allow this extension.
  Eg. add a line with: "sn_script_profiler": true,

#### Exe
* Using the X4 Customizer, run the Modify_Exe.py script.
  - This performs binary edits that convert the 1-second-precision date timer to a 32-bit 10ns-precision profiling timer.
* When profiling, launch X4 using the modified exe, which will have a `_profiling.exe` suffix.
  - Normal play is not recommended with this exe, as saved games will have odd timestamps.

#### Scripts (automatic)
* Using the X4 Customizer, run the Modify_Scripts.py script.
  - This inserts timestamps into scripts at select points: entry and exit of action blocks, and before/after every aiscript blocking action.
  - Diff patches are automatically added to this extension.

#### Scripts (manual)
* Manual profiling points can be added to scripts directly.
* Pending documentation on how.

## Run
* Start X4 from the modified exe, and start the python host server (integrates with the mod support apis).
* Wait some period of time. By default, profile data will be recorded/updated once each minute, with a summary printed to the server window.
* Check the printed summary for the most expensive script paths.
* Pending development: View overall results in the generated profile.txt file generated in the extension's folder.

## Limitations
* Only time spent in script action bodies is measured, not overhead for evaluating cue or interrupt conditions.
* Time spent on blocking actions, eg. moving a ship, is not measured, even if it is only a potentially blocking action that doesn't block.
* If the game is paused, the profiler game-timer will pause as well (eg. paused time doesn't count down the 1-minute periods), though it will continue to measure time spent on any cues that fire during the pause.
  - This may be adjusted in future versions.
* Timestamps add significant overhead if many scripts are being profiled at once, which may influence script behavior if the fps dips too low.
  - Limit scripts being profiled if this occurs.
  - More likely to be a problem in SETA mode.
  - Not observed to be a problem in vanilla without SETA.