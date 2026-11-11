@echo off
rem Starts the SH2-CoopMod relay. Run on both PCs, each entering the OTHER player's VPN address.
rem If this folder is under Program Files, right-click and "Run as administrator".
set /p PEER=Other player's VPN IP (Radmin or Hamachi):
set /p ROLE=Type host or join (one of each):
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0relay.ps1" -PeerIP %PEER% -Role %ROLE%
pause
