REM Change x4_path to point to the x4 installation extensions folder,
REM and run this bat to symlink git repo extensions into x4.
SET "x4_path=C:\Steam\steamapps\common\X4 Foundations\extensions"
SET "src_path=%~dp0"

for %%F in (
	sn_better_target_monitor
	sn_hotkey_api
	sn_hotkey_api_test
	sn_interact_menu_api
	sn_interact_menu_api_test
	sn_lua_loader_api
	sn_named_pipes_api
	sn_named_pipes_api_test
	sn_simple_menu_api
	sn_simple_menu_api_test
	sn_extra_game_options
	sn_time_api
	sn_time_api_test
) do (
	mklink /J "%x4_path%\%%F" "%src_path%\%%F"
)


