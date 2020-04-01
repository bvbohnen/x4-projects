REM TODO: publishx4 version for new mods.
REM "%x_tools_path%" publishx4 -path "%src_path%\%%F" -preview "%src_path%\%%F\preview.png" -batchmode

SET "x_tools_path=E:\Steam\SteamApps\common\X Rebirth Tools\WorkshopTool.exe"
SET "src_path=%~dp0\..\Release\"

for %%F in (
	sn_better_target_monitor
	sn_extra_game_options
	sn_hotkey_collection
	sn_interact_collection
	sn_mod_support_apis
	sn_remove_dock_symbol
	sn_station_kill_helper
) do (
	"%x_tools_path%" update -path "%src_path%\%%F" -batchmode -minor -changenote ""
)
