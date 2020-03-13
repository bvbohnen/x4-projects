# X4 Interact Menu API
This extension implements a generic mission-director level api for adding custom interact menu actions (eg. the right-click menu).  A lua backend interfaces with the egosoft menu code; api users may work purely with mission director scripts.

Warning: this api is in an early version. The method of selecting when an action is valid, and the format of the object returned to the callback cue, are likely to change.

### Example Usage

This code adds a generic "Follow" action to any target.
```xml
<cue name="Reset_On_Reload" instantiate="true">
  <conditions>
    <event_cue_signalled cue="md.Interact_Menu_API.Reloaded"/>
  </conditions>
  <actions>
    <signal_cue_instantly
      cue="md.Interact_Menu_API.Register_Action"
      param = "table[
            $id         = 'target_follow',
            $section    = 'interaction',
            $name       = 'Follow',
            $callback   = Target_Follow,
            $enabled_conditions = [],
            ]"/>
  </actions>
</cue>
<cue name="Target_Follow" instantiate="true" namespace="this">
  <conditions>
    <event_cue_signalled/>
    <check_value value="player.occupiedship"/>
  </conditions>
  <actions>
    <start_player_autopilot destination="event.param.$object"/>
  </actions>
</cue>
```
