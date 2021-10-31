
### MD Interact Menu API Overview

 
MD API support for working with interaction menus (eg. right-click context menus). Listen for Get_Actions being signalled when a menu opens, check conditions and add relevant actions with Add_Actions, wait for callbacks if a player selects a custom action.
  

### MD Interact Menu API Cues

* **Get_Actions**
  
  Cue used to signal when a new menu is being opened, and actions may be added.
        
  The cue event.param holds a table with target data:
  * $object
    - The object the action was selected for, eg. a ship. 
  * $texts
    - Table with several text strings used in context menus.
    - Possible fields are described further below, in the Texts section.
  * <various params>
    - Other menu parameters are included and described further below, in the Params section.
      
* **Add_Action**
  
      
  Add an action to a newly created interact menu. This should be called just following a menu opening event, signalled from lua, holding info on the target object. These actions are removed from the menu after it closes, and need to be re-added on the next menu opening.
      
  This should be called whenever the API signals md.Interact_Menu_API.Get_Actions with target data.
        
  Input to this cue is a table with the following fields:
    * $id
      - String, unique identifier for this action.
    * $text
      - String, text to display in the action menu, left column.
    * $icon
      - String, optional name of an icon to prefix before the text.
    * $text2
      - String, optional text to display in the right column.
      - Support for this varies with $section. Eg. 'main' supports text2 while 'interaction' does not.
    * $mouseover
      - String, optional text to display on menu widget mouseover.
    * $mouseover_icon
      - String, optional name of an icon to prefix before the mouseover text.
    * $section = 'main'
      - Optional string, the menu section this action will go under.
      - Should be one from menu_interactmenu.lua config.sections.
      - TODO: Document these somewhat.
      - For now, just use "main" or "interaction".
    * $callback
      - Cue to call when the player selects the action.
      - See below for event.param contents.
    * $keep_open
      - Bool, if the menu should be left open after this action is selected.
      - Defaults false, closing the menu.
    * $active
      - Bool, if false then the action will be greyed out and unselectable.
      - Defaults true.
    * $echo
      - Optional, anything (string, value, table, etc.), data to be attached to the callback cue param for convenience.
          
          
  The callback cue returns an event.param table with the following:
    * $id
      - Same as $id above.
    * $echo
      - Same as $echo above.
    * $object
      - The object the action was selected for, eg. a ship.
      - Possibly null.
      - This is the same as in Get_Actions.
    * [params]
      - Other menu parameters are included and described further below, in the Params section.
      - These are the same as in Get_Actions.
    * $texts
      - Table with several text strings used in context menus.
      - Possible fields are described further below, in the Texts section.
      - These are the same as in Get_Actions.
      
  Example:
  ```xml
  <cue name="Add_Interact_Actions" instantiate="true">
    <conditions>
      <event_cue_signalled cue="md.Interact_Menu_API.Get_Actions" />
    </conditions>
    <actions>
      <set_value name="$target" exact="event.param.$object"/>
      <do_if value="$target.isclass.{class.ship}">
        <signal_cue_instantly
          cue="md.Interact_Menu_API.Add_Action"
          param = "table[
              $id         = 'my_action_id',
              $text       = 'Do Something',
              $icon       = 'order_follow',
              $callback   = Interact_Callback,
            ]"/>
      </do_if>
    </actions>
  </cue>
  ```
      
* **Update_Action**
  
      
  Updates fields of a currently recorded action. Note: currently this will not update a displayed menu's actions, since those are determined when the  menu is first drawn.
        
  Input to this cue is a table with the following fields:
    * $id
      - String, unique identifier matching an existing action.
    * [params]
      - Other params should match existing ones, and will overwrite them.
      
  Example:
  ```xml
  <signal_cue_instantly
    cue="md.Interact_Menu_API.Update_Action"
    param = "table[
        $id         = 'my_action_id',
        $callback   = Other_Callback_Cue,
      ]"/>
  ```
      
* **Reloaded**
  
  Dummy cue used for signalling that this api reloaded. Users that are registering options should listen to this cue being signalled. Somewhat depricated in favor of Get_Actions.
      
