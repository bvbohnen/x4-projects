REM Change x4_path to point to the x4 installation extensions folder,
REM and run this bat to symlink git repo extensions into x4.
SET "x4_path=C:\Steam\steamapps\common\X4 Foundations\extensions"
SET "src_path=%~dp0"

for %%F in (
    sn_better_target_monitor
    sn_friendlier_fire
    sn_extra_game_options
    sn_hotkey_collection
    sn_interact_collection
    sn_measure_perf
    sn_mod_support_apis
    sn_quiet_target_range_clicks
    sn_reduce_fog
    sn_remove_blinking_lights
    sn_remove_dirty_glass
    sn_remove_dock_glow
    sn_remove_dock_symbol
    sn_remove_highway_blobs
    sn_start_with_seta
    sn_station_kill_helper

    sn_debug_info
    sn_script_profiler

) do (
    mklink /J "%x4_path%\%%F" "%src_path%\%%F"
)

REM sn_script_profiler
REM test_interact_menu_api
REM test_simple_menu_api
REM	test_hotkey_api
REM	test_named_pipes_api
REM	test_time_api
REM test_sector_resize