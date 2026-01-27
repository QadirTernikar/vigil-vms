@echo off
echo ==========================================
echo      Vigil VMS - Permission Fixer
echo ==========================================
echo.
echo This script fixes the "Access Denied" errors by giving 
echo your normal user account full control over the Flutter folder.
echo.
echo [IMPORTANT] You must have right-clicked and selected "Run as Administrator"
echo for this to work.
echo.
pause

echo.
echo [1/2] Taking ownership of C:\src\flutter...
takeown /f "C:\src\flutter" /r /d y 2>nul
echo Done.

echo.
echo [2/2] Granting Full Control to Users group...
icacls "C:\src\flutter" /grant Users:(OI)(CI)F /T
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Failed to update permissions. 
    echo Did you run as Administrator?
) else (
    echo.
    echo [SUCCESS] Permissions fixed! 
    echo You should now be able to run flutter commands
    echo and use VS Code without "Run as Admin".
)
echo.
pause
