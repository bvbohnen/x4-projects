
Change Log

* 0.1
  - Start of log.
  - Target monitor monkey patched, various features in place.
* 0.2
  - Added smoothing filter to speed/distance to reduce noise for low attention targets.
  - Added support for more object types, and hide shields when not installed.
* 1.0
  - Improved rounding for smoother relative speed display.
  - Refined x3 class determination, and made it optional.
* 1.1
  - Fix for missed asteroid rows.
* 1.2
  - Support generic objects, eg. data vaults.
  - Tweaked faction name coloring.
  - Bypassed C.GetPlayerTargetOffset() returning bad z data.
* 1.3
  - Removed distance/eta from some target types that gave errors.
* 1.4
  - Rewrote smoothing filter for distant objects to reduce relative speed and eta jitter.
* 1.5
  - Stabalized relative speed and eta readout at extremely low fps.
* 1.6
  - ETA adjusts down when in SETA.
  - French translation, by Anthony
* 1.7
  - Adjusted x3 tags on interceptor M4, drone DR, lasertower OL, and Khaak medium heavy fighter as M3+.
  - Lua file now exports the text table, for users wanting to monkey-patch in alternate ship identifiers.
  - German translation, by Le Leon