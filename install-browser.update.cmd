@echo off
rem Sets up browser.update.ps1 on this PC:
rem   - a copy in C:\Program Files\browser.update (only administrators can change it)
rem   - a task that runs it every hour as SYSTEM: Chrome and Edge are asked for
rem     updates and install them, Firefox is set (by policy) to check for its
rem     own every hour, and anyone with one of them open when an update is
rem     waiting is told it restarts in 15 minutes ("Restart now" and "Remind
rem     me later" buttons); their tabs come back
rem
rem Keep this file in the same folder as browser.update.ps1, then right-click it >
rem Run as administrator (double-click opens it in Notepad once
rem win11.restrict.and.scan.ps1 has run; see lnkprotect). Answer Yes when Windows asks.
rem Run it again after changing browser.update.ps1, to update the installed copy.
rem To remove it:  install-browser.update.cmd /uninstall
rem
rem If Windows says it "protected your PC" and won't run this, right-click the
rem file > Properties > tick Unblock > OK, then run it again.
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

if not exist "%~dp0browser.update.ps1" (
    echo browser.update.ps1 isn't in %~dp0
    echo Put this file in the same folder as browser.update.ps1 and try again.
    goto done
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0browser.update.ps1" %mode%
if errorlevel 1 (
    echo.
    echo Something went wrong; see the messages above.
)

:done
echo.
pause
