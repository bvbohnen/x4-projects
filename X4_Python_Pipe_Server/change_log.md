
Change Log

* pre-0.8
  - Early pipe test versions.
* 0.8
  - Overhauled to work with named_pipes_api's Pipe_Server_Host api,
    dynamically loading python servers from extensions.
* 0.9
  - More graceful shutdown if a pipe server is already running.
* 0.10
  - Servers restart on receiving 'garbage_collected' pipe client messages.
* 1.0
  - General release.
* 1.1
  - Restricted module loading to those extensions given explicit permission.
* 1.2
  - Added command line arg for enabling test mode to aid extension development.
  - Added command line arg for changing the permission file path.
  - Called module main() functions must now capture one argument.
* 1.3
  - Gave explicit pipe read/write security permission to the current user, to help avoid "access denied" errors on pipe opening in x4 for some users.
* 1.4
  - Added configparser module to exe.
* 1.4.1
  - Added "-v" ("--verbose") command line arg, which will print pipe access permission messages.
* 1.4.2
  - Added fallback to default pipe permissions when failing to look up user account name.
