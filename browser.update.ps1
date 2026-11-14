<#
.SYNOPSIS
    VERSION 2026-11-14
    Keeps Google Chrome, Microsoft Edge and Mozilla Firefox up to date every
    hour, and makes an open browser restart within 15 minutes of an update.

.DESCRIPTION
    Chrome and Edge check for updates by themselves only every 4.5 hours or
    so, and a policy that shortens that is ignored on a PC that isn't in a
    domain, joined to Entra ID or enrolled in Chrome Enterprise Core. An
    update also only takes over once the browser is closed and opened again;
    until then the old version, with the holes the update fixes, keeps
    running.

    This asks each browser's updater for an update right away, the same way
    the browser's own "About" page does (the updater's on-demand COM
    interface, which any program can use on any PC), every hour.

    Firefox has no such interface: it updates itself from inside the running
    browser (every 6 hours) or, while it's closed, from a task of its own
    (every 7). It does obey its policies on any PC, so this sets its
    app.update.interval to an hour by policy (and keeps it set), and checks
    every hour for an update it has downloaded and is waiting to apply.
    Firefox then shows "Your browser is being managed by your organization".

    If an update is installed while the browser is open, the person using it gets a window
    with a countdown: the browser closes and opens again by itself after
    15 minutes ($RelaunchMinutes), or at once with "Restart now". Its tabs and
    windows come back. "Remind me later" puts it off until the next hourly
    check, which starts a new countdown.

    Modes:
      (none)       The hourly check. Runs as SYSTEM from Task Scheduler.
      -Relaunch    The countdown and restart, in the signed-in person's own
                   session. Started by the hourly check; not run by hand.
      -Install     Copies this script to C:\Program Files\browser.update and
                   sets up the tasks. install-browser.update.cmd runs this.
      -Uninstall   Removes the tasks and the copy; the logs stay.

    Logs: C:\ProgramData\browser.update\browser.update.log (the hourly
    check) and %LOCALAPPDATA%\browser.update\relaunch.log (each person's
    restarts).

.NOTES
    - A browser installed for one user only (in AppData) is skipped: it
      can't be updated from SYSTEM, and it updates itself.
    - The restart closes the browser the way signing out of Windows does, so
      it saves every window and tab, then opens it with
      --restore-last-session (Chrome, Edge) or -os-restarted (Firefox: what
      Windows itself uses to reopen it with its tabs after a restart). If the
      browser doesn't close within 30 seconds it's ended by force: then it
      offers to restore the tabs when it opens instead.
    - An update Firefox can only install with an administrator's permission
      (pending-elevate) gets no countdown: restarting would just ask for it.
      Firefox's own "Restart to update" handles that one.
    - Anything typed into a web page and not yet sent is lost in a restart;
      the countdown says so.
    - Not tested on Windows yet: the COM calls follow Chromium's own on-demand
      client (chrome/browser/google/google_update_win.cc). Edge's updater
      isn't documented; it's assumed to be the same, under its own names.

.EXAMPLE
    install-browser.update.cmd
    install-browser.update.cmd /uninstall
