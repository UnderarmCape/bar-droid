@echo off
rem The dev phone kept connected (USB and Wi-Fi adb) and dark, checked every minute (tools\devphone.ps1 watch).
rem Close the window to stop it.
title BAR Droid - dev phone watch
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0devphone.ps1" watch
