@echo off
echo ==========================================
echo      Vigil VMS - Process Cleaner
echo ==========================================
echo.

echo [1/4] Killing stuck Dart/Flutter processes...
taskkill /F /IM dart.exe /T 2>nul
if %errorlevel% equ 0 echo   - Killed dart.exe
taskkill /F /IM flutter.exe /T 2>nul
if %errorlevel% equ 0 echo   - Killed flutter.exe
echo   (Errors above are normal if no process was running)
echo.

echo [2/4] Deleting lockfile...
if exist "C:\src\flutter\bin\cache\lockfile" (
    del /F /Q "C:\src\flutter\bin\cache\lockfile"
    if exist "C:\src\flutter\bin\cache\lockfile" (
        echo   [ERROR] Failed to delete lockfile. START THIS SCRIPT AS ADMIN.
        pause
        exit /b
    ) else (
        echo   - Lockfile deleted successfully.
    )
) else (
    echo   - No lockfile found.
)
echo.

echo [3/4] Verifying removal...
if exist "C:\src\flutter\bin\cache\lockfile" (
    echo   [ERROR] Lockfile still exists!
) else (
    echo   - Clean.
)
echo.

echo [4/4] Running Flutter Doctor again...
call "C:\src\flutter\bin\flutter.bat" doctor
echo.

echo ==========================================
echo If you see the doctor output, you are fixed!
echo Restart VS Code after this.
echo ==========================================
pause