#>
[CmdletBinding(DefaultParameterSetName = 'Check')]
param(
    [Parameter(ParameterSetName = 'Relaunch')][switch]$Relaunch,
    [Parameter(ParameterSetName = 'Install')][switch]$Install,
    [Parameter(ParameterSetName = 'Uninstall')][switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------
# Settings
# ---------------------------------------------------------------
# Minutes between an update and the browser restarting by itself
$RelaunchMinutes = 15
# Longest an update check plus download and install may take, per browser
$UpdateTimeoutMinutes = 20
# How often Firefox checks for updates itself, in seconds (its
# app.update.interval, set by policy; Firefox's own default is 21600, 6 hours)
$FirefoxUpdateCheckSeconds = 3600

$InstallDir = Join-Path $env:ProgramFiles 'browser.update'
$LogDir = Join-Path $env:ProgramData 'browser.update'
$TaskFolder = '\browser.update\'
$CheckTaskName = 'Hourly check'

# Each browser: where it's installed for the whole PC; what its tab and
# helper processes have on their command line (ChildArg), so the browser
# process itself can be told apart; what reopens it with its tabs
# (RestoreArg); and for Chrome and Edge, their updater's on-demand COM class
# (ProgID) and app ID. Chrome's ProgID is from Chromium's
# chrome/updater/win/win_constants.h; Edge's follows the same pattern for its
# updater. The app IDs are the ones each vendor's update policies use.
$Browsers = @(
    @{
        Name = 'Chrome'; Long = 'Google Chrome'; Exe = 'chrome.exe'; Process = 'chrome'; Kind = 'Chromium'
        ChildArg = '--type='; RestoreArg = '--restore-last-session'
        ProgId = 'GoogleUpdate.Update3WebMachine'; AppId = '{8A69D345-D564-463C-AFF1-A69D9E530F96}'
        Dirs = @("$env:ProgramFiles\Google\Chrome\Application", "${env:ProgramFiles(x86)}\Google\Chrome\Application")
    }
    @{
        Name = 'Edge'; Long = 'Microsoft Edge'; Exe = 'msedge.exe'; Process = 'msedge'; Kind = 'Chromium'
        ChildArg = '--type='; RestoreArg = '--restore-last-session'
        ProgId = 'MicrosoftEdgeUpdate.Update3WebMachine'; AppId = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
        Dirs = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application", "$env:ProgramFiles\Microsoft\Edge\Application")
    }
    @{
        Name = 'Firefox'; Long = 'Mozilla Firefox'; Exe = 'firefox.exe'; Process = 'firefox'; Kind = 'Firefox'
        ChildArg = '-contentproc'; RestoreArg = '-os-restarted'
        Dirs = @("$env:ProgramFiles\Mozilla Firefox", "${env:ProgramFiles(x86)}\Mozilla Firefox")
    }
)

# Firefox's policies, which it reads on any PC (no domain needed)
$FirefoxPolicyKey = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'
# Where Firefox keeps a downloaded update: <this>\<hash of the install
# folder>\updates\0\update.status (toolkit/mozapps/update/common/commonupdatedir.cpp)
$FirefoxUpdateRoot = Join-Path $env:ProgramData 'Mozilla-1de4eec8-1241-4177-a864-e594e8d1fb38\updates'

# The updater's states (CurrentState in Chromium's updater_legacy_idl.template)
$StateUpdateAvailable = 4
$StateInstallComplete = 14
$StateNoUpdate = 16
$StateError = 17

# ---------------------------------------------------------------
# Shared
# ---------------------------------------------------------------
$script:LogFile = $null

function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [string]$Color = 'Gray')
    Write-Host $Message -ForegroundColor $Color
    if (-not $script:LogFile) { return }
    try {
        # One file, kept under about 1 MB: the older half is moved to .old
        $item = Get-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
        if ($item -and $item.Length -gt 1MB) { Move-Item -LiteralPath $script:LogFile -Destination "$($script:LogFile).old" -Force }
        Add-Content -LiteralPath $script:LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding UTF8
    } catch {
        Write-Host "  (couldn't write to $($script:LogFile): $($_.Exception.Message))" -ForegroundColor DarkGray
    }
}

# The folder the browser is installed in for the whole PC, or $null
function Get-BrowserDir {
    param([Parameter(Mandatory)][hashtable]$Browser)
    $Browser.Dirs | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ $Browser.Exe)) } | Select-Object -First 1
}

# "133.0.3", "128.5.1esr" or "131.0.6778.86" as a [version]
function ConvertTo-Version {
    param([string]$Text)
    if ("$Text" -notmatch '^\d+(\.\d+){0,3}') { return [version]'0.0' }
    $v = $Matches[0]
    if ($v -notmatch '\.') { $v += '.0' }
    [version]$v
}

