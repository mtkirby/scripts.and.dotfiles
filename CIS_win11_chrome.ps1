<#
.SYNOPSIS
    CIS Hardening Script for Google Chrome Benchmark v3.0.0 and Microsoft Windows 11 Stand-alone Benchmark v5.0.0

.DESCRIPTION
    Implements a subset of high-impact, automatable recommendations from:
    - CIS Google Chrome Benchmark v3.0.0 (01-29-2024)
    - CIS Microsoft Windows 11 Stand-alone Benchmark v5.0.0 (03-25-2026)

    Focuses on registry policies for Chrome, local password/account policies, and disabling unnecessary services.
    Each setting includes a comment explaining its purpose based on the CIS recommendation.

.NOTES
    - Must be run as Administrator.
    - Chrome policies are applied via registry (HKLM\SOFTWARE\Policies\Google\Chrome).
      Requires Chrome Enterprise / policy support. Verify with chrome://policy/
    - Windows settings target stand-alone systems. For domain environments, use Group Policy.
    - Test thoroughly. Some settings (especially Level 2) reduce functionality.
    - This is NOT a complete CIS compliance implementation. Many recommendations are Manual,
      environment-specific, or require additional tooling (e.g., secedit for full security options,
      auditpol for advanced audit policy).
    - Backup the system / registry before running.
    - Restart Chrome (and ideally the system) after applying Chrome policies.

.EXAMPLE
    .\CIS_Hardening_Script.ps1
#>

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== CIS Hardening Script Starting ===" -ForegroundColor Cyan
Write-Host "Chrome Benchmark v3.0.0 + Windows 11 Stand-alone Benchmark v5.0.0" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------

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

