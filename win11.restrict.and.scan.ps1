<#
.VERSION
    2026-11-03

.SYNOPSIS
    Daily Windows run: security hardening, updates, a background Defender scan,
    health and security checks, and a report of Defender's Protection history.

.DESCRIPTION
    Every step runs even if an earlier one fails; the summary at the end lists what failed.

    1. patchmssigs:       update Microsoft Defender signatures
    2. restorepoint:      one System Restore point before the changes below.
                          If Windows already made one in the last 24 hours, that
                          is noted and the run continues. The script never
                          restarts the PC. When a restart is actually needed, a
                          window pops up at the end and says so.
    3. Hardening, re-applied every run so nothing drifts:
       - cis-chrome:      Chrome policies (CIS Google Chrome Benchmark v3.0.0), the
                          extension allowlist, the JavaScript optimizer allowlist,
                          and Chrome Remote Desktop blocked. An installed extension
                          that is not approved is a failure until its ID is added
                          or the extension is removed.
       - cis-services:    unneeded services disabled
       - quickassist:     Quick Assist removed (the app, the provisioned package
                          and the Windows capability). A failure if it was
                          installed, so a return is visible.
       - smb1:            the SMB1Protocol Windows feature removed, without a
                          restart
       - cis-registry:    automatic logon and WDigest off. A saved automatic-logon
                          password is deleted and is not copied into the undo file.
       - dns:             Quad9 / OpenDNS with DNS over HTTPS preferred
       - hostsfile:       hosts file put back to the default plus approved
                          entries, with its location and permissions checked
       - scriptprotect:   Defender ASR rules, PowerShell logging,
                          PowerShell 2.0 removed, Windows Script Host off
       - cis-office:      Microsoft Office (CIS Microsoft Office Enterprise
                          Benchmark v1.2.0, Level 1) for every user account
       - firewall:        a Windows Firewall profile that is off is turned back
                          on, and that is a failure so it stays visible
       - lnkprotect:      shortcut extensions shown, mshta/regsvr32/certutil
                          firewalled, .hta opens in Notepad
       - explorerview:    File Explorer shows extensions, hidden files (not
                          protected operating system files) and the full path
                          in the title bar; End task on the taskbar's
                          right-click menu
       - autoplay:        AutoPlay and AutoRun off for the PC and every user
       - dep:             Data Execution Prevention for all programs
       - coreisolation:   memory integrity, kernel stack protection, LSA
                          protection and the vulnerable driver blocklist on,
                          and checked that they're running
       - devmode:         alert if Developer Mode is on, and turn it off
       - exploitprotect:  Exploit protection system settings back to
                          "Use default", alerting on any that were turned off
       - defendersettings: real-time, cloud, sample submission, potentially
                          unwanted apps, network protection, Dev Drive,
                          Controlled folder access; checks Tamper protection
       - reputation:      App & browser control > Reputation-based protection:
                          SmartScreen (warn and prevent bypass), Edge
                          SmartScreen, phishing protection, Store apps
       - defenderexclusions: fails if Defender has an exclusion, or a Controlled
                          folder access app, that is not on the approved lists
    4. Updates:
       - patchwindows:    Windows Update, drivers and other Microsoft products
                          included; optional updates listed, not installed.
                          Turns on updates for other Microsoft products and
                          restart notifications, and fails if Windows Update is
                          off, paused or redirected. Never restarts the PC.
       - patchoffice:     Click-to-Run Office (Microsoft 365, Office 2019-2024):
                          version and channel, fails if its updates are off or
                          redirected, and starts an update check. Never closes
                          open Office apps.
       - patchchoco:      choco upgrade all
       - patchmsstore:    winget upgrades from the Microsoft Store, then a Store
                          update scan
       - patchwinget:     winget upgrade --all
    5. msert:             Microsoft Safety Scanner, downloaded fresh, detect only:
                          a full scan on Sundays and with -FullScan, a quick
                          scan otherwise
       eekscan:           if C:\EEK exists, Emsisoft Emergency Kit, updated,
                          detect only: a full scan on Saturdays and with
                          -FullScan, quick otherwise
    6. Checks. These report only; they do not turn remote access off, change
       UAC, or turn encryption on:
       - remoteaccess:    fails if Remote Desktop, Remote Assistance or WinRM
                          is on
       - uac:             fails if UAC is off, the secure desktop is off, or an
                          admin can elevate without a prompt
       - bitlocker:       fails if the system drive is not protected by device
                          encryption or BitLocker
       - diskhealth:      fails if a physical disk is Unhealthy or Warning
       - winhealthcheck:  DISM ScanHealth, sfc /scannow, DISM AnalyzeComponentStore
       - windiskcheck:    chkdsk /scan of the system drive
       - mywinprocsigs:   running programs without a valid Authenticode
                          signature, and LOLBAS programs renamed or running from
                          unusual folders
       - winstartupcheck: startup entries (tasks, Run keys, services, WMI...) and
                          shortcuts that run LOLBAS programs, alerting on signs of
                          misuse
       - winmodcheck:     loaded drivers without a valid signature or in the
                          loldrivers.io list, and settings that let unsigned or
                          blocklisted drivers load
    7. mywinvscan:        start a full Defender scan, limited to 50% CPU, in the
                          background. After the checks, so it is not reading the
                          disk during DISM, sfc, or chkdsk
    8. protectionhistory: the last 7 days of Defender's Protection history,
                          written to the log folder
    9. statusfile:        "PC check report.txt" on the Desktop, every run: All
                          clear, or Needs attention with the failures, notes and
                          restart reasons, then the Protection history. Opened
                          in Notepad at the end. If Controlled folder access
                          blocks the Desktop, it goes in the log folder.
    Then a message in plain words: no problems, or how many and who to send the
    report to ($HelperContact at the top), and Yes/No to restart when a restart
    is actually needed.

    For someone who isn't technical: run install-dailyrunme.cmd once on their
    PC, signed in as them (their account must be an administrator). It copies
    the script to C:\Program Files\dailyrunme, schedules it for Fridays at 23:00
    with full scans, and puts "Check and update this PC" on their Desktop, which
    runs it with no permission prompt. See Install-DailyRunMe.

    Any run that changes registry values (including service startup types)
    writes registry-undo-<date>-<time>.reg to the log folder, with those values
    as they were before; importing it puts them back. The first run's file holds
    the PC's original settings, since later runs only change what has drifted.
    The file's header lists what it can't undo.

    The settings to edit (approved Chrome extensions, JavaScript optimizer sites,
    Office's old file formats, Controlled folder access apps, DNS servers, hosts
    entries, and approved Defender exclusions) are at the top of the script.

.PARAMETER LogDir
    Where the transcript, the Defender scan log and the registry undo files go.
    Transcripts older than 30 days are deleted; undo files are kept.

.PARAMETER FullScan
    Full Safety Scanner and Emsisoft scans whatever the day. The weekly
    scheduled run uses it.

.PARAMETER Install
    Set up the weekly run and the Desktop shortcut for the signed-in user, then
    stop. install-dailyrunme.cmd runs this.

.PARAMETER Uninstall
    Remove the scheduled tasks, the Desktop shortcut and the copy in Program
    Files. Settings already applied, logs and undo files stay.

.NOTES
    - Must be run as Administrator. Run it as yourself, not SYSTEM: winget only works
      in a user session, and the report goes to your Desktop.
    - Windows blocks scripts by default, so start it with -ExecutionPolicy Bypass.
    - Exit code 1 if any step failed; the summary at the end lists them.
    - Restart Chrome after the first run (or reload policies at chrome://policy).
      The PC restarts only if Yes is clicked in the message at the end, which
      offers it only when a restart is actually needed. The reasons are also in
      the summary and the Desktop report.
    - Chrome policies need Chrome to read HKLM\SOFTWARE\Policies\Google\Chrome;
      check them at chrome://policy.
    - Hardening targets a stand-alone PC. On a domain, use Group Policy instead.
    - Not a complete CIS implementation: many recommendations are manual or
      environment-specific. Back up the system before the first run.
    - To run it on a schedule, use install-dailyrunme.cmd (see above). To
      change the time: Task Scheduler > dailyrunme > Weekly > Triggers.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\dailyrunme.ps1
#>

#Requires -RunAsAdministrator

param(
    [string]$LogDir = (Join-Path $env:ProgramData 'dailyrunme'),
    # Full Safety Scanner and Emsisoft scans whatever the day (the weekly run)
    [switch]$FullScan,
    # Set up, or remove, the weekly run and the Desktop shortcut (see
    # install-dailyrunme.cmd); nothing else runs
    [switch]$Install,
    [switch]$Uninstall
)

# Not 'Stop': in Windows PowerShell, a native program's stderr line would then end
# the step. Steps catch the errors that matter with -ErrorAction Stop, and the
# hardening steps set 'Stop' for themselves.
$ErrorActionPreference = 'Continue'

$script:Step = ''
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:Notes = [System.Collections.Generic.List[string]]::new()
# Real reasons a restart would finish something this run changed, or that
# Windows is already waiting on. Empty on a clean run: no popup, no nag.
$script:RestartReasons = [System.Collections.Generic.List[string]]::new()
# Set by the protectionhistory step, opened in Notepad at the very end
$script:HistoryFile = $null
# Set by the statusfile step. Written every run; not opened.
$script:StatusFile = $null
# Set by the eekscan step when Emsisoft finds something; also opened at the end
$script:EekLog = $null
# Registry values this run changed, as they were before, for the undo file
# (see Set-TrackedValue); Seen holds each key and value name once
$script:RegistryUndo = [System.Collections.Generic.List[object]]::new()
$script:RegistryUndoSeen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

# ---------------------------------------------------------------
# Approved Chrome extensions: EDIT THIS LIST
# Every other extension is disabled in all users' Chrome profiles (see the
# extension allowlist in Section 1). Each run prints the extensions it finds
# installed, with their IDs, so they can be copied here. An ID is the 32
# letters in the extension's Web Store URL, or shown in chrome://extensions
# with Developer mode on. An empty list disables every extension.
# ---------------------------------------------------------------
$ApprovedChromeExtensions = @(
    'cfhdojbkjhnklbpkdaibdccddilifddb'  # Adblock Plus
)

# ---------------------------------------------------------------
# Sites allowed to use Chrome's JavaScript optimizer (see Section 1)
# Every other site runs JavaScript without the optimizing compilers: safer,
# but slower on heavy web apps. [*.] covers the domain and all its
# subdomains; https:// keeps a tampered plain-HTTP page from getting it.
# Ads and other content a listed site embeds from other domains still
# run without the optimizer.
# ---------------------------------------------------------------
$JsOptimizerAllowedSites = @(
    'https://[*.]google.com'         # Google: Search, Gmail, Docs, Maps, Drive
    'https://[*.]microsoft.com'      # Microsoft: main site, account, Learn
    'https://[*.]microsoft365.com'   # Microsoft 365 / Office web apps
    'https://[*.]office.com'         # Microsoft 365 / Office web apps (older address)
    'https://[*.]cloud.microsoft'    # Microsoft 365 apps' newer address
    'https://[*.]live.com'           # Outlook.com mail, personal OneDrive
    'https://[*.]yahoo.com'          # Yahoo: mail, finance, news
    'https://[*.]wellsfargo.com'     # Wells Fargo online banking
    'https://[*.]vanguard.com'       # Vanguard investments
)

# ---------------------------------------------------------------
# Office: what happens to old binary files (.doc, .xls, .ppt and older
# formats) that CIS blocks (see Section 7)
#   0 = they don't open at all (CIS)
#   1 = they open read-only in Protected View
#   2 = they open in Protected View and can be edited
# ---------------------------------------------------------------
$OfficeBlockedFileBehavior = 1

# ---------------------------------------------------------------
# Programs allowed to change files in folders that Controlled folder access
# protects (Documents, Pictures, Desktop...; see Section 10). Signed,
# well-known programs are allowed automatically. Add the full path of
# anything else it blocks; blocks show in the Protection history report.
# ---------------------------------------------------------------
$ControlledFolderAllowedApps = @(
    'C:\cygwin\bin\bash.exe'
    'C:\cygwin\bin\git.exe'
    'C:\Program Files\Zoom\bin\Zoom.exe'
)

# ---------------------------------------------------------------
# DNS servers, in order of preference (see Section 5)
# Each has its DNS over HTTPS (DoH) address so Windows can encrypt queries to
# it. The IPv6 servers matter too: without them, a router that hands out its
# own IPv6 DNS server keeps getting queries.
# ---------------------------------------------------------------
$DnsServers = @(
    @{ Address = '9.9.9.9';         Template = 'https://dns.quad9.net/dns-query' }    # Quad9 (primary)
    @{ Address = '208.67.222.222';  Template = 'https://doh.opendns.com/dns-query' }  # OpenDNS (secondary)
    @{ Address = '2620:fe::fe';     Template = 'https://dns.quad9.net/dns-query' }    # Quad9 IPv6
    @{ Address = '2620:119:35::35'; Template = 'https://doh.opendns.com/dns-query' }  # OpenDNS IPv6
)

# ---------------------------------------------------------------
# Hosts file entries to keep (see Section 5b). Every run, the hosts file is
# put back to Windows' default plus these entries; anything else is removed
# and reported. One entry per line: the IP address, then one or more names.
# Some programs add their own (Docker Desktop adds host.docker.internal and
# kubernetes.docker.internal); list them here to keep them.
# ---------------------------------------------------------------
$ApprovedHostsEntries = @(
    # '192.168.1.10    nas.lan'  # example
)

# ---------------------------------------------------------------
# Who to send the report to when a run finds problems, as the person using
# this PC should see it in the popup at the end, e.g. 'Mike (555-0123)'.
# Empty: "the person who set up this PC".
# ---------------------------------------------------------------
$HelperContact = ''

# ---------------------------------------------------------------
# Defender exclusions: EDIT THIS LIST
# Anything Defender excludes that is not listed here is a failure, so an
# exclusion added by malware or by an installer shows up in the summary.
# An empty list means every exclusion is a failure. Paths are compared
# without a trailing slash (a drive root such as C:\ keeps its slash) and
# without regard to case. Controlled folder access programs are
# $ControlledFolderAllowedApps above, not this list.
# ---------------------------------------------------------------
$ApprovedDefenderExclusions = @{
    Path                   = @(
        # 'C:\Tools\example.exe'
    )
    Process                = @()
    Extension              = @()
    AttackSurfaceReduction = @()
}

# ---------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------

# Like mkbanner: text centred in a line of $Char across the window
function Write-Banner {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Char = '#',
        [ConsoleColor]$Color = 'Yellow'
    )
    $width = 0
    try { $width = $Host.UI.RawUI.WindowSize.Width } catch { $width = 0 }
    if (-not $width) { $width = 80 }
    $side = $Char * [Math]::Max(3, [int][Math]::Floor($width / 2) - [int][Math]::Floor(($Text.Length + 1) / 2) - 2)
    Write-Host "$side  $Text  $side" -ForegroundColor $Color
}

function Write-Fail {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:Failures.Add("${script:Step}: $Message")
}

# Who the report goes to, for the report and the popup ($HelperContact)
function Get-HelperName {
    if ("$HelperContact".Trim()) { "$HelperContact".Trim() } else { 'the person who set up this PC' }
}

# One place for "a restart is needed", so the summary, the Desktop status file
# and the popup stay the same. Does not restart the PC.
function Add-RestartReason {
    param([Parameter(Mandatory)][string]$Message)
    if (-not $script:RestartReasons.Contains($Message)) {
        $script:RestartReasons.Add($Message)
    }
    $note = "Restart needed: $Message"
    if (-not $script:Notes.Contains($note)) {
        $script:Notes.Add($note)
    }
}

function Write-Skip {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "SKIPPING: $Message" -ForegroundColor Yellow
}

# Run a program with its output passed through PowerShell, so the transcript
# records it; a program left to write straight to the console is not recorded.
# $Skip drops lines such as progress redraws. The exit code is in $LASTEXITCODE.
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$Skip = ''
    )
    & $FilePath @ArgumentList 2>&1 |
        ForEach-Object { "$_" -replace "`0", '' } |
        Where-Object { -not $Skip -or $_ -notmatch $Skip } |
        Out-Host
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )
    $script:Step = $Name
    Write-Banner $Name '#'
    try {
        & $Body | Out-Host
    } catch {
        Write-Fail $_.Exception.Message
    }
}

function Test-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }
    Write-Skip 'winget not found. Install App Installer from the Microsoft Store'
    return $false
}

# 0 = success. -1978335189 (0x8A15002B) = nothing needed an upgrade, which
# winget uses for both "upgrade" (the list) and "upgrade --all".
function Test-WingetExit {
    param([Parameter(Mandatory)][string]$What)
    $code = $LASTEXITCODE
    if ($code -in 0, -1978335189) { return }
    Write-Fail "$What exited $code"
}

# winget's progress bars and spinner, which come out as lines once redirected
$WingetProgress = '^\s*[-\\|/]?\s*$|[\u2588\u2592]{3,}'

# Hardening helpers

# --- Registry undo file ---
# Every registry value the hardening steps write goes through Set-TrackedValue
# (or Remove-TrackedValue), which notes the value as it was if the write
# changed it. Save-RegistryUndo then writes those old values to a .reg file
# in the log folder, which puts them back when imported.

# A value's type and data, or $null if it (or its key) doesn't exist.
# '(default)' is the key's unnamed default value.
function Get-RegistryValueState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $key) { return $null }
    $n = if ($Name -eq '(default)') { '' } else { $Name }
    if ($key.GetValueNames() -notcontains $n) { return $null }
    [pscustomobject]@{
        Kind = "$($key.GetValueKind($n))"
        # Unexpanded, so %SystemRoot% and the like go back as they were
        Data = $key.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
    }
}

# One value as a .reg file line; a $null state is a line that deletes it
function ConvertTo-RegLine {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        $State
    )
    $quote = { param($s) '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }
    $hex = { param([byte[]]$b) ($b | ForEach-Object { $_.ToString('x2') }) -join ',' }
    # Text types other than plain strings are stored as UTF-16 with a closing null
    $utf16 = { param([string]$s) [Text.Encoding]::Unicode.GetBytes("$s`0") }
    $lhs = if ($Name -eq '' -or $Name -eq '(default)') { '@' } else { & $quote $Name }
    if ($null -eq $State) { return "$lhs=-" }
    $data = $State.Data
    switch ($State.Kind) {
        'String' {
            # A quoted string can't hold a line break; hex(1) is the same type
            if ("$data" -match '[\r\n]') { "$lhs=hex(1):$(& $hex (& $utf16 "$data"))" }
            else { "$lhs=$(& $quote "$data")" }
        }
        'DWord' { "$lhs=dword:$(([int]$data).ToString('x8'))" }
        'QWord' { "$lhs=hex(b):$(& $hex ([BitConverter]::GetBytes([long]$data)))" }
        'ExpandString' { "$lhs=hex(2):$(& $hex (& $utf16 "$data"))" }
        'MultiString' { "$lhs=hex(7):$(& $hex (& $utf16 ((@($data) | ForEach-Object { "$_`0" }) -join '')))" }
        'Binary' { "$lhs=hex:$(& $hex ([byte[]]$data))" }
        default { "$lhs=hex(0):$(& $hex ([byte[]]@($data)))" }
    }
}

# After a write: if the value is now different from $Before, note $Before for
# the undo file. Only a value's first change in a run is kept, which is how it
# was before the script touched it.
function Add-RegistryUndo {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        $Before
    )
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $key) { return }
    $old = ConvertTo-RegLine -Name $Name -State $Before
    if ($old -eq (ConvertTo-RegLine -Name $Name -State (Get-RegistryValueState -Path $Path -Name $Name))) { return }
    # A user who wasn't signed in has their registry loaded as HKU\CIS_<sid>
    # (see Invoke-InEachUserHive); it's HKU\<sid> whenever they're signed in
    $keyName = $key.Name -replace '^HKEY_USERS\\CIS_(S-1-[\d-]+)', 'HKEY_USERS\$1'
    $n = if ($Name -eq '(default)') { '' } else { $Name }
    if (-not $script:RegistryUndoSeen.Add("$keyName`0$n")) { return }
    $script:RegistryUndo.Add([pscustomobject]@{ Key = $keyName; Line = $old; Step = $script:Step })
}

# Set-ItemProperty, creating the key if needed, with the old value noted for
# the undo file
function Set-TrackedValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()]$Value,
        [string]$Type = 'DWord'
    )
    $before = Get-RegistryValueState -Path $Path -Name $Name
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    Add-RegistryUndo -Path $Path -Name $Name -Before $before
}

# Remove-ItemProperty, with the old value noted for the undo file
function Remove-TrackedValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    $before = Get-RegistryValueState -Path $Path -Name $Name
    if ($null -eq $before) { return }
    Remove-ItemProperty -Path $Path -Name $Name -Force
    Add-RegistryUndo -Path $Path -Name $Name -Before $before
}

# Write the undo file, if this run changed any registry values
function Save-RegistryUndo {
    param([Parameter(Mandatory)][string]$File)
    if ($script:RegistryUndo.Count -eq 0) { return $null }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Windows Registry Editor Version 5.00')
    $lines.Add('')
    foreach ($comment in @(
        "Written by dailyrunme.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
        "Puts back the $($script:RegistryUndo.Count) registry values that run changed, as they were before it."
        'A value that didn''t exist before is deleted; keys the script created are left, empty.'
        ''
        'dailyrunme.ps1 sets them again on its next run: take the setting out of the'
        'script (or stop running it) first.'
        ''
        'To use: double-click this file, or run  reg import "<this file>"  as'
        'Administrator, then restart Windows (and Chrome).'
        '  - HKEY_USERS\S-1-... entries are other user accounts; each only applies'
        '    while that user is signed in.'
        '  - HKEY_USERS\CIS_Default entries are the Default profile (for new accounts);'
        '    first run:  reg load HKU\CIS_Default C:\Users\Default\NTUSER.DAT'
        '    and afterwards:  reg unload HKU\CIS_Default'
        ''
        'Not in this file, as they aren''t registry values (or Windows won''t take'
        'them from a .reg file): DNS servers and DoH addresses, the hosts file'
        '(backed up beside this file), firewall rules and firewall profiles,'
        'DEP (bcdedit), PowerShell 2.0, the SMB1Protocol feature, Quick Assist,'
        'the PowerShell log size, Defender settings and ASR rules, file permissions,'
        'System Restore points, installed Windows updates, and the Microsoft Update'
        'registration (turn off "Receive updates for other Microsoft products" in'
        'Settings > Windows Update > Advanced options).'
        'A saved automatic-logon password (DefaultPassword) is deleted and is not'
        'written here.'
    )) { $lines.Add("; $comment".TrimEnd()) }

    # Other accounts' keys last: if they can't be written (user not signed in),
    # everything before them is already in
    $entries = @($script:RegistryUndo | Where-Object { $_.Key -notlike 'HKEY_USERS\*' }) +
        @($script:RegistryUndo | Where-Object { $_.Key -like 'HKEY_USERS\*' })
    foreach ($group in $entries | Group-Object Key) {
        $lines.Add('')
        $lines.Add("; $(($group.Group.Step | Select-Object -Unique) -join ', ')")
        $lines.Add("[$($group.Name)]")
        foreach ($e in $group.Group) { $lines.Add($e.Line) }
    }
    # UTF-16 with a byte order mark, as regedit writes them
    Set-Content -LiteralPath $File -Value $lines -Encoding Unicode
    $File
}

function Set-ChromePolicy {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'DWord',
        [string]$Description
    )
    Set-TrackedValue -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name $Name -Value $Value -Type $Type
    Write-Host "  [Chrome] $Name = $Value  # $Description" -ForegroundColor Green
}

# List policies are a subkey with values named 1, 2, 3... The subkey is
# rebuilt each run so entries removed from the script are removed from Chrome.
function Set-ChromePolicyList {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Values = @(),
        [string]$Description
    )
    $path = "HKLM:\SOFTWARE\Policies\Google\Chrome\$Name"
    # The old entries, for the undo file
    $before = @{}
    if (Test-Path $path) {
        foreach ($n in (Get-Item -LiteralPath $path).GetValueNames()) {
            $before[$n] = Get-RegistryValueState -Path $path -Name $n
        }
        Remove-Item -Path $path -Recurse -Force
    }
    New-Item -Path $path -Force | Out-Null
    $i = 1
    foreach ($v in $Values) {
        New-ItemProperty -Path $path -Name "$i" -Value $v -PropertyType String -Force | Out-Null
        $i += 1
    }
    $names = @($before.Keys) + @((Get-Item -LiteralPath $path).GetValueNames()) | Sort-Object -Unique
    foreach ($n in $names) { Add-RegistryUndo -Path $path -Name $n -Before $before[$n] }
    Write-Host "  [Chrome] $Name = [$($Values -join ', ')]  # $Description" -ForegroundColor Green
}

# The extensions installed in every user's Chrome profiles, one object per
# extension per profile. Chrome's built-in extensions (PDF viewer etc.) aren't
# in these folders, and aren't affected by the allowlist.
function Get-InstalledChromeExtension {
    $pattern = "$env:SystemDrive\Users\*\AppData\Local\Google\Chrome\User Data\*\Extensions\*"
    foreach ($dir in Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue) {
        # <id>\<version>\manifest.json; any version's manifest gives the name
        $manifestPath = Get-ChildItem -Path $dir.FullName -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'manifest.json' } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
        $name = '(unknown name)'
        if ($manifestPath) {
            try {
                $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
                $name = $manifest.name
                # A name like __MSG_appName__ is looked up in the extension's translations
                if ($name -match '^__MSG_(.+)__$') {
                    $key = $Matches[1]
                    $locales = @('en', 'en_US')
                    if ($manifest.PSObject.Properties['default_locale']) {
                        $locales += $manifest.default_locale
                    }
                    foreach ($locale in $locales) {
                        $msgPath = Join-Path (Split-Path $manifestPath) "_locales\$locale\messages.json"
                        if (-not (Test-Path $msgPath)) { continue }
                        $msgs = Get-Content -Path $msgPath -Raw | ConvertFrom-Json
                        # Message keys are case-insensitive; -eq matches them that way
                        $entry = $msgs.PSObject.Properties | Where-Object { $_.Name -eq $key } | Select-Object -First 1
                        if ($entry) {
                            $name = $entry.Value.message
                            break
                        }
                    }
                }
            } catch {
                $name = '(unreadable manifest)'
            }
        }
        # ...\Users\<user>\AppData\Local\Google\Chrome\User Data\<profile>\Extensions\<id>
        $profileDir = $dir.Parent.Parent
        [pscustomobject]@{
            Id      = $dir.Name
            Name    = $name
            User    = $profileDir.Parent.Parent.Parent.Parent.Parent.Parent.Name
            Profile = $profileDir.Name
        }
    }
}

function Disable-ServiceIfExists {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Description
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        # Some services refuse a startup-type change even for admins; say so
        # rather than reporting them disabled
        # The startup type is the service key's Start value, so it can go in the
        # undo file (Windows reads it at the next restart)
        # Already disabled: don't ask for a restart every day just because it
        # is still running. A restart reason is only for a change made now.
        $wasDisabled = "$($svc.StartType)" -eq 'Disabled'
        $svcKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"
        $before = Get-RegistryValueState -Path $svcKey -Name 'Start'
        try {
            Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        } catch {
            Write-Fail "[Service] Couldn't disable ${Name}: $($_.Exception.Message)"
            return
        }
        Add-RegistryUndo -Path $svcKey -Name 'Start' -Before $before
        # A service that won't stop now is still disabled, so it won't start after a restart
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        if ((Get-Service -Name $Name).Status -ne 'Stopped') {
            Write-Host "  [Service] Disabled $Name, but it's still running until restart  # $Description" -ForegroundColor Yellow
            if (-not $wasDisabled) {
                Add-RestartReason "$Name ($Description) was disabled and is still running"
            }
        } else {
            Write-Host "  [Service] Disabled $Name  # $Description" -ForegroundColor Green
        }
    } else {
        Write-Host "  [Service] $Name not present (already remediated or not installed)" -ForegroundColor DarkGray
    }
}

# Create the key if needed, set one value, and report it
function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'DWord',
        [string]$Description
    )
    Set-TrackedValue -Path $Path -Name $Name -Value $Value -Type $Type
    Write-Host "  [Registry] $Name = $Value  # $Description" -ForegroundColor Green
}

# Each user's registry: signed-in users' is already loaded; others' is loaded
# from NTUSER.DAT for the moment, under HKU\CIS_<sid>, and unloaded again.
# Runs $Action with the hive's root path and a name for messages. Used here
# and in Section 8.
function Invoke-InEachUserHive {
    param([Parameter(Mandatory)][scriptblock]$Action)
    # Local and Microsoft accounts are S-1-5-21-*, Entra ID (work) accounts S-1-12-1-*
    $profiles = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
        Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-' } |
        ForEach-Object { [pscustomobject]@{ Sid = $_.PSChildName; Path = (Get-ItemProperty -Path $_.PSPath).ProfileImagePath } })
    $profiles += [pscustomobject]@{ Sid = ''; Path = "$env:SystemDrive\Users\Default" }
    foreach ($p in $profiles) {
        $label = if ($p.Sid) { Split-Path $p.Path -Leaf } else { 'Default profile (new accounts)' }
        if ($p.Sid -and (Test-Path "Registry::HKEY_USERS\$($p.Sid)")) {
            & $Action "Registry::HKEY_USERS\$($p.Sid)" $label
            continue
        }
        $hive = Join-Path $p.Path 'NTUSER.DAT'
        if (-not (Test-Path $hive)) {
            Write-Host "  [Users] $label has no registry file yet (never signed in); skipped" -ForegroundColor DarkGray
            continue
        }
        $mount = if ($p.Sid) { "CIS_$($p.Sid)" } else { 'CIS_Default' }
        reg.exe load "HKU\$mount" $hive | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "[Users] Couldn't load $label's registry ($hive); its settings weren't applied"
            continue
        }
        try {
            & $Action "Registry::HKEY_USERS\$mount" $label
        } finally {
            # PowerShell's open registry handles must be released before unloading
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            reg.exe unload "HKU\$mount" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Fail "[Users] Couldn't unload $label's registry; Windows unloads it at restart"
            }
        }
    }
}

