@echo off
copy /y lua_loader_api\ui\addons\ego_debug\lua_loader.lua lua_loader_api\ui\addons\ego_debug\lua_loader.xpl
"%USERPROFILE%\Documents\Visual Studio 2017\Projects\X4_Customizer\bin\X4_Customizer_console.exe" -nogui Cat_Pack -argpass lua_loader_api lua_loader_api\subst_01.cat -include ui/*.xml ui/*.xpl
pause