@echo off
TITLE Vigil VMS Professional - Process Orchestrator
color 0A

echo Is your database migrated? (Camera Name column added?)
echo If not, run this SQL in Supabase first:
echo ---------------------------------------------------
echo ALTER TABLE recordings ADD COLUMN IF NOT EXISTS camera_name TEXT;
echo CREATE INDEX IF NOT EXISTS idx_recordings_camera_name ON recordings(camera_name);
echo ---------------------------------------------------
echo.
pause

echo.
echo [1/4] Starting Go2RTC Media Server...
start "Go2RTC Core" /MIN cmd /c "cd go2rtc && go2rtc.exe"

echo.
echo [2/4] Starting Gateway Recording Controller...
start "Gateway: Recorder (Port 8091)" /MIN cmd /c "dart run gateway/recording_server.dart"

echo.
echo [3/4] Starting Gateway Playback Server...
start "Gateway: Playback (Port 8090)" /MIN cmd /c "dart run gateway/playback_server.dart"

echo.
echo [4/4] Starting Metadata Indexer...
start "Vigil Indexer" /MIN cmd /c "dart run bin/indexer.dart"

echo.
echo ---------------------------------------------------
echo ✅ ALL SYSTEMS GO
echo ---------------------------------------------------
echo.
echo To run the App:
echo   flutter run -d windows
echo.
echo Press any key to exit launcher (background services will keep running)...
pause >nul
exit
