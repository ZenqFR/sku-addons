@echo off
rem Lance l'installateur Zenq Addons (fenetre accessible au lecteur d'ecran).
rem Starts the Zenq Addons installer (screen-reader friendly window).
setlocal
set "SCRIPT=%~dp0ZenqAddons.ps1"
if not exist "%SCRIPT%" (
  echo ZenqAddons.ps1 introuvable a cote de ce fichier / not found next to this file.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%" %*
if errorlevel 1 (
  echo.
  echo L'installateur s'est termine avec une erreur. Journal : %APPDATA%\ZenqAddons\journal.log
  pause
)
endlocal
