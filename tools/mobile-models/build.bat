@echo off
rem Builds mobile_models.exe (the mobile model generator) with the toolchain's w64devkit and meshoptimizer 0.23 (MIT).
rem   tools\mobile-models\build.bat   ->  C:\Tools\BARANDROID\engine-sim\mobile-models\mobile_models.exe
setlocal
set "HERE=%~dp0"
set "TC=%HERE%..\..\..\toolchain"
if defined BARDROID_TOOLCHAIN set "TC=%BARDROID_TOOLCHAIN%"
set "MO=%HERE%..\..\..\research\meshoptimizer-0.23\src"
set "OUT=%HERE%..\..\..\engine-sim\mobile-models"
if not exist "%OUT%" mkdir "%OUT%"
set "PATH=%TC%\hosttools\w64devkit\bin;%PATH%"
g++ -O2 -std=c++17 -I"%MO%" "%HERE%mobile_models.cpp" "%MO%\vcacheoptimizer.cpp" "%MO%\vfetchoptimizer.cpp" "%MO%\allocator.cpp" "%MO%\vcacheanalyzer.cpp" -o "%OUT%\mobile_models.exe" -static -pthread
if errorlevel 1 exit /b 1
echo built "%OUT%\mobile_models.exe"
