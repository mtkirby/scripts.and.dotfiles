<#
.SYNOPSIS
    Daily Windows run: security hardening, updates, a background Defender scan,
    health and security checks, and a report of Defender's Protection history.

.DESCRIPTION
    Every step runs even if an earlier one fails; the summary at the end lists what failed.

    1. patchmssigs:       update Microsoft Defender signatures
    2. Hardening, re-applied every run so nothing drifts:
       - cis-chrome:      Chrome policies (CIS Google Chrome Benchmark v3.0.0), the
                          extension allowlist, the JavaScript optimizer allowlist,
                          and Chrome Remote Desktop blocked
       - cis-passwords:   local password and lockout policy (CIS Windows 11
                          Stand-alone Benchmark v5.0.0)
       - cis-services:    unneeded services disabled
       - cis-registry:    automatic logon and WDigest off
       - dns:             Quad9 / OpenDNS with DNS over HTTPS preferred
       - scriptprotect:   Defender ASR rules, no Win+R, PowerShell logging,
                          PowerShell 2.0 removed, Windows Script Host off
       - cis-office:      Microsoft Office (CIS Microsoft Office Enterprise
                          Benchmark v1.2.0, Level 1) for every user account
       - lnkprotect:      shortcut extensions shown, mshta/regsvr32/certutil
                          firewalled, .hta opens in Notepad
       - dep:             Data Execution Prevention for all programs
       - defendersettings: real-time, cloud, sample submission, Dev Drive,
                          Controlled folder access; checks Tamper protection
    3. Updates:
       - patchchoco:      choco upgrade all
       - patchmsstore:    winget upgrades from the Microsoft Store, then a Store
                          update scan
       - patchwinget:     winget upgrade --all
    4. mywinvscan:        start a full Defender scan, limited to 50% CPU, in the
                          background
    5. Checks:
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
    6. protectionhistory: the last 7 days of Defender's Protection history,
                          written to the Desktop and opened in Notepad at the end

    The settings to edit (approved Chrome extensions, JavaScript optimizer sites,
    Office's old file formats, Controlled folder access apps, DNS servers) are at
    the top of the script.

.PARAMETER LogDir
    Where the transcript and the Defender scan log go. Transcripts older than 30 days
    are deleted.

.NOTES
    - Must be run as Administrator. Run it as yourself, not SYSTEM: winget only works
      in a user session, and the report goes to your Desktop.
    - Windows blocks scripts by default, so start it with -ExecutionPolicy Bypass.
    - Exit code 1 if any step failed; the summary at the end lists them.
    - Restart Chrome after the first run, and Windows after any run that changes
      services, DEP or PowerShell 2.0.
    - Chrome policies need Chrome to read HKLM\SOFTWARE\Policies\Google\Chrome;
      check them at chrome://policy.
    - Hardening targets a stand-alone PC. On a domain, use Group Policy instead.
    - Not a complete CIS implementation: many recommendations are manual or
      environment-specific. Back up the system before the first run.
    - To run it every day at 03:00 (only while you are logged on):
      schtasks /Create /TN dailyrunme /SC DAILY /ST 03:00 /RL HIGHEST /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\path\to\dailyrunme.ps1"

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\dailyrunme.ps1
#>

#Requires -RunAsAdministrator

param(
    [string]$LogDir = (Join-Path $env:ProgramData 'dailyrunme')
)

# Not 'Stop': in Windows PowerShell, a native program's stderr line would then end
# the step. Steps catch the errors that matter with -ErrorAction Stop, and the
# hardening steps set 'Stop' for themselves.
$ErrorActionPreference = 'Continue'

$script:Step = ''
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:Notes = [System.Collections.Generic.List[string]]::new()
# Set by the protectionhistory step, opened in Notepad at the very end
$script:HistoryFile = $null

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
)

# ---------------------------------------------------------------
# Office: what happens to old binary files (.doc, .xls, .ppt and older
# formats) that CIS blocks (see Section 7)
#   0 = they don't open at all (CIS)
#   1 = they open read-only in Protected View
#   2 = they open in Protected View and can be edited
# ---------------------------------------------------------------
$OfficeBlockedFileBehavior = 0