# Defender's running mode: 'Normal' when it's the active antivirus, 'Passive
# Mode' and so on when another antivirus is, 'not running' if it can't be asked
function Get-DefenderMode {
    $status = $null
    try { $status = Get-MpComputerStatus -ErrorAction Stop } catch { $status = $null }
    if ($status -and $status.PSObject.Properties['AMRunningMode']) { return "$($status.AMRunningMode)" }
    'not running'
}

# Defender attack surface reduction (ASR) rules - Block
# Obfuscated scripts: these attacks scramble their commands (string tricks,
#   character codes, layers of encoding) to slip past scanners. Defender
#   blocks scripts that look deliberately scrambled. Plain scripts are
#   unaffected, including ones run with -EncodedCommand, which Defender
#   sees decoded.
# Prevalence: a program Defender's cloud service hasn't seen widely, and that
#   isn't old or signed by a trusted publisher, can't run. Malware downloaded
#   by a pasted command is usually brand new, so it's blocked. So, sometimes,
#   is a new or rare legitimate program. Needs cloud-delivered protection,
#   which is on by default.
# Blocks show in Windows Security > Protection history. To allow a program:
#   Add-MpPreference -AttackSurfaceReductionOnlyExclusions 'C:\path\program.exe'
# ASR only works while Defender is the active antivirus; another antivirus
# product turns Defender (and these rules) off.
# Office rules: these stop what a booby-trapped document or email does once
#   it's open (start PowerShell or other programs, drop or inject malware,
#   call Windows from a macro), whatever trick got it opened. Rarely, an
#   add-in that starts other programs is blocked; it shows in Protection
#   history. Section 7 has the rest of the Office settings.
# USB: programs on a USB drive can't run unless they're signed or widely seen.
#   Aimed at USB worms such as Raspberry Robin, whose shortcuts on a stick
#   look like its folders. Signed installers and well-known tools on USB
#   still run; copy anything else to the PC first.
$asrRules = [ordered]@{
    '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = 'Block execution of potentially obfuscated scripts'
    '01443614-cd74-433a-b99e-2ecdc07bfc25' = 'Block executables unless they meet prevalence, age or trusted list criteria'
    'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 'Block all Office applications from creating child processes'
    '3b576869-a4ec-4529-8536-b80a7769e899' = 'Block Office applications from creating executable content'
    '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 'Block Office applications from injecting code into other processes'
    '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 'Block Win32 API calls from Office macros'
    '26190899-1602-49e8-8b27-eb1d0a1ce869' = 'Block Office communication application (Outlook) from creating child processes'
    'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 'Block executable content from email client and webmail'
    'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 'Block untrusted and unsigned processes that run from USB'
}

# ---------------------------------------------------------------
# Hardening steps
# Each runs strict, so any error ends just that step, which is reported
# as a failure, and the next step carries on.
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# SECTION 1: Google Chrome Policies (CIS Chrome Benchmark v3.0.0)
# Most of these map directly to registry values under
# HKLM\SOFTWARE\Policies\Google\Chrome
#
# Values set here are mandatory: chrome://settings shows a "Managed by your
# organization" note and the user can't change them. Deleting a value from
# that key (then restarting Chrome) hands the setting back to the user.
# chrome://policy lists every policy Chrome read, and flags any it didn't
# recognise or that has a bad value.
# ---------------------------------------------------------------
function Set-ChromeHardening {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Applying Google Chrome CIS Recommendations" '.'

    # 1.1.1 Cross-origin HTTP Authentication prompts - Disabled
    # Prevents third-party content from triggering HTTP auth dialogs (phishing mitigation).
    # An image or iframe from another site on a page could otherwise pop up a
    # username/password box that looks like it belongs to the page you're on.
    # Login prompts from the site in the address bar still work.
    Set-ChromePolicy -Name 'AllowCrossOriginAuthPrompt' -Value 0 -Description 'Disable cross-origin HTTP authentication prompts (anti-phishing)'

    # 1.2.2 Safe Browsing Protection Level - Standard or higher
    # Enables Safe Browsing in standard mode (or enhanced). Protects against malicious sites/downloads.
    # Values: 0 = off (fails CIS), 1 = Standard, 2 = Enhanced. Both 1 and 2 pass.
    # Standard checks sites and downloads against Google's list of known-bad sites,
    # sending only partial, anonymised URL fingerprints through a relay.
    # Enhanced also checks every URL with Google in real time, can upload suspicious
    # downloads for scanning, and warns about breached passwords. It catches new
    # phishing sites sooner, but Google sees far more of your browsing.
    # Being mandatory, 2 keeps Enhanced on, including for anyone who had chosen Standard.
    Set-ChromePolicy -Name 'SafeBrowsingProtectionLevel' -Value 2 -Description 'Enable Safe Browsing (enhanced mode)'

    # 1.3 Allow Google Cast to connect to Cast devices on all IP addresses - Disabled
    # Restricts Cast to private IP addresses only (reduces exposure of media).
    # Only matters if Cast is turned on: 3.2.1 below turns Cast off entirely. Kept
    # so that Cast stays limited to the local network if 3.2.1 is ever removed.
    Set-ChromePolicy -Name 'MediaRouterCastAllowAllIPs' -Value 0 -Description 'Restrict Google Cast to private IPs only'

    # 1.4 Allow queries to a Google time service - Enabled
    # Helps with accurate certificate validation via network time.
    # A wrong system clock makes valid certificates look expired or not yet valid.
    # With the network time, Chrome can say "your clock is wrong" instead of showing
    # a generic certificate error. This is Chrome's default; the policy locks it on.
    Set-ChromePolicy -Name 'BrowserNetworkTimeQueriesEnabled' -Value 1 -Description 'Enable network time queries for certificate validation'

    # 1.5 Allow the audio sandbox to run - Enabled
    # Sandboxes audio processes to limit exploit impact.
    # Audio decoding handles untrusted data from web pages; a bug there stays inside
    # the sandbox instead of reaching the rest of the system. On by default; the
    # policy stops it being turned off. Rarely, audio software that hooks into
    # Chrome's audio process stops working.
    Set-ChromePolicy -Name 'AudioSandboxEnabled' -Value 1 -Description 'Enable audio process sandboxing'

    # 1.6 Ask where to save each file before downloading - Enabled
    # Forces user confirmation before downloads (reduces drive-by malware).
    # Every download opens a Save As dialog, so a page can't quietly drop files into
    # Downloads. The price is one extra click per download.
    Set-ChromePolicy -Name 'PromptForDownloadLocation' -Value 1 -Description 'Prompt for download location'

    # 1.7 Continue running background apps when Google Chrome is closed - Disabled
    # Prevents background processes after browser close (reduces persistence/attack surface).
    # Closing the last window really quits Chrome: no tray icon, and extensions stop
    # running. Site notifications (e.g. web mail or chat) only arrive while Chrome is open.
    Set-ChromePolicy -Name 'BackgroundModeEnabled' -Value 0 -Description 'Disable background apps when Chrome is closed'

    # 1.13 Disable saving browser history - Disabled (i.e. allow history)
    # Note: the policy "Disable saving browser history" set to Disabled means history IS saved.
    # Keeping history aids forensics.
    # Users can still delete their own history; preventing that is a separate
    # policy (AllowDeletingBrowserHistory), which isn't set here.
    Set-ChromePolicy -Name 'SavingBrowserHistoryDisabled' -Value 0 -Description 'Allow browser history (aids forensics)'

    # 1.14 DNS interception checks enabled - Enabled
    # Detects DNS interception (common in some enterprise proxies or malware).
    # Chrome looks up a few made-up host names. If they resolve, the network is
    # answering for names that don't exist (an ISP "search assist" page, a captive
    # portal, or something worse), and Chrome stops trusting such answers when
    # deciding whether a single word typed in the address bar is a local host name.
    # On by default; the policy keeps it on.
    Set-ChromePolicy -Name 'DnsInterceptionChecksEnabled' -Value 1 -Description 'Enable DNS interception checks'

    # Secure DNS - automatic (prefer DNS over HTTPS, fall back to plain DNS)
    # Values: off, automatic, secure (DoH only, no fallback). In automatic mode
    # Chrome uses DoH whenever the system DNS server offers it. Quad9 and OpenDNS
    # (Section 5) both do, so Chrome encrypts its lookups to the same servers
    # Windows uses. "Use secure DNS" in chrome://settings/security shows as managed.
    # Encrypted Client Hello (2.22) relies on DNS answers Chrome gets this way.
    Set-ChromePolicy -Name 'DnsOverHttpsMode' -Value 'automatic' -Type String -Description 'Prefer DNS over HTTPS'

    # 1.15 Enable component updates in Google Chrome - Enabled
    # Ensures component updates (e.g. Widevine, recovery) stay current.
    # Components are updated separately from Chrome itself. They include security
    # data, such as the list of revoked certificates (CRLSet), as well as the
    # Widevine video DRM module. Turning them off would leave that data stale
    # between Chrome releases.
    Set-ChromePolicy -Name 'ComponentUpdatesEnabled' -Value 1 -Description 'Enable component updates'

    # 1.16 Enable globally scoped HTTP auth cache - Disabled
    # Limits HTTP auth credential scope (reduces credential reuse risk).
    # A username and password typed into a site's login box are only reused for
    # that site, not sent when some other site embeds it. This is Chrome's
    # default; the policy locks it.
    Set-ChromePolicy -Name 'GloballyScopeHTTPAuthCacheEnabled' -Value 0 -Description 'Disable globally scoped HTTP auth cache'

    # 1.18 Enable security warnings for command-line flags - Enabled
    # Warns users when potentially dangerous flags are used.
    # If Chrome is started with a flag that weakens security (e.g. --no-sandbox or
    # --disable-web-security), a bar across the top says so. Malware sometimes
    # starts Chrome with such flags; the bar makes that visible.
    Set-ChromePolicy -Name 'CommandLineFlagSecurityWarningsEnabled' -Value 1 -Description 'Enable security warnings for command-line flags'

    # 1.19 Enable third party software injection blocking - Enabled
    # Blocks third-party DLL injection into Chrome processes.
    # Software that isn't Microsoft-signed can't load its code into Chrome. This
    # stops crashes and spying from injected DLLs. Older antivirus, screen readers or
    # keyboard tools that inject into Chrome may stop working inside the browser.
    Set-ChromePolicy -Name 'ThirdPartyBlockingEnabled' -Value 1 -Description 'Block third-party software injection'

    # 2.3.1 Blocks external extensions from being installed - Enabled
    # Prevents sideloading of extensions outside the Chrome Web Store / enterprise policy.
    # "External" extensions are ones other programs on the PC register for Chrome
    # to pick up, a common route for adware. Extensions you install from the Web
    # Store yourself still work, as do ones pushed by policy.
    Set-ChromePolicy -Name 'BlockExternalExtensions' -Value 1 -Description 'Block external (sideloaded) extensions'

    # 2.3 Extension allowlist - block every extension except $ApprovedChromeExtensions
    # CIS recommends blocklisting * and allowing only approved extension IDs.
    # Installed extensions not on the list are disabled ("Blocked by your
    # administrator" in chrome://extensions) and users can't turn them back on or
    # install new ones. Nothing is uninstalled: adding an ID to the list later
    # re-enables that extension with its settings intact. Themes count as
    # extensions, so a theme needs to be listed too. This only allows the listed
    # extensions; it doesn't install them (that's ExtensionInstallForcelist).
    # Chrome normally picks up the change within a minute or so; restart it, or use
    # "Reload policies" in chrome://policy, to apply it straight away.
    # Chrome's IDs are lowercase and won't match in any other case
    $ids = @($ApprovedChromeExtensions | ForEach-Object { "$_".Trim().ToLowerInvariant() })
    foreach ($id in $ids | Where-Object { $_ -cnotmatch '^[a-p]{32}$' }) {
        Write-Fail "[Chrome] '$id' isn't an extension ID (32 letters a-p); left out of the allowlist"
    }
    $allowIds = @($ids | Where-Object { $_ -cmatch '^[a-p]{32}$' } | Sort-Object -Unique)

    # Show what the allowlist will leave on and turn off, so new IDs can be copied
    # into $ApprovedChromeExtensions
    $installed = @(Get-InstalledChromeExtension)
    if ($installed.Count -eq 0) {
        Write-Host "  [Extension] No extensions found in any user's Chrome profiles" -ForegroundColor DarkGray
    }
    # One line per extension, naming every user\profile that has it
    foreach ($group in $installed | Group-Object Id | Sort-Object { $_.Group[0].Name }) {
        $id = $group.Name
        $name = $group.Group[0].Name
        $where = ($group.Group | ForEach-Object { "$($_.User)\$($_.Profile)" }) -join ', '
        if ($allowIds -contains $id) {
            Write-Host "  [Extension] Approved: $name ($id)  # $where" -ForegroundColor Green
        } else {
            Write-Host "  [Extension] Disabling: $name ($id)  # $where" -ForegroundColor Yellow
            Write-Fail "[Extension] $name ($id) is installed and not approved ($where). Add the ID to `$ApprovedChromeExtensions or remove the extension"
        }
    }
    if ($allowIds.Count -eq 0) {
        Write-Host "  [Extension] No approved extensions listed, so every extension will be disabled" -ForegroundColor Yellow
    }

    Set-ChromePolicyList -Name 'ExtensionInstallAllowlist' -Values $allowIds -Description 'Approved extensions'
    Set-ChromePolicyList -Name 'ExtensionInstallBlocklist' -Values @('*') -Description 'Block every extension not on the allowlist'

    # 2.11 Allow download restrictions - Block malicious downloads
    # Blocks downloads flagged as malicious by Safe Browsing.
    # Values: 0 = no restrictions, 1 = block dangerous files, 2 = block potentially
    # dangerous files, 3 = block all downloads, 4 = block malicious downloads.
    # 4 only blocks files Safe Browsing has identified as malware, so legitimate
    # but uncommon files (e.g. new installers) still download, with a warning.
    # Depends on Safe Browsing (1.2.2) being on.
    Set-ChromePolicy -Name 'DownloadRestrictions' -Value 4 -Description 'Block malicious downloads'

    # 2.12 Allow proceeding from the SSL warning page - Disabled
    # Prevents users from bypassing SSL/TLS certificate warnings.
    # The "Advanced > Proceed anyway" link disappears from certificate error pages.
    # This stops a man-in-the-middle attack from working through a click, but it
    # also locks you out of devices with self-signed certificates, such as router,
    # NAS, printer or server management pages. Use another browser for those, or list
    # them in the SSLErrorOverrideAllowedForOrigins policy.
    #Set-ChromePolicy -Name 'SSLErrorOverrideAllowed' -Value 0 -Description 'Disallow proceeding past SSL warnings'
    #------------------
    # The CIS benchmark says to disable this, but it makes Chrome unusable for
    # many home and small-business devices. The policy is left enabled, but the
    # allowlist below lets you add any self-signed sites you need to visit.
    Set-ChromePolicy -Name 'SSLErrorOverrideAllowed' -Value 1 -Description 'Allow proceeding past SSL warnings'

    # 2.13 Disable proceeding from the Safe Browsing warning page - Enabled
    # Prevents users from bypassing Safe Browsing interstitial warnings.
    # The red "Deceptive site ahead" / "Dangerous site" pages can't be clicked
    # through. If Safe Browsing flags a site wrongly, it can't be visited in Chrome
    # until Google removes it from the list.
    Set-ChromePolicy -Name 'DisableSafeBrowsingProceedAnyway' -Value 1 -Description 'Prevent bypassing Safe Browsing warnings'

    # 2.14 Require Site Isolation for every site - Enabled
    # Isolates each site into its own process (Spectre mitigation / stronger isolation).
    # A compromised or malicious page can't read memory belonging to another
    # site's page, such as your bank in another tab. Desktop Chrome already does
    # this by default; the policy stops it being turned off. It uses more memory.
    Set-ChromePolicy -Name 'SitePerProcess' -Value 1 -Description 'Enable Site Isolation for every site'

    # 2.22 Enable TLS Encrypted ClientHello - Enabled
    # Enables Encrypted Client Hello (ECH) for better privacy against network observers.
    # Normally the name of the site you're connecting to travels unencrypted at the
    # start of each HTTPS connection. ECH encrypts it for sites that support it
    # (e.g. many behind Cloudflare). Network filters that block sites by that name
    # can no longer see it, though DNS-based filtering still works.
    Set-ChromePolicy -Name 'EncryptedClientHelloEnabled' -Value 1 -Description 'Enable TLS Encrypted ClientHello (ECH)'

    # 2.28 Enable automatic HTTPS upgrades - Enabled
    # Automatically upgrades HTTP navigations to HTTPS when possible.
    # An http:// link is tried over https:// first, falling back to http:// if the
    # site doesn't support it. This is not HTTPS-only mode: plain HTTP sites still
    # load, without a warning page (that's the separate HttpsOnlyMode policy).
    Set-ChromePolicy -Name 'HttpsUpgradesEnabled' -Value 1 -Description 'Enable automatic HTTPS upgrades'

    # 2.30 Enable Renderer App Container - Enabled
    # Runs renderer processes in an App Container for stronger sandboxing.
    # Renderers (the processes that run web pages) get a tighter Windows sandbox,
    # so an exploited page has even less access to files and the system. Security
    # or DLP software that injects into renderers may stop working there.
    Set-ChromePolicy -Name 'RendererAppContainerEnabled' -Value 1 -Description 'Enable Renderer App Container'

    # Extra (not CIS): JavaScript optimizer - Blocked, except $JsOptimizerAllowedSites
    # Chrome's JavaScript engine (V8) has optimizing compilers that turn
    # frequently run code into fast machine code on the fly. Bugs in them are the
    # most common way real attacks break into Chrome. Blocking them removes that
    # route for every site not on the list.
    # Values: 1 = allow (Chrome's default), 2 = block. Shown in
    # chrome://settings/content/v8 ("JavaScript optimization & security") as
    # managed, and users can't add their own exceptions.
    # Everyday sites feel much the same; heavy web apps (online editors, design
    # tools, web games, big spreadsheets) get noticeably slower, so add any you rely
    # on to $JsOptimizerAllowedSites. If chrome://policy lists this policy as
    # unknown, Chrome is too old for it; update Chrome.
    Set-ChromePolicy -Name 'DefaultJavaScriptOptimizerSetting' -Value 2 -Description 'Block the JavaScript optimizer by default'
    Set-ChromePolicyList -Name 'JavaScriptOptimizerAllowedForSites' -Values $JsOptimizerAllowedSites -Description 'Sites allowed to use the JavaScript optimizer'

    # Extra (not CIS): Chrome Remote Desktop - Blocked
    # Chrome Remote Desktop lets someone with your Google account and PIN (remote
    # access), or anyone given a one-time code (remote support), see and control
    # this PC. Remote support codes are a common tech-support scam.
    # The remote-desktop program on the PC reads these two policies itself, so they
    # also block a copy installed after this script runs. Its service is disabled
    # in Section 3, and its helper extension stays disabled by the extension
    # allowlist above unless its ID is added there.
    Set-ChromePolicy -Name 'RemoteAccessHostAllowRemoteAccessConnections' -Value 0 -Description 'Refuse incoming Chrome Remote Desktop connections'
    Set-ChromePolicy -Name 'RemoteAccessHostAllowRemoteSupportConnections' -Value 0 -Description 'Refuse Chrome Remote Desktop remote support sessions'
    # Blocking the website also stops this PC from connecting out to other
    # computers, which the policies above don't cover. Chrome shows "blocked by
    # your organization" there. This policy blocks any site; add more patterns here
    # (e.g. 'example.com' blocks that domain and its subdomains).
    Set-ChromePolicyList -Name 'URLBlocklist' -Values @('remotedesktop.google.com') -Description 'Block the Chrome Remote Desktop website'

    # 3.1.2 Default geolocation setting - Do not allow
    # Blocks sites from accessing physical location by default.
    # Values: 1 = allow, 2 = block, 3 = ask each time. With 2, sites aren't even
    # allowed to ask, so "near me" searches and map sites fall back to rough,
    # IP-based location or a typed address.
    Set-ChromePolicy -Name 'DefaultGeolocationSetting' -Value 2 -Description 'Block geolocation by default'

    # 3.2.1 Enable Google Cast - Disabled
    # Disables Cast entirely (reduces attack surface and data exposure).
    # The Cast option disappears from Chrome's menu, and tabs, YouTube etc. can't be
    # sent to a Chromecast or Google TV from this browser. Remove this line if you
    # cast from this PC.
    Set-ChromePolicy -Name 'EnableMediaRouter' -Value 0 -Description 'Disable Google Cast'

    # 3.3 Allow websites to query for available payment methods - Disabled
    # Blocks Payment Request API (reduces fingerprinting / data exposure).
    # Sites can't ask Chrome whether you have a saved payment method. That yes/no
    # answer can help a site recognise you. Card payment forms still work.
    Set-ChromePolicy -Name 'PaymentMethodQueryEnabled' -Value 0 -Description 'Disable payment method queries'

    # 3.4 Block third party cookies - Enabled
    # Blocks third-party cookies (privacy / tracking protection).
    # Cookies set by sites embedded in a page (ad and tracking networks) are
    # refused. Some embedded content breaks: sign-in boxes for other sites,
    # comment widgets, and some single sign-on flows. Per-site exceptions can be
    # added in chrome://settings/cookies.
    Set-ChromePolicy -Name 'BlockThirdPartyCookies' -Value 1 -Description 'Block third-party cookies'

    # 3.7 Disable synchronization of data with Google - Enabled
    # Prevents syncing of data (bookmarks, passwords, etc.) to Google accounts.
    # Bookmarks, saved passwords, history, open tabs and extensions stay on this
    # PC only, and passwords saved on your phone won't appear here. You can still
    # sign in to Google websites. Remove this line if you rely on Chrome sync.
    #Set-ChromePolicy -Name 'SyncDisabled' -Value 1 -Description 'Disable Google account sync'
    #------------------
    # The CIS benchmark says to disable this, but it makes Chrome unusable for
    # anyone who signs in to Google websites. The policy is left enabled, so sync
    # works, but the value is set to 0 (enabled) instead of 1 (disabled). If you want to follow CIS, change the value below to 1.
    Set-ChromePolicy -Name 'SyncDisabled' -Value 0 -Description 'Disable Google account sync'

    # 3.12 Enable reporting of usage and crash-related data - Disabled
    # Disables telemetry / crash reporting to Google.
    # Usage statistics and crash reports are no longer sent. Nothing changes for
    # you, except that Google won't see your crashes when fixing bugs.
    Set-ChromePolicy -Name 'MetricsReportingEnabled' -Value 0 -Description 'Disable usage and crash reporting'

    # 4.9 Enable AutoFill for credit cards - Disabled
    # Disables credit card autofill (reduces exposure of payment data).
    # Chrome stops offering to save cards and stops filling in saved ones, so a
    # malicious page or infostealer can't get them from Chrome. Cards you've
    # already saved aren't deleted; remove them in chrome://settings/payments.
    Set-ChromePolicy -Name 'AutofillCreditCardEnabled' -Value 0 -Description 'Disable credit card autofill'

    # 5.2 Incognito mode availability - left available
    # Values: 0 = available, 1 = disabled, 2 = forced (every window is Incognito).
    # CIS sets 1, which removes "New Incognito window". That is left at 0 here:
    # history (1.13) and sync (3.7) stay locked on, and Incognito remains usable.
    # To follow CIS, set the value below to 1.
    Set-ChromePolicy -Name 'IncognitoModeAvailability' -Value 0 -Description 'Leave Incognito mode available'

    Write-Host "Chrome policies applied. Verify at chrome://policy/ after restarting Chrome." -ForegroundColor Cyan
}

# ---------------------------------------------------------------
# SECTION 3: Windows 11 System Services to Disable
# CIS Windows 11 Benchmark v5.0.0 - Section 5 (selected high-value items)
#
# L1 / L2 are CIS profile levels. Level 1 is meant to be safe almost
# everywhere; Level 2 trades away features for security. Several L2 items
# below remove features a home PC may use, so comment out any you need.
# To undo one: Set-Service <name> -StartupType Manual, then Start-Service <name>.
# ---------------------------------------------------------------
function Disable-UnneededService {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Disabling Unnecessary Windows Services" '.'

    # Old SMB1 network-neighbourhood browsing. Not installed on Windows 11 unless
    # SMB1 was added back, so this usually reports "not present". The SMB1Protocol
    # Windows feature itself is removed by the smb1 step.
    Disable-ServiceIfExists -Name 'Browser' -Description 'Computer Browser (legacy NetBIOS service - L1)'
    # Downloads and updates offline maps for the Maps app. Nothing else needs it.
    Disable-ServiceIfExists -Name 'MapsBroker' -Description 'Downloaded Maps Manager (L2 - reduces location data exposure)'
    # Game controller input for games that use Microsoft's GameInput API. Some
    # games may stop seeing controllers.
    Disable-ServiceIfExists -Name 'GameInputSvc' -Description 'GameInput Service (L2 - reduces DMA input capture risk)'
    # Lets other computers read and change this PC's registry over the network.
    # Already disabled by default on Windows 11; this makes sure it stays off.
    Disable-ServiceIfExists -Name 'RemoteRegistry' -Description 'Remote Registry (L1 - reduces remote attack surface)'
    # Lets the PC act as a router or VPN server. Not needed to connect to a VPN,
    # only to host one. Disabled by default on Windows 11.
    Disable-ServiceIfExists -Name 'RemoteAccess' -Description 'Routing and Remote Access (L1)'
    # Not CIS: Chrome Remote Desktop's background program, which accepts incoming
    # connections. Only present if Chrome Remote Desktop was set up on this PC.
    # (Unrelated to RemoteAccess above, despite the names.)
    Disable-ServiceIfExists -Name 'chromoting' -Description 'Chrome Remote Desktop Service (blocks remote control of this PC)'
    # The three Xbox services: sign-in, cloud saves and multiplayer networking.
    # Without them, the Xbox app, Game Pass and Xbox Live features in PC games
    # stop working.
    Disable-ServiceIfExists -Name 'XblAuthManager' -Description 'Xbox Live Auth Manager (L2)'
    Disable-ServiceIfExists -Name 'XblGameSave' -Description 'Xbox Live Game Save (L2)'
    Disable-ServiceIfExists -Name 'XboxNetApiSvc' -Description 'Xbox Live Networking (L2)'
}

# ---------------------------------------------------------------
# SECTION 4: Additional High-Value Windows Registry Settings
# (selected from Administrative Templates / Security Options)
# ---------------------------------------------------------------
function Set-SecurityRegistry {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Applying Additional Windows Security Registry Settings" '.'

    # Disable AutoAdminLogon (MSS)
    # With automatic logon on, Windows signs in by itself at boot using a password
    # stored in the registry (DefaultPassword), readable by admins and some tools.
    # Setting 0 turns automatic logon off. A password left behind is deleted here.
    # Remove-ItemProperty, not Remove-TrackedValue: the undo file must not contain it.
    $mssPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-TrackedValue -Path $mssPath -Name 'AutoAdminLogon' -Value 0
    Write-Host "  [Registry] AutoAdminLogon = 0  # Disable automatic logon (MSS)" -ForegroundColor Green
    $savedPassword = Get-RegistryValueState -Path $mssPath -Name 'DefaultPassword'
    if ($null -ne $savedPassword) {
        Remove-ItemProperty -Path $mssPath -Name 'DefaultPassword' -Force
        Write-Fail '[Registry] A saved automatic-logon password (DefaultPassword) was removed. It was not copied into the registry undo file. Set a normal password sign-in if that account was signing in by itself'
    }

    # WDigest Authentication - Disabled (reduces credential theft risk)
    # When on, Windows keeps a reversible copy of each signed-in user's password in
    # memory (LSASS), which credential dumpers such as Mimikatz read. Windows 10/11
    # already leave it off when the value is absent. Attackers with admin rights set
    # it to 1 and wait for the next sign-in, so setting 0 records the intended
    # state. If you ever find it at 1, treat that as a sign of compromise.
    $wdigestPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
    Set-TrackedValue -Path $wdigestPath -Name 'UseLogonCredential' -Value 0
    Write-Host "  [Registry] WDigest UseLogonCredential = 0  # Disable WDigest (reduces credential exposure in memory)" -ForegroundColor Green
}

