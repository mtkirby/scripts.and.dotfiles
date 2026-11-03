@echo off
rem Sets up dailyrunme.ps1 on this PC for whoever is signed in, so it can be
rem used without knowing PowerShell:
rem   - a copy in C:\Program Files\dailyrunme (only administrators can change it)
rem   - a weekly run, Fridays at 23:00, with full virus scans
rem   - "Check and update this PC" on the Desktop, to run it any time
rem
rem Sign in as the person who uses the PC (their account must be an
rem administrator), keep this file in the same folder as dailyrunme.ps1, and
rem double-click it. Answer Yes when Windows asks for permission.
rem Run it again after changing dailyrunme.ps1, to update the installed copy.
rem To remove it:  install-dailyrunme.cmd /uninstall
rem
rem If Windows says it "protected your PC" and won't run this, right-click the
rem file > Properties > tick Unblock > OK, then double-click it again.
setlocal
set "mode=-Install"
if /i "%~1"=="/uninstall" set "mode=-Uninstall"

rem fltmc only works as administrator. If it fails, start this file again
rem with the permission prompt and let that copy do the work.
fltmc >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1 ' -Verb RunAs"
    exit /b
)

if not exist "%~dp0dailyrunme.ps1" (
    echo dailyrunme.ps1 isn't in %~dp0
    echo Put this file in the same folder as dailyrunme.ps1 and try again.
    goto done
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dailyrunme.ps1" %mode%
if errorlevel 1 (
    echo.
    echo Something went wrong; see the messages above.
    goto done
)
if /i not "%mode%"=="-Install" goto done

echo.
choice /m "Run the first check now? It can take an hour or more"
if errorlevel 2 goto done
schtasks /Run /TN "\dailyrunme\Run now"

:done
echo.
pause
