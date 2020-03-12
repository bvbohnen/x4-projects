REM Change x4_path to point to the x4 installation extensions folder,
REM and run this bat to symlink git repo extensions into x4.
SET "x4_path=C:\Steam\steamapps\common\X4 Foundations\extensions"
SET "src_path=%~dp0"

for %%F in (
	better_target_monitor
	hotkey_api
	hotkey_api_test
	interact_menu_api
	interact_menu_api_test
	lua_loader_api
	named_pipes_api
	named_pipes_api_test
	simple_menu_api
	simple_menu_api_test
	time_api
	time_api_test
) do (
	mklink /J "%x4_path%\%%F" "%src_path%\%%F"
)