# ---------------------------------------------------------------
# SECTION 5: DNS servers and DNS over HTTPS (DoH)
# Uses $DnsServers from the top of the script.
#
# Every physical network adapter (wired, Wi-Fi) gets these DNS servers instead
# of the ones the router or network hands out. Names that only your router
# knows (e.g. nas.lan, or a device's name on the local network) stop resolving.
# A few hotel/airport Wi-Fi sign-in pages and work networks that need their own
# DNS may also have trouble. VPN adapters aren't changed, so a VPN's own DNS
# still works. To undo on one adapter:
#   Set-DnsClientServerAddress -InterfaceIndex <n> -ResetServerAddresses
# Check DoH is in use: Get-DnsClientDohServerAddress, or https://on.quad9.net
# ---------------------------------------------------------------
function Set-SecureDns {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Setting DNS Servers and DNS over HTTPS" '.'

    # Tell Windows each server's DoH address. AutoUpgrade: use DoH whenever an
    # adapter points at this server. AllowFallbackToUdp: if DoH fails, use plain
    # DNS rather than none ("prefer", not "require"). Windows 11 already knows
    # Quad9; OpenDNS has to be added.
    foreach ($server in $DnsServers) {
        try {
            if (Get-DnsClientDohServerAddress -ServerAddress $server.Address -ErrorAction SilentlyContinue) {
                Set-DnsClientDohServerAddress -ServerAddress $server.Address -DohTemplate $server.Template `
                    -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop | Out-Null
            } else {
                Add-DnsClientDohServerAddress -ServerAddress $server.Address -DohTemplate $server.Template `
                    -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop | Out-Null
            }
            Write-Host "  [DoH] $($server.Address) -> $($server.Template)  # encrypted when possible, plain DNS as fallback" -ForegroundColor Green
        } catch {
            Write-Fail "[DoH] Couldn't set the DoH address for $($server.Address): $($_.Exception.Message)"
        }
    }

    # Turn DoH on system-wide. Values: 1 = prohibit DoH, 2 = allow DoH (use it for
    # servers that support it, fall back otherwise), 3 = require DoH (no fallback;
    # DNS fails if DoH can't be reached). This is the "Configure DNS over HTTPS
    # (DoH) name resolution" Group Policy, which CIS asks to be at least "Allow".
    $dohPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    Set-TrackedValue -Path $dohPolicyPath -Name 'DoHPolicy' -Value 2
    Write-Host "  [Registry] DoHPolicy = 2  # Allow DoH: prefer encrypted DNS, plain DNS as fallback" -ForegroundColor Green

    # Point every physical adapter at the servers. Windows keeps IPv4 and IPv6
    # servers in separate lists, each in the order given.
    $dnsAddresses = @($DnsServers | ForEach-Object { $_.Address })
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
    if ($adapters.Count -eq 0) {
        Write-Fail "[DNS] No physical network adapters found; DNS servers not set"
    }
    foreach ($adapter in $adapters) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dnsAddresses -ErrorAction Stop
            Write-Host "  [DNS] $($adapter.Name): $($dnsAddresses -join ', ')" -ForegroundColor Green
        } catch {
            Write-Fail "[DNS] Couldn't set DNS servers on $($adapter.Name): $($_.Exception.Message)"
        }
    }
    # Forget answers from the old servers so the new ones are used straight away
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------
# SECTION 5b: Hosts file restored to the default (not CIS)
# Windows looks names up in the hosts file before asking DNS, so a line in it
# overrides DNS over HTTPS and everything in Section 5. Malware adds lines
# that send a bank, email or update site to its own server, or point
# security sites at nothing so updates fail.
# Each run compares the file's entries (comments and spacing aside) with
# Windows' default plus $ApprovedHostsEntries at the top. If they differ, the
# file is backed up to the log folder, rewritten, and the change reported
# as a failure with the lines removed, so it shows in the summary.
# Also put back if changed:
#   - DataBasePath: the registry setting for the folder Windows reads the
#     hosts file from. Malware can point it at a folder of its own, which
#     leaves the real hosts file looking untouched.
#   - Permissions: only administrators and SYSTEM should be able to change
#     the file. If anyone else can, they're reset to the folder's defaults.
# ---------------------------------------------------------------
function Repair-HostsFile {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Checking the Hosts File' '.'

    # Where Windows reads hosts from
    $tcpip = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    $defaultDir = '%SystemRoot%\System32\drivers\etc'
    $tcpipValues = Get-ItemProperty -Path $tcpip -ErrorAction SilentlyContinue
    $dbPath = if ($tcpipValues -and $tcpipValues.PSObject.Properties['DataBasePath']) { $tcpipValues.DataBasePath } else { $null }
    # Compare expanded, since the value is usually stored unexpanded
    if ($dbPath -and [Environment]::ExpandEnvironmentVariables($dbPath) -ne [Environment]::ExpandEnvironmentVariables($defaultDir)) {
        Set-TrackedValue -Path $tcpip -Name 'DataBasePath' -Value $defaultDir -Type ExpandString
        Write-Fail "[Hosts] Windows was reading the hosts file from $dbPath; set back to $defaultDir"
    }
    $hosts = Join-Path ([Environment]::ExpandEnvironmentVariables($defaultDir)) 'hosts'

    # Windows' default file: all comments, so every name goes to DNS
    $default = @(
        '# Copyright (c) 1993-2009 Microsoft Corp.'
        '#'
        '# This is a sample HOSTS file used by Microsoft TCP/IP for Windows.'
        '#'
        '# This file contains the mappings of IP addresses to host names. Each'
        '# entry should be kept on an individual line. The IP address should'
        '# be placed in the first column followed by the corresponding host name.'
        '# The IP address and the host name should be separated by at least one'
        '# space.'
        '#'
        '# Additionally, comments (such as these) may be inserted on individual'
        "# lines or following the machine name denoted by a '#' symbol."
        '#'
        '# For example:'
        '#'
        '#      102.54.94.97     rhino.acme.com          # source server'
        '#       38.25.63.10     x.acme.com              # x client host'
        ''
        '# localhost name resolution is handled within DNS itself.'
        "#`t127.0.0.1       localhost"
        "#`t::1             localhost"
    )

    # An entry as "ip name name...": comments dropped, spacing and case evened out
    function ConvertTo-HostsEntry([string]$line) {
        $words = @(($line -replace '#.*$', '').Trim() -split '\s+' | Where-Object { $_ })
        if ($words.Count -lt 2) { return }
        (@($words[0]) + @($words[1..($words.Count - 1)] | ForEach-Object { $_.ToLowerInvariant() })) -join ' '
    }
    $approved = @($ApprovedHostsEntries | ForEach-Object { ConvertTo-HostsEntry $_ } | Where-Object { $_ })
    foreach ($line in $ApprovedHostsEntries) {
        if (-not (ConvertTo-HostsEntry $line)) {
            Write-Fail "[Hosts] '$line' in `$ApprovedHostsEntries isn't an IP address followed by a name; left out"
        }
    }

    $current = @()
    $exists = Test-Path -LiteralPath $hosts
    if ($exists) {
        $current = @(Get-Content -LiteralPath $hosts | ForEach-Object { ConvertTo-HostsEntry $_ } | Where-Object { $_ })
    }
    $extra = @($current | Where-Object { $approved -notcontains $_ })
    $missing = @($approved | Where-Object { $current -notcontains $_ })

    if ($exists -and $extra.Count -eq 0 -and $missing.Count -eq 0) {
        Write-Host "  [Hosts] Unchanged (approved entries: $($current.Count), nothing else)" -ForegroundColor Green
    } else {
        if ($exists) {
            $backup = Join-Path $LogDir "hosts-$(Get-Date -Format yyyyMMdd-HHmmss-fff).txt"
            Copy-Item -LiteralPath $hosts -Destination $backup -Force
        }
        $content = $default
        if ($approved) { $content += @('', '# Approved entries (dailyrunme.ps1 $ApprovedHostsEntries)') + $approved }
        # A read-only hosts file has to be made writable, then put back as it was
        $readOnly = $exists -and (Get-Item -LiteralPath $hosts).IsReadOnly
        try {
            if ($readOnly) { Set-ItemProperty -LiteralPath $hosts -Name IsReadOnly -Value $false }
            Set-Content -LiteralPath $hosts -Value $content -Encoding ASCII -Force
        } finally {
            # Put the flag back even when the write fails, or a locked file stays writable
            if ($readOnly) {
                try { Set-ItemProperty -LiteralPath $hosts -Name IsReadOnly -Value $true } catch {
                    Write-Fail "[Hosts] Couldn't put the read-only flag back: $($_.Exception.Message)"
                }
            }
        }
        Clear-DnsClientCache -ErrorAction SilentlyContinue

        if (-not $exists) {
            Write-Fail "[Hosts] The hosts file was missing; recreated it"
        } elseif ($extra) {
            Write-Fail "[Hosts] Removed $($extra.Count) unapproved entries (backup: $backup): $($extra -join '; ')"
        } else {
            Write-Host "  [Hosts] Added $($missing.Count) approved entries (backup: $backup)" -ForegroundColor Green
        }
    }

    # Permissions: anyone other than administrators, SYSTEM and TrustedInstaller
    # able to write it means they've been loosened. Only the rights that allow a
    # change count (Modify and FullControl also contain the read rights every
    # user has): write and append data, write attributes, delete, change
    # permissions, take ownership, and the generic write and all rights.
    $writeRights = 0x2 -bor 0x4 -bor 0x10 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x40000000 -bor 0x10000000
    $trusted = 'S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
    $loose = @((Get-Acl -LiteralPath $hosts).Access | Where-Object {
        $_.AccessControlType -eq 'Allow' -and ([int]$_.FileSystemRights -band $writeRights) -and
        $(try { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { '' }) -notin $trusted
    })
    if ($loose) {
        icacls.exe $hosts /reset | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "[Hosts] $(($loose.IdentityReference) -join ', ') can change the hosts file, and resetting its permissions failed (icacls exit $LASTEXITCODE)"
        } else {
            Write-Fail "[Hosts] $(($loose.IdentityReference) -join ', ') could change the hosts file; permissions reset to the folder's defaults"
        }
    } else {
        Write-Host "  [Hosts] Permissions: only administrators and SYSTEM can change it" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------
# SECTION 6: PowerShell and script protections
# Aimed at "ClickFix" tricks: a fake CAPTCHA or error page copies a command
# to the clipboard and tells the user to press Win+R (or open Terminal),
# paste and press Enter. Typically: powershell -w hidden -c "iwr <url> | iex".
# None of this stops a determined user, but it breaks the usual commands, stops
# what they download from running, and records what ran.
# Execution policy isn't used: it only covers .ps1 files, not pasted
# commands, and -ExecutionPolicy Bypass skips it.
# ---------------------------------------------------------------
function Set-ScriptProtection {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Applying PowerShell and Script Protections" '.'

    $mpMode = Get-DefenderMode
    if ($mpMode -ne 'Normal') {
        Write-Fail "[ASR] Defender isn't the active antivirus (mode: $mpMode); ASR rules not set"
    } else {
        # Actions already stored for one rule, in order. Defender uses the first.
        # $null when the preference isn't set, so a missing list isn't one empty entry.
        function Get-AsrActions {
            param([Parameter(Mandatory)][string]$RuleId)
            $pref = Get-MpPreference
            $rawIds = $pref.AttackSurfaceReductionRules_Ids
            $rawActions = $pref.AttackSurfaceReductionRules_Actions
            if ($null -eq $rawIds) { return @() }
            $ids = @($rawIds)
            $actions = @($rawActions)
            $found = @()
            for ($n = 0; $n -lt $ids.Count; $n++) {
                if ("$($ids[$n])".ToLowerInvariant() -eq $RuleId -and $n -lt $actions.Count) {
                    $found += ,$actions[$n]
                }
            }
            return $found
        }
        foreach ($id in $asrRules.Keys) {
            $actionsNow = @(Get-AsrActions $id)
            # One Block entry is the state we want. Anything else (missing, Audit,
            # Warn, or a copy appended by an earlier run) is cleared and set again.
            # Add-MpPreference only appends, and Defender keeps the first copy.
            $already = ($actionsNow.Count -eq 1 -and [int]$actionsNow[0] -eq 1)
            if (-not $already) {
                try {
                    $guard = 0
                    while (($actionsNow = @(Get-AsrActions $id)).Count -gt 0 -and $guard -lt 30) {
                        $guard += 1
                        Remove-MpPreference -AttackSurfaceReductionRules_Ids $id `
                            -AttackSurfaceReductionRules_Actions ([int]$actionsNow[0]) -ErrorAction Stop
                    }
                    if (@(Get-AsrActions $id).Count -gt 0) {
                        Write-Fail "[ASR] Couldn't clear the old copies of '$($asrRules[$id])'"
                        continue
                    }
                    Add-MpPreference -AttackSurfaceReductionRules_Ids $id `
                        -AttackSurfaceReductionRules_Actions Enabled -ErrorAction Stop
                } catch {
                    Write-Fail "[ASR] Couldn't set '$($asrRules[$id])': $($_.Exception.Message)"
                    continue
                }
            }
            # 1 = block (0 = off, 2 = audit only, 6 = warn)
            $after = @(Get-AsrActions $id)
            if ($after.Count -ge 1 -and [int]$after[0] -eq 1) {
                Write-Host "  [ASR] Block: $($asrRules[$id])" -ForegroundColor Green
            } else {
                Write-Fail "[ASR] '$($asrRules[$id])' didn't take effect (check Tamper Protection or other management)"
            }
        }
    }

    # The Run dialog (Win+R) is left on. Earlier versions of this script turned
    # it off with the NoRun policy, which also stops File Explorer opening a
    # typed path such as C:\ProgramData ("restrictions in effect on this
    # computer"). That policy is removed here; the ASR rules above and script
    # block logging below cover the same tricks.
    $explorerPolicy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    if (Get-RegistryValueState -Path $explorerPolicy -Name 'NoRun') {
        Remove-TrackedValue -Path $explorerPolicy -Name 'NoRun'
        Write-Host '  [Registry] NoRun removed: the Run dialog and typed paths in File Explorer work again (after sign-out or an Explorer restart)' -ForegroundColor Green
    }

    # PowerShell Script Block Logging - Enabled (CIS)
    # Records the full text of every PowerShell command and script that runs,
    # after decoding, so obfuscated or encoded commands are logged readable. It
    # detects rather than prevents. Logs land in Event Viewer: Applications and
    # Services Logs > Microsoft > Windows > PowerShell > Operational, event 4104.
    # PowerShell 7 (pwsh) has its own policy key and logs to PowerShellCore >
    # Operational. Secrets typed into commands are logged too.
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' `
        -Name 'EnableScriptBlockLogging' -Value 1 -Description 'Log every PowerShell command (Windows PowerShell)'
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\PowerShellCore\ScriptBlockLogging' `
        -Name 'EnableScriptBlockLogging' -Value 1 -Description 'Log every PowerShell command (PowerShell 7)'
    # The log's default 15 MB fills in days with full command text; at 100 MB it
    # keeps weeks, and the oldest entries are overwritten first.
    wevtutil sl 'Microsoft-Windows-PowerShell/Operational' /ms:104857600
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "[Logging] Couldn't enlarge the PowerShell log (wevtutil exit $LASTEXITCODE)"
    } else {
        Write-Host "  [Logging] PowerShell Operational log max size = 100 MB" -ForegroundColor Green
    }

    # Remove PowerShell 2.0
    # PowerShell 2.0 predates script block logging and Defender's script scanning
    # (AMSI), so attacks run "powershell -version 2" to avoid both. Recent
    # Windows 11 updates remove it entirely; this makes sure. Nothing current
    # needs it. Listing every Windows feature takes a few seconds.
    try {
        $ps2 = Get-WindowsOptionalFeature -Online -ErrorAction Stop |
            Where-Object { $_.FeatureName -eq 'MicrosoftWindowsPowerShellV2Root' }
        $ps2State = if ($ps2) { "$($ps2.State)" } else { 'Disabled' }
        if ($ps2State -eq 'DisablePending') {
            Write-Host '  [Feature] PowerShell 2.0 removal finishes at the next restart' -ForegroundColor Yellow
            Add-RestartReason 'Removing PowerShell 2.0 finishes at the next restart'
        } elseif ($ps2State -notlike 'Enable*') {
            Write-Host "  [Feature] PowerShell 2.0 already removed" -ForegroundColor Green
        } else {
            $result = Disable-WindowsOptionalFeature -Online -FeatureName 'MicrosoftWindowsPowerShellV2Root' -NoRestart -ErrorAction Stop
            if ($result.RestartNeeded) {
                Add-RestartReason 'Removing PowerShell 2.0 finishes at the next restart'
            }
            $note = if ($result.RestartNeeded) { ' (finishes at the next restart)' } else { '' }
            Write-Host "  [Feature] PowerShell 2.0 removed$note" -ForegroundColor Green
        }
    } catch {
        Write-Fail "[Feature] Couldn't check or remove PowerShell 2.0: $($_.Exception.Message)"
    }

    # Windows Script Host - Disabled
    # Windows Script Host runs .js, .jse, .vbs, .vbe and .wsf files (wscript.exe,
    # cscript.exe). Malicious email attachments and downloads use these, and the
    # same pasted-command tricks use them as an alternative to PowerShell. Once
    # off, running one shows "Windows Script Host access is disabled on this
    # machine".
    # IgnoreUserSettings stops a per-user setting (which any program can write
    # without admin rights) from turning it back on. The WOW6432Node key covers
    # the 32-bit copies of wscript and cscript.
    # Breaks: Windows' slmgr.vbs (activation) and Office's ospp.vbs, plus any old
    # .vbs scripts you use; set Enabled back to 1 to run them. The setting is
    # checked by wscript.exe and cscript.exe, so PowerShell's WScript.Shell object
    # (used to read shortcuts) should keep working. mshta (.hta files) is a
    # separate program and isn't affected.
    foreach ($wshPath in 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings',
                         'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Script Host\Settings') {
        Set-RegistryValue -Path $wshPath -Name 'Enabled' -Value 0 -Description "Disable Windows Script Host ($(if ($wshPath -like '*WOW6432Node*') { '32-bit' } else { '64-bit' }))"
        Set-RegistryValue -Path $wshPath -Name 'IgnoreUserSettings' -Value 1 -Description 'Users can''t turn Windows Script Host back on'
    }
}

# ---------------------------------------------------------------
# SECTION 7: Microsoft Office
# CIS Microsoft Office Enterprise Benchmark v1.2.0, Level 1. It covers the
# desktop Office apps installed on the PC (Microsoft 365 Apps, Office
# 2016/2019/2021/2024, which all use the "16.0" policy keys): Access,
# Excel, Outlook, PowerPoint, Publisher and Word. (CIS's "Microsoft 365
# Foundations" benchmark is a different one, for the cloud tenant.)
#
# Most Office policies are per user, so they're written into every user
# account's registry, plus the Default profile that new accounts are copied
# from. Accounts that aren't signed in have their registry loaded briefly.
#
# Changed from CIS for a stand-alone home PC (CIS says the benchmark is
# written for domain-joined PCs and may need tailoring):
#   2.3.22.2 'Block signing into Office: Org ID only' - skipped. It blocks
#     personal Microsoft accounts, which a home Microsoft 365 subscription
#     needs in order to activate.
#   2.5.1.2.1 'Authentication with Exchange server: Kerberos' - skipped.
#     Kerberos needs a company domain; it would break home email accounts.
# Fixed where the benchmark points at the wrong key or value:
#   1.1.4.1.14 uses FEATURE_WINDOW_RESTRICTIONS (CIS repeats 1.1.4.1.13's key)
#   2.2.4.7.2.3.4/5 use Excel's file validation key (CIS gives Word's)
#   2.6.6.6.2.1.1 uses powerpoint\security\fileblock (CIS has excel\powerpoint)
#   2.5.14.3.3.2/3 use promptoomaddressbookaccess and promptoomformulaaccess
#     (CIS repeats other items' value names); CIS's names are set as well
# Level 2 items aren't applied: they turn off all trusted locations, Office's
# online content and services, and show all email as plain text.
#
# Expect after running:
#   - Macros only run if signed by a publisher you've chosen to trust. Others
#     are blocked without a prompt, so there's no "Enable Content" button.
#   - Add-ins must be signed by a trusted publisher. Unsigned ones are
#     disabled without a prompt.
#   - Old binary files (.doc, .xls, .ppt) and older formats are blocked:
#     see $OfficeBlockedFileBehavior at the top to let them open read-only.
#   - Other programs can't send mail or read the address book through
#     Outlook (some scanners and accounting apps do this).
#   - Junk mail filtering is set to High; check the Junk folder at first.
# Settings take effect the next time each Office app starts.
# ---------------------------------------------------------------
function Set-OfficeHardening {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Applying Microsoft Office Protections" '.'

    if (-not ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration') -or
              (Test-Path 'HKLM:\SOFTWARE\Microsoft\Office\16.0'))) {
        Write-Host "  [Office] Office isn't installed; the settings are applied anyway, ready for when it is" -ForegroundColor DarkGray
    }

    # --- Machine-wide settings ---

    $officeExes = 'excel.exe', 'msaccess.exe', 'mspub.exe', 'onenote.exe', 'outlook.exe',
                  'powerpnt.exe', 'visio.exe', 'winproj.exe', 'winword.exe'

    # 1.1.4.1.1-14 IE Security - Enabled for every Office app
    # Office uses Internet Explorer's engine for web content inside documents
    # (web pages, embedded HTML). These turn on IE's own safety restrictions
    # for the Office programs: no add-ons or ActiveX installs, no silent
    # downloads, no zone elevation, stricter file type checks, and so on. The
    # WOW6432Node copy covers 32-bit Office.
    $ieFeatures = [ordered]@{
        FEATURE_ADDON_MANAGEMENT                = 'Add-on Management'
        FEATURE_SAFE_BINDTOOBJECT               = 'Bind to object'
        FEATURE_MIME_HANDLING                   = 'Consistent Mime Handling'
        FEATURE_HTTP_USERNAME_PASSWORD_DISABLE  = 'Disable user name and password'
        FEATURE_SECURITYBAND                    = 'Information Bar'
        FEATURE_LOCALMACHINE_LOCKDOWN           = 'Local Machine Zone Lockdown Security'
        FEATURE_MIME_SNIFFING                   = 'Mime Sniffing Safety Feature'
        FEATURE_VALIDATE_NAVIGATE_URL           = 'Navigate URL'
        FEATURE_OBJECT_CACHING                  = 'Object Caching Protection'
        FEATURE_ZONE_ELEVATION                  = 'Protection From Zone Elevation'
        FEATURE_RESTRICT_ACTIVEXINSTALL         = 'Restrict ActiveX Install'
        FEATURE_RESTRICT_FILEDOWNLOAD           = 'Restrict File Download'
        FEATURE_UNC_SAVEDFILECHECK              = 'Saved from URL'
        FEATURE_WINDOW_RESTRICTIONS             = 'Scripted Window Security Restrictions'
    }
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main\FeatureControl',
                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Internet Explorer\Main\FeatureControl') {
        foreach ($feature in $ieFeatures.Keys) {
            $key = "$root\$feature"
            foreach ($exe in $officeExes) {
                Set-TrackedValue -Path $key -Name $exe -Value 1
            }
        }
    }
    Write-Host "  [Office] IE security restrictions on for Office's web content ($($ieFeatures.Count) features, CIS 1.1.4.1.1-14)" -ForegroundColor Green

    # 1.1.5.1 Enable Automatic Updates - Enabled
    # 1.1.5.2 Hide option to enable or disable updates - Enabled
    # Most real attacks on Office use bugs that are already patched. Office keeps
    # updating itself, and the option to turn updates off is hidden.
    $officeUpdatePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate'
    Set-RegistryValue -Path $officeUpdatePath -Name 'enableautomaticupdates' -Value 1 -Description 'Office updates itself (CIS 1.1.5.1)'
    Set-RegistryValue -Path $officeUpdatePath -Name 'hideenabledisableupdates' -Value 1 -Description 'Users can''t turn Office updates off (CIS 1.1.5.2)'

    # 1.3.1 Block Flash activation in Office documents - Block all activation
    # 0x400 is Office's COM kill bit for the Shockwave Flash control. Flash was
    # removed from Windows in 2021; this still stops a document loading it if a
    # copy remained. The Policies key is what CIS checks. The Office and
    # WOW6432Node keys are what 64-bit and 32-bit Office read directly.
    # A previous version of this script wrote a Comment string on the parent
    # key, which Office ignores; that value is removed.
    $flashClsid = '{D27CDB6E-AE6D-11cf-96B8-444553540000}'
    Remove-TrackedValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Office\Common\COM Compatibility' -Name 'Comment'
    foreach ($flashRoot in @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Office\Common\COM Compatibility'
        'HKLM:\SOFTWARE\Microsoft\Office\Common\COM Compatibility'
        'HKLM:\SOFTWARE\Microsoft\Office\16.0\Common\COM Compatibility'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Common\COM Compatibility'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Common\COM Compatibility'
    )) {
        Set-TrackedValue -Path "$flashRoot\$flashClsid" -Name 'Compatibility Flags' -Value 0x400
    }
    Write-Host '  [Office] Flash activation blocked (Compatibility Flags = 0x400, CIS 1.3.1)' -ForegroundColor Green

    # 1.3.2 Restrict legacy JScript execution for Office - Enabled
    # Stops Office's web content from running the old JScript engine
    # (jscript.dll) that attackers exploit; 69632 (0x11000) blocks it in the
    # Internet and Restricted Sites zones.
    $jscriptPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_RESTRICT_LEGACY_JSCRIPT_PER_SECURITY_ZONE'
    foreach ($exe in $officeExes) {
        Set-TrackedValue -Path $jscriptPath -Name $exe -Value 69632
    }
    Write-Host "  [Office] Legacy JScript blocked in Office (CIS 1.3.2)" -ForegroundColor Green

    # --- Per-user settings ---
    # Each entry: key under Software\Policies\Microsoft, value name, value.
    # Numbers are written as DWORD, text as REG_SZ, and $null deletes the value
    # (CIS wants some settings absent).
    $o = 'office\16.0'
    $officeUserSettings = [System.Collections.Generic.List[object]]::new()
    function Add-OfficeSetting { param([string]$Key, [string]$Name, $Value) $officeUserSettings.Add(@($Key, $Name, $Value)) }

    # Settings CIS repeats for each app ---------------------------------
    foreach ($app in 'access', 'excel', 'powerpoint', 'publisher', 'word') {
        # Block macros in files from the internet (email attachments, downloads)
        Add-OfficeSetting "$o\$app\security" 'blockcontentexecutionfrominternet' 1
        # Add-ins must be signed by a trusted publisher; unsigned ones are
        # disabled without asking the user
        Add-OfficeSetting "$o\$app\security" 'requireaddinsig' 1
        Add-OfficeSetting "$o\$app\security" 'notbpromptunsignedaddin' 1
    }
    foreach ($app in 'excel', 'powerpoint', 'publisher', 'word') {
        # Macros: disabled unless signed by a publisher in Trusted Publishers;
        # no prompt, so no "Enable Content" button to be tricked into clicking
        Add-OfficeSetting "$o\$app\security" 'vbawarnings' 3
        Add-OfficeSetting "$o\$app\security" 'vbadigsigtrustedpublishers' 1
    }
    foreach ($app in 'excel', 'powerpoint', 'word') {
        # Macros can't modify other macros or Office's own code
        Add-OfficeSetting "$o\$app\security" 'accessvbom' 0
        # Protected View (read-only, sandboxed) for files from the internet,
        # Outlook attachments and unsafe locations such as Temp
        Add-OfficeSetting "$o\$app\security\protectedview" 'disableinternetfilesinpv' 0
        Add-OfficeSetting "$o\$app\security\protectedview" 'disableattachmentsinpv' 0
        Add-OfficeSetting "$o\$app\security\protectedview" 'disableunsafelocationsinpv' 0
        # File validation checks files for signs of tampering; ones that fail
        # open in Protected View and can't be edited
        Add-OfficeSetting "$o\$app\security\filevalidation" 'enableonload' 1
        Add-OfficeSetting "$o\$app\security\filevalidation" 'openinprotectedview' 1
        Add-OfficeSetting "$o\$app\security\filevalidation" 'disableeditfrompv' 1
        # What happens to blocked file types (see $OfficeBlockedFileBehavior)
        Add-OfficeSetting "$o\$app\security\fileblock" 'openinprotectedview' $OfficeBlockedFileBehavior
        # Not CIS: embedded packages (an .exe or script disguised as an icon or
        # picture in a document) can't be opened
        Add-OfficeSetting "$o\$app\security" 'packagerprompt' 2
        # Not CIS: no Trusted Documents, so one click on "Enable Content" can't
        # permanently trust a file
        Add-OfficeSetting "$o\$app\security\trusted documents" 'disabletrusteddocuments' 1
    }
    foreach ($app in 'access', 'excel', 'powerpoint', 'word') {
        # Network shares can't be trusted locations, where macros run freely
        Add-OfficeSetting "$o\$app\security\trusted locations" 'allownetworklocations' 0
    }
    # Office toolbars and menus can't be changed by code in a document (2.3.12.1.2)
    foreach ($app in 'access', 'excel', 'infopath', 'outlook', 'powerpoint', 'project', 'publisher', 'visio', 'word') {
        Add-OfficeSetting "$o\common\toolbars\$app" 'noextensibilitycustomizationfromdocument' 1
    }

    # Access (2.1) -------------------------------------------------------
    Add-OfficeSetting "$o\access\internet" 'donotunderlinehyperlinks' 0     # links are visibly underlined
    Add-OfficeSetting "$o\access\settings" 'defaultfileformat' 12           # new databases in .accdb format
    Add-OfficeSetting "$o\access\settings" 'noconvertdialog' 0              # offer to convert old databases
    Add-OfficeSetting "$o\access\security" 'modaltrustdecisiononly' 0       # trust prompts use the message bar

    # Excel (2.2) --------------------------------------------------------
    Add-OfficeSetting "$o\excel\options" 'extractdatadisableui' 1           # no data recovery from corrupt workbooks (a parsing risk)
    Add-OfficeSetting "$o\excel\internet" 'donotloadpictures' 1             # no pictures from web pages not made in Excel
    Add-OfficeSetting "$o\excel\options\binaryoptions" 'fupdateext_78_1' 0  # ask before updating links to other files
    Add-OfficeSetting "$o\excel\options" 'autohyperlink' 0                  # typed paths and URLs don't become links
    Add-OfficeSetting "$o\excel\options" 'defaultformat' 51                 # save as .xlsx
    Add-OfficeSetting "$o\excel\options" 'disableautorepublish' 1           # no automatic republishing to the web
    Add-OfficeSetting "$o\excel\options" 'disableautorepublishwarning' 0
    Add-OfficeSetting "$o\excel\options\binaryoptions" 'fglobalsheet_37_1' 1  # recorded macros go to the Personal workbook
    # Untrusted Microsoft Query files can't open; no DDE (an old way for a
    # workbook to start other programs without macros)
    Add-OfficeSetting "$o\excel\security\external content" 'enableblockunsecurequeryfiles' 1
    Add-OfficeSetting "$o\excel\security\external content" 'disableddeserverlaunch' 1
    Add-OfficeSetting "$o\excel\security\external content" 'disableddeserverlookup' 1
    # File Block: old and rarely used formats that attackers favour. 2 = can't
    # be opened or saved, following $OfficeBlockedFileBehavior
    foreach ($name in 'dbasefiles', 'difandsylkfiles', 'xl2macros', 'xl2worksheets', 'xl3macros', 'xl3worksheets',
                      'xl4macros', 'xl4workbooks', 'xl4worksheets', 'xl95workbooks', 'xl9597workbooksandtemplates',
                      'xl97workbooksandtemplates', 'htmlandxmlssfiles') {
        Add-OfficeSetting "$o\excel\security\fileblock" $name 2
    }
    Add-OfficeSetting "$o\excel\security\fileblock" 'excel12betafilesfromconverters' 1  # pre-release 2007 formats (2.3.23.1)
    Add-OfficeSetting "$o\excel\security\protectedview" 'enabledatabasefileprotectedview' 1
    Add-OfficeSetting "$o\excel\security" 'blockxllfrominternet' 1          # no XLL add-ins from the internet
    Add-OfficeSetting "$o\excel\security" 'xl4macrooff' 1                   # no Excel 4.0 (XLM) macros
    Add-OfficeSetting "$o\excel\security" 'extensionhardening' 2            # a file's extension must match its contents
    Add-OfficeSetting "$o\excel\security" 'excelbypassencryptedmacroscan' 0 # scan macros in encrypted workbooks
    Add-OfficeSetting "$o\excel\security" 'webservicefunctionwarnings' 1    # WEBSERVICE() off (CIS accepts 1 or 2)

    # PowerPoint (2.6) ---------------------------------------------------
    Add-OfficeSetting "$o\powerpoint\options" 'defaultformat' 27            # save as .pptx
    Add-OfficeSetting "$o\powerpoint\options" 'markupopensave' 1            # show hidden comments and changes
    Add-OfficeSetting "$o\powerpoint\security\fileblock" 'binaryfiles' 2    # .ppt and other 97-2003 files
    Add-OfficeSetting "$o\powerpoint\security\fileblock" 'powerpoint12betafilesfromconverters' 1  # (2.3.23.2)
    Add-OfficeSetting "$o\powerpoint\security" 'runprograms' 0              # slides can't start programs
    Add-OfficeSetting "$o\powerpoint\security" 'powerpointbypassencryptedmacroscan' 0
    Add-OfficeSetting "$o\powerpoint\security" 'downloadimages' 0           # no automatic download of linked images

    # Publisher (2.8) ----------------------------------------------------
    Add-OfficeSetting 'office\common\security' 'automationsecuritypublisher' 2  # macros in files opened by other programs follow the UI setting

    # Word (2.11) --------------------------------------------------------
    Add-OfficeSetting "$o\word\options" 'dontupdatelinks' 1                 # don't update links to other files on open
    Add-OfficeSetting "$o\word\options" 'showhiddentext' 1                  # hidden text is shown, so nothing hides in it
    Add-OfficeSetting "$o\word\options" 'defaultformat' ''                  # save as .docx (empty text = .docx)
    Add-OfficeSetting "$o\word\options" 'showmarkupopensave' 1              # show hidden comments and tracked changes
    foreach ($name in 'word2files', 'word60files', 'word95files', 'word97files', 'word2000files', 'wordxpfiles',
                      'word2003files', 'word2007files') {
        # Binary .doc files saved by each Word version
        Add-OfficeSetting "$o\word\security\fileblock" $name 2
    }
    Add-OfficeSetting "$o\word\security" 'allowdde' $null                   # DDE stays off (Word's default)
    Add-OfficeSetting "$o\word\security" 'wordbypassencryptedmacroscan' 0

    # Office-wide (2.3) --------------------------------------------------
    Add-OfficeSetting "$o\common\documentinformationpanel" 'msoridcuxdocspropertypanelbeaconing' 1  # warn about web-beacon document properties
    # Rights-managed (IRM) documents: stricter permission handling
    Add-OfficeSetting "$o\common\drm" 'includehtml' 0
    Add-OfficeSetting "$o\common\drm\autoexpanddls" 'autoexpanddlsenable' 1
    Add-OfficeSetting "$o\common\drm" 'requireconnection' 1
    Add-OfficeSetting "$o\common\drm" 'neverallowdls' 1
    Add-OfficeSetting "$o\common\drm" 'disablecreation' 0
    Add-OfficeSetting "$o\common\drm" 'compatibleencryption' 1
    Add-OfficeSetting 'office\common\blog' 'disableblog' 2                  # no publishing to blogs from Word
    # Privacy: no feedback, usage data or personal details sent to Microsoft
    Add-OfficeSetting "$o\common\feedback" 'enabled' 0
    Add-OfficeSetting "$o\common" 'updatereliabilitydata' 0
    Add-OfficeSetting "$o\common\general" 'shownfirstrunoptin' 1
    Add-OfficeSetting "$o\common" 'qmenable' 0
    Add-OfficeSetting "$o\common" 'sendcustomerdata' 0
    Add-OfficeSetting "$o\common\security\trusted locations" 'allowuserlocations' 0  # users can't add trusted locations
    # ActiveX: controls in documents get the strictest initialization (6), and
    # not CIS, all ActiveX controls in documents are off
    Add-OfficeSetting 'office\common\security' 'uficontrols' 6
    Add-OfficeSetting 'office\common\security' 'disableallactivex' 1
    Add-OfficeSetting "$o\common\identity" 'basicauthproxybehavior' 0       # no password prompts from network proxies
    Add-OfficeSetting 'vba\security' 'allowvbaintranetreferences' 0
    # Files opened by another program (a script driving Word) have macros off
    Add-OfficeSetting 'office\common\security' 'automationsecurity' 3
    Add-OfficeSetting "$o\common" 'fbabehavior' 1                           # block web-form sign-in prompts (phishing)
    Add-OfficeSetting 'vba\security' 'disablestrictvbarefssecurity' 0
    Add-OfficeSetting "$o\common\trustcenter" 'trustbar' 0                  # security warnings stay visible
    Add-OfficeSetting "$o\common\security" 'disablepasswordui' 0
    # Password-protected files use AES-256
    Add-OfficeSetting "$o\common\security" 'defaultencryption12' 'Microsoft Enhanced RSA and AES Cryptographic Provider,AES 256,256'
    Add-OfficeSetting "$o\common\security" 'openxmlencryption' 'Microsoft Enhanced RSA and AES Cryptographic Provider,AES 256,256'
    Add-OfficeSetting 'vba\security' 'loadcontrolsinforms' 4
    Add-OfficeSetting "$o\common\security" 'macroruntimescanscope' 2        # Defender scans every macro as it runs
    Add-OfficeSetting "$o\common\security" 'openxmlencryptproperty' 1
    Add-OfficeSetting "$o\common\security" 'drmencryptproperty' 1
    Add-OfficeSetting "$o\common\security" 'disablehyperlinkwarning' 0      # warn before following unsafe links
    Add-OfficeSetting "$o\common\portal" 'linkpublishingdisabled' 1
    Add-OfficeSetting "$o\common\services\fax" 'nofax' 1
    Add-OfficeSetting "$o\common\signatures" 'enablecreationofweakxpsignatures' 0
    Add-OfficeSetting "$o\common\signatures" 'suppressextsigningsvcs' 1
    Add-OfficeSetting 'office\common\smart tag' 'neverloadmanifests' 1
    Add-OfficeSetting "$o\common\internet" 'opendocumentsreadwritewhilebrowsing' 0

    # Outlook (2.5) ------------------------------------------------------
    $ol = "$o\outlook"
    Add-OfficeSetting "$ol\options\folders" 'disableeditpermissions' 1
    Add-OfficeSetting "$ol\rpc" 'enablerpcencryption' 1
    # Internet calendars and RSS feeds: off, with no automatic attachments
    Add-OfficeSetting "$ol\options\webcal" 'enableattachments' 0
    Add-OfficeSetting "$ol\options\webcal" 'disable' 1
    Add-OfficeSetting "$ol\options\rss" 'enablefulltexthtml' 0
    Add-OfficeSetting "$ol\options\rss" 'synctosyscfl' 0
    Add-OfficeSetting "$ol\options\rss" 'disable' 1
    Add-OfficeSetting "$ol\webview" 'disable' 1                             # folders can't have web home pages (an old attack)
    Add-OfficeSetting "$o\meetings\profile" 'serverui' 2
    Add-OfficeSetting "$ol\pst" 'pstnullfreeondelete' 1                     # deleted mail is wiped from .pst files
    Add-OfficeSetting "$ol\options\mail" 'message plain format mime' 1
    # Outlook scripts: no folder home pages, public/shared folder scripts or
    # scripts in one-off forms
    Add-OfficeSetting "$ol\security" 'nondefaultstorescript' 0
    Add-OfficeSetting "$ol\security" 'publicfolderscript' 0
    Add-OfficeSetting "$ol\security" 'sharedfolderscript' 0
    Add-OfficeSetting "$ol\security" 'enableoneoffformscripts' 0
    Add-OfficeSetting "$ol\options\general" 'msgformat' 0
    Add-OfficeSetting "$ol\options\general" 'checkdefaultclient' 1
    # Published calendars: restricted access, limited details
    Add-OfficeSetting "$ol\options\pubcal" 'restrictedaccessonly' 1
    Add-OfficeSetting "$ol\options\pubcal" 'disabledav' 1
    Add-OfficeSetting "$ol\options\pubcal" 'disableofficeonline' 1
    Add-OfficeSetting "$ol\options\pubcal" 'publishcalendardetailspolicy' 16384
    Add-OfficeSetting "$ol\options\pubcal" 'singleuploadonly' 1
    # Junk mail: on, High, and contacts/recipients aren't automatically trusted;
    # links in suspected phishing are disabled
    Add-OfficeSetting "$ol\options\mail" 'junkmailtrustoutgoingrecipients' 0
    Add-OfficeSetting $ol 'disableantispam' 0
    Add-OfficeSetting "$ol\options\mail" 'junkmailprotection' 3
    Add-OfficeSetting "$ol\options\mail" 'junkmailtrustcontacts' 0
    Add-OfficeSetting "$ol\options\mail" 'junkmailenablelinks' 0
    Add-OfficeSetting 'office\outlook\socialconnector' 'runosc' 0           # path as CIS gives it
    Add-OfficeSetting "$ol\socialconnector" 'runosc' 0                      # and the usual 16.0 path
    # Pictures and external content in email aren't downloaded automatically
    # (they tell senders you opened the mail)
    Add-OfficeSetting "$ol\options\mail" 'unblockspecificsenders' 0
    Add-OfficeSetting "$ol\options\mail" 'trustedzone' 0
    Add-OfficeSetting "$ol\options\mail" 'blockextcontent' 1
    Add-OfficeSetting "$ol\options\mail" 'unblocksafezone' 1
    Add-OfficeSetting "$ol\options\mail" 'internet' 0
    # Signed and encrypted (S/MIME) mail: strict certificate checking, AES-256
    Add-OfficeSetting "$ol\security" 'outlooksecuretempfolder' $null
    Add-OfficeSetting "$ol\security" 'sigstatusnocrl' 1
    Add-OfficeSetting "$ol\security" 'sigstatusnotrustdecision' 2
    Add-OfficeSetting "$ol\security" 'promoteerrorsaswarnings' 0
    Add-OfficeSetting "$ol\security" 'usecrlchasing' 1
    Add-OfficeSetting "$ol\security" 'publishtogaldisabled' 1
    Add-OfficeSetting "$ol\security" 'disablecontinueencryption' 1
    Add-OfficeSetting "$ol\security" 'msgformats' 1
    Add-OfficeSetting "$ol\security" 'minenckey' 256
    Add-OfficeSetting "$ol\security" 'externalsmime' 0
    Add-OfficeSetting "$ol\security" 'warnaboutinvalid' 1
    Add-OfficeSetting "$ol\security" 'nosignonreply' 0
    # Dangerous attachments (.exe, .js, etc.) stay blocked, and users can't
    # unblock them
    Add-OfficeSetting "$ol\security" 'allowuserstolowerattachments' 0
    Add-OfficeSetting "$ol\security" 'showlevel1attach' 0
    Add-OfficeSetting "$ol\security" 'dontpromptlevel1attachclose' 0
    Add-OfficeSetting "$ol\security" 'dontpromptlevel1attachsend' 0
    Add-OfficeSetting "$ol\security" 'fileextensionsremovelevel1' $null
    Add-OfficeSetting "$ol\security" 'fileextensionsremovelevel2' $null
    Add-OfficeSetting $ol 'disallowattachmentcustomization' 1
    # Other programs using Outlook (to send mail, read contacts, save items) are
    # refused without a prompt; adminsecuritymode makes Outlook use these policies
    Add-OfficeSetting "$ol\security" 'adminsecuritymode' 3
    foreach ($name in 'promptoomcustomaction', 'promptoomaddressbookaccess', 'promptoomformulaaccess',
                      'promptoomsaveas', 'promptoomaddressinformationaccess', 'promptoommeetingtaskrequestresponse',
                      'promptoomsend') {
        Add-OfficeSetting "$ol\security" $name 0
    }
    Add-OfficeSetting "$ol\security" 'level' 3                              # Outlook macros: signed only, warn
    Add-OfficeSetting "$ol\security" 'allowactivexoneoffforms' 0            # forms load only Outlook's own controls
    Add-OfficeSetting "$ol\security" 'enablerememberpwd' 0                  # no saved passwords for POP/IMAP accounts
    Add-OfficeSetting "$ol\security" 'forcedefaultprofile' 0

    Invoke-InEachUserHive {
        param($root, $label)
        $done = 0
        $errors = [System.Collections.Generic.List[string]]::new()
        foreach ($s in $officeUserSettings) {
            $key = "$root\Software\Policies\Microsoft\$($s[0])"
            try {
                if ($null -eq $s[2]) {
                    Remove-TrackedValue -Path $key -Name $s[1]
                } else {
                    $type = if ($s[2] -is [string]) { 'String' } else { 'DWord' }
                    Set-TrackedValue -Path $key -Name $s[1] -Value $s[2] -Type $type
                }
                $done += 1
            } catch {
                $errors.Add("$($s[0])\$($s[1]): $($_.Exception.Message)")
            }
        }
        if ($errors.Count -eq 0) {
            Write-Host "  [Office] $label`: $done settings applied" -ForegroundColor Green
        } else {
            Write-Fail "[Office] ${label}: $($errors.Count) of $($officeUserSettings.Count) settings failed, first: $($errors[0])"
        }
    }
}

