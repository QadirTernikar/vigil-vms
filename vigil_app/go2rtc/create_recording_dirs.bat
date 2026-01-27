@echo off
REM M6-1 Directory Structure Creator
REM Creates date-based folders for all cameras to prevent FFmpeg write failures

echo Creating M6-compliant recording directories...

REM Get current date in YYYY-MM-DD format
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "YYYY=%dt:~0,4%"
set "MM=%dt:~4,2%"
set "DD=%dt:~6,2%"
set "TODAY=%YYYY%-%MM%-%DD%"

echo Today's date: %TODAY%

REM Create directories for bunny test stream
if not exist "recordings\bunny\%TODAY%" (
    mkdir "recordings\bunny\%TODAY%"
    echo Created: recordings\bunny\%TODAY%
)

REM Create directories for real cameras
if not exist "recordings\cam_221540953\%TODAY%" (
    mkdir "recordings\cam_221540953\%TODAY%"
    echo Created: recordings\cam_221540953\%TODAY%
)

if not exist "recordings\cam_231556246\%TODAY%" (
    mkdir "recordings\cam_231556246\%TODAY%"
    echo Created: recordings\cam_231556246\%TODAY%
)

if not exist "recordings\cam_541166789\%TODAY%" (
    mkdir "recordings\cam_541166789\%TODAY%"
    echo Created: recordings\cam_541166789\%TODAY%
)

echo.
echo Directory structure ready for recording.
echo Run this script daily or before starting Go2RTC.
pause