# Firefox's downloaded update, if it's waiting for Firefox to restart: the
# state in update.status (pending, pending-service, applied,
# applied-service; pending-elevate needs an administrator's permission), or
# $null. The folder is named for a hash of the install folder, which the
# installer keeps in TaskBarIDs; without it, every Firefox's is looked at.
function Get-FirefoxPendingState {
    param([Parameter(Mandatory)][string]$Dir)
    $hash = $null
    foreach ($hive in 'HKLM:', 'HKCU:') {
        $ids = Get-ItemProperty -Path "$hive\SOFTWARE\Mozilla\Firefox\TaskBarIDs" -ErrorAction SilentlyContinue
        if ($ids -and $ids.PSObject.Properties[$Dir]) { $hash = "$($ids.PSObject.Properties[$Dir].Value)"; break }
    }
    $dirs = if ($hash) { @(Join-Path $FirefoxUpdateRoot $hash) } else {
        @(Get-ChildItem -LiteralPath $FirefoxUpdateRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
    foreach ($d in $dirs) {
        $status = Join-Path $d 'updates\0\update.status'
        if (-not (Test-Path -LiteralPath $status)) { continue }
        $state = "$(Get-Content -LiteralPath $status -TotalCount 1 -ErrorAction SilentlyContinue)".Trim()
        if ($state -match '^(pending|applied)') { return $state }
    }
    $null
}

# The version the browser runs when opened (its .exe's), the newest one
# installed, and whether one is waiting for the browser to restart. For
# Chrome and Edge, one installed while the browser was open waits in a
# folder named for its version, with new_chrome.exe or new_msedge.exe, until
# the browser is closed and opened again. Firefox's waits in its update
# folder (Get-FirefoxPendingState), its version not known until it's applied.
function Get-BrowserVersion {
    param([Parameter(Mandatory)][hashtable]$Browser, [Parameter(Mandatory)][string]$Dir)
    $exe = ConvertTo-Version (Get-Item -LiteralPath (Join-Path $Dir $Browser.Exe)).VersionInfo.ProductVersion
    if ($Browser.Kind -eq 'Firefox') {
        $state = Get-FirefoxPendingState $Dir
        return [pscustomobject]@{
            Exe = $exe
            Installed = $exe
            # pending-elevate: restarting would only ask for an administrator
            Pending = [bool]($state -and $state -ne 'pending-elevate')
            State = $state
        }
    }
    $newest = @(Get-ChildItem -LiteralPath $Dir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+(\.\d+){3}$' } | ForEach-Object { [version]$_.Name } |
            Sort-Object -Descending | Select-Object -First 1)
    $installed = if ($newest.Count -and $newest[0] -gt $exe) { $newest[0] } else { $exe }
    [pscustomobject]@{
        Exe = $exe
        Installed = $installed
        Pending = ($installed -gt $exe) -or (Test-Path -LiteralPath (Join-Path $Dir "new_$($Browser.Exe)"))
        State = $null
    }
}

# ---------------------------------------------------------------
# The hourly check (SYSTEM)
# ---------------------------------------------------------------

# Asks the browser's updater to check for an update now and install it, as
# the browser's About page does, and waits for the result. Returns
# Updated, Current or Failed, and a message.
function Invoke-BrowserUpdate {
    param([Parameter(Mandatory)][hashtable]$Browser)
    $result = { param($r, $m) [pscustomobject]@{ Result = $r; Message = $m } }
    try {
        $web = New-Object -ComObject $Browser.ProgId
    } catch {
        return & $result 'Failed' "its updater's $($Browser.ProgId) isn't registered or didn't start: $($_.Exception.Message)"
    }
    $bundle = $null
    try {
        $bundle = $web.createAppBundleWeb()
        $bundle.initialize()
        # Chromium passes the app ID in lower case. This fails while the
        # updater is already updating the browser by itself.
        $bundle.createInstalledApp($Browser.AppId.ToLowerInvariant())
        $app = $bundle.appWeb(0)
        $bundle.checkForUpdate()

        $installing = $false
        $version = ''
        $deadline = (Get-Date).AddMinutes($UpdateTimeoutMinutes)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $state = $app.currentState
            switch ([int]$state.stateValue) {
                $StateUpdateAvailable {
                    if (-not $installing) {
                        $version = "$($state.availableVersion)"
                        Write-Log "  [$($Browser.Name)] $version is available; downloading and installing it"
                        $bundle.install()
                        $installing = $true
                    }
                }
                $StateInstallComplete { return & $result 'Updated' "updated to $version" }
                $StateNoUpdate { return & $result 'Current' 'no update' }
                $StateError {
                    $msg = "error 0x{0:X8}" -f [int]$state.errorCode
                    try { if ("$($state.completionMessage)") { $msg += ": $($state.completionMessage)" } } catch { Write-Verbose 'no message' }
                    try { if ([int]$state.installerResultCode) { $msg += " (installer exit code $($state.installerResultCode))" } } catch { Write-Verbose 'no installer code' }
                    return & $result 'Failed' $msg
                }
            }
        }
        try { $bundle.cancel() } catch { Write-Verbose 'cancel failed' }
        return & $result 'Failed' "no result after $UpdateTimeoutMinutes minutes; cancelled"
    } catch {
        $hr = if ($_.Exception -is [System.Runtime.InteropServices.COMException]) { ' (0x{0:X8})' -f $_.Exception.ErrorCode } else { '' }
        return & $result 'Failed' "$($_.Exception.Message)$hr"
    } finally {
        foreach ($o in @($bundle, $web)) {
            if ($o) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch { Write-Verbose 'release failed' } }
        }
    }
}