function Disable-ServiceIfExists {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Description
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Write-Host "  [Service] Disabled $Name  # $Description" -ForegroundColor Green
    } else {
        Write-Host "  [Service] $Name not present (already remediated or not installed)" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------
# SECTION 1: Google Chrome Policies (CIS Chrome Benchmark v3.0.0)
# Most of these map directly to registry values under
# HKLM\SOFTWARE\Policies\Google\Chrome
# ---------------------------------------------------------------

Write-Host "`n=== Applying Google Chrome CIS Recommendations ===" -ForegroundColor Yellow

# 1.1.1 Cross-origin HTTP Authentication prompts - Disabled
# Prevents third-party content from triggering HTTP auth dialogs (phishing mitigation).
Set-ChromePolicy -Name 'AllowCrossOriginAuthPrompt' -Value 0 -Description 'Disable cross-origin HTTP authentication prompts (anti-phishing)'

# 1.2.2 Safe Browsing Protection Level - Standard or higher
# Enables Safe Browsing in standard mode (or enhanced). Protects against malicious sites/downloads.
Set-ChromePolicy -Name 'SafeBrowsingProtectionLevel' -Value 1 -Description 'Enable Safe Browsing (standard mode)'

# 1.3 Allow Google Cast to connect to Cast devices on all IP addresses - Disabled
# Restricts Cast to private IP addresses only (reduces exposure of media).
Set-ChromePolicy -Name 'MediaRouterCastAllowAllIPs' -Value 0 -Description 'Restrict Google Cast to private IPs only'

# 1.4 Allow queries to a Google time service - Enabled
# Helps with accurate certificate validation via network time.
Set-ChromePolicy -Name 'BrowserNetworkTimeQueriesEnabled' -Value 1 -Description 'Enable network time queries for certificate validation'

# 1.5 Allow the audio sandbox to run - Enabled
# Sandboxes audio processes to limit exploit impact.
Set-ChromePolicy -Name 'AudioSandboxEnabled' -Value 1 -Description 'Enable audio process sandboxing'

# 1.6 Ask where to save each file before downloading - Enabled
# Forces user confirmation before downloads (reduces drive-by malware).
Set-ChromePolicy -Name 'PromptForDownloadLocation' -Value 1 -Description 'Prompt for download location'

# 1.7 Continue running background apps when Google Chrome is closed - Disabled
# Prevents background processes after browser close (reduces persistence/attack surface).
Set-ChromePolicy -Name 'BackgroundModeEnabled' -Value 0 -Description 'Disable background apps when Chrome is closed'

# 1.13 Disable saving browser history - Disabled (i.e. allow history)
# Note: the policy "Disable saving browser history" set to Disabled means history IS saved.
# Keeping history aids forensics.
Set-ChromePolicy -Name 'SavingBrowserHistoryDisabled' -Value 0 -Description 'Allow browser history (aids forensics)'

# 1.14 DNS interception checks enabled - Enabled
# Detects DNS interception (common in some enterprise proxies or malware).
Set-ChromePolicy -Name 'DnsInterceptionChecksEnabled' -Value 1 -Description 'Enable DNS interception checks'

# 1.15 Enable component updates in Google Chrome - Enabled
# Ensures component updates (e.g. Widevine, recovery) stay current.
Set-ChromePolicy -Name 'ComponentUpdatesEnabled' -Value 1 -Description 'Enable component updates'

# 1.16 Enable globally scoped HTTP auth cache - Disabled
# Limits HTTP auth credential scope (reduces credential reuse risk).
Set-ChromePolicy -Name 'GloballyScopeHTTPAuthCacheEnabled' -Value 0 -Description 'Disable globally scoped HTTP auth cache'

# 1.18 Enable security warnings for command-line flags - Enabled
# Warns users when potentially dangerous flags are used.
Set-ChromePolicy -Name 'CommandLineFlagSecurityWarningsEnabled' -Value 1 -Description 'Enable security warnings for command-line flags'

# 1.19 Enable third party software injection blocking - Enabled
# Blocks third-party DLL injection into Chrome processes.
Set-ChromePolicy -Name 'ThirdPartyBlockingEnabled' -Value 1 -Description 'Block third-party software injection'

# 2.3.1 Blocks external extensions from being installed - Enabled
# Prevents sideloading of extensions outside the Chrome Web Store / enterprise policy.
Set-ChromePolicy -Name 'BlockExternalExtensions' -Value 1 -Description 'Block external (sideloaded) extensions'

# 2.11 Allow download restrictions - Block malicious downloads
# Blocks downloads flagged as malicious by Safe Browsing.
Set-ChromePolicy -Name 'DownloadRestrictions' -Value 4 -Description 'Block malicious downloads'

# 2.12 Allow proceeding from the SSL warning page - Disabled
# Prevents users from bypassing SSL/TLS certificate warnings.
Set-ChromePolicy -Name 'SSLErrorOverrideAllowed' -Value 0 -Description 'Disallow proceeding past SSL warnings'

# 2.13 Disable proceeding from the Safe Browsing warning page - Enabled
# Prevents users from bypassing Safe Browsing interstitial warnings.
Set-ChromePolicy -Name 'DisableSafeBrowsingProceedAnyway' -Value 1 -Description 'Prevent bypassing Safe Browsing warnings'

# 2.14 Require Site Isolation for every site - Enabled
# Isolates each site into its own process (Spectre mitigation / stronger isolation).
Set-ChromePolicy -Name 'SitePerProcess' -Value 1 -Description 'Enable Site Isolation for every site'

# 2.22 Enable TLS Encrypted ClientHello - Enabled
# Enables Encrypted Client Hello (ECH) for better privacy against network observers.
Set-ChromePolicy -Name 'EncryptedClientHelloEnabled' -Value 1 -Description 'Enable TLS Encrypted ClientHello (ECH)'

# 2.28 Enable automatic HTTPS upgrades - Enabled
# Automatically upgrades HTTP navigations to HTTPS when possible.
Set-ChromePolicy -Name 'HttpsUpgradesEnabled' -Value 1 -Description 'Enable automatic HTTPS upgrades'

# 2.30 Enable Renderer App Container - Enabled
# Runs renderer processes in an App Container for stronger sandboxing.
Set-ChromePolicy -Name 'RendererAppContainerEnabled' -Value 1 -Description 'Enable Renderer App Container'

# 3.1.2 Default geolocation setting - Do not allow
# Blocks sites from accessing physical location by default.
Set-ChromePolicy -Name 'DefaultGeolocationSetting' -Value 2 -Description 'Block geolocation by default'

# 3.2.1 Enable Google Cast - Disabled
# Disables Cast entirely (reduces attack surface and data exposure).
Set-ChromePolicy -Name 'EnableMediaRouter' -Value 0 -Description 'Disable Google Cast'

# 3.3 Allow websites to query for available payment methods - Disabled
# Blocks Payment Request API (reduces fingerprinting / data exposure).
Set-ChromePolicy -Name 'PaymentMethodQueryEnabled' -Value 0 -Description 'Disable payment method queries'

# 3.4 Block third party cookies - Enabled
# Blocks third-party cookies (privacy / tracking protection).
Set-ChromePolicy -Name 'BlockThirdPartyCookies' -Value 1 -Description 'Block third-party cookies'

# 3.7 Disable synchronization of data with Google - Enabled
# Prevents syncing of data (bookmarks, passwords, etc.) to Google accounts.
Set-ChromePolicy -Name 'SyncDisabled' -Value 1 -Description 'Disable Google account sync'

# 3.12 Enable reporting of usage and crash-related data - Disabled
# Disables telemetry / crash reporting to Google.
Set-ChromePolicy -Name 'MetricsReportingEnabled' -Value 0 -Description 'Disable usage and crash reporting'

# 4.9 Enable AutoFill for credit cards - Disabled
# Disables credit card autofill (reduces exposure of payment data).
Set-ChromePolicy -Name 'AutofillCreditCardEnabled' -Value 0 -Description 'Disable credit card autofill'

# 5.2 Incognito mode availability - Disabled
# Disables Incognito mode (reduces ability to hide browsing activity in managed environments).
Set-ChromePolicy -Name 'IncognitoModeAvailability' -Value 1 -Description 'Disable Incognito mode'

Write-Host "Chrome policies applied. Verify at chrome://policy/ after restarting Chrome." -ForegroundColor Cyan

# ---------------------------------------------------------------
# SECTION 2: Windows 11 Stand-alone Password & Account Policies
# CIS Windows 11 Benchmark v5.0.0 - Section 1
# ---------------------------------------------------------------

Write-Host "`n=== Applying Windows 11 Password & Lockout Policies ===" -ForegroundColor Yellow

# 1.1.1 Enforce password history - 24 or more
# 1.1.2 Maximum password age - 365 or fewer, but not 0
# 1.1.3 Minimum password age - 1 or more days
# 1.1.4 Minimum password length - 14 or more
# These are set via net accounts (local accounts).

net accounts /minpwlen:14 /maxpwage:365 /minpwage:1 /uniquepw:24 | Out-Null
Write-Host "  [Password] History=24, MaxAge=365, MinAge=1, MinLength=14" -ForegroundColor Green
Write-Host "    # Reduces password reuse, forces periodic changes, and increases strength" -ForegroundColor DarkGray

# 1.1.5 Password must meet complexity requirements - Enabled
# 1.1.7 Store passwords using reversible encryption - Disabled
# These require secedit or Local Security Policy. Using a temporary INF.

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
secedit /configure /db $sdbPath /cfg $infPath /areas SECURITYPOLICY | Out-Null
Remove-Item $infPath, $sdbPath -ErrorAction SilentlyContinue
Write-Host "  [Password] Complexity Enabled, Reversible encryption Disabled" -ForegroundColor Green
Write-Host "    # Requires mixed character types; prevents storing passwords in reversible form" -ForegroundColor DarkGray

# 1.2.1 Account lockout duration - 15 or more minutes
# 1.2.2 Account lockout threshold - 5 or fewer (not 0)
# 1.2.4 Reset account lockout counter after - 15 or more minutes
net accounts /lockoutthreshold:5 /lockoutduration:15 /lockoutwindow:15 | Out-Null
Write-Host "  [Lockout] Threshold=5, Duration=15 min, Reset=15 min" -ForegroundColor Green
Write-Host "    # Limits brute-force attempts while allowing reasonable recovery" -ForegroundColor DarkGray

# ---------------------------------------------------------------
# SECTION 3: Windows 11 System Services to Disable
# CIS Windows 11 Benchmark v5.0.0 - Section 5 (selected high-value items)
# ---------------------------------------------------------------

Write-Host "`n=== Disabling Unnecessary Windows Services ===" -ForegroundColor Yellow

Disable-ServiceIfExists -Name 'BTAGService' -Description 'Bluetooth Audio Gateway (L2 - reduces wireless attack surface)'
Disable-ServiceIfExists -Name 'bthserv' -Description 'Bluetooth Support Service (L2 - reduces wireless attack surface)'
Disable-ServiceIfExists -Name 'Browser' -Description 'Computer Browser (legacy NetBIOS service - L1)'
Disable-ServiceIfExists -Name 'MapsBroker' -Description 'Downloaded Maps Manager (L2 - reduces location data exposure)'
Disable-ServiceIfExists -Name 'GameInputSvc' -Description 'GameInput Service (L2 - reduces DMA input capture risk)'
Disable-ServiceIfExists -Name 'lfsvc' -Description 'Geolocation Service (L2 - reduces location tracking)'
Disable-ServiceIfExists -Name 'RemoteRegistry' -Description 'Remote Registry (L1 - reduces remote attack surface)'
Disable-ServiceIfExists -Name 'RemoteAccess' -Description 'Routing and Remote Access (L1)'
Disable-ServiceIfExists -Name 'SSDPSRV' -Description 'SSDP Discovery (L1 - reduces network discovery)'
Disable-ServiceIfExists -Name 'upnphost' -Description 'UPnP Device Host (L1 - reduces network discovery)'
Disable-ServiceIfExists -Name 'XblAuthManager' -Description 'Xbox Live Auth Manager (L2)'
Disable-ServiceIfExists -Name 'XblGameSave' -Description 'Xbox Live Game Save (L2)'
Disable-ServiceIfExists -Name 'XboxNetApiSvc' -Description 'Xbox Live Networking (L2)'

# ---------------------------------------------------------------
# SECTION 4: Additional High-Value Windows Registry Settings
# (selected from Administrative Templates / Security Options)
# ---------------------------------------------------------------

Write-Host "`n=== Applying Additional Windows Security Registry Settings ===" -ForegroundColor Yellow

# Example: Disable AutoAdminLogon (MSS)
$mssPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
if (-not (Test-Path $mssPath)) { New-Item -Path $mssPath -Force | Out-Null }
Set-ItemProperty -Path $mssPath -Name 'AutoAdminLogon' -Value 0 -Type DWord -Force
Write-Host "  [Registry] AutoAdminLogon = 0  # Disable automatic logon (MSS)" -ForegroundColor Green

# WDigest Authentication - Disabled (reduces credential theft risk)
$wdigestPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'
if (-not (Test-Path $wdigestPath)) { New-Item -Path $wdigestPath -Force | Out-Null }
Set-ItemProperty -Path $wdigestPath -Name 'UseLogonCredential' -Value 0 -Type DWord -Force
Write-Host "  [Registry] WDigest UseLogonCredential = 0  # Disable WDigest (reduces credential exposure in memory)" -ForegroundColor Green

Write-Host "`n=== CIS Hardening Script Complete ===" -ForegroundColor Cyan
Write-Host "Recommendations applied. Please:" -ForegroundColor White
Write-Host "  1. Restart Google Chrome and verify policies at chrome://policy/" -ForegroundColor White
Write-Host "  2. Restart the system for full Windows service/registry changes to take effect" -ForegroundColor White
Write-Host "  3. Review the full CIS PDFs for remaining Manual recommendations and environment-specific exceptions" -ForegroundColor White
Write-Host "  4. Use official CIS tools (CIS-CAT, Build Kits) for comprehensive compliance scanning" -ForegroundColor White
Write-Host ""
Write-Host "Script finished successfully." -ForegroundColor Green
