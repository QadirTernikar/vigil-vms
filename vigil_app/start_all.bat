@echo off
echo ========================================
echo    VIGIL VMS - STARTUP SCRIPT
echo ========================================
echo.

cd /d "%~dp0"

echo [1/3] Starting Go2RTC...
start "Go2RTC" /MIN cmd /c "cd go2rtc && go2rtc.exe"
timeout /t 2 /nobreak > nul

echo [2/3] Starting Recording Server (8091)...
start "Recording Server" cmd /c "dart run gateway/recording_server.dart"
timeout /t 3 /nobreak > nul

echo [3/3] Starting Playback Server (8090)...
start "Playback Server" cmd /c "dart run gateway/playback_server.dart"
timeout /t 2 /nobreak > nul

echo.
echo ========================================
echo    ALL SERVICES STARTED
echo ========================================
echo.
echo   Go2RTC:           http://127.0.0.1:1984
echo   Recording Server: http://127.0.0.1:8091
echo   Playback Server:  http://127.0.0.1:8090
echo.
echo Now run: flutter run -d windows
echo.
pause
