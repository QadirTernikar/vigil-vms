@echo off
REM M6-1 Gateway Recording Engine
REM Records Go2RTC stream to segmented MP4 files using API endpoint
REM Usage: record_stream.bat <stream_name>

SET STREAM_NAME=%1
SET CAM_NAME=%2
if "%STREAM_NAME%"=="" (
    echo Error: Stream name required
    echo Usage: record_stream.bat bunny BunnyCam
    exit /b 1
)

REM Get current date for folder
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "YYYY=%dt:~0,4%"
set "MM=%dt:~4,2%"
set "DD=%dt:~6,2%"
set "TODAY=%YYYY%-%MM%-%DD%"

:: Create "recordings\CameraName\Date" folder
if not exist "recordings\%CAM_NAME%\%TODAY%" (
    mkdir "recordings\%CAM_NAME%\%TODAY%"
)

echo Starting Recording for %CAM_NAME% (%STREAM_NAME%) into recordings\%CAM_NAME%\%TODAY%
echo Press Ctrl+C to stop recording
echo.

REM Record using Go2RTC HTTP API
ffmpeg.exe -i "http://127.0.0.1:1984/api/stream.mp4?src=%STREAM_NAME%" ^
    -c copy ^
    -f segment ^
    -segment_time 60 ^
    -segment_format mp4 ^
    -strftime 1 ^
    -reset_timestamps 1 ^
    "recordings\%CAM_NAME%\%TODAY%\%%H-%%M-%%S.mp4"

echo.
echo Recording stopped.
REM pause
