REM Change x4_path to point to the x4 installation extensions folder,
REM and run this bat to symlink git repo extensions into x4.
SET "x4_path=C:\Steam\steamapps\common\X4 Foundations\extensions"
SET "src_path=%~dp0"

for %%F in (
	sn_better_target_monitor
	sn_extra_game_options
	sn_hotkey_collection
	sn_interact_collection
	sn_mod_support_apis
	sn_remove_dock_symbol
	sn_station_kill_helper

) do (
	mklink /J "%x4_path%\%%F" "%src_path%\%%F"
)


REM	test_hotkey_api
REM	test_interact_menu_api
REM	test_named_pipes_api
REM	test_simple_menu_api
REM	test_time_api