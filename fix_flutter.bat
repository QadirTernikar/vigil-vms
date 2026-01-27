@echo off
echo ==========================================
echo       Vigil VMS - Flutter Fixer
echo ==========================================
echo.

echo [1/3] Checking for stale lockfile...
if exist "C:\src\flutter\bin\cache\lockfile" (
    del "C:\src\flutter\bin\cache\lockfile"
    echo Found and deleted 'lockfile'.
) else (
    echo No lockfile found.
)
echo.

echo [2/3] Checking Git availability...
where git >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Git is NOT found in PATH.
    echo Flutter requires Git to function.
    echo Please install Git for Windows or add it to your PATH.
) else (
    echo Git found:
    git --version
)
echo.

echo [3/3] Running Flutter Doctor (Direct Path)...
echo Executing: C:\src\flutter\bin\flutter.bat doctor
echo.
call "C:\src\flutter\bin\flutter.bat" doctor
echo.

echo ==========================================
echo Done. If you see 'Doctor summary', it works!
echo If Git was missing, please install it.
echo ==========================================
pause
