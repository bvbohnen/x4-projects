@echo off
copy /y ui\addons\ego_debug\lua_loader_api.lua ui\addons\ego_debug\lua_loader_api.xpl
"%USERPROFILE%\Documents\Visual Studio 2017\Projects\X4_Customizer\bin\X4_Customizer_console.exe" -nogui Cat_Pack -argpass . subst_01.cat -include ui/*.xml ui/*.xpl
pause