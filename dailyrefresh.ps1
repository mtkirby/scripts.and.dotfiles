<#
.SYNOPSIS
    Daily Windows refresh: updates, a background Defender scan, and health and
    signature checks.

.DESCRIPTION
    PowerShell version of these .bashrc Cygwin functions, run in mywinpatchall's order:
    - patchmssigs:    update Microsoft Defender signatures
    - patchchoco:     choco upgrade all
    - patchmsstore:   winget upgrades from the Microsoft Store, then a Store update scan
    - patchwinget:    winget upgrade --all
    - mywinvscan:     start a full Defender scan, limited to 50% CPU, in the background
    - winhealthcheck: DISM ScanHealth, sfc /scannow, DISM AnalyzeComponentStore
    - windiskcheck:   chkdsk /scan of the system drive
    - mywinprocsigs:  running programs without a valid Authenticode signature, and
                      LOLBAS programs renamed or running from unusual folders
    - winstartupcheck: startup entries (tasks, Run keys, services, WMI...) that run
                      LOLBAS programs, alerting on signs of misuse
    - winmodcheck:    loaded drivers without a valid signature or in the loldrivers.io
                      list, and settings that let unsigned or blocklisted drivers load

.PARAMETER LogDir
    Where the transcript and the Defender scan log go. Transcripts older than 30 days
    are deleted.

.NOTES
    - Must be run as Administrator. Run it as yourself, not SYSTEM: winget only works
      in a user session.
    - Windows blocks scripts by default, so start it with -ExecutionPolicy Bypass.
    - Exit code 1 if any step failed; the summary at the end lists them.
    - To run it every day at 03:00 (only while you are logged on):
      schtasks /Create /TN dailyrefresh /SC DAILY /ST 03:00 /RL HIGHEST /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\path\to\dailyrefresh.ps1"

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\dailyrefresh.ps1
#>

#Requires -RunAsAdministrator

param(
    [string]$LogDir = (Join-Path $env:ProgramData 'dailyrefresh')
)

# Not 'Stop': in Windows PowerShell, a native program's stderr line would then end
# the step. Steps catch the errors that matter with -ErrorAction Stop.
$ErrorActionPreference = 'Continue'

$script:Step = ''
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:Notes = [System.Collections.Generic.List[string]]::new()

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

# winget's progress bars and spinner, which come out as lines once redirected
$WingetProgress = '^\s*[-\\|/]?\s*$|[\u2588\u2592]{3,}'

# ---------------------------------------------------------------
# Steps
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
        Write-Banner 'winget upgrade --all --source msstore' '.'
        Invoke-Native winget 'upgrade', '--all', '--include-unknown', '--source', 'msstore',
            '--accept-source-agreements', '--accept-package-agreements',
            '--disable-interactivity' -Skip $WingetProgress
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
    Get-Process | Where-Object Path | ForEach-Object Path | Sort-Object -Unique |
        ForEach-Object {
            $s = Get-AuthenticodeSignature -LiteralPath $_ -ErrorAction SilentlyContinue
            if ($s -and $s.Status -ne 'Valid') { '{0,-14} {1}' -f $s.Status, $_ }
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
            $found++
            continue
        }
        if ($where[$name] | Where-Object { $p -like $_ }) { continue }
        if ((Split-Path -Parent $p) -eq $env:SystemRoot) { continue }
        if (($trusted | Where-Object { $p -like $_ }) -and $p -notmatch $writable) { continue }
        "ALERT=`"Windows program=$name running from $p, outside its usual folders`""
        $found++
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
# Startup folders, services, Winlogon and WMI subscriptions.
#   ALERT: the command shows a sign of misuse (a URL, javascript:, a scriptlet,
#     encoded PowerShell, a temp or public folder...), or Winlogon or WMI is set to
#     run something it normally does not.
#   NOTE: a LOLBAS program started by a Run key, Startup folder, WMI subscription or
#     a scheduled task outside \Microsoft\, for review. Windows' own tasks and
#     services use these programs all the time, so they are only alerted on.
function Test-StartupEntry {
    Write-Banner 'Startup Entries Running LOLBAS Programs' '.'
    $ErrorActionPreference = 'SilentlyContinue'
    $count = @{ found = 0; noted = 0 }
    function Alert([string]$m) { "ALERT=`"$m`""; $count.found++ }
    function Note([string]$m) { "NOTE=`"$m`""; $count.noted++ }

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
        "Found $($count.found) startup entries with signs of misuse, and $($count.noted) to review"
        Write-Fail "Found $($count.found) startup entries with signs of misuse; see the ALERT lines above"
    } elseif ($count.noted) {
        "No startup entries show signs of misuse; $($count.noted) listed above to review"
    } else {
        'No startup entries run LOLBAS programs'
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
    function Alert([string]$m) { "ALERT=`"$m`""; $count.found++ }
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
        $count.third++
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
# Main
# ---------------------------------------------------------------

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Get-ChildItem -LiteralPath $LogDir -Filter 'dailyrefresh-*.log' |
    Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) |
    Remove-Item -Force
$transcript = Join-Path $LogDir "dailyrefresh-$(Get-Date -Format yyyyMMdd-HHmmss).log"
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
    Write-Banner 'dailyrefresh' '#' Cyan
    Invoke-Step 'patchmssigs' { Update-DefenderSignature }
    Invoke-Step 'patchchoco' { Update-ChocolateyPackage }
    Invoke-Step 'patchmsstore' { Update-StoreApp }
    Invoke-Step 'patchwinget' { Update-WingetPackage }
    Invoke-Step 'mywinvscan' { Start-DefenderScan }
    Invoke-Step 'winhealthcheck' { Test-WindowsHealth }
    Invoke-Step 'windiskcheck' { Test-SystemDisk }
    Invoke-Step 'mywinprocsigs' { Find-UnsignedProcess; Find-LolbasCopy }
    Invoke-Step 'winstartupcheck' { Test-StartupEntry }
    Invoke-Step 'winmodcheck' { Test-DriverSignature }

    Write-Banner 'dailyrefresh summary' '#' Cyan
    foreach ($n in $script:Notes) { Write-Host "NOTE: $n" -ForegroundColor Yellow }
    foreach ($f in $script:Failures) { Write-Host "FAIL: $f" -ForegroundColor Red }
    if ($script:Failures.Count -eq 0) { Write-Host 'All steps finished' -ForegroundColor Green }
    Write-Host "Log: $transcript"
} finally {
    if ($consoleEncoding) {
        try { [Console]::OutputEncoding = $consoleEncoding } catch { Write-Verbose 'no console' }
    }
    Stop-Transcript | Out-Null
}

if ($script:Failures.Count -gt 0) { exit 1 }
exit 0