# Firefox's Preferences policy: JSON in a REG_MULTI_SZ (or REG_SZ) value,
# {"pref": {"Value": ..., "Status": "locked"}}. Merged, so any other
# preferences already in it stay. Locked: about:config can't change it back.
function Set-FirefoxUpdatePolicy {
    param([switch]$Remove)
    if (Test-Path -LiteralPath "$FirefoxPolicyKey\Preferences") {
        return "its Preferences policy is set as registry keys by something else, so app.update.interval was left alone"
    }
    $prefs = [ordered]@{}
    $item = Get-ItemProperty -LiteralPath $FirefoxPolicyKey -ErrorAction SilentlyContinue
    $existing = if ($item -and $item.PSObject.Properties['Preferences']) { $item.Preferences } else { $null }
    if ($existing) {
        try {
            $parsed = (@($existing) -join "`n") | ConvertFrom-Json
        } catch {
            return "its Preferences policy isn't valid JSON, so it was left alone: $($_.Exception.Message)"
        }
        foreach ($p in $parsed.PSObject.Properties) { $prefs[$p.Name] = $p.Value }
    }
    $current = $prefs['app.update.interval']
    if ($Remove) {
        if (-not $current) { return $null }
        $prefs.Remove('app.update.interval')
    } else {
        $value = if ($current -and $current.PSObject.Properties['Value']) { "$($current.Value)" } else { '' }
        $status = if ($current -and $current.PSObject.Properties['Status']) { "$($current.Status)" } else { '' }
        if ($value -eq "$FirefoxUpdateCheckSeconds" -and $status -eq 'locked') { return $null }
        $prefs['app.update.interval'] = [pscustomobject]@{ Value = $FirefoxUpdateCheckSeconds; Status = 'locked'; Type = 'number' }
    }
    if ($prefs.Count) {
        if (-not (Test-Path -LiteralPath $FirefoxPolicyKey)) { New-Item -Path $FirefoxPolicyKey -Force | Out-Null }
        $json = @(($prefs | ConvertTo-Json -Depth 5) -split "`r?`n")
        New-ItemProperty -LiteralPath $FirefoxPolicyKey -Name 'Preferences' -PropertyType MultiString -Value $json -Force | Out-Null
    } else {
        Remove-ItemProperty -LiteralPath $FirefoxPolicyKey -Name 'Preferences' -ErrorAction SilentlyContinue
    }
    if ($Remove) { 'app.update.interval policy removed' } else { "app.update.interval set to $FirefoxUpdateCheckSeconds seconds by policy" }
}

# Firefox's hourly part: its update check every hour, by policy; anything
# stopping its updates (the DisableAppUpdate or AppAutoUpdate policies);
# and its version against Mozilla's latest. Returns a result like
# Invoke-BrowserUpdate's: Current, Behind or Failed.
function Invoke-FirefoxCheck {
    param([Parameter(Mandatory)][hashtable]$Browser, [Parameter(Mandatory)][string]$Dir)
    $result = { param($r, $m) [pscustomobject]@{ Result = $r; Message = $m } }
    try {
        $msg = Set-FirefoxUpdatePolicy
        if ($msg) { Write-Log "  [$($Browser.Name)] $msg" }
    } catch {
        return & $result 'Failed' "couldn't set its update policy: $($_.Exception.Message)"
    }
    $policy = Get-ItemProperty -LiteralPath $FirefoxPolicyKey -ErrorAction SilentlyContinue
    if ($policy -and $policy.PSObject.Properties['DisableAppUpdate'] -and [int]$policy.DisableAppUpdate -eq 1) {
        return & $result 'Failed' "the DisableAppUpdate policy turns its updates off ($FirefoxPolicyKey)"
    }
    if ($policy -and $policy.PSObject.Properties['AppAutoUpdate'] -and [int]$policy.AppAutoUpdate -eq 0) {
        return & $result 'Failed' "the AppAutoUpdate policy (0) stops it installing updates by itself ($FirefoxPolicyKey)"
    }

    $installed = (Get-BrowserVersion $Browser $Dir).Exe
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $v = Invoke-RestMethod -UseBasicParsing -TimeoutSec 60 -Uri 'https://product-details.mozilla.org/1.0/firefox_versions.json'
        $release = ConvertTo-Version $v.LATEST_FIREFOX_VERSION
        $esr = ConvertTo-Version $v.FIREFOX_ESR
        # An ESR Firefox stays on its major version
        $latest = if ($installed.Major -eq $esr.Major) { $esr } else { $release }
    } catch {
        return & $result 'Current' "couldn't get Mozilla's latest version ($($_.Exception.Message)); Firefox checks for updates itself every hour"
    }
    if ($installed -ge $latest) { return & $result 'Current' "the latest is $latest" }
    & $result 'Behind' "the latest is $latest; Firefox checks for it itself within the hour"
}

