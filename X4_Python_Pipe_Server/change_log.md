
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