# ---------------------------------------------------------------
# Programs allowed to change files in folders that Controlled folder access
# protects (Documents, Pictures, Desktop...; see Section 10). Signed,
# well-known programs are allowed automatically. Add the full path of
# anything else it blocks; blocks show in the Protection history report.
# ---------------------------------------------------------------
$ControlledFolderAllowedApps = @(
    # 'C:\cygwin64\bin\git.exe'  # example
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

# Hardening helpers

function Set-ChromePolicy {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'DWord',
        [string]$Description
    )
    $path = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    Set-ItemProperty -Path $path -Name $Name -Value $Value -Type $Type -Force
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
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force
    }
    New-Item -Path $path -Force | Out-Null
    $i = 1
    foreach ($v in $Values) {
        New-ItemProperty -Path $path -Name "$i" -Value $v -PropertyType String -Force | Out-Null
        $i++
    }
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
        try {
            Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        } catch {
            Write-Fail "[Service] Couldn't disable ${Name}: $($_.Exception.Message)"
            return
        }
        # A service that won't stop now is still disabled, so it won't start after a restart
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        if ((Get-Service -Name $Name).Status -ne 'Stopped') {
            Write-Host "  [Service] Disabled $Name, but it's still running until restart  # $Description" -ForegroundColor Yellow
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
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
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
    # Being mandatory, 1 also drops any user who had chosen Enhanced back to Standard.
    Set-ChromePolicy -Name 'SafeBrowsingProtectionLevel' -Value 1 -Description 'Enable Safe Browsing (standard mode)'

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
    Set-ChromePolicy -Name 'SSLErrorOverrideAllowed' -Value 0 -Description 'Disallow proceeding past SSL warnings'

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
    Set-ChromePolicy -Name 'SyncDisabled' -Value 1 -Description 'Disable Google account sync'

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

    # 5.2 Incognito mode availability - Disabled
    # Disables Incognito mode (reduces ability to hide browsing activity in managed environments).
    # Values: 0 = available, 1 = disabled, 2 = forced (every window is Incognito).
    # With 1, "New Incognito window" disappears. This helps forensics, because all
    # browsing lands in normal history (1.13). You lose a quick way to open a
    # session that isn't signed in to anything, which other browser profiles can
    # also give you.
    Set-ChromePolicy -Name 'IncognitoModeAvailability' -Value 1 -Description 'Disable Incognito mode'

    Write-Host "Chrome policies applied. Verify at chrome://policy/ after restarting Chrome." -ForegroundColor Cyan
}

# ---------------------------------------------------------------
# SECTION 2: Windows 11 Stand-alone Password & Account Policies
# CIS Windows 11 Benchmark v5.0.0 - Section 1
#
# These apply to local accounts only. Signing in with a Microsoft account uses
# that account's password rules, set online, and a Windows Hello PIN has its
# own rules. Existing passwords aren't checked against new rules until they
# are next changed.
# ---------------------------------------------------------------
function Set-PasswordPolicy {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Banner "Applying Windows 11 Password & Lockout Policies" '.'

    # 1.1.1 Enforce password history - 24 or more
    # 1.1.2 Maximum password age - 365 or fewer, but not 0
    # 1.1.3 Minimum password age - 1 or more days
    # 1.1.4 Minimum password length - 14 or more
    # These are set via net accounts (local accounts).
    # History: a new password can't match any of the last 24.
    # Max age: local passwords older than 365 days must be changed at next sign-in,
    #   including any that are already older than that. 0 would mean never expire.
    #   (NIST now advises against forced changes; CIS still asks for a limit.)
    # Min age: one day between changes, so the 24-password history can't be beaten
    #   by changing the password 24 times in a row to get back to the old one.
    # Min length: 14 characters is the most Windows enforces without the separate
    #   RelaxMinimumPasswordLengthLimits setting.

    # $ErrorActionPreference doesn't cover programs like net and secedit, so check
    # their exit codes. stderr is left alone: under 'Stop', redirecting it would
    # turn any message into a terminating error in Windows PowerShell 5.1.
    net accounts /minpwlen:14 /maxpwage:365 /minpwage:1 /uniquepw:24 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "[Password] net accounts failed (exit $LASTEXITCODE); history/age/length not set"
    } else {
        Write-Host "  [Password] History=24, MaxAge=365, MinAge=1, MinLength=14" -ForegroundColor Green
        Write-Host "    # Reduces password reuse, forces periodic changes, and increases strength" -ForegroundColor DarkGray
    }

    # 1.1.5 Password must meet complexity requirements - Enabled
    # 1.1.7 Store passwords using reversible encryption - Disabled
    # These require secedit or Local Security Policy. Using a temporary INF.
    # Complexity: at least 3 of uppercase, lowercase, digit and symbol, and not
    #   containing the account name.
    # Reversible encryption: if enabled, Windows keeps passwords in a form that can
    #   be turned back into plain text. Only some old authentication protocols need
    #   it; disabled is the Windows default.
    # secedit only changes the settings listed in the INF; the .sdb is a scratch
    # database it needs, and both are deleted afterwards.

    $inf = @"
