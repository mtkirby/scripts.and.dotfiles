**CIS Google Android Benchmark v1.6.0 — Detailed Checklist**  
*(Tested against Android 16; this is the final release of this benchmark. CIS recommends migrating to more recent, supported guidance when available. All items are Manual.)*

Use this as a practical audit/remediation checklist. Level 1 items are the practical baseline; Level 2 extends them for higher-security environments. Paths may vary slightly by OEM/skin (Pixel vs. Samsung, etc.).

### 1. Android OS Security Settings

- [ ] **1.1 Device firmware / security patch level is current** (Level 1)  
  Settings → System → Advanced → System update. Apply any available updates. Latest security patch reduces remote exploitation risk.

- [ ] **1.2 Screen Lock is Enabled** (Pattern / PIN / Password) (Level 1)  
  Settings → Security → Screen lock. Set a complex credential. Default is unset.

- [ ] **1.3 Make pattern visible is Disabled** (if using Pattern lock) (Level 1)  
  Settings → Security → Gear next to Screen lock → Make pattern visible = OFF. Prevents shoulder surfing.

- [ ] **1.4 Automatically Lock is set to Immediately** (Level 1)  
  Settings → Security → Gear next to Screen lock → Automatically lock = Immediately. Default is often ~5 seconds.

- [ ] **1.5 Power button instantly locks is Enabled** (Level 1)  
  Settings → Security → Gear next to Screen lock. Should be ON (often default).

- [ ] **1.6 Lock Screen Message is configured** (Level 1)  
  Settings → Display → Advanced → Lock screen display → Lock screen message. Useful for ownership/contact info (visible without unlock).

- [ ] **1.7 Do not connect to untrusted Wi-Fi networks** (Level 2)  
  Settings → Network & internet. Prefer Off or only trusted networks. Use VPN on public Wi-Fi if necessary.

- [ ] **1.8 Show passwords is Disabled** (Level 2)  
  Settings → Privacy → Show passwords = OFF. Reduces shoulder-surfing risk.

- [ ] **1.9 Developer Options is Disabled** (Level 1)  
  Settings → System → Advanced → Developer options = OFF. Prevents USB debugging and other advanced attack surfaces.

- [ ] **1.10 Install unknown apps is Disabled for all apps** (Level 1)  
  Settings → Apps & notifications → Advanced → Special app access → Install unknown apps. All sources should show “Not allowed.”

- [ ] **1.11 Device is not rooted** (Level 1)  
  Use a root checker or manufacturer guidance. Rooting voids protections and complicates updates; unroot if needed (often requires factory reset).

- [ ] **1.12 Smart Lock is Disabled** (Level 2)  
  Settings → Security → Advanced → Trust agents → Smart Lock (Google) = OFF. Prevents automatic unlock based on location/voice/etc.

- [ ] **1.13 Find My Device is Enabled** (Level 2)  
  Settings → Security → Find My Device = ON. Enables remote locate/lock/erase (note location tracking implication).

- [ ] **1.14 Use network-provided time and time zone are Enabled** (Level 1)  
  Settings → System → Date & time. Both toggles ON (usually default). Helps forensics and log accuracy.

- [ ] **1.15 Remotely locate this device is Enabled** (Level 1)  
  Settings → Google → Security → Find My Device → Remotely locate this device = ON.

- [ ] **1.16 Allow remote lock and erase is Enabled** (Level 1)  
  Settings → Security → Device admin apps → Find My Device active and permitted.

- [ ] **1.17 Scan device for security threats (Play Protect) is Enabled** (Level 1)  
  Settings → Google → Security → Google Play Protect → Settings → Scan device for security threats = ON.

- [ ] **1.18 Improve harmful app detection is Enabled** (Level 1)  
  Same Play Protect area → Improve harmful app detection = ON. Sends anonymous data to improve detection.

- [ ] **1.19 Ask for unlock pattern/PIN/password before unpinning is Enabled** (if using screen pinning) (Level 1)  
  Settings → Security → Advanced → Screen pinning. If pinning is used, require authentication to unpin.

- [ ] **1.20 Screen timeout is set to 2 minutes** (Level 1)  
  Settings → Display → Advanced → Screen timeout = 2 minutes.

- [ ] **1.21 Wi-Fi assistant is Disabled** (Level 1; Pixel/Nexus-specific where available)  
  Settings → Google → Networking → Wi-Fi assistant = OFF. Avoids automatic open-network connections.

- [ ] **1.22 Device apps are up to date** (Level 1)  
  Play Store → Menu → My apps & games → Update All. Prefer auto-update on trusted networks.

- [ ] **1.23 Add users from lock screen is Disabled** (Level 1)  
  Settings → System → Advanced → Multiple users → Add users from lock screen = OFF.

- [ ] **1.24 No Guest profiles exist** (Level 1)  
  Settings → System → Advanced → Multiple users. Remove any guest profiles.

- [ ] **1.25 App permissions reviewed periodically** (Level 1)  
  Settings → Apps & notifications → App permissions (or See all apps). Revoke over-broad permissions; uninstall unnecessary apps.