# ---------------------------------------------------------------
# SECTION 8: Shortcut (.lnk) and HTML application protections (not CIS)
# Malicious shortcuts arrive by email or download, often in a ZIP or ISO,
# with a PDF or Word icon. Opening one runs mshta, PowerShell, cmd and so on
# with a hidden command that downloads the real malware. Section 6's ASR
# rules block most of what they download; these make the disguise visible
# and cut off the download step for the programs they use most.
# The winstartupcheck step (and .bashrc's winstartupcheck) checks every
# shortcut on Desktops, Start menus and the taskbar for hijacking.
# ---------------------------------------------------------------
function Set-ShortcutProtection {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Applying Shortcut and HTML Application Protections" '.'

    # Show the .lnk extension
    # Windows hides the extension of shortcuts (.lnk), internet shortcuts (.url)
    # and old DOS shortcuts (.pif) even when "File name extensions" is on, so
    # "Invoice.pdf.lnk" shows as "Invoice.pdf". Removing NeverShowExt and adding
    # AlwaysShowExt shows it whatever the Explorer setting. Shortcut names get
    # longer, e.g. "Google Chrome.lnk" in the Start menu folder. Shows after the
    # next sign-in or Explorer restart.
    foreach ($type in 'lnkfile', 'InternetShortcut', 'piffile') {
        $key = "HKLM:\SOFTWARE\Classes\$type"
        if (-not (Test-Path $key)) { continue }
        Remove-TrackedValue -Path $key -Name 'NeverShowExt'
        Set-TrackedValue -Path $key -Name 'AlwaysShowExt' -Value '' -Type String
    }
    Write-Host "  [Explorer] .lnk, .url and .pif extensions always shown" -ForegroundColor Green

    # Show every file's extension, for every user (Explorer's "File name
    # extensions"), so "Invoice.pdf.exe" can't pass as a PDF either.
    Invoke-InEachUserHive {
        param($root, $label)
        try {
            $key = "$root\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Set-TrackedValue -Path $key -Name 'HideFileExt' -Value 0
            Write-Host "  [Explorer] $label`: file name extensions shown" -ForegroundColor Green
        } catch {
            Write-Fail "[Explorer] ${label}: couldn't turn on file name extensions: $($_.Exception.Message)"
        }
    }

    # Block mshta, regsvr32 and certutil from the internet
    # Outbound Windows Firewall rules for the 64-bit and 32-bit copies. These are
    # what shortcut and pasted-command attacks use to fetch their payload
    # (mshta https://..., regsvr32 /i:https://... scrobj.dll, certutil
    # -urlcache -f https://...). Nothing in normal use needs them online; they
    # still run, just without network access (local networks included).
    # The rules are rebuilt each run; to undo:
    #   Remove-NetFirewallRule -Group 'MY_ADDED_FW_RULES: block internet for LOLBins'
    # Another firewall product that replaces Windows Firewall ignores them.
    $fwGroup = 'MY_ADDED_FW_RULES: block internet for LOLBins'
    try {
        Get-NetFirewallRule -Group $fwGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop
        $blocked = @()
        foreach ($exe in 'mshta.exe', 'regsvr32.exe', 'certutil.exe') {
            foreach ($dir in 'System32', 'SysWOW64') {
                $program = "$env:SystemRoot\$dir\$exe"
                if (-not (Test-Path $program)) { continue }
                New-NetFirewallRule -DisplayName "Block $exe internet access ($dir)" -Group $fwGroup -Direction Outbound `
                    -Program $program -Action Block -Profile Any -ErrorAction Stop | Out-Null
                $blocked += "$dir\$exe"
            }
        }
        Write-Host "  [Firewall] Internet blocked for $($blocked -join ', ')" -ForegroundColor Green
        # The firewall step turns a profile back on. This is only a backstop, in
        # case that step failed and these rules would then do nothing.
        $offProfiles = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object { -not $_.Enabled })
        if ($offProfiles) {
            Write-Host "  [Firewall] Windows Firewall is off for the $(($offProfiles.Name) -join ', ') profile(s), where these rules do nothing" -ForegroundColor Yellow
        }
    } catch {
        Write-Fail "[Firewall] Couldn't create the LOLBin firewall rules: $($_.Exception.Message)"
    }

    # .hta files open in Notepad
    # Double-clicking an HTML application (.hta) runs it with mshta, with full
    # access to the PC; attachments and downloads use this. Now it opens as text
    # instead. A real .hta can still be run with: mshta.exe C:\path\file.hta
    $htaCommand = 'HKLM:\SOFTWARE\Classes\htafile\shell\open\command'
    if (Test-Path $htaCommand) {
        Set-TrackedValue -Path $htaCommand -Name '(default)' -Value '"%SystemRoot%\System32\notepad.exe" "%1"' -Type ExpandString
        Write-Host "  [Explorer] .hta files open in Notepad instead of running" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------
# SECTION 8b: File Explorer view settings (not CIS)
# File Explorer > View > Show, and Folder Options > View, for every user
# account and the Default profile new accounts are copied from:
#   Show file extensions (HideFileExt = 0), so "Invoice.pdf.exe" can't pass as
#     a PDF. Section 8 sets this too.
#   Show hidden files (Hidden = 1; 2 hides them), so malware that marks its
#     files hidden can't hide from you in Explorer.
#   Protected operating system files stay hidden (ShowSuperHidden = 0):
#     files marked both hidden and system. Showing them (1) would also show
#     Windows' own, faded, e.g. a desktop.ini on the Desktop and in many
#     folders. Malware uses that combination too, so to look for it, set 1
#     on the commented-out line below, or untick "Hide protected operating
#     system files" in Folder Options > View for a while.
#   Full path in the title bar (CabinetState\FullPath = 1). On Windows 11
#     the path shows in the tab's name.
#   End task on the taskbar (Advanced\TaskbarDeveloperSettings\
#     TaskbarEndTask = 1): right-click an app on the taskbar > End task
#     force-closes it, like Task Manager, for a frozen app. Settings >
#     System > For developers > End task; separate from Developer Mode,
#     which Section 9c keeps off. Shows straight away.
# The others take effect when Explorer next starts: sign out and in, or
# restart "Windows Explorer" in Task Manager.
# ---------------------------------------------------------------
function Set-ExplorerView {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Setting File Explorer View Options' '.'

    # Hashtables, not nested arrays, which @( ) would flatten into one list
    $settings = @(
        @{ Key = 'Advanced'; Name = 'HideFileExt'; Value = 0; What = 'file extensions shown' }
        @{ Key = 'Advanced'; Name = 'Hidden'; Value = 1; What = 'hidden files shown' }
        #@{ Key = 'Advanced'; Name = 'ShowSuperHidden'; Value = 1; What = 'protected operating system files shown' }
        @{ Key = 'Advanced'; Name = 'ShowSuperHidden'; Value = 0; What = 'protected operating system files NOT shown' }
        @{ Key = 'CabinetState'; Name = 'FullPath'; Value = 1; What = 'full path in the title bar' }
        @{ Key = 'Advanced\TaskbarDeveloperSettings'; Name = 'TaskbarEndTask'; Value = 1; What = 'End task on the taskbar' }
    )
    Invoke-InEachUserHive {
        param($root, $label)
        $errors = @()
        foreach ($s in $settings) {
            $key = "$root\Software\Microsoft\Windows\CurrentVersion\Explorer\$($s.Key)"
            try {
                Set-TrackedValue -Path $key -Name $s.Name -Value $s.Value
            } catch {
                $errors += "$($s.What): $($_.Exception.Message)"
            }
        }
        if ($errors) {
            Write-Fail "[Explorer] ${label}: $($errors -join '; ')"
        } else {
            Write-Host "  [Explorer] $label`: $(($settings | ForEach-Object { $_.What }) -join ', ')" -ForegroundColor Green
        }
    }
}

# ---------------------------------------------------------------
# SECTION 9: Data Execution Prevention (DEP) for all programs (not CIS;
# DISA's Windows STIG asks for at least OptOut)
# DEP stops code running from memory that's meant to hold only data, which
# is how many exploits run what they've injected. 64-bit programs always
# have it; this setting decides which 32-bit programs do.
#   OptIn    - Windows' own programs only (the Windows default)
#   OptOut   - every program, except ones listed in System Properties >
#              Advanced > Performance Settings > Data Execution Prevention
#              ("Turn on DEP for all programs and services except those I
#              select")
#   AlwaysOn - every program, no exceptions possible
# This sets OptOut, and leaves AlwaysOn alone. A very old 32-bit program that
# generates its own code may crash; add it to the exceptions in that dialog.
# Takes effect after a restart.
# ---------------------------------------------------------------
function Enable-Dep {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Turning On Data Execution Prevention" '.'

    $bcd = bcdedit /enum '{current}'
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "[DEP] Couldn't read the boot settings (bcdedit exit $LASTEXITCODE); DEP not changed"
    } else {
        # No nx line means the default, OptIn
        $nxLine = $bcd | Select-String -Pattern '^nx\s+(\S+)' | Select-Object -First 1
        $nxNow = if ($nxLine) { $nxLine.Matches[0].Groups[1].Value } else { 'OptIn' }
        if ($nxNow -in 'OptOut', 'AlwaysOn') {
            Write-Host "  [DEP] Already $nxNow (on for all programs)" -ForegroundColor Green
        } else {
            # BitLocker checks this boot setting at startup; a change it wasn't told
            # about makes it ask for the recovery key. Suspending it for one restart
            # avoids that, and it turns itself back on afterwards.
            $bitlockerOn = $false
            try {
                $bitlockerOn = "$((Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop).ProtectionStatus)" -eq 'On'
            } catch {
                # No BitLocker on this edition, or the drive isn't encrypted
            }
            $canChange = $true
            if ($bitlockerOn) {
                try {
                    Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 -ErrorAction Stop | Out-Null
                    Write-Host "  [DEP] BitLocker suspended until the next restart, so the change doesn't ask for the recovery key" -ForegroundColor Yellow
                } catch {
                    Write-Fail "[DEP] Couldn't suspend BitLocker ($($_.Exception.Message)); DEP not changed, to avoid a recovery key prompt"
                    $canChange = $false
                }
            }
            if ($canChange) {
                bcdedit /set '{current}' nx OptOut | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    # Suspend-BitLocker -RebootCount 1 would otherwise stay off until the
                    # next restart even though the boot setting did not change.
                    # Resume-BitLocker turns protection back on now.
                    if ($bitlockerOn) {
                        try {
                            Resume-BitLocker -MountPoint $env:SystemDrive -ErrorAction Stop | Out-Null
                            Write-Fail "[DEP] bcdedit couldn't change DEP (exit $LASTEXITCODE); still $nxNow. BitLocker protection is back on"
                        } catch {
                            Write-Fail "[DEP] bcdedit couldn't change DEP (exit $LASTEXITCODE); still $nxNow. BitLocker is still suspended until the next restart: $($_.Exception.Message)"
                        }
                    } else {
                        Write-Fail "[DEP] bcdedit couldn't change DEP (exit $LASTEXITCODE); still $nxNow"
                    }
                } else {
                    Write-Host "  [DEP] $nxNow -> OptOut: on for all programs after the next restart" -ForegroundColor Green
                    Add-RestartReason 'Data Execution Prevention now covers all programs'
                }
            }
        }
        # The line above is what the next boot will use. If it already says OptOut
        # but the running policy does not, the PC has not rebooted since the change.
        # 1 = AlwaysOn, 3 = OptOut. Don't touch BitLocker here: nothing is changing.
        if ($nxNow -in 'OptOut', 'AlwaysOn') {
            $runningDep = $null
            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                if ($os.PSObject.Properties['DataExecutionPrevention_SupportPolicy']) {
                    $runningDep = [int]$os.DataExecutionPrevention_SupportPolicy
                }
            } catch {
                $runningDep = $null
            }
            if ($null -ne $runningDep -and $runningDep -notin 1, 3) {
                Add-RestartReason 'Data Execution Prevention was set for all programs and is waiting for a restart'
            }
        }
    }
}

