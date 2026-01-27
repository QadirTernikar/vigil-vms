@echo off
color 0C
echo 🛑 KILLING ALL VMS PROCESSES...
echo --------------------------------

echo Killing Dart processes (Servers)...
taskkill /F /IM dart.exe /T

echo Killing Go2RTC...
taskkill /F /IM go2rtc.exe /T

echo Killing FFmpeg/FFplay...
taskkill /F /IM ffmpeg.exe /T
taskkill /F /IM ffplay.exe /T

echo.
echo --------------------------------
echo ✅ Clean sweep complete.
echo You may now run start_vms_pro.bat
echo --------------------------------
pause