- [ ] **1.26 Bluetooth pairing is configured / Bluetooth disabled when not needed** (Level 1)  
  Settings → Connected devices → Connection preferences → Bluetooth. Off, or only authorized paired devices.

- [ ] **1.27 No third-party keyboards installed** (Level 1)  
  Settings → Apps & notifications → See all apps. Uninstall any non-stock keyboards (keystroke risk).

- [ ] **1.28 Existing user profiles reviewed periodically** (Level 1)  
  Settings → System → Advanced → Multiple users. Delete unused profiles.

### 2. Android OS Privacy Settings

- [ ] **2.1 Lock screen notifications set to “Don’t show notifications at all”** (Level 1)  
  Settings → Apps & notifications → Notifications → Advanced → Lock screen.

- [ ] **2.2 Back up to Google Drive is Disabled** (Level 2)  
  Settings → System → Advanced → Backup → Back up to Google Drive = OFF. Avoids personal-account data exfiltration.

- [ ] **2.3 Web and App Activity is Disabled** (Level 1; primarily Pixel)  
  Settings → Privacy → Advanced → Activity controls.

- [ ] **2.4 Device Information is Disabled** (Level 1; primarily Pixel)  
  Same Activity controls area.

- [ ] **2.5 Voice & Audio Activity is Disabled** (Level 1; primarily Pixel)  
  Same Activity controls area.

- [ ] **2.6 YouTube Search History is Disabled** (Level 1; primarily Pixel)  
  Same Activity controls area.

- [ ] **2.7 YouTube Watch History is Disabled** (Level 1; primarily Pixel)  
  Same Activity controls area.

- [ ] **2.8 Google Location History is Disabled** (Level 1; primarily Pixel)  
  Same Activity controls area.

- [ ] **2.9 Opt out of Ads Personalization is Enabled** (Level 1)  
  Settings → Google → Ads → Opt out of Ads Personalization = ON.

- [ ] **2.10 Wi-Fi scanning is Disabled** (Level 1)  
  Settings → Location → Location services → Wi-Fi scanning = OFF. Reduces “evil twin” and tracking risk.

- [ ] **2.11 Bluetooth scanning is Disabled** (Level 1)  
  Settings → Location → Location services → Bluetooth scanning = OFF.

### 3. Android OS Chrome Browser Settings

- [ ] **3.1 Microphone permission is set to Ask first** (Level 1)  
  Chrome → Menu → Settings → Site settings → Microphone.

- [ ] **3.2 Location permission is set to Ask first** (Level 1)  
  Chrome → Site settings → Location.

- [ ] **3.3 Allow third-party cookies is Disabled** (Level 1)  
  Chrome → Site settings → Allow third-party cookies = off / “Allowed, except third-party.”

- [ ] **3.4 Safe Browsing is Enabled** (Level 1)  
  Chrome → Settings → Privacy → Safe Browsing checked.

- [ ] **3.5 Search and URL suggestions is Disabled** (Level 2)  
  Chrome → Settings → Privacy → Search and URL suggestions unchecked.

- [ ] **3.6 Do Not Track is Enabled** (Level 2)  
  Chrome → Settings → Privacy → Do Not Track = ON. (Note: effectiveness varies by site.)

---

### Suggested Additional / Modern Hardening Items  
*(Not in the v1.6.0 benchmark; based on current Android capabilities and common enterprise practice. Evaluate for your environment.)*

- [ ] **Stronger lock credential** — Prefer PIN ≥6 digits or complex password over pattern; disable biometric-only unlock where policy requires knowledge factor.
- [ ] **Biometric enrollment limited** — Review enrolled fingerprints/faces; remove unused ones. Consider requiring PIN after restart or after timeout.
- [ ] **Private DNS (DNS-over-TLS)** — Settings → Network & internet → Private DNS = Automatic or a trusted provider (e.g., Cloudflare, Quad9).
- [ ] **VPN always-on or per-app VPN** where corporate traffic requires it.
- [ ] **Verified Boot / Play Protect certification status** — Confirm device is not in a compromised/unlocked bootloader state.
- [ ] **USB debugging / ADB explicitly disabled** (covered by Dev Options, but re-check after any developer activity).
- [ ] **Accessibility and Notification access reviewed** — Settings → Accessibility and Apps → Special app access → Notification access. Remove untrusted apps.
- [ ] **Location permission modes** — Prefer “Approximate” or “While using the app”; deny “Always” unless required.
- [ ] **Work profile / managed profile** (if enterprise) — Isolate corporate data; enforce via MDM.
- [ ] **Disable Nearby Share / Quick Share** or restrict to contacts when not needed.
- [ ] **Auto-fill service** — Use a trusted password manager; disable Google or other untrusted autofill if policy requires.
- [ ] **Screen recording / cast / media projection permissions** reviewed and restricted.
- [ ] **Encryption confirmed** — Device should show as encrypted (file-based or full-disk); check in security settings or via `adb shell getprop ro.crypto.state` if accessible.
- [ ] **App installation from Play Store only** + periodic review of installed apps (beyond unknown sources).
- [ ] **Disable “Install unknown apps” exceptions** and monitor for sideloading attempts.
- [ ] **Battery optimization / background restrictions** for non-essential apps; allow only security/MDM apps unrestricted where needed.
- [ ] **Find My Device / remote wipe tested** periodically in a controlled way.
- [ ] **Chrome (and other browsers)**: Additional site settings (camera, sensors, JavaScript where possible), HTTPS-only mode if available, and disable password saving if using a separate manager.
- [ ] **Review Special app access** (Usage access, Device admin, VPN, etc.) for least privilege.
- [ ] **OEM-specific extras** (Samsung Knox, Xiaomi, etc.) — apply manufacturer hardening guides in addition to this baseline.