# Starts the countdown in the session of everyone who has the browser open,
# as them: a task of their own (Relaunch <name>), started now. A countdown
# already running is left alone.
function Start-RelaunchTask {
    param([Parameter(Mandatory)][string[]]$Users)
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script = Join-Path $InstallDir 'browser.update.ps1'
    foreach ($user in $Users) {
        $name = 'Relaunch ' + ($user -replace '[\\/:*?"<>|]', '_')
        try {
            $existing = Get-ScheduledTask -TaskPath $TaskFolder -TaskName $name -ErrorAction SilentlyContinue
            if ($existing -and "$($existing.State)" -eq 'Running') {
                Write-Log "  Countdown already running for $user"
                continue
            }
            $action = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Relaunch"
            $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
            Register-ScheduledTask -TaskPath $TaskFolder -TaskName $name -Action $action -Principal $principal -Settings $settings `
                -Description "browser.update: restarts Chrome, Edge or Firefox for $user $RelaunchMinutes minutes after an update; started by the hourly check" -Force | Out-Null
            Start-ScheduledTask -TaskPath $TaskFolder -TaskName $name
            Write-Log "  Countdown started for $user ($RelaunchMinutes minutes)" Green
        } catch {
            Write-Log "  Couldn't start the countdown for ${user}: $($_.Exception.Message)" Red
        }
    }
}

function Invoke-HourlyCheck {
    New-LogDir
    $script:LogFile = Join-Path $LogDir 'browser.update.log'
    Write-Log "Hourly check as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    $failed = $false
    $relaunchUsers = @()
    foreach ($b in $Browsers) {
        $dir = Get-BrowserDir $b
        if (-not $dir) {
            Write-Log "  [$($b.Name)] Not installed for the whole PC; skipped"
            continue
        }
        $before = Get-BrowserVersion $b $dir
        $r = if ($b.Kind -eq 'Firefox') { Invoke-FirefoxCheck $b $dir } else { Invoke-BrowserUpdate $b }
        $after = Get-BrowserVersion $b $dir
        switch ($r.Result) {
            'Updated' { Write-Log "  [$($b.Name)] $($before.Installed) -> $($after.Installed): $($r.Message)" Green }
            'Current' { Write-Log "  [$($b.Name)] $($after.Installed): up to date ($($r.Message))" }
            'Behind' { Write-Log "  [$($b.Name)] $($after.Installed): $($r.Message)" Yellow }
            default {
                Write-Log "  [$($b.Name)] $($after.Installed): update check failed: $($r.Message)" Red
                $failed = $true
            }
        }

        if ($after.State -eq 'pending-elevate') {
            Write-Log "  [$($b.Name)] Has an update that needs an administrator's permission to install; Firefox asks for it when it restarts" Yellow
        }
        # Waiting for a restart, whether this update or the updater's own
        # earlier one: whoever has it open gets the countdown
        if ($after.Pending) {
            $open = @(Get-Process -Name $b.Process -IncludeUserName -ErrorAction SilentlyContinue |
                    Where-Object { "$($_.Path)" -like "$dir\*" -and $_.UserName })
            $users = @($open | ForEach-Object { $_.UserName } | Sort-Object -Unique)
            if ($users.Count) {
                $what = if ($after.State) { "An update ($($after.State))" } else { "$($after.Installed)" }
                Write-Log "  [$($b.Name)] $what is waiting for a restart; open for: $($users -join ', ')" Yellow
                $relaunchUsers += $users
            } else {
                Write-Log "  [$($b.Name)] The update takes over the next time it's opened"
            }
        }
    }
    if ($relaunchUsers.Count) { Start-RelaunchTask -Users @($relaunchUsers | Sort-Object -Unique) }
    if ($failed) { exit 1 }
}

# The log folder: only SYSTEM and administrators can write to it, so nobody
# else can plant a link there for SYSTEM to write through. Everyone can read.
# Anyone can make folders in ProgramData, so one that's already there must be
# a real folder owned by SYSTEM or Administrators, or nothing is written.
function New-LogDir {
    if (Test-Path -LiteralPath $LogDir) {
        $item = Get-Item -LiteralPath $LogDir -Force
        $owner = (Get-Acl -LiteralPath $LogDir).GetOwner([Security.Principal.SecurityIdentifier]).Value
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $owner -notin @('S-1-5-18', 'S-1-5-32-544')) {
            throw "$LogDir wasn't made by this script (it's a link, or owned by $owner). Delete it and run install-browser.update.cmd again"
        }
    } else {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    & icacls.exe $LogDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Couldn't set the permissions of $LogDir (icacls exit $LASTEXITCODE)" }
}

# ---------------------------------------------------------------
# The countdown and restart (the signed-in person, in their session)
# ---------------------------------------------------------------

# Closes a program the way signing out of Windows does (Restart Manager), so
# Chrome, Edge and Firefox save every window and tab first
$RestartManager = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class BrowserUpdateRestartManager {
    [StructLayout(LayoutKind.Sequential)]
    struct RM_UNIQUE_PROCESS {
        public int dwProcessId;
        public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, StringBuilder strSessionKey);
    [DllImport("rstrtmgr.dll")]
    static extern int RmEndSession(uint pSessionHandle);
    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames,
        uint nApplications, RM_UNIQUE_PROCESS[] rgApplications, uint nServices, string[] rgsServiceNames);
    [DllImport("rstrtmgr.dll")]
    static extern int RmShutdown(uint pSessionHandle, uint lActionFlags, IntPtr fnStatus);

    // Returns 0, or the Win32 error code. startTimes are FILETIMEs (UTC).
    public static int Shutdown(int[] pids, long[] startTimes) {
        uint session;
        int rc = RmStartSession(out session, 0, new StringBuilder(64));
        if (rc != 0) return rc;
        try {
            RM_UNIQUE_PROCESS[] apps = new RM_UNIQUE_PROCESS[pids.Length];
            for (int i = 0; i < pids.Length; i++) {
                apps[i].dwProcessId = pids[i];
                apps[i].ProcessStartTime.dwLowDateTime = (int)(startTimes[i] & 0xFFFFFFFF);
                apps[i].ProcessStartTime.dwHighDateTime = (int)(startTimes[i] >> 32);
            }
            rc = RmRegisterResources(session, 0, null, (uint)apps.Length, apps, 0, null);
            if (rc != 0) return rc;
            // 0: no force; fails if the program won't close
            return RmShutdown(session, 0, IntPtr.Zero);
        } finally {
            RmEndSession(session);
        }
    }
}
'@

# This session's processes of the browser
function Get-SessionProcess {
    param([Parameter(Mandatory)][hashtable]$Browser)
    $session = (Get-Process -Id $PID).SessionId
    @(Get-Process -Name $Browser.Process -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $session -and "$($_.Path)" -like "$($Browser.Dir)\*" })
}

# Closes the browser in this session, saving its windows and tabs, and opens
# it again with them if it had a window open
function Restart-Browser {
    param([Parameter(Mandatory)][hashtable]$Browser, [switch]$NoReopen)
    $procs = @(Get-SessionProcess $Browser)
    if (-not $procs.Count) { return }
    $hadWindow = [bool]@($procs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count
    # The browser process itself: the one without --type= (Chrome, Edge) or
    # -contentproc (Firefox). The others are its tabs and helpers, and close
    # with it.
    $session = (Get-Process -Id $PID).SessionId
    $mainIds = @(Get-CimInstance Win32_Process -Filter "Name = '$($Browser.Exe)' AND SessionId = $session" -ErrorAction SilentlyContinue |
            Where-Object { "$($_.CommandLine)" -notmatch [regex]::Escape($Browser.ChildArg) } | ForEach-Object { [int]$_.ProcessId })
    $main = @($procs | Where-Object { $mainIds -contains $_.Id })
    if (-not $main.Count) { $main = $procs }

    $graceful = $false
    try {
        if (-not ('BrowserUpdateRestartManager' -as [type])) { Add-Type -TypeDefinition $RestartManager }
        $rc = [BrowserUpdateRestartManager]::Shutdown([int[]]@($main | ForEach-Object { $_.Id }),
            [long[]]@($main | ForEach-Object { $_.StartTime.ToFileTime() }))
        if ($rc -eq 0) { $graceful = $true } else { Write-Log "  [$($Browser.Name)] Restart Manager couldn't close it (error $rc)" Yellow }
    } catch {
        Write-Log "  [$($Browser.Name)] Restart Manager failed: $($_.Exception.Message)" Yellow
    }

    # Wait for every one of its processes to end; then end what's left
    $deadline = (Get-Date).AddSeconds(30)
    while (@(Get-SessionProcess $Browser).Count -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    $left = @(Get-SessionProcess $Browser)
    if ($left.Count) {
        Write-Log "  [$($Browser.Name)] Still open after 30 seconds; ended by force (it offers to restore the tabs when it opens)" Yellow
        $left | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $graceful = $false
    }

    if ($hadWindow -and -not $NoReopen) {
        Start-Process -FilePath (Join-Path $Browser.Dir $Browser.Exe) -ArgumentList $Browser.RestoreArg
        Write-Log "  [$($Browser.Name)] Closed$(if ($graceful) { ' cleanly' }) and opened again with its tabs" Green
    } else {
        Write-Log "  [$($Browser.Name)] Closed (it had no window open, so not opened again)" Green
    }
}

# The browsers this session has open that are waiting for a restart
function Get-PendingBrowser {
    @($Browsers | Where-Object {
            $_.Dir -and @(Get-SessionProcess $_).Count -and (Get-BrowserVersion $_ $_.Dir).Pending
        })
}

function Show-Countdown {
    param([Parameter(Mandatory)][hashtable[]]$Pending)
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $deadline = (Get-Date).AddMinutes($RelaunchMinutes)
    $names = ($Pending | ForEach-Object { $_.Long }) -join ' and '
    $has = if ($Pending.Count -gt 1) { 'have' } else { 'has' }
    $state = @{ Result = $null; NextCheck = (Get-Date).AddSeconds(10); Raised = $false }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$names updated"
    $form.TopMost = $true
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.AutoSize = $true
    $form.AutoSizeMode = 'GrowAndShrink'
    $form.Padding = New-Object System.Windows.Forms.Padding 16
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 11)

    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.FlowDirection = 'TopDown'
    $panel.AutoSize = $true
    $panel.WrapContents = $false

    $text = New-Object System.Windows.Forms.Label
    $text.AutoSize = $true
    $text.MaximumSize = New-Object System.Drawing.Size 460, 0
    $text.Text = "$names $has been updated with security fixes, and $has to restart to use them.`n`n" +
        "It will close and open again by itself. Your tabs come back, but anything typed into a web page " +
        "and not yet sent (an email, a form) is lost: finish or save it now.`n`n" +
        "Not a good time? Remind me later asks again within the hour."
    $count = New-Object System.Windows.Forms.Label
    $count.AutoSize = $true
    $count.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $count.Margin = New-Object System.Windows.Forms.Padding 0, 12, 0, 12
    $button = New-Object System.Windows.Forms.Button
    $button.Text = 'Restart now'
    $button.AutoSize = $true
    $button.Padding = New-Object System.Windows.Forms.Padding 8, 4, 8, 4
    $snooze = New-Object System.Windows.Forms.Button
    $snooze.Text = 'Remind me later'
    $snooze.AutoSize = $true
    $snooze.Padding = New-Object System.Windows.Forms.Padding 8, 4, 8, 4
    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.FlowDirection = 'LeftToRight'
    $buttons.AutoSize = $true
    $buttons.WrapContents = $false
    $buttons.Margin = New-Object System.Windows.Forms.Padding 0
    $buttons.Controls.AddRange(@($button, $snooze))
    $panel.Controls.AddRange(@($text, $count, $buttons))
    $form.Controls.Add($panel)
    $form.AcceptButton = $button

    $update = {
        $left = $deadline - (Get-Date)
        if ($left -le [TimeSpan]::Zero) {
            $state.Result = 'Restart'
            $form.Close()
            return
        }
        $count.Text = 'Restarting in {0}:{1:D2}' -f [int][math]::Floor($left.TotalMinutes), $left.Seconds
        # The last minute: back in front, in case it was minimized
        if (-not $state.Raised -and $left.TotalSeconds -le 60) {
            $state.Raised = $true
            $form.WindowState = 'Normal'
            $form.Activate()
        }
        # Closed (or restarted) by hand in the meantime: nothing left to do
        if ((Get-Date) -ge $state.NextCheck) {
            $state.NextCheck = (Get-Date).AddSeconds(10)
            if (-not @(Get-PendingBrowser).Count) {
                $state.Result = 'Done'
                $form.Close()
            }
        }
    }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick($update)
    $button.Add_Click({ $state.Result = 'Restart'; $form.Close() })
    # No restart now. The update is still waiting, so the next hourly check
    # starts a new countdown.
    $snooze.Add_Click({ $state.Result = 'Snooze'; $form.Close() })
    # The X minimizes it: the restart happens anyway
    $form.Add_FormClosing({
            param($s, $e)
            if (-not $state.Result -and $e.CloseReason -eq 'UserClosing') {
                $e.Cancel = $true
                $form.WindowState = 'Minimized'
            }
        })
    & $update
    $timer.Start()
    if (-not $state.Result) { [void]$form.ShowDialog() }
    $timer.Stop()
    $timer.Dispose()
    $form.Dispose()
    # Ended some other way (signing out): restart only if it was due
    if (-not $state.Result) { $state.Result = if ((Get-Date) -ge $deadline) { 'Restart' } else { 'Done' } }
    $state.Result
}

function Invoke-Relaunch {
    $userLogDir = Join-Path $env:LOCALAPPDATA 'browser.update'
    try {
        New-Item -ItemType Directory -Path $userLogDir -Force | Out-Null
        $script:LogFile = Join-Path $userLogDir 'relaunch.log'
    } catch {
        $script:LogFile = $null
    }
    foreach ($b in $Browsers) { $b.Dir = Get-BrowserDir $b }
    $pending = @(Get-PendingBrowser)
    if (-not $pending.Count) {
        Write-Log 'Nothing waiting for a restart in this session'
        return
    }
    Write-Log "Waiting for a restart: $(($pending | ForEach-Object { $_.Name }) -join ', ')"

    # Open with no window (Edge's startup boost, Chrome's background apps):
    # nothing to lose, so closed now and left closed
    $windowed = @()
    foreach ($b in $pending) {
        if (@(Get-SessionProcess $b | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count) {
            $windowed += $b
        } else {
            Restart-Browser $b -NoReopen
        }
    }
    if (-not $windowed.Count) { return }

    $result = Show-Countdown -Pending $windowed
    if ($result -eq 'Snooze') {
        Write-Log 'Remind me later: asked again at the next hourly check'
        return
    }
    if ($result -ne 'Restart') {
        Write-Log 'Restarted by hand before the countdown ended'
        return
    }
    foreach ($b in $windowed) {
        if (@(Get-SessionProcess $b).Count -and (Get-BrowserVersion $b $b.Dir).Pending) { Restart-Browser $b }
    }
}

# ---------------------------------------------------------------
# Install and uninstall
# ---------------------------------------------------------------
function Assert-Administrator {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this as administrator (install-browser.update.cmd asks for it).'
    }
}

function Install-BrowserUpdate {
    Assert-Administrator
    Write-Host 'Installing browser.update' -ForegroundColor Cyan

    # A copy only administrators can change, since SYSTEM runs it
    $target = Join-Path $InstallDir 'browser.update.ps1'
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    if ($PSCommandPath -ne $target) { Copy-Item -LiteralPath $PSCommandPath -Destination $target -Force }
    & icacls.exe $InstallDir /reset /T /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Couldn't reset the permissions of $InstallDir (icacls exit $LASTEXITCODE)" }
    Unblock-File -LiteralPath $target
    New-LogDir
    Write-Host "  Script: $target" -ForegroundColor Green

    # Every hour, all day (a daily trigger repeating hourly), and 5 minutes
    # after Windows starts. A run missed while the PC was off or asleep runs
    # when it's back; a second one while one runs is ignored.
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target`""
    $hourly = New-ScheduledTaskTrigger -Daily -At '00:05'
    $hourly.Repetition = (New-ScheduledTaskTrigger -Once -At '00:05' -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition
    $startup = New-ScheduledTaskTrigger -AtStartup
    $startup.Delay = 'PT5M'
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskPath $TaskFolder -TaskName $CheckTaskName -Action $action -Trigger @($hourly, $startup) `
        -Principal $principal -Settings $settings `
        -Description "browser.update: updates Chrome, Edge and Firefox every hour, and restarts an open one $RelaunchMinutes minutes after an update" -Force | Out-Null
    Write-Host "  Task: Task Scheduler > $($TaskFolder)$CheckTaskName, every hour as SYSTEM" -ForegroundColor Green

    Start-ScheduledTask -TaskPath $TaskFolder -TaskName $CheckTaskName
    Write-Host '  First check started' -ForegroundColor Green
    Write-Host ''
    Write-Host "Installed. Logs: $LogDir\browser.update.log"
}

function Uninstall-BrowserUpdate {
    Assert-Administrator
    Write-Host 'Removing browser.update' -ForegroundColor Cyan
    Get-ScheduledTask -TaskPath $TaskFolder -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
    try {
        $service = New-Object -ComObject Schedule.Service
        $service.Connect()
        $service.GetFolder('\').DeleteFolder($TaskFolder.Trim('\'), 0)
    } catch {
        Write-Verbose 'task folder already gone'
    }
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Tasks and $InstallDir removed" -ForegroundColor Green
    try {
        $msg = Set-FirefoxUpdatePolicy -Remove
        if ($msg) { Write-Host "  Firefox: $msg" -ForegroundColor Green }
    } catch {
        Write-Host "  Firefox: couldn't remove the app.update.interval policy: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host "The logs stay in $LogDir."
}

# ---------------------------------------------------------------
# Main
# ---------------------------------------------------------------
switch ($PSCmdlet.ParameterSetName) {
    'Install' { Install-BrowserUpdate }
    'Uninstall' { Uninstall-BrowserUpdate }
    'Relaunch' { Invoke-Relaunch }
    default { Invoke-HourlyCheck }
}