* **Register_Action**
  
      
  Register a new context menu action. If the action already exists, it will be updated with the new arguments. These actions are persistent, and will be checked every time the menu options for condition matches.
      
  Note: slightly depricated in favor of Add_Action.
        
  This should be called whenever the API signals md.Interact_Menu_API.Reloaded
        
  Input is a table with the following fields:
    * $id
      - String, unique identifier for this action.
    * $text
      - String, text to display in the action menu.
    * $icon
      - String, optional name of an icon to prefix before the name.
      - Typical order icons are 32x32, though any icon given will be scaled to 32 height.
    * $section = 'main'
      - Optional string, the menu section this action will go under.
      - Should be one from menu_interactmenu.lua config.sections.
      - TODO: Document these somewhat.
      - For now, just use "main" or "interaction".
    * $enabled_conditions
      - List of strings, flag names understood by the backend, of which at least one must be True to enable the action.
    * $disabled_conditions
      - List of strings, flag names understood by the backend, of which all must be False to enable the action.
    * $mouseover
      - String, text to display on menu widget mouseover.
    * $callback
      - Cue to call when the player selects the action.
      - See below for event.param contents.
    * $echo
      - Optional, anything (string, value, table, etc.), data to be attached to the callback cue param for convenience.
    * $disabled = 0
      - Optional, 0 or 1; if the option will not be displayed in the menu.
          
          
  The callback cue returns an event.param table with the following:
    * $id
      - Same as $id above.
    * $echo
      - Same as $echo above.
    * $object
      - The object the action was selected for, eg. a ship.
      
      
  The flags available for matching include the following. All are strings, and may be negated by a prefixed '~', eg. '~isenemy'.
    * Component class
      - class_controllable
      - class_destructible
      - class_gate
      - class_ship
      - class_station
    * Component data
      - is_dock
      - is_deployable
      - is_enemy
      - is_playerowned
    * Menu flags
      - show_PlayerInteractions
        - Menu flagged to show player interactions.
      - has_PlayerShipPilot
        - Selection is a player ship and has a pilot.
    * Misc
      - is_operational
        - Selection is operational?
      - is_inplayersquad
        - Selection is in the player's squad.
      - has_pilot
        - Selection has a pilot.
      - have_selectedplayerships
        - Selection(s) include one or more player ships.
    * Player related
      - player_is_piloting
        - True if the player is piloting a ship.
      - is_playeroccupiedship
        - Selection is the player's ship.
        
        
  Example:
  ```xml
  <cue name="Reset_On_Reload" instantiate="true">
    <conditions>
      <event_cue_signalled cue="md.Interact_Menu_API.Reloaded"/>
    </conditions>
    <actions>
      <signal_cue_instantly
        cue="md.Interact_Menu_API.Register_Action"
        param = "table[
          $id         = 'some_unique_id',
          $section    = 'main',
          $name       = 'My Action',
          $callback   = My_Callback_Cue,
          $mouseover  = '',
          $enabled_conditions  = ['show_PlayerInteractions'],
          $disabled_conditions = [],
          ]"/>
    </actions>
  </cue>
  ```
      


    
#### Params
    
When an interact menu is opened, various parameters on the target object and the source object(s) are populated, and used to guide which actions will show and what to do when actions are taken. A version of these params will be polished for MD usage, and passed to the event.param of Get_Actions and any action callback cues.
    
The possible params are as follows. Not all of these will exist for every target type.
         
* $object
  - Target object, or possibly a parent of the target.
  - When selecting a spot on a map, may be a sector.
  - May be null, eg. when opening a context menu for a mission.
* $isshipconsole
  - Bool, True if the target is a ship console.
  - This includes when the player selects the console at a docking pad.
* $isdockedship
  - Bool, True if a ship console is open at a dock with a docked ship.
  - If True, the $object will be the docked ship.
  - If False for a ship console, it indicates the console is for an empty dock, and $object is that dock.
* $selectedplayerships
  - List of player ships that are currently selected.
  - This is often populated by default with the player-piloted ship if the $object isn't the player ship.
* $showPlayerInteractions
  - Bool, True if the menu wants to show player interactions with the object.
  - Convenience term that gets set when $selectedplayerships is a list with only the player occupied ship in it.
  - Typically true when the player opens an interact menu on another object while flying.
* $hasPlayerShipPilot
  - Bool, True if a ship in $selectedplayerships has an assigned pilot and is not the player occupied ship.
  - This will always be False if $showPlayerInteractions is True.
* $selectedplayerdeployables
  - List of player deployables that are currently selected.
* $selectedotherobjects
  - List of other objects that are currently selected, eg. ships and stations.
