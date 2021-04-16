'''
Transforms related to sector size reduction and removal of travel drive.
As SETA will now be the standard way to reduce travel times, some tweaks
are aimed at improving performance so that SETA can maintain okay framerates.
'''
import sys
from pathlib import Path
this_dir = Path(__file__).resolve().parent

# Set up the customizer import.
project_dir = this_dir.parents[1]
x4_customizer_dir = str(project_dir.parent / 'X4_Customizer')
if x4_customizer_dir not in sys.path:
    sys.path.append(x4_customizer_dir)
        
# Import all transform functions.
from Plugins import *

Settings(
    # Set the path to the X4 installation folder.
    path_to_x4_folder   = r'D:\Games\Steam\SteamApps\common\X4 Foundations',
    # Generate the extension here.
    path_to_output_folder = this_dir.parent,
    extension_name = this_dir.name,
    # TODO: maybe whitelist only official dlc.
    developer = True,
    )

# Prune some mass traffic.
# (There may also be a way to adjust this in-game now.)
# Update: "trafficdensity" option added to extra game options mod to help out.
# This might still help with many stations near each other.
#Adjust_Job_Count(('id masstraffic*', 0.5))

# TODO: check if script changes are really needed.
if 0:
    # Slow down ai scripts a bit for better fps.
    # Note on 20k ships save 300km out of vision:
    #  1x/1x: 37 fps (vanilla)
    #  2x/4x: 41 fps (default args)
    #  4x/8x: 46 fps
    Increase_AI_Script_Waits(
        oos_multiplier = 2,
        oos_seta_multiplier = 6,
        oos_max_wait = 20,
        iv_multiplier = 1,
        # TODO: is iv wait modification safe?
        iv_seta_multiplier = 2,
        iv_max_wait = 5,
        include_extensions = False,
        skip_combat_scripts = False,
        )


# Sector/speed rescaling stuff. Requires new game to work well.
    
# Enable seta when not piloting.
# TODO: couldn't find a way to do this.

# TODO: lower superhighway exit speed from 5000 to something lower, eg. 500,
# else the player can cruise out of a highway at excessive speed.
# need to target parameters.xml, spaceflight/superhighway@exitspeed

# Reduce weapon rofs; seta impact is a bit much on the faster stuff (6 rps).
# Prevent dropping below 1 rps.
Adjust_Weapon_Fire_Rate(
    {'match_any' : ['tags standard weapon','tags standard turret'],  
        'multiplier' : 0.5, 'min' : 1},
    )

# Retune radars to shorter range, for fps and for smaller sectors.
Set_Default_Radar_Ranges(
    ship_xl       = 30,
    ship_l        = 30,
    ship_m        = 25,
    ship_s        = 20,
    ship_xs       = 20,
    spacesuit     = 15,
    station       = 30,
    satellite     = 20,
    adv_satellite = 30,
    )
Set_Ship_Radar_Ranges(
    # Bump scounts back up. 30 or 40 would be good.
    ('type scout'  , 30),
    # Give carriers more stategic value with highest radar.
    ('type carrier', 40),
    )
    
# Adjust engines to remove the split base speed advantage, and shift
# the travel drive bonus over to base stats.
# TODO: think about how race/purpose adjustments multiply; do any engines
# end up being strictly superior to another?
# All of these will force travel drives to the same amount, and adjust
# cargo accordingly, ahead of removing travel drives.
common = {'travel' : 1, 'adjust_cargo' : True}
Rebalance_Engines(        
    race_speed_mults = {
        'argon'   : {'thrust' : 1,    'boost'  : 1,    'boost_time' : 1,   **common },
        # Slightly better base speed, worse boost.
        'paranid' : {'thrust' : 1.05, 'boost'  : 0.80, 'boost_time' : 0.8, **common },
        # Fast speeds, short boost.
        'split'   : {'thrust' : 1.10, 'boost'  : 1.20, 'boost_time' : 0.7, **common },
        # Slower teladi speeds, but balance with long boosts.
        'teladi'  : {'thrust' : 0.95, 'boost'  : 0.90, 'boost_time' : 1.3, **common },
        },
    purpose_speed_mults = {
        'allround' : {'thrust' : 1,    'boost' : 1,    'boost_time' : 1,   **common  },
        # Combat will be slowest but best boost.
        'combat'   : {'thrust' : 0.9,  'boost' : 1.2,  'boost_time' : 1.5, **common  },
        # Travel is fastest, worst boost.
        'travel'   : {'thrust' : 1.1,  'boost' : 0.8,  'boost_time' : 0.8, **common  },
        },
    )