[Unicode]
Unicode=yes
[System Access]
PasswordComplexity = 1
ClearTextPassword = 0
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

    $infPath = "$env:TEMP\cis_password.inf"
    $sdbPath = "$env:TEMP\cis_password.sdb"
    $inf | Out-File -FilePath $infPath -Encoding Unicode -Force
    $seceditOut = secedit /configure /db $sdbPath /cfg $infPath /areas SECURITYPOLICY
    $seceditRc = $LASTEXITCODE
    Remove-Item $infPath, $sdbPath -ErrorAction SilentlyContinue
    # 0 = done; 3 = done, but some settings gave warnings; anything else failed.
    # secedit prints its errors to stdout, so show that output when it isn't 0.
    if ($seceditRc -eq 0 -or $seceditRc -eq 3) {
        Write-Host "  [Password] Complexity Enabled, Reversible encryption Disabled" -ForegroundColor Green
        Write-Host "    # Requires mixed character types; prevents storing passwords in reversible form" -ForegroundColor DarkGray
        if ($seceditRc -eq 3) {
            Write-Host "    # secedit reported warnings; see $env:windir\security\logs\scesrv.log" -ForegroundColor Yellow
        }
    } else {
        $seceditOut | Where-Object { $_ } | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        Write-Fail "[Password] secedit failed (exit $seceditRc); complexity/reversible encryption not set"
    }

    # 1.2.1 Account lockout duration - 15 or more minutes
    # 1.2.2 Account lockout threshold - 5 or fewer (not 0)
    # 1.2.4 Reset account lockout counter after - 15 or more minutes
    # Threshold: after 5 wrong passwords a local account is locked. 0 means never
    #   lock, which leaves password guessing unlimited, so CIS fails it.
    # Duration: the lock clears by itself after 15 minutes; no admin is needed.
    # Reset counter: failed attempts are forgotten after 15 minutes without one.
    #   Windows requires this to be no longer than the duration.
    # Anyone who can try to sign in, including over the network (SMB, RDP), can
    # lock an account on purpose. The 15-minute limit keeps that a nuisance.
    # Not set here: 1.2.3 "Allow Administrator account lockout".
    net accounts /lockoutthreshold:5 /lockoutduration:15 /lockoutwindow:15 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "[Lockout] net accounts failed (exit $LASTEXITCODE); lockout policy not set"
    } else {
        Write-Host "  [Lockout] Threshold=5, Duration=15 min, Reset=15 min" -ForegroundColor Green
        Write-Host "    # Limits brute-force attempts while allowing reasonable recovery" -ForegroundColor DarkGray
    }
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

    # Bluetooth hands-free profile. Without it, Bluetooth headsets still play
    # audio but their microphones stop working (calls, meetings).
    Disable-ServiceIfExists -Name 'BTAGService' -Description 'Bluetooth Audio Gateway (L2 - reduces wireless attack surface)'
    # Core Bluetooth service. Without it, NO Bluetooth device works: mice,
    # keyboards, headphones, phones. Comment this out on a PC that uses any.
    Disable-ServiceIfExists -Name 'bthserv' -Description 'Bluetooth Support Service (L2 - reduces wireless attack surface)'
    # Old SMB1 network-neighbourhood browsing. Not installed on Windows 11 unless
    # SMB1 was added back, so this usually reports "not present".
    Disable-ServiceIfExists -Name 'Browser' -Description 'Computer Browser (legacy NetBIOS service - L1)'
    # Downloads and updates offline maps for the Maps app. Nothing else needs it.
    Disable-ServiceIfExists -Name 'MapsBroker' -Description 'Downloaded Maps Manager (L2 - reduces location data exposure)'
    # Game controller input for games that use Microsoft's GameInput API. Some
    # games may stop seeing controllers.
    Disable-ServiceIfExists -Name 'GameInputSvc' -Description 'GameInput Service (L2 - reduces DMA input capture risk)'
    # Windows location. Without it, apps can't get your location, and automatic
    # time zone and Find My Device stop working.
    Disable-ServiceIfExists -Name 'lfsvc' -Description 'Geolocation Service (L2 - reduces location tracking)'
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
    # Finds UPnP devices on the network. Without it, media servers, smart TVs and
    # some printers don't show up under Network in Explorer.
    Disable-ServiceIfExists -Name 'SSDPSRV' -Description 'SSDP Discovery (L1 - reduces network discovery)'
    # Lets this PC offer UPnP services, e.g. media streaming to a TV. Depends on
    # SSDP Discovery above.
    Disable-ServiceIfExists -Name 'upnphost' -Description 'UPnP Device Host (L1 - reduces network discovery)'
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

    # Example: Disable AutoAdminLogon (MSS)
    # With automatic logon on, Windows signs in by itself at boot using a password
    # stored in the registry (DefaultPassword), readable by admins and some tools.
    # Setting 0 turns automatic logon off, but doesn't delete a DefaultPassword
    # value that's already there; check for it and remove it.
    $mssPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    if (-not (Test-Path $mssPath)) { New-Item -Path $mssPath -Force | Out-Null }
    Set-ItemProperty -Path $mssPath -Name 'AutoAdminLogon' -Value 0 -Type DWord -Force
    Write-Host "  [Registry] AutoAdminLogon = 0  # Disable automatic logon (MSS)" -ForegroundColor Green

    # WDigest Authentication - Disabled (reduces credential theft risk)
    # When on, Windows keeps a reversible copy of each signed-in user's password in
    # memory (LSASS), which credential dumpers such as Mimikatz read. Windows 10/11
    # already leave it off when the value is absent. Attackers with admin rights set
    # it to 1 and wait for the next sign-in, so setting 0 records the intended
    # state. If you ever find it at 1, treat that as a sign of compromise.
    $wdigestPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
    if (-not (Test-Path $wdigestPath)) { New-Item -Path $wdigestPath -Force | Out-Null }
    Set-ItemProperty -Path $wdigestPath -Name 'UseLogonCredential' -Value 0 -Type DWord -Force
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
    if (-not (Test-Path $dohPolicyPath)) { New-Item -Path $dohPolicyPath -Force | Out-Null }
    Set-ItemProperty -Path $dohPolicyPath -Name 'DoHPolicy' -Value 2 -Type DWord -Force
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
        foreach ($id in $asrRules.Keys) {
            # Add-MpPreference, not Set-MpPreference: Set replaces every existing rule
            try {
                Add-MpPreference -AttackSurfaceReductionRules_Ids $id -AttackSurfaceReductionRules_Actions Enabled -ErrorAction Stop
            } catch {
                Write-Fail "[ASR] Couldn't set '$($asrRules[$id])': $($_.Exception.Message)"
                continue
            }
            # Read it back: 1 = block (0 = off, 2 = audit only, 6 = warn)
            $pref = Get-MpPreference
            $ids = @($pref.AttackSurfaceReductionRules_Ids | ForEach-Object { "$_".ToLowerInvariant() })
            $i = [array]::IndexOf($ids, $id)
            if ($i -ge 0 -and @($pref.AttackSurfaceReductionRules_Actions)[$i] -eq 1) {
                Write-Host "  [ASR] Block: $($asrRules[$id])" -ForegroundColor Green
            } else {
                Write-Fail "[ASR] '$($asrRules[$id])' didn't take effect (check Tamper Protection or other management)"
            }
        }
    }

    # Disable the Run dialog (Win+R) for every user
    # Win+R is the step most of these tricks ask for. The Run entry also goes from
    # the Start button's right-click menu. Takes effect at next sign-in.
    # Terminal (Win+X), the Start menu search box and File Explorer's address
    # bar can still run commands, and newer variants of the trick use them, so
    # this cuts the risk without removing it.
    $explorerPolicy = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    Set-RegistryValue -Path $explorerPolicy -Name 'NoRun' -Value 1 -Description 'Disable the Run dialog (Win+R)'

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
        if (-not $ps2 -or "$($ps2.State)" -notlike 'Enable*') {
            Write-Host "  [Feature] PowerShell 2.0 already removed" -ForegroundColor Green
        } else {
            $result = Disable-WindowsOptionalFeature -Online -FeatureName 'MicrosoftWindowsPowerShellV2Root' -NoRestart -ErrorAction Stop
            $note = if ($result.RestartNeeded) { ', finishes at next restart' } else { '' }
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
            if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
            foreach ($exe in $officeExes) {
                Set-ItemProperty -Path $key -Name $exe -Value 1 -Type DWord -Force
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
    # Flash was removed from Windows in 2021, so this mostly records the setting
    # CIS checks for; it would stop a document loading Flash if a copy remained.
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Office\Common\COM Compatibility' -Name 'Comment' `
        -Value 'Block all Flash activation' -Type String -Description 'Block Flash in Office documents (CIS 1.3.1)'

    # 1.3.2 Restrict legacy JScript execution for Office - Enabled
    # Stops Office's web content from running the old JScript engine
    # (jscript.dll) that attackers exploit; 69632 (0x11000) blocks it in the
    # Internet and Restricted Sites zones.
    $jscriptPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_RESTRICT_LEGACY_JSCRIPT_PER_SECURITY_ZONE'
    if (-not (Test-Path $jscriptPath)) { New-Item -Path $jscriptPath -Force | Out-Null }
    foreach ($exe in $officeExes) {
        Set-ItemProperty -Path $jscriptPath -Name $exe -Value 69632 -Type DWord -Force
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
                    if (Test-Path $key) { Remove-ItemProperty -Path $key -Name $s[1] -ErrorAction SilentlyContinue }
                } else {
                    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
                    $type = if ($s[2] -is [string]) { 'String' } else { 'DWord' }
                    Set-ItemProperty -Path $key -Name $s[1] -Value $s[2] -Type $type -Force
                }
                $done++
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
        Remove-ItemProperty -Path $key -Name 'NeverShowExt' -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $key -Name 'AlwaysShowExt' -Value '' -Type String -Force
    }
    Write-Host "  [Explorer] .lnk, .url and .pif extensions always shown" -ForegroundColor Green

    # Show every file's extension, for every user (Explorer's "File name
    # extensions"), so "Invoice.pdf.exe" can't pass as a PDF either.
    Invoke-InEachUserHive {
        param($root, $label)
        try {
            $key = "$root\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
            Set-ItemProperty -Path $key -Name 'HideFileExt' -Value 0 -Type DWord -Force
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
        Set-ItemProperty -Path $htaCommand -Name '(default)' -Value '"%SystemRoot%\System32\notepad.exe" "%1"' -Type ExpandString -Force
        Write-Host "  [Explorer] .hta files open in Notepad instead of running" -ForegroundColor Green
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
                    Write-Fail "[DEP] bcdedit couldn't change DEP (exit $LASTEXITCODE); still $nxNow"
                } else {
                    Write-Host "  [DEP] $nxNow -> OptOut: on for all programs after the next restart" -ForegroundColor Green
                }
            }
        }
    }
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

        foreach ($app in $ControlledFolderAllowedApps) {
            try {
                Add-MpPreference -ControlledFolderAccessAllowedApplications $app -ErrorAction Stop
                Write-Host "  [Defender] Controlled folder access allows $app" -ForegroundColor Green
            } catch {
                Write-Fail "[Defender] Couldn't allow $app in Controlled folder access: $($_.Exception.Message)"
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
    $script:HistoryFile = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Defender Protection History.txt'
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
        Set-Content -Path $script:HistoryFile -Value $report -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Controlled folder access (Section 10) blocks PowerShell writing to the Desktop
        $fallback = Join-Path $LogDir 'Defender Protection History.txt'
        Write-Host "  Couldn't write $script:HistoryFile ($($_.Exception.Message)); using $fallback" -ForegroundColor Yellow
        $script:HistoryFile = $fallback
        try {
            Set-Content -Path $script:HistoryFile -Value $report -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Fail "[History] Couldn't write ${script:HistoryFile}: $($_.Exception.Message)"
            $script:HistoryFile = $null
            return
        }
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
        $shortcuts++
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
Get-ChildItem -LiteralPath $LogDir -Filter 'dailyrunme-*.log' |
    Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) |
    Remove-Item -Force
$transcript = Join-Path $LogDir "dailyrunme-$(Get-Date -Format yyyyMMdd-HHmmss).log"
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
    # Signatures first, so everything after runs with Defender up to date
    Invoke-Step 'patchmssigs' { Update-DefenderSignature }

    # Hardening, before anything is installed
    Invoke-Step 'cis-chrome' { Set-ChromeHardening }
    Invoke-Step 'cis-passwords' { Set-PasswordPolicy }
    Invoke-Step 'cis-services' { Disable-UnneededService }
    Invoke-Step 'cis-registry' { Set-SecurityRegistry }
    Invoke-Step 'dns' { Set-SecureDns }
    Invoke-Step 'scriptprotect' { Set-ScriptProtection }
    Invoke-Step 'cis-office' { Set-OfficeHardening }
    Invoke-Step 'lnkprotect' { Set-ShortcutProtection }
    Invoke-Step 'dep' { Enable-Dep }
    Invoke-Step 'defendersettings' { Set-DefenderSetting }

    # Updates, the background scan, then the checks
    Invoke-Step 'patchchoco' { Update-ChocolateyPackage }
    Invoke-Step 'patchmsstore' { Update-StoreApp }
    Invoke-Step 'patchwinget' { Update-WingetPackage }
    Invoke-Step 'mywinvscan' { Start-DefenderScan }
    Invoke-Step 'winhealthcheck' { Test-WindowsHealth }
    Invoke-Step 'windiskcheck' { Test-SystemDisk }
    Invoke-Step 'mywinprocsigs' { Find-UnsignedProcess; Find-LolbasCopy }
    Invoke-Step 'winstartupcheck' { Test-StartupEntry }
    Invoke-Step 'winmodcheck' { Test-DriverSignature }

    # Last, so it includes anything the steps above set off
    Invoke-Step 'protectionhistory' { Save-ProtectionHistory }

    Write-Banner 'dailyrunme summary' '#' Cyan
    foreach ($n in $script:Notes) { Write-Host "NOTE: $n" -ForegroundColor Yellow }
    foreach ($f in $script:Failures) { Write-Host "FAIL: $f" -ForegroundColor Red }
    if ($script:Failures.Count -eq 0) { Write-Host 'All steps finished' -ForegroundColor Green }
    Write-Host 'Restart Chrome for its policies (or chrome://policy > Reload policies), and'
    Write-Host 'restart Windows to finish service, DEP and PowerShell 2.0 changes.'
    if ($script:HistoryFile) { Write-Host "Protection history: $script:HistoryFile" }
    Write-Host "Log: $transcript"
} finally {
    if ($consoleEncoding) {
        try { [Console]::OutputEncoding = $consoleEncoding } catch { Write-Verbose 'no console' }
    }
    Stop-Transcript | Out-Null
}

# Last of all, so the window opens once the script has nothing left to do
if ($script:HistoryFile) {
    Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$script:HistoryFile`""
}

if ($script:Failures.Count -gt 0) { exit 1 }
exit 0