* $order_queueidx
  - Int, index of an order in the queue, if target is an order.
  - May be unspecified.
* $subordinategroup
  - Int, 1-24, matches the corresponding greek letter of a selected subordinate group.
  - May be unspecified.
* $construction
  - Object under construction, which the menu opened on.
  - This occurs in the map view, looking at a shipyard, right clicking on a ship under construction, in which case the $object is the shipyard and $construction is the ship.
  - May be unspecified.
* $mission
  - ID of an active mission, as a cdata string representation.
  - May be unspecified.
* $missionoffer
  - ID of a mission offer, as a cdata string representation.
  - May be unspecified.
* $componentMissions
  - Potentially a list of mission ids (untested), as cdata strings.
  - May be unspecified.
* $offsetcomponent
  - Reference object for a position targeted, often a sector.
  - May be unspecified.
* $offset
  - Position offset from $offsetcomponent of a target.
  - May be unspecified.
    



#### Texts
    
In lua, various potentially useful text strings are created based on the target and selected objects. They are passed over to md in the Get_Actions event.param, and listed here. Note: many of these fields may not exist for a given target.
    
* $targetShortName
  - Name of the target.
  - This should always be present.
  - Missions and mission offers will lack any other text.
* $targetName
  - Name of the target with color prefix, object id, and other fields as applicable (eg. gate destination).
* $targetBaseName
  - Ships only, the short base ship name.
* $targetBaseOrShortName
  - Either $targetBaseName if defined, else $targetShortName.
  - This should always be present.
  - Vanilla actions often use $targetBaseName if available, else $targetShortName, as text2; this is a convenience term added to mimic that behavior.
* $commanderShortName
  - Objects with commanders only, commander name.
* $commanderName
  - Objects with commanders only, command name with sector prefix and if, as applicable.
* $selectedName
  - If player ships selected, the name of the ship (if one) or an indicator of number of ships selected.
* $selectedFullNames
  - If player ships selected, names of all ships separated by newlines, suitable for mouseover.
* $selectedNameAll
  - If object is player owned ship, the count of selected ships including the menu target.
* $selectedFullNamesAll
  - As $selectedFullNames, but including the target object.
* $otherName
  - As $selectedName, but for selected other objects (not ships).
* $otherFullNames
  - As $selectedFullNames, but for selected other objects (not ships).
* $constructionName
  - Construction only, name of the construction.
* $buildstorageName
  - Build storage only, name of the build storage.
    
    


    
#### Sections and subsections
    
The following is a quick listing of the different context menu sections and subsections an action can be added to. Actions in a subsection will show in the expanded menu on mouseover.
    
* main
* interaction
* hiringbuilderoption
  - hiringbuilder
* trade
* playersquad_orders
* main_orders
* formationshapeoption
  - formationshape
* main_assignments
* main_assignments_subsections
  - main_assignments_defence
  - main_assignments_attack
  - main_assignments_interception
  - main_assignments_supplyfleet
  - main_assignments_mining
  - main_assignments_trade
  - main_assignments_tradeforbuildstorage
* order
* guidance
* player_interaction
* consumables
  - consumables_civilian
  - consumables_military
* cheats
* selected_orders_all
* selected_orders
* mining_orders
  - mining
* venturedockoption
  - venturedock
* trade_orders
* selected_assignments_all
* selected_assignments
  - selected_assignments_defence
  - selected_assignments_attack
  - selected_assignments_interception
  - selected_assignments_supplyfleet
  - selected_assignments_mining
  - selected_assignments_trade
  - selected_assignments_tradeforbuildstorage
* selected_consumables
  - selected_consumables_civilian
  - selected_consumables_military
* shipconsole
    
Sections have a couple special properties, which relate to when a section's actions will be shown. They are listed here, to better indicate when each section will be shown.
    
* isorder
  - Relates to if a section is shown when player ships are selected.
  - true:
    - selected_orders_all, selected_orders, mining_orders, venturedockoption, trade_orders, selected_assignments_all, selected_assignments, selected_consumables
  - false:
    - main, interaction, hiringbuilderoption, trade, playersquad_orders, main_orders, formationshapeoption, main_assignments, main_assignments_subsections, player_interaction, consumables, cheats, shipconsole
  - undefined:
    - order, guidance
* isplayerinteraction
  - Shown when a single player-owned ship is selected, and the player occupies it.
  - true:
    - guidance, player_interaction
  - undefined:
    - all other categories
    
    