@echo off
rem Runs win11.restrict.and.scan.ps1 once, now.
rem   run-win11.restrict.and.scan.cmd         quick scans (full on Fridays)
rem   run-win11.restrict.and.scan.cmd /full   full scans, as the weekly run does
rem
rem If the installer has been run, this starts its scheduled task, which runs
rem the installed copy in Program Files in its own window: "Run now" with no
rem permission prompt, or "Weekly" for /full (that one needs the prompt).
rem If neither can be started, this runs win11.restrict.and.scan.ps1 from the
rem folder this file is in, and Windows asks for permission.
rem
rem To start it: right-click it > Run as administrator. Double-click opens
rem .cmd files in Notepad once the script has run (see lnkprotect). The
rem installer's Start menu entry "My OS Refresher" needs neither.
rem
rem If Windows says it "protected your PC" and won't run this, right-click the
rem file > Properties > tick Unblock > OK, then run it again.
setlocal
set "extra="
set "task=\win11.restrict.and.scan\Run now"
if /i "%~1"=="/full" (
    set "extra=-FullScan"
    set "task=\win11.restrict.and.scan\Weekly"
)

rem The installed copy. If the task isn't there, or this account isn't
rem allowed to start it, schtasks fails and the copy here is used instead.
schtasks /Run /TN "%task%" >nul 2>&1
if not errorlevel 1 goto started

rem fltmc only works as administrator. If it fails, start this file again
rem with the permission prompt and let that copy do the work (it tries the
rem task again first: "Weekly" needs administrator rights to start).
fltmc >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1 ' -Verb RunAs"
    exit /b
)

if not exist "%~dp0win11.restrict.and.scan.ps1" (
    echo The installed copy isn't set up, and win11.restrict.and.scan.ps1 isn't in %~dp0
    echo Run install-win11.restrict.and.scan.cmd, or put this file in the same
    echo folder as win11.restrict.and.scan.ps1, and try again.
    goto done
)

echo The installed copy isn't set up; running the one in %~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0win11.restrict.and.scan.ps1" %extra%
goto done

:started
echo Started the installed copy ("%task%"). It runs in its own window and
echo shows a message when it's finished. If it was already running, it carries
echo on and no second copy starts.
echo.
echo This window closes in 15 seconds.
timeout /t 15 >nul
exit /b

:done
echo.
pause
