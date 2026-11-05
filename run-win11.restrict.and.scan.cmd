@echo off
rem Runs win11.restrict.and.scan.ps1 once, now, from the folder this file is in.
rem Nothing needs to be installed: double-click it and answer Yes when Windows
rem asks for permission. Keep it in the same folder as win11.restrict.and.scan.ps1.
rem   run-win11.restrict.and.scan.cmd         quick scans (full on Fridays)
rem   run-win11.restrict.and.scan.cmd /full   full scans, as the weekly run does
rem
rem For a Desktop icon: right-click this file > Show more options > Send to >
rem Desktop (create shortcut). The shortcut still finds the script here.
rem
rem If Windows says it "protected your PC" and won't run this, right-click the
rem file > Properties > tick Unblock > OK, then double-click it again.
setlocal
set "extra="
if /i "%~1"=="/full" set "extra=-FullScan"

rem fltmc only works as administrator. If it fails, start this file again
rem with the permission prompt and let that copy do the work.
fltmc >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1 ' -Verb RunAs"
    exit /b
)

if not exist "%~dp0win11.restrict.and.scan.ps1" (
    echo win11.restrict.and.scan.ps1 isn't in %~dp0
    echo Put this file in the same folder as win11.restrict.and.scan.ps1 and try again.
    goto done
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0win11.restrict.and.scan.ps1" %extra%

:done
echo.
pause