# ---------------------------------------------------------------
# SECTION 9b: Core isolation (not CIS)
# Windows Security > Device security > Core isolation:
#   Memory integrity (HVCI): Windows checks kernel code in a separate,
#     hypervisor-protected space, so malware that reaches the kernel can't
#     load unsigned code or change protected memory. Needs virtualization
#     turned on in the PC's firmware (Intel VT-x / AMD SVM).
#   Kernel-mode Hardware-enforced Stack Protection: the CPU keeps a shadow
#     copy of each kernel return address, which stops exploits that rewrite
#     them. Needs memory integrity, and an Intel 11th gen or AMD Zen 3 or
#     newer CPU; on older CPUs it's set but never runs, which is only noted.
#   Local Security Authority protection: lsass.exe, which holds signed-in
#     users' credentials, runs as a protected process that tools like
#     Mimikatz can't read. Set to 2 (on, without a UEFI lock) so it can still
#     be turned off in Windows Security; a 1 (UEFI-locked) is left alone.
#   Microsoft Vulnerable Driver Blocklist: stops known-vulnerable drivers
#     loading, which malware brings along to get into the kernel ("bring your
#     own vulnerable driver"). winmodcheck checks loaded drivers against the
#     larger loldrivers.io list.
# All but the blocklist start after a restart; a setting changed here adds a
# restart note to the summary. Otherwise Windows is asked whether each is
# actually running, and one that isn't is a failure (stack protection, only
# a note).
# Watch for after the first restart:
#   - Windows Security won't turn memory integrity on while an incompatible
#     driver is installed, but this sets it directly. That driver then won't
#     load, so its device (often an old printer, audio, VPN or anti-cheat
#     driver) may stop working. Windows Security > Device security > Core
#     isolation details lists them; update or remove the driver, or turn
#     memory integrity off there.
#   - LSA protection blocks unsigned add-ins to Windows sign-in, such as some
#     smart card or older VPN tools.
# ---------------------------------------------------------------
function Set-CoreIsolation {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Turning On Core Isolation' '.'

    $dg = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    # Ok: values that count as on. Feature: the name for the restart note.
    $settings = @(
        @{ Feature = 'Memory integrity'; Path = "$dg\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = 'Enabled'; Value = 1; Ok = @(1) }
        @{ Feature = 'Memory integrity'; Path = $dg; Name = 'EnableVirtualizationBasedSecurity'; Value = 1; Ok = @(1) }
        @{ Feature = 'Kernel-mode Hardware-enforced Stack Protection'; Path = "$dg\Scenarios\KernelShadowStacks"; Name = 'Enabled'; Value = 1; Ok = @(1) }
        @{ Feature = 'Local Security Authority protection'; Path = $lsa; Name = 'RunAsPPL'; Value = 2; Ok = @(1, 2) }
        @{ Feature = 'Local Security Authority protection'; Path = $lsa; Name = 'RunAsPPLBoot'; Value = 2; Ok = @(1, 2) }
        @{ Feature = 'Microsoft Vulnerable Driver Blocklist'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config'; Name = 'VulnerableDriverBlocklistEnable'; Value = 1; Ok = @(1) }
    )
    $changed = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $settings) {
        $item = Get-ItemProperty -Path $s.Path -ErrorAction SilentlyContinue
        $now = if ($item -and $item.PSObject.Properties[$s.Name]) { $item.($s.Name) } else { $null }
        if ($null -ne $now -and $s.Ok -contains [int]$now) {
            Write-Host "  [Core isolation] $($s.Name) = $now  # $($s.Feature): already on" -ForegroundColor Green
            continue
        }
        Set-RegistryValue -Path $s.Path -Name $s.Name -Value $s.Value -Description "$($s.Feature): turned on (was $(if ($null -eq $now) { 'not set' } else { $now }))"
        if (-not $changed.Contains($s.Feature)) { $changed.Add($s.Feature) }
    }
    if ($changed.Count) {
        $restart = @($changed | Where-Object { $_ -ne 'Microsoft Vulnerable Driver Blocklist' })
        if ($restart) { Add-RestartReason "Turn on $($restart -join ', ')" }
    }

    # What's running now. Win32_DeviceGuard lists running services by number:
    # 2 = memory integrity, 5 = kernel-mode hardware-enforced stack protection.
    # VirtualizationBasedSecurityStatus: 0 = off, 1 = on but not running, 2 = running.
    $dgInfo = $null
    try {
        $dgInfo = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName 'Win32_DeviceGuard' -ErrorAction Stop
    } catch {
        Write-Fail "[Core isolation] Couldn't ask Windows what's running: $($_.Exception.Message)"
        return
    }
    $running = @($dgInfo.SecurityServicesRunning | ForEach-Object { [int]$_ })
    $vbs = [int]$dgInfo.VirtualizationBasedSecurityStatus

    if ($running -contains 2) {
        Write-Host "  [Core isolation] Memory integrity: running" -ForegroundColor Green
    } elseif (-not $changed.Contains('Memory integrity')) {
        $why = if ($vbs -eq 0) {
            'virtualization-based security is off; turn on virtualization (Intel VT-x / AMD SVM) in the PC''s firmware settings'
        } else {
            'an incompatible driver may be stopping it; see Windows Security > Device security > Core isolation details'
        }
        Write-Fail "[Core isolation] Memory integrity is set but not running after a restart: $why"
    }

    if ($running -contains 5) {
        Write-Host "  [Core isolation] Kernel-mode Hardware-enforced Stack Protection: running" -ForegroundColor Green
    } elseif (-not $changed.Contains('Kernel-mode Hardware-enforced Stack Protection')) {
        $msg = 'Kernel-mode Hardware-enforced Stack Protection is set but not running; it needs memory integrity running and an Intel 11th gen or AMD Zen 3 or newer CPU'
        Write-Host "  [Core isolation] $msg" -ForegroundColor Yellow
        $script:Notes.Add($msg)
    }

    # LSA protection: Wininit logs event 12, "LSASS.exe was started as a
    # protected process", at each startup where it's on
    if (-not $changed.Contains('Local Security Authority protection')) {
        $boot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
        $ppl = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Wininit'; Id = 12; StartTime = $boot } `
            -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($ppl) {
            Write-Host "  [Core isolation] Local Security Authority protection: running" -ForegroundColor Green
        } else {
            Write-Fail "[Core isolation] Local Security Authority protection is set but LSASS didn't start protected at the last restart (no Wininit event 12 since $boot)"
        }
    }
}

# ---------------------------------------------------------------
# SECTION 9c: Developer Mode off (not CIS)
# Settings > System > For developers > Developer Mode. While it's on, apps can
# be installed from loose, unsigned files (not just signed packages), any user
# can create symbolic links without admin rights, and the Device Portal and
# Device discovery options can expose services to the network. Malware and
# attackers use the first two. If it's on, this reports a failure (in case
# something other than you turned it on) and turns it off.
# To use it for a while, turn it on in Settings; the next run turns it off.
# Tools that make symlinks as a normal user (git with core.symlinks, npm,
# Cygwin with winsymlinks:native) fall back to copies or fail while it's off.
# ---------------------------------------------------------------
function Disable-DeveloperMode {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Checking Developer Mode' '.'

    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    $name = 'AllowDevelopmentWithoutDevLicense'
    $read = {
        $item = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($item -and $item.PSObject.Properties[$name]) { [int]$item.$name } else { 0 }
    }
    if ((& $read) -eq 0) {
        Write-Host '  [Developer Mode] Off' -ForegroundColor Green
        return
    }
    Set-TrackedValue -Path $key -Name $name -Value 0
    if ((& $read) -eq 0) {
        Write-Fail '[Developer Mode] Was on; turned it off. If you (or a developer tool you installed) didn''t turn it on, find out what did'
    } else {
        Write-Fail '[Developer Mode] Is on, and turning it off didn''t stick (a policy may be holding it on)'
    }
}

# ---------------------------------------------------------------
# SECTION 9d: Exploit protection system settings at their defaults (not CIS)
# Windows Security > App & browser control > Exploit protection > System
# settings. Each shows "Use default", which is:
#   Control flow guard (CFG)                     on
#   Data Execution Prevention (DEP)              on
#   Force randomization for images (Mandatory ASLR)  off
#   Randomize memory allocations (Bottom-up ASLR)    on
#   High-entropy ASLR                            on
#   Validate exception chains (SEHOP)            on
#   Validate heap integrity                      on
# Turning one off weakens every program on the PC, which malware or a
# "game booster" may do. Turning Mandatory ASLR on breaks some older programs.
# If any system setting (including ones the page doesn't show, and audit
# settings) isn't "Use default", all are reset to it. One that was off is
# reported as a failure; one that was on is just reset. Needs a restart.
# Program settings (per-program overrides) aren't changed: Windows and some
# programs' installers add their own, and there's no list of Windows' own to
# reset them to.
# ---------------------------------------------------------------
function Reset-ExploitProtection {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Checking Exploit Protection System Settings' '.'

    if (-not (Get-Command Get-ProcessMitigation -ErrorAction SilentlyContinue)) {
        Write-Fail '[Exploit protection] The ProcessMitigations PowerShell module is missing; settings not checked'
        return
    }
    $labels = @{
        'CFG.Enable'               = 'Control flow guard (CFG)'
        'DEP.Enable'               = 'Data Execution Prevention (DEP)'
        'ASLR.ForceRelocateImages' = 'Force randomization for images (Mandatory ASLR)'
        'ASLR.BottomUp'            = 'Randomize memory allocations (Bottom-up ASLR)'
        'ASLR.HighEntropy'         = 'High-entropy ASLR'
        'SEHOP.Enable'             = 'Validate exception chains (SEHOP)'
        'Heap.TerminateOnError'    = 'Validate heap integrity'
    }
    # Every system setting that's ON or OFF rather than NOTSET ("Use default"),
    # as Group.Setting
    $read = {
        $system = Get-ProcessMitigation -System
        foreach ($group in $system.PSObject.Properties) {
            $v = $group.Value
            if ($null -eq $v -or $v -is [string] -or $v.GetType().IsPrimitive -or $v.GetType().IsEnum) { continue }
            foreach ($p in $v.PSObject.Properties) {
                $state = "$($p.Value)"
                if ($state -eq 'ON' -or $state -eq 'OFF') {
                    $id = "$($group.Name).$($p.Name)"
                    $label = if ($labels.ContainsKey($id)) { $labels[$id] } else { $id }
                    [pscustomobject]@{ Label = $label; State = $state }
                }
            }
        }
    }

    $changed = @(& $read)
    if ($changed.Count -eq 0) {
        Write-Host '  [Exploit protection] All system settings: Use default' -ForegroundColor Green
        return
    }

    # Where Windows keeps them, for the undo file
    $kernel = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
    $before = @{}
    foreach ($n in 'MitigationOptions', 'MitigationAuditOptions') { $before[$n] = Get-RegistryValueState -Path $kernel -Name $n }
    Set-ProcessMitigation -System -Reset
    foreach ($n in $before.Keys) { Add-RegistryUndo -Path $kernel -Name $n -Before $before[$n] }

    $left = @(& $read | ForEach-Object { $_.Label })
    foreach ($c in $changed) {
        $was = if ($c.State -eq 'OFF') { 'was turned off' } else { 'was on' }
        if ($left -contains $c.Label) {
            Write-Fail "[Exploit protection] $($c.Label) $was, and resetting it to Use default didn't stick (a policy may be holding it)"
        } elseif ($c.State -eq 'OFF') {
            Write-Fail "[Exploit protection] $($c.Label) $was; set back to Use default. If you didn't turn it off, find out what did"
        } else {
            Write-Host "  [Exploit protection] $($c.Label) $was; set back to Use default" -ForegroundColor Yellow
        }
    }
    $script:Notes.Add('Restart Windows to apply the Exploit protection system settings')
}

# ---------------------------------------------------------------
# SECTION 10: Microsoft Defender Antivirus settings
# The switches in Windows Security > Virus & threat protection > Manage
# settings. Each is read back afterwards: a setting that didn't stick was
# usually blocked by Tamper protection or by a policy.
#   Real-time protection - scans files as they're opened, downloaded or run.
#   Cloud-delivered protection - asks Microsoft's cloud about files it hasn't
#     seen before, which catches brand-new malware in seconds. The ASR
#     prevalence rule (Section 6) depends on it. "Advanced" sends more detail
#     about suspicious files.
#   Automatic sample submission - "send safe samples": suspicious program
#     files are uploaded for analysis automatically. Files that may hold
#     personal data (documents, email) aren't sent without asking.
#   Potentially unwanted app protection - blocks adware and bundleware that
#     isn't quite malware, the "PUA" switch in Windows Security.
#   Network protection - blocks programs, not only browsers, from connecting
#     to sites Microsoft has marked malicious. Needs cloud-delivered protection.
#   Dev Drive protection - Dev Drives (a fast volume type for code) are
#     scanned in performance mode, which checks files just after opening
#     them instead of before. Without it a Dev Drive gets regular scanning,
#     or none if antivirus has been excluded from it, so this also makes sure
#     antivirus is allowed on Dev Drives. Needs Windows 11 23H2 or later.
#   Controlled folder access - only trusted programs can change files in
#     Documents, Pictures, Videos, Music, Desktop and Favorites, which stops
#     ransomware encrypting them. Unknown programs that save there are
#     blocked (Windows shows a notification); allow them with
#     $ControlledFolderAllowedApps at the top.
#   Tamper protection - stops anything, including malware with admin rights,
#     changing these settings. Windows deliberately has no way to turn it on
#     from a script, so it's checked and, if off, Windows Security opens at
#     the page to turn it on.
# ---------------------------------------------------------------
function Set-DefenderSetting {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Applying Microsoft Defender Antivirus Settings" '.'

    $mpMode = Get-DefenderMode
    if ($mpMode -ne 'Normal') {
        Write-Fail "[Defender] Defender isn't the active antivirus (mode: $mpMode); its settings weren't changed"
    } else {
        # Name -> Set-MpPreference parameters, and a test of Get-MpPreference that
        # it took. Get-MpPreference reports numbers, e.g. MAPSReporting 2 = Advanced.
        $defenderSettings = [ordered]@{
            'Real-time protection' = @{
                Set   = @{ DisableRealtimeMonitoring = $false }
                Check = { param($p) -not $p.DisableRealtimeMonitoring }
            }
            'Cloud-delivered protection' = @{
                Set   = @{ MAPSReporting = 'Advanced' }
                Check = { param($p) "$($p.MAPSReporting)" -in '2', 'Advanced' }
            }
            'Automatic sample submission' = @{
                Set   = @{ SubmitSamplesConsent = 'SendSafeSamples' }
                Check = { param($p) "$($p.SubmitSamplesConsent)" -in '1', 'SendSafeSamples' }
            }
            # 0 = off, 1 = on, 2 = audit. Audit is not enough: it only logs.
            'Potentially unwanted app protection' = @{
                Set   = @{ PUAProtection = 'Enabled' }
                Check = { param($p) "$($p.PUAProtection)" -in '1', 'Enabled' }
            }
            # 0 = off, 1 = block, 2 = audit. Enabled and Block are both the block mode.
            'Network protection' = @{
                Set   = @{ EnableNetworkProtection = 'Enabled' }
                Check = { param($p) "$($p.EnableNetworkProtection)" -in '1', 'Enabled', 'Block' }
            }
            'Dev Drive protection' = @{
                Set   = @{ PerformanceModeStatus = 'Enabled' }
                Check = { param($p) "$($p.PerformanceModeStatus)" -in '0', 'Enabled' }
            }
            'Controlled folder access' = @{
                Set   = @{ EnableControlledFolderAccess = 'Enabled' }
                Check = { param($p) "$($p.EnableControlledFolderAccess)" -in '1', 'Enabled' }
            }
        }
        $setFailed = @{}
        foreach ($name in $defenderSettings.Keys) {
            $splat = $defenderSettings[$name].Set
            try {
                Set-MpPreference @splat -ErrorAction Stop
            } catch [System.Management.Automation.ParameterBindingException] {
                Write-Fail "[Defender] $name isn't available on this version of Windows"
                $setFailed[$name] = $true
            } catch {
                Write-Fail "[Defender] Couldn't turn on ${name}: $($_.Exception.Message)"
                $setFailed[$name] = $true
            }
        }

        # Antivirus allowed on Dev Drives (it can be excluded when one is set up)
        fsutil devdrv enable /allowAv | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [Defender] Couldn't allow antivirus on Dev Drives (fsutil exit $LASTEXITCODE); Windows may be too old for Dev Drives" -ForegroundColor Yellow
        }

        $folderAllowed = @()
        try { $folderAllowed = @((Get-MpPreference).ControlledFolderAccessAllowedApplications) } catch { $folderAllowed = @() }
        foreach ($app in $ControlledFolderAllowedApps) {
            if ($folderAllowed -contains $app) {
                Write-Host "  [Defender] Controlled folder access already allows $app" -ForegroundColor Green
                continue
            }
            try {
                Add-MpPreference -ControlledFolderAccessAllowedApplications $app -ErrorAction Stop
                Write-Host "  [Defender] Controlled folder access allows $app" -ForegroundColor Green
            } catch {
                # A path stored with different casing still counts as present
                if ($_.Exception.Message -match 'already') {
                    Write-Host "  [Defender] Controlled folder access already allows $app" -ForegroundColor Green
                } else {
                    Write-Fail "[Defender] Couldn't allow $app in Controlled folder access: $($_.Exception.Message)"
                }
            }
        }

        # Read back what Defender is actually using
        $pref = Get-MpPreference
        foreach ($name in $defenderSettings.Keys) {
            if ($setFailed[$name]) { continue }
            $ok = $false
            try { $ok = [bool](& $defenderSettings[$name].Check $pref) } catch { }
            if ($ok) {
                Write-Host "  [Defender] $name`: on" -ForegroundColor Green
            } else {
                Write-Fail "[Defender] $name didn't turn on (Tamper protection or a policy may be holding it off)"
            }
        }

        $tamper = $null
        try { $tamper = (Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected } catch { }
        if ($tamper -eq $true) {
            Write-Host "  [Defender] Tamper protection: on" -ForegroundColor Green
        } else {
            Write-Fail "[Defender] Tamper protection is off; turn it on in Windows Security > Virus & threat protection > Manage settings (opened for you)"
            Start-Process 'windowsdefender://threatsettings' -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------
# SECTION 10b: Reputation-based protection (CIS, where it has them)
# The switches in Windows Security > App & browser control > Reputation-based
# protection, set as policies so the switches are locked on ("managed by your
# organization"). Potentially unwanted app blocking's "Block apps" switch is
# Defender's PUA protection, set in Section 10.
#   Check apps and files - SmartScreen checks programs and files downloaded
#     from the internet against Microsoft's list of known good and bad
#     software. Set to "Warn and prevent bypass": a flagged or unknown
#     download has no "Run anyway" button. To run one you trust: right-click
#     it > Properties > tick Unblock > OK, or Unblock-File <path>.
#   SmartScreen for Microsoft Edge - the same checks for sites and downloads
#     in Edge, with no way to click past a warning. Windows still opens some
#     links in Edge whatever the default browser is.
#   Phishing protection - warns when your Windows password is typed into a
#     phishing site or app, reused on a website, or saved in Notepad, Word or
#     WordPad. Only works when you sign in to Windows with a password, not a
#     PIN or Windows Hello.
#   Potentially unwanted app blocking, Block downloads - Edge blocks
#     downloads of adware and bundleware.
#   SmartScreen for Microsoft Store apps - checks the web content Store apps
#     load. A per-user setting, so it's set for every account.
# A setting that was there but off is reported as a failure, in case
# something other than you turned it off; one that wasn't there yet (the
# Windows default) is just turned on.
# ---------------------------------------------------------------
function Set-ReputationProtection {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Applying Reputation-based Protection' '.'

    # Sets one value, reports it, and says whether it was already right
    $apply = {
        param($label, $path, $name, $value, $type)
        $same = { param($s) $s -and $s.Kind -eq $type -and "$($s.Data)" -eq "$value" }
        $before = Get-RegistryValueState -Path $path -Name $name
        if (& $same $before) {
            Write-Host "  [Reputation] $label`: on" -ForegroundColor Green
            return
        }
        Set-TrackedValue -Path $path -Name $name -Value $value -Type $type
        if (-not (& $same (Get-RegistryValueState -Path $path -Name $name))) {
            Write-Fail "[Reputation] ${label}: couldn't turn it on ($path $name)"
        } elseif ($before) {
            Write-Fail "[Reputation] ${label}: was off ($name = $($before.Data)); turned back on. If you didn't turn it off, find out what did"
        } else {
            Write-Host "  [Reputation] $label`: turned on" -ForegroundColor Green
        }
    }

    # Check apps and files. ShellSmartScreenLevel Block = warn and prevent
    # bypass; Warn would keep "Run anyway".
    $system = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    & $apply 'Check apps and files' $system 'EnableSmartScreen' 1 'DWord'
    & $apply 'Check apps and files: warn and prevent bypass' $system 'ShellSmartScreenLevel' 'Block' 'String'

    # Microsoft Edge (restart Edge to apply). The two Prevent... policies
    # remove the option to continue past a warning for sites and downloads.
    $edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    & $apply 'SmartScreen for Microsoft Edge' $edge 'SmartScreenEnabled' 1 'DWord'
    & $apply 'SmartScreen for Microsoft Edge: no bypass for sites' $edge 'PreventSmartScreenPromptOverride' 1 'DWord'
    & $apply 'SmartScreen for Microsoft Edge: no bypass for downloads' $edge 'PreventSmartScreenPromptOverrideForFiles' 1 'DWord'
    & $apply 'Potentially unwanted app blocking: block downloads' $edge 'SmartScreenPuaEnabled' 1 'DWord'

    # Phishing protection (Enhanced Phishing Protection, Windows 11 22H2 and
    # later). The "collect content for analysis" option isn't set: it sends
    # screenshots of the page or app to Microsoft.
    $wtds = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WTDS\Components'
    & $apply 'Phishing protection' $wtds 'ServiceEnabled' 1 'DWord'
    & $apply 'Phishing protection: warn about malicious apps and sites' $wtds 'NotifyMalicious' 1 'DWord'
    & $apply 'Phishing protection: warn about password reuse' $wtds 'NotifyPasswordReuse' 1 'DWord'
    & $apply 'Phishing protection: warn about unsafe password storage' $wtds 'NotifyUnsafeApp' 1 'DWord'

    # SmartScreen for Microsoft Store apps, per user
    Invoke-InEachUserHive {
        param($root, $label)
        try {
            & $apply "SmartScreen for Microsoft Store apps ($label)" "$root\Software\Microsoft\Windows\CurrentVersion\AppHost" 'EnableWebContentEvaluation' 1 'DWord'
        } catch {
            Write-Fail "[Reputation] ${label}: couldn't turn on SmartScreen for Microsoft Store apps: $($_.Exception.Message)"
        }
    }
}

# ---------------------------------------------------------------
# Defender Protection History - the last 7 days
# The same entries as Windows Security > Protection history, read from
# Defender's event log (Event Viewer: Applications and Services Logs >
# Microsoft > Windows > Windows Defender > Operational). Includes blocks by
# the ASR rules from Section 6, so a legitimate program they stopped shows up
# here with its path, ready for an exclusion.
# Written to a text file on the Desktop (replaced each run), which opens in
# Notepad at the end of the script. GetFolderPath finds the Desktop even when
# OneDrive has moved it. Run elevated from your own account, that's your
# Desktop; run as a different admin account, it's that account's Desktop.
# ---------------------------------------------------------------
function Save-ProtectionHistory {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $historyDays = 7
    $historyMax = 1000
    # Kept in the log folder; the Desktop report (Save-RunStatus) includes it.
    # Earlier versions wrote it to the Desktop.
    $script:HistoryFile = Join-Path $LogDir 'Defender Protection History.txt'
    Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Defender Protection History.txt') -ErrorAction SilentlyContinue
    $historyLog = 'Microsoft-Windows-Windows Defender/Operational'
    $historyEvents = @{
        1116 = 'Threat found'
        1117 = 'Threat action taken'
        1118 = 'Threat action failed'
        1119 = 'Threat action failed (critical)'
        1121 = 'ASR rule blocked'
        1122 = 'ASR rule audited'
        1123 = 'Folder access blocked'
        1124 = 'Folder access audited'
        1125 = 'Network protection audited'
        1126 = 'Network protection blocked'
    }

    Write-Banner "Defender Protection History (last $historyDays days)" '.'

    $since = (Get-Date).AddDays(-$historyDays)
    $report = [System.Collections.Generic.List[string]]::new()
    $report.Add("Defender Protection History for $env:COMPUTERNAME")
    $report.Add("$($since.ToString('yyyy-MM-dd HH:mm')) to $((Get-Date).ToString('yyyy-MM-dd HH:mm')), newest first")
    $report.Add("Written by dailyrunme.ps1. Source: Event Viewer > Applications and Services Logs >")
    $report.Add("Microsoft > Windows > Windows Defender > Operational")
    $report.Add('')
    $historySummary = ''

    if (-not (Get-WinEvent -ListLog $historyLog -ErrorAction SilentlyContinue)) {
        $historySummary = "Defender's event log isn't available on this PC"
        $report.Add($historySummary)
    } else {
        # Newest first. No matching events is reported as an error, hence SilentlyContinue.
        $events = @(Get-WinEvent -ErrorAction SilentlyContinue -FilterHashtable @{
            LogName   = $historyLog
            Id        = @($historyEvents.Keys)
            StartTime = $since
        })
        $historySummary = "$($events.Count) entries"
        if ($events.Count -eq 0) {
            $historySummary = "Nothing in the last $historyDays days"
            $report.Add($historySummary)
        } elseif ($events.Count -gt $historyMax) {
            $historySummary = "$($events.Count) entries, newest $historyMax listed"
            $report.Add("$($events.Count) entries; the newest $historyMax are listed (the rest are in Event Viewer)")
            $report.Add('')
        }
        foreach ($e in $events | Select-Object -First $historyMax) {
            # The event's named fields, e.g. 'Threat Name', 'ID', 'Path', 'Process Name'
            $data = @{}
            foreach ($d in ([xml]$e.ToXml()).GetElementsByTagName('Data')) {
                $data[$d.GetAttribute('Name')] = $d.InnerText
            }
            $title = $historyEvents[$e.Id]
            if ($data['Threat Name']) {
                $title += ": $($data['Threat Name'])"
                if ($data['Severity Name']) { $title += " ($($data['Severity Name']) severity)" }
            } elseif ($data['ID']) {
                # ASR events name the rule by ID; show the name for the rules this script sets
                $rule = "$($data['ID'])".ToLowerInvariant()
                $title += ": $(if ($asrRules.Contains($rule)) { $asrRules[$rule] } else { "rule $rule (not set by this script)" })"
            }
            if ($e.Id -eq 1117 -and $data['Action Name']) { $title += " -> $($data['Action Name'])" }

            # Failures to remove a threat need attention first
            $flag = if ($e.Id -in 1118, 1119) { '!! ' } else { '' }
            $report.Add("$($e.TimeCreated.ToString('yyyy-MM-dd HH:mm'))  $flag$title")
            # Threat paths come as e.g. "file:_C:\x.exe;process:_pid:123,ProcessStart:..."
            # Keep the files and drop the process entries; ASR paths are plain
            $path = (@("$($data['Path'])" -split ';' |
                Where-Object { $_ -and $_ -notlike 'process:_*' } |
                ForEach-Object { $_ -replace '^\w+:_', '' }) -join ', ')
            if ($path) { $report.Add("    File:    $path") }
            if ($data['Process Name']) { $report.Add("    Process: $($data['Process Name'])") }
            if ($data['Detection User']) { $report.Add("    User:    $($data['Detection User'])") }
            $report.Add('')
        }
        if ($events | Where-Object { $_.Id -in 1118, 1119 }) {
            $historySummary += ", including threats Defender couldn't remove (marked !!)"
        }
    }

    $report.Add('')
    $report.Add('To allow a program an ASR rule blocked (run as admin):')
    $report.Add("    Add-MpPreference -AttackSurfaceReductionOnlyExclusions 'C:\path\program.exe'")

    try {
        Set-Content -LiteralPath $script:HistoryFile -Value $report -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Fail "[History] Couldn't write ${script:HistoryFile}: $($_.Exception.Message)"
        $script:HistoryFile = $null
        return
    }
    Write-Host "  $historySummary; saved to $script:HistoryFile" -ForegroundColor Green
}

# ---------------------------------------------------------------
# Update, scan and check steps
# ---------------------------------------------------------------

# patchmssigs
function Update-DefenderSignature {
    Write-Banner 'Microsoft Defender Signature Update' '.'
    $show = {
        Get-MpComputerStatus -ErrorAction Stop |
            Format-Table AntivirusSignatureVersion, AntivirusSignatureLastUpdated -AutoSize |
            Out-Host
    }
    try {
        & $show
        Update-MpSignature -ErrorAction Stop
        & $show
    } catch {
        Write-Fail "Defender signature update: $($_.Exception.Message)"
    }
}

# patchwindows: Windows Update, through its own API (the one Settings uses), so
# nothing has to be installed. Installs what Windows Update would install on its
# own, drivers included, now rather than on its schedule; optional updates
# (Settings > Windows Update > Advanced options > Optional updates) are listed,
# not installed. Never restarts the PC. Also turns on, in Settings > Windows
# Update > Advanced options:
#   - Receive updates for other Microsoft products: Office, Visual C++
#     runtimes, .NET and so on, through Microsoft Update. Turning it off in
#     Settings undoes it (as well as the registry undo file).
#   - Notify me when a restart is required to finish updating
# and fails if Windows Update has been switched off, paused, or pointed at
# another update server, which malware does to keep its holes open.
function Update-Windows {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $ux = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    Set-TrackedValue -Path $ux -Name 'AllowMUUpdateService' -Value 1
    Set-TrackedValue -Path $ux -Name 'RestartNotificationsAllowed2' -Value 1
    Write-Host '  [Windows Update] Restart notifications on' -ForegroundColor Green

    # Microsoft Update is a second update service; the Settings switch registers
    # it, as this does. Flags 7: register now, or at next restart if it can't,
    # and use it for automatic updates too.
    $muId = '7971f918-a847-4430-9279-4a52d1efe18d'
    $useMu = $false
    try {
        $serviceManager = New-Object -ComObject Microsoft.Update.ServiceManager
        if (@($serviceManager.Services | Where-Object { $_.ServiceID -eq $muId }).Count -eq 0) {
            [void]$serviceManager.AddService2($muId, 7, '')
            Write-Host '  [Windows Update] Updates for other Microsoft products: turned on' -ForegroundColor Green
        } else {
            Write-Host '  [Windows Update] Updates for other Microsoft products: on' -ForegroundColor Green
        }
        $useMu = $true
    } catch {
        Write-Fail "[Windows Update] Couldn't turn on updates for other Microsoft products: $($_.Exception.Message)"
    }

    # Switched off, paused or redirected
    foreach ($name in 'wuauserv', 'UsoSvc') {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc -and "$($svc.StartType)" -eq 'Disabled') {
            Write-Fail "[Windows Update] The $($svc.DisplayName) service ($name) is disabled. Unless you did that: Set-Service $name -StartupType Manual"
        }
    }
    $wuPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $policyValue = {
        param($path, $name)
        $state = Get-RegistryValueState -Path $path -Name $name
        if ($state) { $state.Data } else { $null }
    }
    if ((& $policyValue "$wuPolicy\AU" 'NoAutoUpdate') -eq 1) {
        Write-Fail "[Windows Update] Automatic updates are turned off by policy ($wuPolicy\AU NoAutoUpdate = 1)"
    }
    if ((& $policyValue $wuPolicy 'DisableWindowsUpdateAccess') -eq 1) {
        Write-Fail "[Windows Update] Windows Update is blocked by policy ($wuPolicy DisableWindowsUpdateAccess = 1)"
    }
    if ((& $policyValue $wuPolicy 'DoNotConnectToWindowsUpdateInternetLocations') -eq 1) {
        Write-Fail "[Windows Update] Windows Update is cut off from Microsoft by policy ($wuPolicy DoNotConnectToWindowsUpdateInternetLocations = 1)"
    }
    # A stand-alone PC gets updates from Microsoft; an update server (WSUS) is
    # for company networks
    if ((& $policyValue "$wuPolicy\AU" 'UseWUServer') -eq 1) {
        Write-Fail "[Windows Update] Updates come from $(& $policyValue $wuPolicy 'WUServer') instead of Microsoft ($wuPolicy\AU UseWUServer = 1)"
    }
    $uxValues = Get-ItemProperty -Path $ux -ErrorAction SilentlyContinue
    if ($uxValues) {
        foreach ($p in $uxValues.PSObject.Properties | Where-Object { $_.Name -match '^Pause.*(ExpiryTime|EndTime)$' }) {
            $until = [datetime]::MinValue
            if ([datetime]::TryParse("$($p.Value)", [ref]$until) -and $until -gt (Get-Date)) {
                Write-Fail "[Windows Update] Updates are paused until $($until.ToString('yyyy-MM-dd')) ($($p.Name)). Unless you did that: Settings > Windows Update > Resume updates"
                break
            }
        }
    }

    try {
        if ((New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired) {
            Write-Host '  [Windows Update] A restart from earlier updates is waiting; some updates may not install until then' -ForegroundColor Yellow
            Add-RestartReason 'Windows Update is already waiting for a restart'
        }
    } catch {
        Write-Verbose 'restart status unknown'
    }

    Write-Banner 'Searching Windows Update' '.'
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'dailyrunme'
    $searcher = $session.CreateUpdateSearcher()
    if ($useMu) {
        # 3 = a service named by ServiceID, here Microsoft Update (which includes
        # everything Windows Update has)
        $searcher.ServerSelection = 3
        $searcher.ServiceID = $muId
    }
    # No Type: both software and driver updates. Hidden ones were hidden on purpose.
    try {
        $found = @($searcher.Search('IsInstalled=0 and IsHidden=0').Updates)
    } catch {
        Write-Fail "[Windows Update] Search failed: $($_.Exception.Message)"
        return
    }
    $optional = @($found | Where-Object { $_.BrowseOnly })
    $wanted = @($found | Where-Object { -not $_.BrowseOnly })
    foreach ($u in $optional) { Write-Host "  [Windows Update] Optional, not installed: $($u.Title)" -ForegroundColor DarkGray }
    if ($wanted.Count -eq 0) {
        Write-Host '  [Windows Update] Up to date' -ForegroundColor Green
        return
    }
    Write-Host "  [Windows Update] $($wanted.Count) update(s) to install" -ForegroundColor Cyan

    # One at a time: some updates must install on their own, and one failing
    # doesn't hold up the rest. 2 = succeeded, 3 = succeeded with errors.
    $results = @{ 0 = 'not started'; 1 = 'in progress'; 2 = 'installed'; 3 = 'installed with errors'; 4 = 'failed'; 5 = 'aborted' }
    $restart = $false
    $i = 0
    foreach ($u in $wanted) {
        $i += 1
        $kind = if ($u.Type -eq 2) { 'Driver' } else { 'Update' }
        $title = "[$kind] $($u.Title)"
        Write-Host "  ($i/$($wanted.Count)) $title" -ForegroundColor Cyan
        if ($u.InstallationBehavior.CanRequestUserInput) {
            Write-Host '    Skipped: it asks questions while installing; install it from Settings > Windows Update' -ForegroundColor Yellow
            continue
        }
        try {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            $one = New-Object -ComObject Microsoft.Update.UpdateColl
            [void]$one.Add($u)
            if (-not $u.IsDownloaded) {
                $downloader = $session.CreateUpdateDownloader()
                $downloader.Updates = $one
                $dl = $downloader.Download()
                if ($dl.ResultCode -notin 2, 3) {
                    Write-Fail "[Windows Update] Download $($results[[int]$dl.ResultCode]) (0x$('{0:X8}' -f $dl.HResult)): $title"
                    continue
                }
            }
            $installer = $session.CreateUpdateInstaller()
            $installer.Updates = $one
            # No installer windows; older Windows Update clients don't have the setting
            try { $installer.ForceQuiet = $true } catch { Write-Verbose 'ForceQuiet not available' }
            $result = $installer.Install()
            $code = [int]$result.ResultCode
            if ($code -in 2, 3) {
                Write-Host "    $($results[$code])" -ForegroundColor Green
            } else {
                Write-Fail "[Windows Update] Install $($results[$code]) (0x$('{0:X8}' -f $result.GetUpdateResult(0).HResult)): $title"
            }
            if ($result.RebootRequired) { $restart = $true }
        } catch {
            Write-Fail "[Windows Update] ${title}: $($_.Exception.Message)"
        }
    }
    if ($restart) { Add-RestartReason 'Windows updates that were just installed need a restart' }
}

# patchoffice: Microsoft 365 Apps and Office 2019/2021/2024 install as Click-to-Run,
# which updates itself with its own updater, not through Windows Update. This
# reports its version, channel and update settings, fails if updates are off,
# blocked or redirected away from Microsoft's servers, and asks the updater to
# check now. The updater works in the background and doesn't report back, so a
# new version shows on the next run (compared with the last run's version, kept
# in the log folder) or in any Office app under File > Account. Office apps are
# never closed; an update waits until they are. MSI-installed Office (2016 and
# older, mostly business copies) is updated through Microsoft Update instead, by
# patchwindows.
function Update-Office {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $cfgPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $cfg = Get-ItemProperty -Path $cfgPath -ErrorAction SilentlyContinue
    if (-not $cfg) {
        Write-Host '  [Office] No Click-to-Run Office installed; MSI Office, if any, is updated by patchwindows' -ForegroundColor DarkGray
        return
    }
    $get = {
        param($from, $name)
        if ($from -and $from.PSObject.Properties[$name]) { "$($from.$name)" } else { '' }
    }

    # Version, against the last run's
    $version = & $get $cfg 'VersionToReport'
    $versionFile = Join-Path $LogDir 'office-version.txt'
    $last = if (Test-Path -LiteralPath $versionFile) { "$(Get-Content -LiteralPath $versionFile -TotalCount 1)".Trim() } else { '' }
    $products = (& $get $cfg 'ProductReleaseIds') -replace ',', ', '
    if ($last -and $version -and $last -ne $version) {
        Write-Host "  [Office] $products updated since the last run: $last -> $version" -ForegroundColor Green
    } else {
        Write-Host "  [Office] $products version $version" -ForegroundColor Green
    }
    if ($version) { Set-Content -LiteralPath $versionFile -Value $version -Encoding ASCII }

    # Update channel: a policy's choice wins over Office's own setting
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate'
    $policy = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
    $channels = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current Channel'
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'Current Channel (Preview)'
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'Beta Channel'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'Monthly Enterprise Channel'
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'Semi-Annual Enterprise Channel'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'Semi-Annual Enterprise Channel (Preview)'
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'Office 2019 (volume licence)'
        '5030841d-c919-4594-8d2d-84ae4f96e58e' = 'Office 2021 (volume licence)'
        '7983bac0-e531-40cf-be00-fd24fe66619c' = 'Office 2024 (volume licence)'
    }
    $channelUrl = & $get $cfg 'UpdateChannel'
    if (-not $channelUrl) { $channelUrl = & $get $cfg 'CDNBaseUrl' }
    $channel = '(unknown)'
    if ($channelUrl -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') {
        $channel = if ($channels.ContainsKey($Matches[0])) { $channels[$Matches[0]] } else { $Matches[0] }
    }
    $branch = & $get $policy 'updatebranch'
    if ($branch) { $channel = "$branch (set by policy)" }
    Write-Host "  [Office] Update channel: $channel" -ForegroundColor Green

    # Off, blocked or redirected
    if ((& $get $cfg 'UpdatesEnabled') -eq 'False' -or (& $get $policy 'enableautomaticupdates') -eq '0') {
        Write-Fail '[Office] Automatic updates are off (File > Account > Update Options in any Office app, or the cis-office step)'
    }
    # Office normally gets updates from officecdn.microsoft.com. A business can
    # point it at a file share; on a stand-alone PC anything else is suspect.
    foreach ($source in @(
        @{ Where = "$cfgPath UpdateUrl"; Url = (& $get $cfg 'UpdateUrl') }
        @{ Where = "$policyPath updatepath"; Url = (& $get $policy 'updatepath') }
    )) {
        if ($source.Url -and $source.Url -notmatch '^https?://officecdn\.microsoft\.com/') {
            Write-Fail "[Office] Updates come from $($source.Url) instead of Microsoft ($($source.Where))"
        }
    }
    $svc = Get-Service -Name 'ClickToRunSvc' -ErrorAction SilentlyContinue
    if ($svc -and "$($svc.StartType)" -eq 'Disabled') {
        Write-Fail '[Office] The Microsoft Office Click-to-Run service is disabled, so Office can''t update. Unless you did that: Set-Service ClickToRunSvc -StartupType Automatic'
    }
    $task = Get-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'Office Automatic Updates 2.0' -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Fail '[Office] The "Office Automatic Updates 2.0" scheduled task is missing; repair Office (Settings > Apps > Installed apps > Microsoft 365 > Modify > Quick Repair)'
    } elseif ("$($task.State)" -eq 'Disabled') {
        Write-Fail '[Office] The "Office Automatic Updates 2.0" scheduled task is disabled. Unless you did that: Enable-ScheduledTask -TaskPath ''\Microsoft\Office\'' -TaskName ''Office Automatic Updates 2.0'''
    }

    # Check for updates now
    $clientDir = & $get $cfg 'ClientFolder'
    if (-not $clientDir) {
        # The 64-bit Common Files, even from 32-bit PowerShell
        $common = if ($env:CommonProgramW6432) { $env:CommonProgramW6432 } else { $env:CommonProgramFiles }
        $clientDir = Join-Path $common 'microsoft shared\ClickToRun'
    }
    $client = Join-Path $clientDir 'OfficeC2RClient.exe'
    if (-not (Test-Path -LiteralPath $client)) {
        Write-Fail "[Office] Office's updater isn't at $client; repair Office"
        return
    }
    $sig = Get-AuthenticodeSignature -LiteralPath $client
    $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { 'no signer' }
    if ($sig.Status -ne 'Valid' -or $signer -notmatch 'O=Microsoft Corporation') {
        Write-Fail "[Office] $client isn't validly signed by Microsoft ($($sig.Status), $signer); not run"
        return
    }
    $open = @(Get-Process -Name 'WINWORD', 'EXCEL', 'POWERPNT', 'OUTLOOK', 'ONENOTE', 'MSACCESS', 'MSPUB', 'VISIO', 'WINPROJ' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
    # displaylevel=false: no windows; forceappshutdown=false: never close open apps
    $p = Start-Process -FilePath $client -ArgumentList '/update', 'user', 'displaylevel=false', 'forceappshutdown=false' -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(120000)) {
        Write-Host '  [Office] Update check started; still running in the background' -ForegroundColor Green
    } elseif ($p.ExitCode -ne 0) {
        Write-Fail "[Office] Office's updater exited with code $($p.ExitCode)"
        return
    } else {
        Write-Host '  [Office] Update check started; any update downloads and installs in the background' -ForegroundColor Green
    }
    if ($open) {
        Write-Host "  [Office] Open now: $($open -join ', '). An update finishes once they're closed" -ForegroundColor Yellow
    }
}

# patchchoco
function Update-ChocolateyPackage {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Skip 'Chocolatey is not installed'
        return
    }
    Invoke-Native choco 'upgrade', 'all', '--ignore-dependencies', '-y'
    if ($LASTEXITCODE -ne 0) { Write-Fail "choco exited $LASTEXITCODE" }
}

# patchmsstore
function Update-StoreApp {
    if (Test-Winget) {
        Write-Banner 'winget upgrade --source msstore' '.'
        Invoke-Native winget 'upgrade', '--source', 'msstore', '--accept-source-agreements' -Skip $WingetProgress
        Test-WingetExit 'winget upgrade --source msstore'
        Write-Banner 'winget upgrade --all --source msstore' '.'
        Invoke-Native winget 'upgrade', '--all', '--include-unknown', '--source', 'msstore',
            '--accept-source-agreements', '--accept-package-agreements',
            '--disable-interactivity' -Skip $WingetProgress
        Test-WingetExit 'winget upgrade --all --source msstore'
    }
    Write-Banner 'Store update scan' '.'
    try {
        Get-CimInstance -Namespace root/cimv2/mdm/dmmap -ClassName MDM_EnterpriseModernAppManagement_AppManagement01 -ErrorAction Stop |
            Invoke-CimMethod -MethodName UpdateScanMethod -ErrorAction Stop |
            Out-Null
        Write-Host 'Store update scan started.  Updates install in the background'
    } catch {
        Write-Fail "Store update scan: $($_.Exception.Message)"
    }
}

# patchwinget
function Update-WingetPackage {
    if (-not (Test-Winget)) { return }
    Write-Banner 'winget upgrade --all' '.'
    Invoke-Native winget 'upgrade', '--all', '--include-unknown', '--accept-source-agreements',
        '--accept-package-agreements', '--disable-interactivity' -Skip $WingetProgress
    Test-WingetExit 'winget upgrade --all'
}

# msert: Microsoft Safety Scanner, a second opinion that doesn't depend on Defender's
# installation. It uses the same engine and signatures, packaged separately, so it
# still works if malware has disabled or damaged Defender. It expires 10 days after
# download, so a fresh copy is downloaded every run (a few hundred MB), its
# Microsoft signature checked before it runs, and deleted afterwards. Detect only
# (/N): it reports, and Defender or you remove. A full scan on Sundays and on the
# weekly run (-FullScan; can take hours), otherwise a quick scan (minutes). msert.exe scans in its own process, so
# unlike Defender it can run at below-normal priority. Runs before mywinvscan so
# the two scans don't compete. Results come from this run's part of
# %SystemRoot%\debug\msert.log, which Safety Scanner adds to each run.
function Start-SafetyScan {
    $full = $FullScan -or (Get-Date).DayOfWeek -eq 'Sunday'
    $why = if ($FullScan) { 'weekly run' } else { 'Sunday' }
    $url = if ([Environment]::Is64BitOperatingSystem) { 'https://go.microsoft.com/fwlink/?LinkId=212732' } else { 'https://go.microsoft.com/fwlink/?LinkId=212733' }
    $dir = Join-Path $env:TEMP "msert-$PID"
    $exe = Join-Path $dir 'msert.exe'
    $log = Join-Path $env:SystemRoot 'debug\msert.log'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        Write-Host 'Downloading Microsoft Safety Scanner'
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            # Windows PowerShell redraws its progress bar for every chunk, which slows downloads
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $exe -TimeoutSec 900 -ErrorAction Stop
        } catch {
            Write-Fail "Safety Scanner download: $($_.Exception.Message)"
            return
        }
        $sig = Get-AuthenticodeSignature -LiteralPath $exe
        $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { 'no signer' }
        if ($sig.Status -ne 'Valid' -or $signer -notmatch 'O=Microsoft Corporation') {
            Write-Fail "the Safety Scanner download isn't validly signed by Microsoft ($($sig.Status), $signer); not run"
            return
        }

        # Safety Scanner adds to its log each run; this run's part is what's new
        $before = [string](Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue)
        $opts = @('/Q', '/N')
        if ($full) { $opts += '/F' }
        Write-Host "Running a $(if ($full) { "full scan ($why; this can take hours)" } else { 'quick scan' }), detect only: msert.exe $($opts -join ' ')"
        try {
            $p = Start-Process -FilePath $exe -ArgumentList $opts -WindowStyle Hidden -PassThru -ErrorAction Stop
        } catch {
            Write-Fail "could not start the Safety Scanner: $($_.Exception.Message)"
            return
        }
        try { $p.PriorityClass = 'BelowNormal' } catch { Write-Verbose 'priority unchanged' }
        $p.WaitForExit()

        $after = [string](Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue)
        $run = if ($before -and $after.StartsWith($before)) { $after.Substring($before.Length) } else { $after }
        $lines = @($run.Trim() -split "`r?`n")
        $lines | ForEach-Object { "  $_" } | Out-Host
        # Results Summary lists each threat as "Found <name>, not removed."; the
        # scan results above it as "Threat Detected: <name>..."
        $found = @($lines | Where-Object { $_ -match '^\s*Found\s' })
        if (-not $found) { $found = @($lines | Where-Object { $_ -match '^\s*Threat Detected' }) }
        if ($found) {
            Write-Fail "Safety Scanner found $($found.Count) threat(s), not removed (detect only); run a Defender scan or remove them: $(($found | ForEach-Object { $_.Trim() }) -join '; ')"
        } elseif ($run -match 'No infection found') {
            Write-Host 'Safety Scanner: no infection found' -ForegroundColor Green
        } else {
            Write-Fail "Safety Scanner results unclear (exit code $($p.ExitCode)); see $log"
        }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# eekscan: Emsisoft Emergency Kit's command-line scanner, a2cmd.exe. A different
# engine from Defender's (Bitdefender's plus Emsisoft's own), so unlike the Safety
# Scanner it's an independent second opinion. Runs only if C:\EEK exists (the kit
# is portable: extract it there). Updates its signatures, then scans detect only
# (no /quarantine or /delete): /full on Saturdays and on the weekly run
# (-FullScan; can take hours), /quick otherwise. Output goes to eek-scan.log in $LogDir, which opens in Notepad at the
# end of the run if anything is found.
# This runs as administrator, but a folder made at the root of C: can be changed
# by the user who made it, so a2cmd.exe must be validly signed by Emsisoft, checked
# before the update and again after it.
# a2cmd's exit codes and summary wording are checked conservatively: a detection
# line, a non-zero "found" count or a non-zero exit code is a failure, and so is
# output with no summary at all.
function Start-EmsisoftScan {
    $eek = Join-Path $env:SystemDrive 'EEK'
    if (-not (Test-Path -LiteralPath $eek)) {
        Write-Skip "$eek not found (Emsisoft Emergency Kit isn't installed)"
        return
    }
    $a2cmd = @('bin64', 'bin32') | ForEach-Object { Join-Path $eek "$_\a2cmd.exe" } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $a2cmd) {
        Write-Fail "a2cmd.exe not found in $eek\bin64 or $eek\bin32"
        return
    }
    $signedByEmsisoft = {
        $s = Get-AuthenticodeSignature -LiteralPath $a2cmd
        $s.Status -eq 'Valid' -and $s.SignerCertificate -and $s.SignerCertificate.Subject -match 'Emsisoft'
    }
    if (-not (& $signedByEmsisoft)) {
        Write-Fail "$a2cmd isn't validly signed by Emsisoft; not run"
        return
    }

    Write-Banner 'a2cmd /update' '.'
    Invoke-Native $a2cmd '/update'
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARN: a2cmd /update exited $LASTEXITCODE; scanning with the signatures it has" -ForegroundColor Yellow
    }
    if (-not (& $signedByEmsisoft)) {
        Write-Fail "$a2cmd isn't validly signed by Emsisoft after the update; not run"
        return
    }

    $full = $FullScan -or (Get-Date).DayOfWeek -eq 'Saturday'
    $why = if ($FullScan) { 'weekly run' } else { 'Saturday' }
    $scan = if ($full) { '/full' } else { '/quick' }
    $log = Join-Path $LogDir 'eek-scan.log'
    Write-Banner "a2cmd $scan$(if ($full) { " ($why; this can take hours)" })" '.'
    # Shown as it runs, and kept for the result check and the log
    $out = @(& $a2cmd $scan 2>&1 | ForEach-Object {
        $line = "$_" -replace "`0", ''
        $line | Out-Host
        $line
    })
    $rc = $LASTEXITCODE
    Set-Content -LiteralPath $log -Value $out -Encoding UTF8

    $detected = @($out | Where-Object { $_ -match '(?i)\bdetected:' })
    $summary = $out | Where-Object { $_ -match '(?i)^\s*found\s*:?\s*\d+\s*$' } | Select-Object -Last 1
    $count = if ($summary -match '(\d+)\s*$') { [int]$Matches[1] } else { -1 }
    if ($detected -or $count -gt 0 -or $rc -ne 0) {
        $what = if ($detected) { ($detected | ForEach-Object { $_.Trim() }) -join '; ' } elseif ($count -gt 0) { "$count found" } else { 'no detections listed' }
        Write-Fail "Emsisoft found malware or failed (exit code $rc; nothing removed, detect only; see $log): $what"
        # Found something: open the log in Notepad at the end of the run
        if ($detected -or $count -gt 0) { $script:EekLog = $log }
    } elseif ($count -eq 0) {
        Write-Host 'Emsisoft Emergency Kit: no malware found' -ForegroundColor Green
    } else {
        Write-Fail "Emsisoft results unclear: no summary in the output (exit code $rc); see $log"
    }
}

# mywinvscan: starts a full Defender scan limited to 50% CPU and returns. The scan
# runs in a hidden PowerShell of its own, so it keeps going after this script ends;
# it can take hours. Its output and MpCmdRun's exit code (0 clean or remediated,
# 2 needs attention) go to defender-scan.log in $LogDir. MsMpEng.exe does the
# scanning and its priority can't be lowered, so the CPU limit is set in Defender's
# preferences. MpCmdRun.exe isn't on PATH, and the current one is in a versioned
# Platform dir.
function Start-DefenderScan {
    $cpu = 50
    $log = Join-Path $LogDir 'defender-scan.log'
    # A second run while the first scan is still going would delete its log and
    # start another full scan on top of it.
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($mp.FullScanInProgress -or $mp.QuickScanInProgress) {
            Write-Host "A Defender scan is already running; this run left it alone and did not replace $log" -ForegroundColor Yellow
            $script:Notes.Add('A Defender scan was already running, so this run did not start another')
            return
        }
    } catch {
        Write-Verbose "scan status unknown: $($_.Exception.Message)"
    }
    $platform = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
    # Newest version first; numbers are padded so 4.18.10 sorts after 4.18.9
    $mpcmd = Get-ChildItem -LiteralPath $platform -Directory -ErrorAction SilentlyContinue |
        Sort-Object { [regex]::Replace($_.Name, '\d+', { param($m) $m.Value.PadLeft(10, '0') }) } -Descending |
        ForEach-Object { Join-Path $_.FullName 'MpCmdRun.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if (-not $mpcmd) { $mpcmd = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe' }
    if (-not (Test-Path -LiteralPath $mpcmd)) {
        Write-Fail 'MpCmdRun.exe not found'
        return
    }

    # By default Defender throttles only scheduled scans. These preferences
    # persist, so scheduled scans get the same limit afterwards.
    Write-Host "Limiting Defender scans to ${cpu}% CPU"
    try {
        Set-MpPreference -ScanAvgCPULoadFactor $cpu -ThrottleForScheduledScanOnly $false -ErrorAction Stop
        Get-MpPreference | Format-List ScanAvgCPULoadFactor, ThrottleForScheduledScanOnly | Out-Host
    } catch {
        Write-Host "WARN: could not set the Defender CPU limit; the scan will not be throttled: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    $opts = @('-Scan', '-ScanType', '2')
    # Ask this scan to follow that limit, on platforms whose MpCmdRun lists the switch
    if ((& $mpcmd -h 2>&1 | Out-String) -match 'CpuThrottling') { $opts += '-CpuThrottling' }

    # The hidden PowerShell runs MpCmdRun, logs its output, then appends the exit
    # code. Encoded, so there is no quoting to survive Windows command-line parsing.
    $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
    $command = "& $(& $q $mpcmd) $($opts -join ' ') 2>&1 | Out-File -Encoding ascii -FilePath $(& $q $log)`n" +
        "Add-Content -Encoding ascii -Path $(& $q $log) -Value `"MpCmdRun exit code: `$LASTEXITCODE (0 = clean or remediated)`""
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    Write-Host "Starting $mpcmd $($opts -join ' ')"
    try {
        Start-Process -WindowStyle Hidden -ErrorAction Stop `
            -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
            -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded
    } catch {
        Write-Fail "could not start the Defender scan: $($_.Exception.Message)"
        return
    }
    Write-Host 'Defender full scan started in the background. When it finishes, the exit code is'
    Write-Host "at the end of $log; non-zero means check Windows Security > Protection history."
    Write-Host "Cancel it with: & '$mpcmd' -Scan -Cancel"
}

# winhealthcheck: checks the Windows component store and system files, and reports
# what to run next. Output is collected, so nothing shows until each step finishes.
# Summary matching is English-only.
function Test-WindowsHealth {
    $cmds = @(
        , @('dism.exe', '/Online', '/Cleanup-Image', '/ScanHealth')
        , @('sfc.exe', '/scannow')
        , @('dism.exe', '/Online', '/Cleanup-Image', '/AnalyzeComponentStore')
    )
    # Blank lines, and the progress bars and "N% complete" lines that \r redraws
    $progress = '^\s*$|^\s*\[[= ]*[0-9.]+%[= ]*\]\s*$|[0-9]+% complete\.?\s*$'
    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $cmds) {
        $exe, $rest = $c
        $line = $c -join ' '
        Write-Banner $line '.'
        Write-Host 'Running; this can take 10-30 minutes...'
        # sfc writes UTF-16 when its output is redirected
        $saved = [Console]::OutputEncoding
        if ($exe -eq 'sfc.exe') {
            try { [Console]::OutputEncoding = [Text.Encoding]::Unicode } catch { Write-Verbose 'no console' }
        }
        try {
            $out = @(& $exe @rest 2>&1 |
                ForEach-Object { "$_" -replace "`0", '' } |
                Where-Object { $_ -notmatch $progress })
            $rc = $LASTEXITCODE
        } finally {
            try { [Console]::OutputEncoding = $saved } catch { Write-Verbose 'no console' }
        }
        $out | Out-Host
        $text = $out -join "`n"
        if ($rc -ne 0) { $found.Add("$line exited $rc") }
        if ($text -like '*component store is repairable*') {
            $found.Add('Component store is corrupt but repairable: run DISM /Online /Cleanup-Image /RestoreHealth, then sfc /scannow')
        } elseif ($text -like '*component store is not repairable*') {
            $found.Add('Component store is NOT repairable: an in-place Windows repair install is needed')
        } elseif ($text -like '*unable to fix some of them*') {
            $found.Add('sfc could not fix some files: run DISM /Online /Cleanup-Image /RestoreHealth, then sfc /scannow again; details in C:\Windows\Logs\CBS\CBS.log')
        } elseif ($text -like '*successfully repaired them*') {
            $found.Add('sfc found and repaired corrupt files; details in C:\Windows\Logs\CBS\CBS.log')
        } elseif ($text -like '*could not perform the requested operation*') {
            $found.Add('sfc could not run; try again after a reboot')
        } elseif ($text -like '*Cleanup Recommended : Yes*') {
            $found.Add('Component store cleanup recommended: run DISM /Online /Cleanup-Image /StartComponentCleanup')
        }
    }
    Write-Banner 'Windows health summary' '.'
    if ($found.Count -eq 0) {
        Write-Host 'No problems found'
    } else {
        foreach ($f in $found) {
            Write-Host $f
            $script:Notes.Add("${script:Step}: $f")
        }
    }
}

# windiskcheck: online NTFS check of the system drive (chkdsk /scan): finds problems
# while Windows runs and queues fixes it can't make online. Exit codes, per
# Microsoft's chkdsk docs: 0 none found, 1 found and fixed, 2 cleanup done or
# needed, 3 not fixed
function Test-SystemDisk {
    $drive = $env:SystemDrive
    # chkdsk redraws a "Progress: ... done; Stage: ..." line, one line each once redirected
    Invoke-Native chkdsk.exe $drive, '/scan' -Skip '^\s*Progress: '
    $rc = $LASTEXITCODE
    switch ($rc) {
        0 { Write-Host "chkdsk: no problems found on $drive" }
        1 { Write-Host "chkdsk: problems found on $drive and fixed" }
        2 { Write-Host "chkdsk: only housekeeping on $drive (cleanup done, or left for a /f run)" }
        default {
            Write-Fail "chkdsk exited ${rc}: $drive could not be checked, or problems were not fixed."
            Write-Host "      Run chkdsk $drive /spotfix and answer Y to fix them at the next restart"
        }
    }
}

# mywinprocsigs: running programs without a valid Authenticode signature
function Find-UnsignedProcess {
    Write-Banner 'Processes W/O Valid Authenticode Signature' '.'
    # Listed for review. Many legitimate programs are unsigned, so this is a note
    # in the summary rather than a failure. Renamed or relocated Windows programs
    # are the failure, in Find-LolbasCopy.
    $unsigned = @(Get-Process | Where-Object Path | ForEach-Object Path | Sort-Object -Unique |
        ForEach-Object {
            $s = Get-AuthenticodeSignature -LiteralPath $_ -ErrorAction SilentlyContinue
            if ($s -and $s.Status -ne 'Valid') { '{0,-14} {1}' -f $s.Status, $_ }
        })
    $unsigned
    if ($unsigned.Count) {
        $script:Notes.Add("${script:Step}: $($unsigned.Count) running programs have no valid Authenticode signature (listed above)")
    }
}

# The LOLBAS list (lolbas-project.github.io) of Windows programs attackers misuse,
# such as certutil and mshta. Downloaded once per run; $null if it can't be.
$script:LolbasList = $null
$script:LolbasError = ''
function Get-LolbasList {
    if ($null -eq $script:LolbasList -and -not $script:LolbasError) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            # Windows PowerShell redraws its progress bar for every chunk, which slows downloads
            $ProgressPreference = 'SilentlyContinue'
            $script:LolbasList = @((Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop -Uri https://lolbas-project.github.io/api/lolbas.json).Content | ConvertFrom-Json)
        } catch {
            $script:LolbasError = $_.Exception.Message
        }
    }
    $script:LolbasList
}

# mywinprocsigs, second part: a copy of a LOLBAS program is still validly signed by
# Microsoft, so Find-UnsignedProcess passes it. Alerts on a running one that was
# renamed, or that runs from outside its usual folders.
function Find-LolbasCopy {
    Write-Banner 'Windows Programs Renamed or Outside Their Usual Folders' '.'
    $ErrorActionPreference = 'SilentlyContinue'
    $list = Get-LolbasList
    if (-not $list) {
        "NOTE=`"Not checked: LOLBAS list not downloaded ($script:LolbasError)`""
        return
    }
    # Usual folders as wildcards: <version>, <username> and version-numbered
    # folders (Defender Platform\4.18.x-0) can be anything, and so can the drive
    $where = @{}
    foreach ($e in $list) {
        $n = "$($e.Name)".ToLower()
        if (-not $where.ContainsKey($n)) { $where[$n] = @() }
        foreach ($f in @($e.Full_Path)) {
            $p = "$($f.Path)"
            if ($p -notmatch '^[A-Za-z]:\\') { continue }
            $p = ($p -replace '<[^>]*>', '*') -replace '\\\d+(\.\d+)+[^\\]*\\', '\*\'
            $where[$n] += '?' + $p.Substring(1)
        }
    }
    # LOLBAS does not list every place Windows and Office keep these programs,
    # so folders only an administrator can write to are accepted too
    $trusted = "$env:SystemRoot\System32\*", "$env:SystemRoot\SysWOW64\*", "$env:SystemRoot\WinSxS\*",
        "$env:SystemRoot\Microsoft.NET\*", "$env:SystemRoot\SystemApps\*", "$env:ProgramFiles\*", "${env:ProgramFiles(x86)}\*"
    $writable = '\\(Temp|Tasks|Tracing|Debug|spool)\\'

    $found = 0
    foreach ($p in (Get-Process | Where-Object Path | ForEach-Object Path | Sort-Object -Unique)) {
        $leaf = (Split-Path -Leaf $p).ToLower()
        # The name it was built with; Windows programs give e.g. CertUtil.exe.MUI
        $orig = "$((Get-Item -LiteralPath $p).VersionInfo.OriginalFilename)".Trim().ToLower() -replace '\.mui$', ''
        if ($where.ContainsKey($orig)) { $name = $orig } elseif ($where.ContainsKey($leaf)) { $name = $leaf } else { continue }
        # Same-named programs from other publishers (e.g. Discord Update.exe) are not the LOLBAS one
        $s = Get-AuthenticodeSignature -LiteralPath $p
        if ($s.Status -ne 'Valid' -or $s.SignerCertificate.GetNameInfo('SimpleName', $false) -notlike 'Microsoft*') { continue }
        if ($name -ne $leaf) {
            "ALERT=`"Renamed Windows program=$p is $name`""
            $found += 1
            continue
        }
        if ($where[$name] | Where-Object { $p -like $_ }) { continue }
        if ((Split-Path -Parent $p) -eq $env:SystemRoot) { continue }
        if (($trusted | Where-Object { $p -like $_ }) -and $p -notmatch $writable) { continue }
        "ALERT=`"Windows program=$name running from $p, outside its usual folders`""
        $found += 1
    }

    if ($found) {
        "Found $found renamed or relocated Windows programs"
        Write-Fail "Found $found renamed or relocated Windows programs; see the ALERT lines above"
    } else {
        "No renamed or relocated Windows programs running ($($where.Count) LOLBAS programs checked)"
    }
}

# winstartupcheck: startup entries that run LOLBAS programs. Malware that survives a
# reboot has to start from somewhere, so this looks at scheduled tasks, Run keys,
# Startup folders, services, Winlogon and WMI subscriptions. It also checks every
# shortcut on Desktops, in Start menus and pinned to the taskbar, since .lnk
# malware disguises itself as a document or hijacks an existing shortcut.
#   ALERT: the command shows a sign of misuse (a URL, javascript:, a scriptlet,
#     encoded PowerShell, a temp or public folder...), or Winlogon or WMI is set to
#     run something it normally does not, or a shortcut pads its arguments out of
#     sight or runs a program from a temp or public folder.
#   NOTE: a LOLBAS program started by a Run key, Startup folder, WMI subscription,
#     a scheduled task outside \Microsoft\ or a shortcut with arguments, for
#     review. Windows' own tasks and services use these programs all the time, so
#     they are only alerted on.
function Test-StartupEntry {
    Write-Banner 'Startup Entries Running LOLBAS Programs' '.'
    $ErrorActionPreference = 'SilentlyContinue'
    $count = @{ found = 0; noted = 0 }
    function Alert([string]$m) { "ALERT=`"$m`""; $count.found += 1 }
    function Note([string]$m) { "NOTE=`"$m`""; $count.noted += 1 }

    $names = @{}
    $list = Get-LolbasList
    if ($list) {
        foreach ($e in $list) { $names["$($e.Name)".ToLower()] = 1 }
        # LOLBAS leaves out PowerShell, the most common of all
        foreach ($n in 'powershell.exe', 'pwsh.exe') { $names[$n] = 1 }
    } else {
        Note "LOLBAS list not downloaded ($script:LolbasError), so only Winlogon and WMI are checked"
    }

    # Signs of misuse in a command line
    $signs = [ordered]@{
        'a URL' = '(?i)\b(https?|ftps?)://'
        'a network share' = '\\\\\w[\w.-]*\\'
        'script in a URL' = '(?i)\b(javascript|vbscript):'
        'a scriptlet or HTML application' = '(?i)\bscrobj\b|\.(sct|hta)\b'
        'certutil download or decode options' = '(?i)[-/](urlcache|verifyctl|decodehex|decode|encode)\b'
        'encoded or downloaded PowerShell' = '(?i)\s[-/](e|ec|en|enc\w*)\s|frombase64string|downloadstring|downloadfile|invoke-expression|\biex\b|net\.webclient'
        'a temporary or public folder' = '(?i)\\(users\\public|appdata\\local\\temp|windows\\temp)\\|%te?mp%'
        'a memory dump' = '(?i)minidump'
        'a BITS transfer' = '(?i)[-/](transfer|addfile)\b'
    }

    # LOLBAS programs a command runs: any word naming one (C:\...\certutil.exe,
    # mshta.exe), or a bare name (rundll32) that starts the command or follows
    # cmd /c, /k or start
    function Hits([string]$cmd) {
        $found = @{}
        $words = @($cmd -split "[\s`",;']+" | Where-Object { $_ })
        for ($i = 0; $i -lt $words.Count; $i++) {
            $w = ($words[$i] -split '[\\/]')[-1].ToLower()
            if ($names.ContainsKey($w)) {
                $found[$w] = 1
            } elseif (($i -eq 0 -or $words[$i - 1] -in '/c', '/k', 'start') -and $names.ContainsKey("$w.exe")) {
                $found["$w.exe"] = 1
            }
        }
        @($found.Keys | Sort-Object)
    }

    # $quiet: only alert, never note (Windows tasks and services)
    function Check([string]$src, [string]$cmd, [bool]$quiet) {
        $cmd = [Environment]::ExpandEnvironmentVariables($cmd).Trim()
        if (-not $cmd) { return }
        $bins = Hits $cmd
        if (-not $bins) { return }
        $why = @($signs.Keys | Where-Object { $cmd -match $signs[$_] })
        if ($why) {
            Alert "$src runs $($bins -join '+') with $($why -join ', '): $cmd"
        } elseif (-not $quiet) {
            Note "$src runs $($bins -join '+'): $cmd"
        }
    }

    # Scheduled tasks
    foreach ($t in Get-ScheduledTask) {
        foreach ($a in @($t.Actions)) {
            if ($a.Execute) { Check "Task $($t.TaskPath)$($t.TaskName)" "$($a.Execute) $($a.Arguments)" ($t.TaskPath -like '\Microsoft\*') }
        }
    }

    # Run keys, for the machine and every loaded user
    $keys = @()
    $roots = @('HKLM:\Software', 'HKLM:\Software\WOW6432Node') +
        @(Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -notlike '*_Classes' } | ForEach-Object { "Registry::$($_.Name)\Software" })
    foreach ($r in $roots) {
        $keys += "$r\Microsoft\Windows\CurrentVersion\Run", "$r\Microsoft\Windows\CurrentVersion\RunOnce", "$r\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"
    }
    foreach ($k in $keys) {
        $item = Get-Item -LiteralPath $k
        if (-not $item) { continue }
        foreach ($v in $item.GetValueNames()) {
            if ($v) { Check "Run key $k\$v" "$($item.GetValue($v))" $false }
        }
    }

    # Startup folders: shortcuts are checked like commands; anything else is noted
    $sh = New-Object -ComObject WScript.Shell
    $dirs = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp") +
        @(Get-ChildItem "$env:SystemDrive\Users" -Directory | ForEach-Object { "$($_.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" })
    foreach ($d in $dirs) {
        foreach ($f in Get-ChildItem -LiteralPath $d -File -Force) {
            if ($f.Name -eq 'desktop.ini') { continue }
            if ($f.Extension -eq '.lnk') {
                $l = $sh.CreateShortcut($f.FullName)
                Check "Startup shortcut $($f.FullName)" "`"$($l.TargetPath)`" $($l.Arguments)" $false
            } else {
                Note "Startup folder file $($f.FullName)"
            }
        }
    }

    # Every other shortcut: Desktops (including OneDrive's), Start menus and taskbar
    # pins. Malware arrives as a shortcut disguised as a document, or edits an
    # existing shortcut to run itself first. A shortcut that runs a LOLBAS program
    # with no arguments (Command Prompt, PowerShell) is normal, so only alerts.
    $places = @("$env:PUBLIC\Desktop", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs") +
        @(Get-ChildItem "$env:SystemDrive\Users" -Directory | ForEach-Object {
            "$($_.FullName)\Desktop"
            "$($_.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
            "$($_.FullName)\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch"
            Get-ChildItem -LiteralPath $_.FullName -Directory -Filter 'OneDrive*' | ForEach-Object { "$($_.FullName)\Desktop" }
        })
    $shortcuts = 0
    # Sorted unique: the Public Desktop is also C:\Users\Public\Desktop
    foreach ($f in Get-ChildItem -LiteralPath $places -Recurse -File -Force -Filter *.lnk | Sort-Object FullName -Unique) {
        # Startup folders were checked above
        if ($f.DirectoryName -match '\\Start Menu\\Programs\\Startup$') { continue }
        $l = $sh.CreateShortcut($f.FullName)
        if (-not $l) { continue }
        $shortcuts += 1
        $target = [Environment]::ExpandEnvironmentVariables($l.TargetPath)
        $sargs = "$($l.Arguments)"
        if ($sargs -match '\s{20,}|[\r\n]') {
            # Padding pushes the real command out of sight in the Properties dialog
            Alert "Shortcut $($f.FullName) hides its arguments behind padding: `"$target`" $($sargs -replace '\s+', ' ')"
        } elseif ($target -match $signs['a temporary or public folder']) {
            Alert "Shortcut $($f.FullName) runs a program in a temporary or public folder: `"$target`" $sargs"
        } else {
            Check "Shortcut $($f.FullName)" "`"$target`" $sargs" (-not $sargs.Trim())
        }
    }

    # Services
    foreach ($s in Get-CimInstance Win32_Service) {
        if ($s.PathName) { Check "Service $($s.Name)" $s.PathName $true }
    }

    # Winlogon starts the shell and Userinit at every logon
    $wl = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
    if ($wl.Shell -and $wl.Shell -notmatch '^\s*explorer\.exe\s*$') { Alert "Winlogon Shell is $($wl.Shell), not explorer.exe" }
    if ($wl.Userinit -and $wl.Userinit -notmatch '^\s*([a-z]:\\windows\\system32\\)?userinit\.exe\s*,?\s*$') {
        Alert "Winlogon Userinit is $($wl.Userinit), not userinit.exe"
    }

    # WMI subscriptions run a command or script whenever an event fires
    foreach ($w in Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer) {
        $cmd = "$($w.ExecutablePath) $($w.CommandLineTemplate)"
        if (Hits $cmd) { Check "WMI subscription $($w.Name)" $cmd $false } else { Note "WMI subscription $($w.Name) runs: $cmd" }
    }
    foreach ($w in Get-CimInstance -Namespace root\subscription -ClassName ActiveScriptEventConsumer) {
        Alert "WMI subscription $($w.Name) runs a $($w.ScriptingEngine) script"
    }

    if ($count.found) {
        "Found $($count.found) startup entries or shortcuts with signs of misuse, and $($count.noted) to review ($shortcuts shortcuts checked)"
        Write-Fail "Found $($count.found) startup entries or shortcuts with signs of misuse; see the ALERT lines above"
    } elseif ($count.noted) {
        "No startup entries or shortcuts show signs of misuse; $($count.noted) listed above to review ($shortcuts shortcuts checked)"
    } else {
        "No startup entries or shortcuts run LOLBAS programs ($shortcuts shortcuts checked)"
    }
}

# winmodcheck: like modpkgcheck, but Windows drivers come with signatures, not
# packages. Alerts on loaded drivers without a valid signature, on settings that let
# unsigned or blocklisted drivers load, and on drivers in the loldrivers.io list of
# known vulnerable or malicious drivers (a ~35 MB download; if it fails, the rest of
# the check still runs). Drivers signed by someone other than Windows itself are
# listed for review.
function Test-DriverSignature {
    Write-Banner 'Windows Driver Signature Check' '.'
    $ErrorActionPreference = 'SilentlyContinue'
    $count = @{ found = 0; third = 0 }
    function Alert([string]$m) { "ALERT=`"$m`""; $count.found += 1 }
    function Note([string]$m) { "NOTE=`"$m`"" }
    # Kernel paths look like \SystemRoot\..., \??\C:\..., \Windows\..., or System32\...
    function Norm([string]$p) {
        $p = $p.Trim([char]34)
        if ($p -match '^\\SystemRoot\\') { return $env:SystemRoot + $p.Substring(11) }
        if ($p.StartsWith('\??\')) { return $p.Substring(4) }
        if ($p -match '^\\') { return $env:SystemDrive + $p }
        if ($p -notmatch '^[A-Za-z]:\\') { return $env:SystemRoot + '\' + $p }
        return $p
    }

    # Settings that let unsigned or blocklisted drivers load
    $bcd = bcdedit /enum '{current}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Note 'Boot options not checked: bcdedit failed'
    } else {
        foreach ($o in 'testsigning', 'nointegritychecks', 'debug') {
            if ($bcd -match "^$o\s+Yes") { Alert "Boot option $o is on" }
        }
    }
    try {
        if (-not (Confirm-SecureBootUEFI -ErrorAction Stop)) { Alert 'Secure Boot is off' }
    } catch {
        Note "Secure Boot not checked: $($_.Exception.Message)"
    }
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard
    if ($dg -and $dg.SecurityServicesRunning -notcontains 2) {
        if ($dg.SecurityServicesConfigured -contains 2) {
            Alert 'Memory Integrity (HVCI) is configured but not running'
        } else {
            Note 'Memory Integrity (HVCI) is off'
        }
    }
    $bl = (Get-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config).VulnerableDriverBlocklistEnable
    if ($bl -eq 0) { Alert 'Microsoft vulnerable driver blocklist is off' }

    # Every loaded kernel image (including ntoskrnl.exe and hal.dll), plus running driver services
    $paths = @{}
    try {
        # Added once per session; a second Add-Type of the same type fails
        if (-not ('WinModCheck.Psapi' -as [type])) {
            Add-Type -Namespace WinModCheck -Name Psapi -MemberDefinition '
                [DllImport("psapi.dll")] public static extern bool EnumDeviceDrivers(IntPtr[] bases, int cb, out int needed);
                [DllImport("psapi.dll", CharSet = CharSet.Unicode)] public static extern int GetDeviceDriverFileNameW(IntPtr b, System.Text.StringBuilder name, int size);'
        }
        $need = 0
        [void][WinModCheck.Psapi]::EnumDeviceDrivers($null, 0, [ref]$need)
        $bases = New-Object IntPtr[] ($need / [IntPtr]::Size)
        if ([WinModCheck.Psapi]::EnumDeviceDrivers($bases, $need, [ref]$need)) {
            foreach ($b in $bases) {
                $sb = New-Object System.Text.StringBuilder 1024
                if ([WinModCheck.Psapi]::GetDeviceDriverFileNameW($b, $sb, 1024) -gt 0) { $paths[(Norm $sb.ToString())] = 1 }
            }
        }
    } catch {
        Write-Verbose "EnumDeviceDrivers failed: $($_.Exception.Message)"
    }
    if ($paths.Count -eq 0) { Note 'EnumDeviceDrivers gave no names, so only driver services are checked' }
    Get-CimInstance Win32_SystemDriver | Where-Object { $_.State -eq 'Running' -and $_.PathName } |
        ForEach-Object { $paths[(Norm $_.PathName)] = 1 }

    # SHA-256 of every sample in the loldrivers.io list
    $lol = @{}
    $why = 'no hashes in it'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # Windows PowerShell redraws its progress bar for every chunk, which makes a
        # download this size many times slower
        $ProgressPreference = 'SilentlyContinue'
        $json = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop -Uri https://www.loldrivers.io/api/drivers.json).Content
        foreach ($m in [regex]::Matches($json, '"SHA256"\s*:\s*"([0-9A-Fa-f]{64})"')) { $lol[$m.Groups[1].Value] = 1 }
    } catch {
        $why = $_.Exception.Message
    }
    if ($lol.Count -eq 0) {
        Note "Known vulnerable drivers not checked: loldrivers.io list not downloaded ($why)"
    } else {
        Note "Checking against $($lol.Count) loldrivers.io hashes"
    }

    foreach ($p in ($paths.Keys | Sort-Object)) {
        # Crash dump and hibernation copies of storage drivers (dump_x.sys,
        # hiber_x.sys) only exist in memory, so check the driver they copy
        if ((Split-Path -Leaf $p) -match '^(dump|hiber)_(.+)$') {
            $orig = (Split-Path -Parent $p) + '\' + $Matches[2]
            if ($paths.ContainsKey($orig)) { continue }
            if (Test-Path -LiteralPath $orig) { $p = $orig }
        }
        if (-not (Test-Path -LiteralPath $p)) { Alert "No file for driver=$p"; continue }
        if ($lol.Count -and $lol.ContainsKey((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash)) {
            Alert "Known vulnerable driver=$p (loldrivers.io)"
        }
        $s = Get-AuthenticodeSignature -LiteralPath $p
        if ($s.Status -ne 'Valid') { Alert "Bad signature for driver=$p status=$($s.Status)"; continue }
        # Third-party drivers are often signed by Microsoft too, as its Hardware Compatibility Publisher
        $signer = $s.SignerCertificate.GetNameInfo('SimpleName', $false)
        if ($signer -in 'Microsoft Windows', 'Microsoft Windows Publisher', 'Microsoft Corporation') { continue }
        $count.third += 1
        Note "Third-party driver=$p signer=$signer company=$("$((Get-Item -LiteralPath $p).VersionInfo.CompanyName)".Trim())"
    }

    if ($count.found) {
        "Found $($count.found) driver problems"
        Write-Fail "Found $($count.found) driver problems; see the ALERT lines above"
    } elseif ($count.third) {
        "No driver problems found, and $($count.third) third-party drivers are validly signed"
    } else {
        'No driver problems found, and every loaded driver is signed by Windows'
    }
}

# ---------------------------------------------------------------
# Restore point, removals, and checks that only report
# ---------------------------------------------------------------

# One restore point before the hardening steps. Windows refuses a second point
# within 24 hours (SystemRestorePointCreationFrequency, left at its default);
# that refusal is a note, not a failure. Anything else is a failure, and the
# run continues either way.
function New-DailyRestorePoint {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Creating a System Restore Point' '.'

    try {
        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction Stop
    } catch {
        Write-Fail "[Restore point] Couldn't turn on System Restore for ${env:SystemDrive}: $($_.Exception.Message)"
        return
    }

    $desc = "dailyrunme $runStamp"
    $warn = @()
    $created = $false
    try {
        Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS `
            -WarningVariable warn -WarningAction Continue -ErrorAction Stop
        $created = $true
    } catch {
        $warn += "$_"
    }
    $warnText = (@($warn) | ForEach-Object { "$_" }) -join ' '
    $mine = @()
    try {
        $mine = @(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { $_.Description -eq $desc })
    } catch {
        $mine = @()
    }
    if ($mine.Count -gt 0 -or ($created -and $warnText -notmatch 'already been created|1440 minutes')) {
        Write-Host "  [Restore point] Created: $desc" -ForegroundColor Green
        return
    }
    if ($warnText -match 'already been created|1440 minutes') {
        Write-Host '  [Restore point] Windows skipped it: a restore point was created in the last 24 hours' -ForegroundColor Yellow
        $note = 'A restore point was already created in the last 24 hours, so this run did not create another'
        if (-not $script:Notes.Contains($note)) { $script:Notes.Add($note) }
        return
    }
    $why = if ($warnText) { $warnText } else { 'Checkpoint-Computer did not create it' }
    Write-Fail "[Restore point] Couldn't create one: $why"
}

# Quick Assist is the program tech-support scams talk people into opening.
# Remove the installed app, the copy Windows would reinstall for a new user,
# and the Windows capability. If it was here, removing it is a failure so a
# return (Windows Update puts it back) shows up the next day too.
function Remove-QuickAssist {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Removing Quick Assist' '.'

    $removed = [System.Collections.Generic.List[string]]::new()
    $found = $false
    $listFailed = $false
    # -AllUsers lists the same package once per user. Remove each full name once.
    $seenPkg = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $packages = @()
    try {
        $packages = @(Get-AppxPackage -AllUsers -Name '*QuickAssist*' -ErrorAction Stop)
    } catch {
        $listFailed = $true
        Write-Fail "[Quick Assist] Couldn't list installed apps: $($_.Exception.Message)"
    }
    foreach ($pkg in $packages) {
        if (-not $pkg.PackageFullName -or -not $seenPkg.Add($pkg.PackageFullName)) { continue }
        $found = $true
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            $removed.Add($pkg.Name)
        } catch {
            # -AllUsers is missing on older Windows; remove it for this user instead
            if ("$_" -match 'AllUsers') {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                    $removed.Add("$($pkg.Name) (this user)")
                } catch {
                    Write-Fail "[Quick Assist] Couldn't remove $($pkg.Name): $($_.Exception.Message)"
                }
            } else {
                Write-Fail "[Quick Assist] Couldn't remove $($pkg.Name): $($_.Exception.Message)"
            }
        }
    }

    $provisioned = @()
    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object {
            $display = ''
            $full = ''
            if ($_.PSObject.Properties['DisplayName']) { $display = "$($_.DisplayName)" }
            if ($_.PSObject.Properties['PackageName']) { $full = "$($_.PackageName)" }
            $display -match 'QuickAssist' -or $full -match 'QuickAssist'
        })
    } catch {
        $listFailed = $true
        Write-Fail "[Quick Assist] Couldn't list provisioned apps: $($_.Exception.Message)"
    }
    foreach ($pkg in $provisioned) {
        $found = $true
        $full = ''
        if ($pkg.PSObject.Properties['PackageName']) { $full = "$($pkg.PackageName)" }
        $label = if ($pkg.PSObject.Properties['DisplayName'] -and $pkg.DisplayName) { "$($pkg.DisplayName)" } else { $full }
        if (-not $full) {
            Write-Fail "[Quick Assist] Couldn't remove provisioned $label (no package name)"
            continue
        }
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $full -ErrorAction Stop | Out-Null
            $removed.Add("provisioned $label")
        } catch {
            Write-Fail "[Quick Assist] Couldn't remove provisioned ${label}: $($_.Exception.Message)"
        }
    }

    $caps = @()
    try {
        $caps = @(Get-WindowsCapability -Online -Name 'App.Support.QuickAssist*' -ErrorAction Stop |
            Where-Object { "$($_.State)" -ne 'NotPresent' })
    } catch {
        $listFailed = $true
        Write-Fail "[Quick Assist] Couldn't list the Quick Assist Windows capability: $($_.Exception.Message)"
    }
    foreach ($cap in $caps) {
        $found = $true
        try {
            $result = Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop
            $removed.Add($cap.Name)
            if ($result.RestartNeeded) {
                Add-RestartReason 'Removing Quick Assist finishes at the next restart'
            }
        } catch {
            Write-Fail "[Quick Assist] Couldn't remove $($cap.Name): $($_.Exception.Message)"
        }
    }

    if ($removed.Count -gt 0) {
        Write-Fail "[Quick Assist] Was installed ($($removed -join ', ')); removed it. Windows Update sometimes puts it back, which the next run will catch"
    } elseif (-not $found -and -not $listFailed) {
        Write-Host '  [Quick Assist] Not installed' -ForegroundColor Green
    }
}

# The SMB1Protocol Windows feature, not the Computer Browser service (that one
# is in cis-services). -NoRestart: this script never restarts the PC. A removal
# that is waiting on a restart keeps saying so until the PC is restarted.
function Remove-SmbV1 {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Removing SMBv1' '.'

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction Stop
    } catch {
        Write-Fail "[SMB1] Couldn't check the SMB1Protocol feature: $($_.Exception.Message)"
        return
    }
    $state = "$($feature.State)"
    if ($state -eq 'Disabled') {
        Write-Host '  [SMB1] SMB1Protocol is not enabled' -ForegroundColor Green
        return
    }
    if ($state -eq 'DisablePending') {
        Write-Host '  [SMB1] SMB1Protocol removal finishes at the next restart' -ForegroundColor Yellow
        Add-RestartReason 'Removing SMBv1 finishes at the next restart'
        return
    }
    try {
        $result = Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction Stop
    } catch {
        Write-Fail "[SMB1] Couldn't turn off SMB1Protocol (${state}): $($_.Exception.Message)"
        return
    }
    if ($result.RestartNeeded) {
        Add-RestartReason 'Removing SMBv1 finishes at the next restart'
    }
    $pending = if ($result.RestartNeeded) { ' It finishes at the next restart.' } else { '' }
    Write-Fail "[SMB1] SMB1Protocol was $state and has been turned off.$pending"
}

# A profile that is off makes every firewall rule, including the LOLBin rules
# in the next step, do nothing. Turn it back on and fail, so the fact that it
# was off stays visible. Runs before lnkprotect.
function Enable-FirewallProfile {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Checking Windows Firewall' '.'

    try {
        $profiles = @(Get-NetFirewallProfile -ErrorAction Stop)
    } catch {
        Write-Fail "[Firewall] Couldn't read the firewall profiles: $($_.Exception.Message)"
        return
    }
    $off = @($profiles | Where-Object { -not $_.Enabled })
    if ($off.Count -eq 0) {
        Write-Host "  [Firewall] On for $(($profiles.Name) -join ', ')" -ForegroundColor Green
        return
    }
    foreach ($p in $off) {
        try {
            Set-NetFirewallProfile -Name $p.Name -Enabled True -ErrorAction Stop
            Write-Fail "[Firewall] The $($p.Name) profile was off; turned it back on"
        } catch {
            Write-Fail "[Firewall] The $($p.Name) profile is off and couldn't be turned on: $($_.Exception.Message)"
        }
    }
}

# AutoPlay runs whatever a USB stick or a CD offers. Off for the whole PC
# (NoDriveTypeAutoRun = 0xFF is every drive type, NoAutorun stops the old
# dialog) and for each user (DisableAutoplay). A change is a failure so it
# is visible; the values are in the registry undo file.
function Disable-AutoPlay {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Turning Off AutoPlay' '.'

    $turnedOff = [System.Collections.Generic.List[string]]::new()
    $policy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $drive = Get-RegistryValueState -Path $policy -Name 'NoDriveTypeAutoRun'
    $autorun = Get-RegistryValueState -Path $policy -Name 'NoAutorun'
    $driveOff = ($null -ne $drive -and $drive.Kind -eq 'DWord' -and [int]$drive.Data -eq 255)
    $autorunOff = ($null -ne $autorun -and $autorun.Kind -eq 'DWord' -and [int]$autorun.Data -eq 1)
    if (-not $driveOff -or -not $autorunOff) { $turnedOff.Add('this PC') }
    Set-TrackedValue -Path $policy -Name 'NoDriveTypeAutoRun' -Value 0xFF
    Set-TrackedValue -Path $policy -Name 'NoAutorun' -Value 1

    # $turnedOff is this function's list; the scriptblock below adds to it
    Invoke-InEachUserHive {
        param($root, $label)
        try {
            $key = "$root\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"
            $now = Get-RegistryValueState -Path $key -Name 'DisableAutoplay'
            $off = ($null -ne $now -and $now.Kind -eq 'DWord' -and [int]$now.Data -eq 1)
            if (-not $off) { $turnedOff.Add($label) }
            Set-TrackedValue -Path $key -Name 'DisableAutoplay' -Value 1
        } catch {
            Write-Fail "[AutoPlay] ${label}: couldn't turn AutoPlay off: $($_.Exception.Message)"
        }
    }
    if ($turnedOff.Count -gt 0) {
        Write-Fail "[AutoPlay] Was on for $($turnedOff -join ', '); turned off"
    } else {
        Write-Host '  [AutoPlay] Already off' -ForegroundColor Green
    }
}

# A trailing slash is ignored, except on a drive root (C:\) or a UNC share
# root (\\server\share\). Comparison is case-insensitive.
function ConvertTo-NormalizedDefenderPath {
    param([string]$Value)
    $p = "$Value".Trim()
    if (-not $p) { return '' }
    if ($p -match '^[A-Za-z]:\\$') { return $p.ToLowerInvariant() }
    if ($p -match '^\\\\[^\\]+\\[^\\]+\\$') { return $p.ToLowerInvariant() }
    return $p.TrimEnd('\', '/').ToLowerInvariant()
}

function ConvertTo-NormalizedDefenderItem {
    param(
        [string]$Value,
        [ValidateSet('path', 'extension')][string]$Kind
    )
    if ($Kind -eq 'extension') {
        return "$Value".Trim().ToLowerInvariant().TrimStart('.')
    }
    $p = "$Value".Trim()
    if ($p -match '[\\/]') { return (ConvertTo-NormalizedDefenderPath $p) }
    return $p.ToLowerInvariant()
}

# $null stays an empty list. A single value must not be wrapped before that
# test: @($null) is a one-element list in Windows PowerShell 5.1.
function Get-DefenderPreferenceList {
    param(
        $Preference,
        [Parameter(Mandatory)][string]$Name
    )
    $prop = $Preference.PSObject.Properties[$Name]
    if (-not $prop -or $null -eq $prop.Value) { return @() }
    return @($prop.Value)
}

# Fail on any exclusion Defender has that the lists at the top don't name.
# Does not remove them: an exclusion can be a program the PC needs, and the
# failure is what makes it get added to the list, or deleted, on purpose.
function Test-DefenderExclusion {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Checking Defender Exclusions' '.'

    try {
        $pref = Get-MpPreference -ErrorAction Stop
    } catch {
        Write-Fail "[Defender] Couldn't read exclusions: $($_.Exception.Message)"
        return
    }
    $checks = @(
        @{ Label = 'path'; Property = 'ExclusionPath'; Approved = @($ApprovedDefenderExclusions.Path); Kind = 'path' }
        @{ Label = 'process'; Property = 'ExclusionProcess'; Approved = @($ApprovedDefenderExclusions.Process); Kind = 'path' }
        @{ Label = 'extension'; Property = 'ExclusionExtension'; Approved = @($ApprovedDefenderExclusions.Extension); Kind = 'extension' }
        @{ Label = 'ASR-only exclusion'; Property = 'AttackSurfaceReductionOnlyExclusions'; Approved = @($ApprovedDefenderExclusions.AttackSurfaceReduction); Kind = 'path' }
        @{ Label = 'Controlled folder access app'; Property = 'ControlledFolderAccessAllowedApplications'; Approved = @($ControlledFolderAllowedApps); Kind = 'path' }
    )
    $extra = 0
    foreach ($check in $checks) {
        $approved = @($check.Approved | ForEach-Object {
            ConvertTo-NormalizedDefenderItem -Value "$_" -Kind $check.Kind
        } | Where-Object { $_ })
        foreach ($raw in @(Get-DefenderPreferenceList -Preference $pref -Name $check.Property)) {
            if ($null -eq $raw) { continue }
            $text = "$raw".Trim()
            if (-not $text) { continue }
            $norm = ConvertTo-NormalizedDefenderItem -Value $text -Kind $check.Kind
            if ($approved -notcontains $norm) {
                $extra += 1
                Write-Fail "[Defender] Unapproved $($check.Label): $text"
            }
        }
    }
    if ($extra -eq 0) {
        Write-Host '  [Defender] Exclusions match the approved lists' -ForegroundColor Green
    }
}

# Report only. Turning these off from here could cut off a remote session
# that is being used on purpose, including one that is running this script.
function Test-RemoteAccess {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Checking Remote Access' '.'

    $rdp = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue
    if ($rdp -and $rdp.PSObject.Properties['fDenyTSConnections'] -and [int]$rdp.fDenyTSConnections -eq 0) {
        Write-Fail '[Remote access] Remote Desktop is allowed (fDenyTSConnections = 0). This script does not turn it off, so a remote session is not cut off'
    } else {
        Write-Host '  [Remote access] Remote Desktop is not allowed' -ForegroundColor Green
    }

    $assist = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name 'fAllowToGetHelp' -ErrorAction SilentlyContinue
    if ($assist -and $assist.PSObject.Properties['fAllowToGetHelp'] -and [int]$assist.fAllowToGetHelp -eq 1) {
        Write-Fail '[Remote access] Remote Assistance is on (fAllowToGetHelp = 1). This script does not turn it off'
    } else {
        Write-Host '  [Remote access] Remote Assistance is off' -ForegroundColor Green
    }

    $winrm = Get-Service -Name 'WinRM' -ErrorAction SilentlyContinue
    $winrmRunning = $winrm -and "$($winrm.Status)" -eq 'Running'
    $listeners = @()
    $listenersKnown = $false
    try {
        $listeners = @(Get-ChildItem 'WSMan:\localhost\Listener' -ErrorAction Stop)
        $listenersKnown = $true
    } catch {
        $listenersKnown = $false
    }
    if ($winrmRunning -or ($listenersKnown -and $listeners.Count -gt 0)) {
        $why = @()
        if ($winrmRunning) { $why += 'the WinRM service is running' }
        if ($listenersKnown -and $listeners.Count -gt 0) { $why += "$($listeners.Count) WinRM listener(s) are configured" }
        Write-Fail "[Remote access] $($why -join ', '). This script does not turn WinRM off"
    } else {
        Write-Host '  [Remote access] WinRM is not running and no listener was found' -ForegroundColor Green
    }
}

# Report only. A working UAC level is left as it is. Fail when UAC is off,
# the prompt is not on the secure desktop, or an admin elevates with no prompt
# (ConsentPromptBehaviorAdmin = 0). Other prompt styles are left alone.
function Test-UacSetting {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Checking User Account Control' '.'

    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $item = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    $read = {
        param([string]$Name)
        if ($item -and $item.PSObject.Properties[$Name]) { return [int]$item.$Name }
        return $null
    }
    $bad = $false
    $lua = & $read 'EnableLUA'
    if ($null -eq $lua -or $lua -ne 1) {
        $bad = $true
        $shown = if ($null -eq $lua) { 'missing' } else { "$lua" }
        Write-Fail "[UAC] EnableLUA is $shown (it should be 1). This script does not change UAC"
    }
    $desktop = & $read 'PromptOnSecureDesktop'
    if ($null -eq $desktop -or $desktop -ne 1) {
        $bad = $true
        $shown = if ($null -eq $desktop) { 'missing' } else { "$desktop" }
        Write-Fail "[UAC] PromptOnSecureDesktop is $shown (it should be 1). This script does not change UAC"
    }
    $consent = & $read 'ConsentPromptBehaviorAdmin'
    if ($consent -eq 0) {
        $bad = $true
        Write-Fail '[UAC] ConsentPromptBehaviorAdmin is 0, so an administrator elevates without a prompt. This script does not change UAC'
    }
    if (-not $bad) {
        Write-Host '  [UAC] On, with a prompt on the secure desktop' -ForegroundColor Green
    }
}

# Report only. Do not enable encryption and do not create a recovery key.
# WMI, not the BitLocker module: Windows Home has device encryption and does
# not have Get-BitLockerVolume. ProtectionStatus 1 with conversion 1 (encrypted)
# or 2 (encryption in progress) is protected.
function Test-DriveEncryption {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Checking Device Encryption' '.'

    $vols = @()
    try {
        $vols = @(Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName 'Win32_EncryptableVolume' -ErrorAction Stop)
    } catch {
        Write-Fail "[BitLocker] Couldn't check device encryption: $($_.Exception.Message)"
        return
    }
    $want = $env:SystemDrive.TrimEnd('\').ToUpperInvariant()
    $matchLetter = {
        param($Letter)
        $letter = "$Letter".Trim().TrimEnd('\').ToUpperInvariant()
        $letter -and ($letter -eq $want -or "${letter}:" -eq $want)
    }
    $sys = @($vols | Where-Object { & $matchLetter $_.DriveLetter })
    # Some PCs leave DriveLetter blank on Win32_EncryptableVolume. The volume id
    # matches Win32_Volume, which does have the drive letter.
    if ($sys.Count -eq 0) {
        $ids = @(Get-CimInstance -ClassName Win32_Volume -ErrorAction SilentlyContinue | Where-Object {
            (& $matchLetter $_.DriveLetter) -or (& $matchLetter $_.Name)
        } | ForEach-Object { "$($_.DeviceID)".TrimEnd('\').ToUpperInvariant() })
        $sys = @($vols | Where-Object { $ids -contains "$($_.DeviceID)".TrimEnd('\').ToUpperInvariant() })
    }
    if ($sys.Count -eq 0) {
        Write-Fail "[BitLocker] Couldn't find an encryptable volume for $want. Turn on device encryption or BitLocker and save the recovery key. This script does not turn encryption on"
        return
    }
    foreach ($vol in $sys) {
        try {
            $protResult = Invoke-CimMethod -InputObject $vol -MethodName 'GetProtectionStatus' -ErrorAction Stop
            $convResult = Invoke-CimMethod -InputObject $vol -MethodName 'GetConversionStatus' -ErrorAction Stop
        } catch {
            Write-Fail "[BitLocker] Couldn't read encryption status for ${want}: $($_.Exception.Message)"
            continue
        }
        if ([int]$protResult.ReturnValue -ne 0 -or [int]$convResult.ReturnValue -ne 0) {
            Write-Fail "[BitLocker] Couldn't read encryption status for $want (protection result $($protResult.ReturnValue), conversion result $($convResult.ReturnValue))"
            continue
        }
        $prot = [int]$protResult.ProtectionStatus
        $conv = [int]$convResult.ConversionStatus
        # 1 = protected. Conversion 1 = fully encrypted, 2 = encryption in progress.
        if ($prot -eq 1 -and ($conv -eq 1 -or $conv -eq 2)) {
            $words = if ($conv -eq 2) { 'encryption in progress' } else { 'encrypted' }
            Write-Host "  [BitLocker] $want is protected ($words)" -ForegroundColor Green
        } else {
            Write-Fail "[BitLocker] $want is not protected (protection status $prot, conversion status $conv). Turn on device encryption or BitLocker and save the recovery key. This script does not turn encryption on"
        }
    }
}

# HealthStatus only. Unknown is an empty card reader or a disk Windows
# couldn't ask; that is not a failed disk. This is separate from chkdsk.
function Test-DiskHealth {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Checking Disk Health' '.'

    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop)
    } catch {
        Write-Fail "[Disk] Couldn't check disk health: $($_.Exception.Message)"
        return
    }
    if ($disks.Count -eq 0) {
        Write-Fail "[Disk] Get-PhysicalDisk returned no disks, so disk health couldn't be checked"
        return
    }
    $bad = @($disks | Where-Object { "$($_.HealthStatus)" -in 'Unhealthy', 'Warning' })
    foreach ($d in $bad) {
        $name = if ("$($d.FriendlyName)".Trim()) { "$($d.FriendlyName)".Trim() } else { "$($d.DeviceId)" }
        Write-Fail "[Disk] $name is $($d.HealthStatus)"
    }
    if ($bad.Count -eq 0) {
        Write-Host "  [Disk] $($disks.Count) disk(s): health is fine. A status of Unknown, such as an empty card reader, is left alone" -ForegroundColor Green
    }
}

# "PC check report.txt" on the Desktop, replaced every run and opened in
# Notepad at the end: the one file the person using the PC is asked to send
# when there are problems. The run's result, then the Protection history.
function Save-RunStatus {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("PC check report for $env:COMPUTERNAME (dailyrunme)")
    $lines.Add((Get-Date -Format 'yyyy-MM-dd HH:mm'))
    $lines.Add('')
    if ($script:Failures.Count -gt 0) {
        $lines.Add("Needs attention: $($script:Failures.Count) problem(s). Please send this file to $(Get-HelperName).")
    } elseif ($script:RestartReasons.Count -gt 0) {
        $lines.Add('All clear, but a restart is needed (see below)')
    } else {
        $lines.Add('All clear')
    }
    if ($script:Failures.Count -gt 0) {
        $lines.Add('')
        foreach ($f in $script:Failures) { $lines.Add("FAIL: $f") }
    }
    if ($script:Notes.Count -gt 0) {
        $lines.Add('')
        foreach ($n in $script:Notes) { $lines.Add("NOTE: $n") }
    }
    if ($script:RestartReasons.Count -gt 0) {
        $lines.Add('')
        $lines.Add('A restart is needed:')
        foreach ($r in $script:RestartReasons) { $lines.Add("- $r") }
    }
    $lines.Add('')
    $lines.Add("Log: $transcript")
    if ($script:HistoryFile -and (Test-Path -LiteralPath $script:HistoryFile)) {
        $lines.Add('')
        $lines.Add('=' * 72)
        foreach ($l in Get-Content -LiteralPath $script:HistoryFile) { $lines.Add($l) }
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    # Earlier versions' name for it
    Remove-Item -LiteralPath (Join-Path $desktop 'dailyrunme status.txt') -ErrorAction SilentlyContinue
    $path = Join-Path $desktop 'PC check report.txt'
    try {
        Set-Content -LiteralPath $path -Value $lines -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Controlled folder access blocks PowerShell writing to the Desktop
        $fallback = Join-Path $LogDir 'PC check report.txt'
        Write-Host "  Couldn't write $path ($($_.Exception.Message)); using $fallback" -ForegroundColor Yellow
        $path = $fallback
        try {
            Set-Content -LiteralPath $path -Value $lines -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Fail "[Status] Couldn't write ${path}: $($_.Exception.Message)"
            return
        }
    }
    $script:StatusFile = $path
    Write-Host "  Status: $path" -ForegroundColor Green
}

# ---------------------------------------------------------------
# -Install and -Uninstall (run by install-dailyrunme.cmd)
# Sets it up for whoever is signed in at the screen, who must be an
# administrator:
#   - a copy of this script in C:\Program Files\dailyrunme, where only
#     administrators can change it. It runs with admin rights every week, so
#     a copy anywhere the user (or malware running as them) can write would
#     hand out admin rights.
#   - Task Scheduler \dailyrunme\Weekly: Fridays at 23:00 with full scans,
#     with the user's admin rights and no prompt. Wakes the PC from sleep; if
#     the PC was off or signed out, it runs at the next chance.
#   - Task Scheduler \dailyrunme\Run now: the same, without full scans unless
#     it's the weekend, started by the Desktop shortcut "Check and update this
#     PC" (no permission prompt).
# Run it again after changing the script, to update the copy.
# ---------------------------------------------------------------
$InstallDir = Join-Path $env:ProgramFiles 'dailyrunme'
$TaskFolder = '\dailyrunme\'
$ShortcutName = 'Check and update this PC.lnk'

function Install-DailyRunMe {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # The account signed in at the screen (the owner of this session's
    # Explorer) must be the one running this. If Windows asked for another
    # account's password to get admin rights, the signed-in user isn't an
    # administrator, and a task running as them couldn't get admin rights.
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $session = (Get-Process -Id $PID).SessionId
    $explorer = @(Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe' AND SessionId = $session")
    if ($explorer.Count -gt 0) {
        $owner = (Invoke-CimMethod -InputObject $explorer[0] -MethodName GetOwnerSid).Sid
        if ($owner -and $owner -ne $me.User.Value) {
            $name = $owner
            try { $name = ([Security.Principal.SecurityIdentifier]$owner).Translate([Security.Principal.NTAccount]).Value } catch { Write-Verbose 'no account name' }
            throw "The account signed in at the screen ($name) isn't an administrator, so the weekly run couldn't get admin rights. Make it an administrator, or sign in as one, and run install-dailyrunme.cmd again."
        }
    }

    Write-Banner 'Installing dailyrunme' '#' Cyan
    $target = Join-Path $InstallDir 'dailyrunme.ps1'
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    if ($PSCommandPath -ne $target) { Copy-Item -LiteralPath $PSCommandPath -Destination $target -Force }
    # Program Files' own permissions, in case the folder was made with others
    & icacls.exe $InstallDir /reset /T /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Couldn't reset the permissions of $InstallDir (icacls exit $LASTEXITCODE)" }
    # The downloaded-from-the-internet mark, which SmartScreen would block
    Unblock-File -LiteralPath $target
    Write-Host "  Script: $target" -ForegroundColor Green

    # The old schtasks example in this script's notes made \dailyrunme
    Get-ScheduledTask -TaskPath '\' -TaskName 'dailyrunme' -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $principal = New-ScheduledTaskPrincipal -UserId $me.Name -LogonType Interactive -RunLevel Highest
    # A run takes hours on the weekly run's full scans, so no time limit
    # beyond Windows' default of 3 days; a second start while one runs is ignored
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    $action = { param($extra) New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$target`"$extra" }
    Register-ScheduledTask -TaskPath $TaskFolder -TaskName 'Weekly' -Action (& $action ' -FullScan') `
        -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At '23:00') -Principal $principal -Settings $settings `
        -Description 'dailyrunme with full scans, every Friday at 23:00' -Force | Out-Null
    Register-ScheduledTask -TaskPath $TaskFolder -TaskName 'Run now' -Action (& $action '') `
        -Principal $principal -Settings $settings -Description 'dailyrunme, started by the Desktop shortcut' -Force | Out-Null
    # Let the user start "Run now" without admin rights (read and execute), so
    # the shortcut doesn't need a permission prompt. It still runs with their
    # admin rights, as set up here.
    try {
        $service = New-Object -ComObject Schedule.Service
        $service.Connect()
        $task = $service.GetFolder($TaskFolder.TrimEnd('\')).GetTask('Run now')
        $dacl = $task.GetSecurityDescriptor(4)   # 4: the DACL only, "D:(A;...)..."
        $ace = "(A;;GRGX;;;$($me.User.Value))"
        if ($dacl -notlike "*$ace*") { $task.SetSecurityDescriptor("$dacl$ace", 0) }
    } catch {
        Write-Host "  Couldn't let $($me.Name) start the task without a prompt ($($_.Exception.Message)); the shortcut may need Run as administrator" -ForegroundColor Yellow
    }
    Write-Host "  Weekly run: Fridays at 23:00, as $($me.Name) (Task Scheduler > $($TaskFolder)Weekly)" -ForegroundColor Green

    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName
    $schtasks = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    try {
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $s.TargetPath = $schtasks
        $s.Arguments = "/Run /TN `"$($TaskFolder)Run now`""
        $s.WindowStyle = 7   # minimized: schtasks only starts the task
        $s.Description = 'Checks this PC for problems and installs updates. Can take an hour or more; leave its window open until a message says it has finished.'
        $icon = Join-Path $env:SystemRoot 'System32\SecurityHealthSystray.exe'
        $s.IconLocation = if (Test-Path -LiteralPath $icon) { "$icon,0" } else { "$env:SystemRoot\System32\shell32.dll,47" }
        $s.Save()
        Write-Host "  Desktop shortcut: $lnk" -ForegroundColor Green
    } catch {
        # Controlled folder access protects the Desktop
        Write-Fail "[Install] Couldn't make the Desktop shortcut ($($_.Exception.Message)). Make one by hand: target $schtasks /Run /TN `"$($TaskFolder)Run now`""
    }

    Write-Host ''
    Write-Host 'Installed. To check the PC now, double-click the Desktop shortcut.'
    Write-Host "Logs, reports and registry undo files: $LogDir"
}

function Uninstall-DailyRunMe {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner 'Removing dailyrunme' '#' Cyan
    Get-ScheduledTask -TaskPath $TaskFolder -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
    try {
        $service = New-Object -ComObject Schedule.Service
        $service.Connect()
        $service.GetFolder('\').DeleteFolder($TaskFolder.Trim('\'), 0)
    } catch {
        Write-Verbose 'task folder already gone'
    }
    Write-Host '  Scheduled tasks removed' -ForegroundColor Green
    Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName) -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Desktop shortcut and $InstallDir removed" -ForegroundColor Green
    Write-Host ''
    Write-Host "The settings it applied stay. Logs, reports and registry undo files are kept in $LogDir."
}

# ---------------------------------------------------------------
# Main
# ---------------------------------------------------------------

if ($Install -or $Uninstall) {
    $script:Step = if ($Install) { 'install' } else { 'uninstall' }
    try {
        if ($Install) { Install-DailyRunMe } else { Uninstall-DailyRunMe }
    } catch {
        Write-Fail $_.Exception.Message
    }
    if ($script:Failures.Count -gt 0) { exit 1 }
    exit 0
}

# What the person using the PC sees in the taskbar while it runs
try {
    $Host.UI.RawUI.WindowTitle = 'Checking and updating this PC. This can take an hour or more; please leave this window open.'
} catch {
    Write-Verbose 'no console'
}

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Get-ChildItem -LiteralPath $LogDir -Filter 'dailyrunme-*.log' |
    Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) |
    Remove-Item -Force
$runStamp = Get-Date -Format yyyyMMdd-HHmmss
$transcript = Join-Path $LogDir "dailyrunme-$runStamp.log"
Start-Transcript -LiteralPath $transcript | Out-Null

# Read programs' output as UTF-8, and have programs that follow the console's code
# page (choco, dism, chkdsk) write it, so winget's progress bars can be filtered
$consoleEncoding = $null
try {
    $consoleEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
} catch {
    Write-Verbose 'no console'
}

try {
    Write-Banner 'dailyrunme' '#' Cyan
    # Signatures first, so everything after runs with Defender up to date.
    # The restore point is next, before any setting changes.
    Invoke-Step 'patchmssigs' { Update-DefenderSignature }
    Invoke-Step 'restorepoint' { New-DailyRestorePoint }

    # Hardening, before anything is installed
    Invoke-Step 'cis-chrome' { Set-ChromeHardening }
    Invoke-Step 'cis-services' { Disable-UnneededService }
    Invoke-Step 'quickassist' { Remove-QuickAssist }
    Invoke-Step 'smb1' { Remove-SmbV1 }
    Invoke-Step 'cis-registry' { Set-SecurityRegistry }
    Invoke-Step 'dns' { Set-SecureDns }
    Invoke-Step 'hostsfile' { Repair-HostsFile }
    Invoke-Step 'scriptprotect' { Set-ScriptProtection }
    Invoke-Step 'cis-office' { Set-OfficeHardening }
    Invoke-Step 'firewall' { Enable-FirewallProfile }
    Invoke-Step 'lnkprotect' { Set-ShortcutProtection }
    Invoke-Step 'explorerview' { Set-ExplorerView }
    Invoke-Step 'autoplay' { Disable-AutoPlay }
    Invoke-Step 'dep' { Enable-Dep }
    Invoke-Step 'coreisolation' { Set-CoreIsolation }
    Invoke-Step 'devmode' { Disable-DeveloperMode }
    Invoke-Step 'exploitprotect' { Reset-ExploitProtection }
    Invoke-Step 'defendersettings' { Set-DefenderSetting }
    Invoke-Step 'reputation' { Set-ReputationProtection }
    Invoke-Step 'defenderexclusions' { Test-DefenderExclusion }

    # Updates, then the checks. The Defender scan starts after them so it is
    # not reading the disk during DISM, sfc, or chkdsk.
    Invoke-Step 'patchwindows' { Update-Windows }
    Invoke-Step 'patchoffice' { Update-Office }
    Invoke-Step 'patchchoco' { Update-ChocolateyPackage }
    Invoke-Step 'patchmsstore' { Update-StoreApp }
    Invoke-Step 'patchwinget' { Update-WingetPackage }
    Invoke-Step 'msert' { Start-SafetyScan }
    Invoke-Step 'eekscan' { Start-EmsisoftScan }
    Invoke-Step 'remoteaccess' { Test-RemoteAccess }
    Invoke-Step 'uac' { Test-UacSetting }
    Invoke-Step 'bitlocker' { Test-DriveEncryption }
    Invoke-Step 'diskhealth' { Test-DiskHealth }
    Invoke-Step 'winhealthcheck' { Test-WindowsHealth }
    Invoke-Step 'windiskcheck' { Test-SystemDisk }
    Invoke-Step 'mywinprocsigs' { Find-UnsignedProcess; Find-LolbasCopy }
    Invoke-Step 'winstartupcheck' { Test-StartupEntry }
    Invoke-Step 'winmodcheck' { Test-DriverSignature }
    Invoke-Step 'mywinvscan' { Start-DefenderScan }

    # Last of the checks, so it includes anything the steps above set off
    Invoke-Step 'protectionhistory' { Save-ProtectionHistory }

    # Kept, unlike the transcripts: the first run's file is the only record of
    # how the PC was before
    $script:Step = 'registryundo'
    $undoFile = $null
    try {
        $undoFile = Save-RegistryUndo -File (Join-Path $LogDir "registry-undo-$runStamp.reg")
    } catch {
        Write-Fail "Couldn't write the registry undo file: $($_.Exception.Message)"
    }

    # After the undo file, so a failure writing it is in the status file too
    Invoke-Step 'statusfile' { Save-RunStatus }

    Write-Banner 'dailyrunme summary' '#' Cyan
    foreach ($n in $script:Notes) { Write-Host "NOTE: $n" -ForegroundColor Yellow }
    foreach ($f in $script:Failures) { Write-Host "FAIL: $f" -ForegroundColor Red }
    if ($script:Failures.Count -eq 0) { Write-Host 'All steps finished' -ForegroundColor Green }
    Write-Host 'Restart Chrome for its policies (or chrome://policy > Reload policies).'
    if ($script:RestartReasons.Count -gt 0) {
        Write-Host 'A restart is needed:'
        foreach ($r in $script:RestartReasons) { Write-Host "  $r" -ForegroundColor Yellow }
    }
    if ($script:StatusFile) { Write-Host "Status: $script:StatusFile" }
    if ($script:HistoryFile) { Write-Host "Protection history: $script:HistoryFile" }
    if ($script:EekLog) { Write-Host "Emsisoft found malware; its log: $script:EekLog" -ForegroundColor Red }
    if ($undoFile) {
        Write-Host "Registry values changed: $($script:RegistryUndo.Count); to put them back: $undoFile"
    } else {
        Write-Host 'Registry values changed: none'
    }
    Write-Host "Log: $transcript"
} finally {
    if ($consoleEncoding) {
        try { [Console]::OutputEncoding = $consoleEncoding } catch { Write-Verbose 'no console' }
    }
    Stop-Transcript | Out-Null
}

# Last of all, so the windows open once the script has nothing left to do.
# The report includes the Protection history.
if ($script:StatusFile) {
    Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$script:StatusFile`""
} elseif ($script:HistoryFile) {
    Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$script:HistoryFile`""
}
if ($script:EekLog) {
    Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$script:EekLog`""
}

# Then one message in plain words, after Notepad so it's in front. After a
# weekly run at night it waits there for the morning. The PC restarts only
# if Yes is clicked, when something is actually waiting on a restart.
$report = if ($script:StatusFile -and $script:StatusFile -like "$([Environment]::GetFolderPath('Desktop'))*") {
    '"PC check report.txt" on your Desktop'
} elseif ($script:StatusFile) {
    $script:StatusFile
} else {
    $transcript
}
$popup = [System.Collections.Generic.List[string]]::new()
if ($script:Failures.Count -gt 0) {
    $popup.Add("The check found $($script:Failures.Count) problem(s).")
    $popup.Add('')
    $popup.Add("The details are in $report, open in Notepad. Please send that file to $(Get-HelperName).")
    if ($script:EekLog) {
        $popup.Add('')
        $popup.Add('Emsisoft Emergency Kit found possible malware; its log is open in Notepad too.')
    }
} else {
    $popup.Add('Your PC has been checked and updated. No problems were found.')
}
$restart = $script:RestartReasons.Count -gt 0
if ($restart) {
    $popup.Add('')
    $popup.Add('A restart is needed to finish:')
    foreach ($r in $script:RestartReasons) { $popup.Add("- $r") }
    $popup.Add('')
    $popup.Add('Save your work, then click Yes to restart now. Click No to restart later yourself.')
}
$shown = $false
$answer = $null
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
        $buttons = if ($restart) { 'YesNo' } else { 'OK' }
        $icon = if ($script:Failures.Count -gt 0) { 'Warning' } elseif ($restart) { 'Question' } else { 'Information' }
        # A hidden always-on-top window as its owner, so the message isn't
        # lost behind Notepad or other windows
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
        $answer = [System.Windows.Forms.MessageBox]::Show($owner, ($popup -join "`r`n"), 'PC check',
            [System.Windows.Forms.MessageBoxButtons]::$buttons, [System.Windows.Forms.MessageBoxIcon]::$icon)
        $owner.Dispose()
        $shown = $true
    }
} catch {
    $shown = $false
}
if (-not $shown) {
    # msg.exe has no Yes/No buttons
    if ($restart) { $popup[$popup.Count - 1] = 'Please restart the PC when you can.' }
    $msg = ($popup -join ' ')
    if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) }
    $msgCmd = Get-Command msg.exe -ErrorAction SilentlyContinue
    if ($msgCmd) { & $msgCmd.Source $env:USERNAME /TIME:3600 $msg | Out-Null }
    if (-not $msgCmd -or $LASTEXITCODE -ne 0) {
        Write-Host 'The final message could not be shown; the result is in the summary and the report.' -ForegroundColor Yellow
    }
}
if ("$answer" -eq 'Yes') {
    # 30 seconds' warning; Windows closes programs that are still open
    & shutdown.exe /r /t 30 /c 'Restarting to finish the PC check'
}

if ($script:Failures.Count -gt 0) { exit 1 }
exit 0
