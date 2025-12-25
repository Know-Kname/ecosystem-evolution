@echo off
:: Device Ecosystem Manager Launcher
:: Automatically requests administrator privileges

cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', '%~dp0Device-Ecosystem-Manager-v3.2.ps1'"
