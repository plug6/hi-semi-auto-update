@echo off
:: Batch file to run PowerShell script as administrator

:: Set script path
set "scriptPath=C:\apps\autoUpdate\HI-frontend-backend-deploy.ps1"

:: Use PowerShell to launch the script with elevation
powershell -Command "Start-Process powershell -ArgumentList '-NoExit -ExecutionPolicy Bypass -File \"%scriptPath%\"' -Verb RunAs"