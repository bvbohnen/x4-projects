
### Userdata API Cues

* **Reloaded**
  
  Dummy cue used for signalling that the api reloaded. Users can listen to this being signalled to know it is safe to read userdata. This will be signalled before the other apis load, so waiting for this is unnecessary if already waiting for other apis.
      
* **Read**
  
  Read a userdata value, using a paramaterized library call. Params:
  * Owner
    - String, unique name of the owner of this data (mod or modder).
    - Should avoid conflicting with other mods.
  * Key
    - String, optional, more specific name of the owner userdata when the owner entry is a table.
    - If not given, the full Owner entry is returned.
  * Default
    - Optional, default value to return if the Owner/Key lookup fails.
    - If not given, null is returned.
        
  Example:
    ```xml
    <run_actions ref="md.Userdata.Read" result="$retval">
      <param name="Owner" value="'sn_mod_support_apis'"/>
      <param name="Key" value="'hotkey_data'"/>
      <param name="Default" value="table[]"/>
    </run_actions>
    ```
      
* **Write**
  
  Write a userdata value, using a paramaterized library call. Params:
  * Owner
    - String, unique name of the owner of this data (mod or modder).
    - Should avoid conflicting with other mods.
  * Key
    - String, optional, more specific name of the owner userdata when the owner entry is a table.
    - If not given, the full Owner entry is overwritten.
  * Value
    - Table or other basic data type to save.
    - Should generally consist of numbers, strings, nested lists/tables, and similar basic values that are consistent across save games.
    - Avoid including references to objects, cue instances, etc. which differ across save games.
    - If "null", the userdata entry will be removed.
        
  Example:
    ```xml
    <run_actions ref="md.Userdata.Write">
      <param name="Owner" value="'sn_mod_support_apis'"/>
      <param name="Key" value="'hotkey_data'"/>
      <param name="Value" value="table[$zoom='z']"/>
    </run_actions>
    ```
      