**Notes**  
- All original items are Manual; automation requires MDM/EMM or CIS-CAT-style tooling.  
- Document any exceptions with risk acceptance.  
- Test changes on a non-production device first.  
- Paths are based on the benchmark’s Android 16 testing; minor menu differences exist across devices.  

# SIM Swapping Protection

**SIM swapping** (or port-out fraud) is still a real risk. An attacker convinces your carrier to move your number to a SIM or eSIM they control, then intercepts SMS codes and takes over accounts that rely on them.

## Highest-Impact Protections

### 1. Stop Using SMS for Important 2FA and Recovery
This is the most effective step. Move email, banking, crypto, password managers, and other high-value accounts to:

- Authenticator apps (Google Authenticator, Microsoft Authenticator, Authy, 2FAS, Aegis, etc.)
- Passkeys or hardware security keys (YubiKey, etc.)

SMS should be a last-resort fallback, not the primary method.

### 2. Turn On Your Carrier’s Free Locks
These are opt-in and block unauthorized SIM/eSIM changes and number ports. Most people never enable them.

| Carrier     | Features                          | How to Enable (Approx.)                                      |
|-------------|-----------------------------------|--------------------------------------------------------------|
| **AT&T**    | Wireless Account Lock            | myAT&T app → person icon or Services → Mobile Security → Wireless Account Lock (swipe to lock). Applies to the whole account. |
| **Verizon** | SIM Protection + Number Lock     | My Verizon app → Me → Edit profile and settings → Security → turn on both for each line. |
| **T-Mobile**| SIM Protection + Port Out Protection | T-Life app: SIM Protection under Security; Port Out Protection under Manage add-ons (per line). |

These are free and required by FCC rules. Enable them on every line.

### 3. Set a Strong Unique Account PIN/Passcode
Set one with your carrier that is **not** a birthday, address number, or last 4 of SSN. Store it somewhere that doesn’t require your phone.

## Extra Layers

- Secure the carrier account itself with a strong password and non-SMS 2FA if available.
- Watch for sudden “No Service,” unexpected “SIM changed” messages, or password-reset emails you didn’t request — call the carrier immediately from another phone.
- Reduce publicly available personal data (data-broker opt-outs help make social engineering harder).
- For high-value targets (large crypto holdings, high profile, etc.): Consider specialized carriers like **Efani** (~$99/mo). It adds multi-person manual review, a mandatory 14-day port-out cooling period, and up to $5M insurance. It’s overkill for most people but meaningfully stronger than standard carrier locks.

## Priority Order for Most People

1. Move critical accounts off SMS 2FA  
2. Enable carrier SIM/port locks  
3. Set a unique carrier PIN  
4. Consider hardware keys for the most sensitive accounts  

These steps dramatically raise the difficulty of a successful attack.

# Google Fi SIM Swap Protection

**Google Fi has a free “Number Lock” feature** that blocks SIM swaps and number ports. Here’s how to enable it and the important caveats.

## Enable Number Lock (Google Fi)

1. Go to [fi.google.com](https://fi.google.com) on a web browser and sign in.
2. Under **Phone settings**, select **Privacy & security**.
3. Under **Number Lock**, click **Sign in to manage Number Lock**.
4. Re-enter your Google Account credentials.
5. Toggle **Number Lock** to **ON**.

When Number Lock is on, no one can:
- Transfer your number to another phone
- Port your number to another carrier

**Note:** This setting is only available on the website (not in the Fi app). You must turn it off yourself before you can move the number to a new device or switch carriers.

## Critical Caveat

Google Fi is tightly tied to your **Google Account**. If you lose access to that Google Account while Number Lock is on, Google Fi cannot give you the port-out information.  
So you **must** harden the Google Account first:

- Remove SMS as a 2-Step Verification method (use authenticator app, passkeys, or security keys instead).
- Add a recovery email (or recovery contact) that is **not** tied to the same phone number.
- Strongly consider enrolling in the **Advanced Protection Program** (passkeys or hardware keys required).
- Generate and securely store backup codes.

## Additional Steps

- Enable 2-Step Verification on the Google Account linked to Fi (if not already done).
- Watch for sudden loss of service or unexpected account alerts.
- If you ever need to transfer the number, temporarily turn Number Lock off, complete the transfer, then turn it back on.