# Disable travel drives for ai.
Disable_AI_Travel_Drive()

# Remove travel speed for player.
Remove_Engine_Travel_Bonus()
    
# Note: with speed rescale, boost ends up being a bit crazy good, with
# ship overall travel distance coming largely from boosting regularly.
# Example:
# - ship speed of 300
# - vanilla boost mult of 8x, duration of 10s.
# - boosting moves +21km (24km total vs 3km without boost)
# - small shield with 10s recharge delay, 9s recharge time.
# - can boost every 29s.
# - in 29s: 8.7km from base speed, 21km from boost.
# AI doesn't use boost for general travel, which breaks immersion when
# it would be so beneficial.
# Ideally, boosting would benefit travel less than +20% or so.
# Cannot change shield recharge delay/rate without other effects.
# In above example: change boost to only add +2km or so per 29s.
# - boost mult of 2x, duration of 5s = 2.7km.
Adjust_Engine_Boost_Duration(1/2)
Adjust_Engine_Boost_Speed   (1/4)

# Rebalance speeds per ship class.
# Do this after the engine rebalance.
# Note: vanilla averages and ranges are:    
# xs: 130 (58 to 152)
# s : 328 (71 to 612)
# m : 319 (75 to 998)
# l : 146 (46 to 417)
# xl: 102 (55 to 164)
# Try clamping variation to within 0.5x (mostly affects medium).
# TODO: more fine-grain, by purpose (corvette vs frigate vs trade, etc.).    
Rescale_Ship_Speeds(
    # Ignore the python (unfinished).
    {'match_any' : ['name ship_spl_xl_battleship_01_a_macro'], 'skip' : True},
    {'match_all' : ['type  scout' ],  'average' : 500, 'variation' : 0.2},
    {'match_all' : ['class ship_s'],  'average' : 400, 'variation' : 0.25},
    {'match_all' : ['class ship_m'],  'average' : 300, 'variation' : 0.3},
    {'match_all' : ['class ship_l'],  'average' : 200, 'variation' : 0.4},
    {'match_all' : ['class ship_xl'], 'average' : 150, 'variation' : 0.4})
    
# TODO: reduce highway speeds similarly (eg. 2000 instead of 20000).

# Miners can struggle to keep up. Increase efficiency somewhat by
# letting them haul more cargo.
# Traders could also use a little bump, though not as much as miners
# since stations are closer than regions.
Adjust_Ship_Cargo_Capacity(
    {'match_all' : ['purpose  mine' ],  'multiplier' : 2},
    {'match_all' : ['purpose  trade' ], 'multiplier' : 2})


    
# Rescale the sectors.
Scale_Sector_Size(
    # Whatever this is set to, want around 0.4 or less at 250 km sectors.
    scaling_factor                     = 0.4,
    scaling_factor_2                   = 0.3,
    transition_size_start              = 200000,
    transition_size_end                = 400000,
    precision_steps                    = 20,
    remove_ring_highways               = True,
    remove_nonring_highways            = False,
    extra_scaling_for_removed_highways = 0.7,
    )
    
if 0:
    # Use rescaler just to remove highways.
    Scale_Sector_Size(
        scaling_factor                     = 1,
        scaling_factor_2                   = 1,
        transition_size_start              = 200000,
        transition_size_end                = 400000,
        precision_steps                    = 20,
        remove_ring_highways               = True,
        remove_nonring_highways            = True,
        extra_scaling_for_removed_highways = 1,
        )
if 0:
    Scale_Sector_Size(
        scaling_factor                     = 0.3,
        scaling_factor_2                   = 0.25,
        transition_size_start              = 200000,
        transition_size_end                = 400000,
        precision_steps                    = 20,
        remove_ring_highways               = True,
        remove_nonring_highways            = True,
        extra_scaling_for_removed_highways = 0.7,
        move_free_ships = True,
        debug = True
        )


Write_To_Extension(skip_content = True)


