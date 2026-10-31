# Personal Windows 11 + Chrome Security Checklist

A practical checklist for a personal (non-enterprise) PC running Windows 11 and Google Chrome.  
These recommendations focus on meaningful security and privacy improvements without excessive restrictions.

---

## Windows 11

### Accounts & Access
- [ ] Use a **standard (non-administrator)** account for daily use
- [ ] Keep a separate administrator account for system changes
- [ ] Disable the Guest account if it is enabled
- [ ] Review and remove unused local accounts

### Encryption & Device Protection
- [ ] Enable **BitLocker** (or Device Encryption on Windows 11 Home)
- [ ] Confirm BitLocker is active and the recovery key is safely stored

### Microsoft Defender & Security
- [ ] Real-time protection is enabled
- [ ] Cloud-delivered protection is enabled
- [ ] Automatic sample submission is enabled (or set to your preference)
- [ ] **Controlled Folder Access** (ransomware protection) is enabled
- [ ] **Memory Integrity** (Core isolation) is enabled
- [ ] SmartScreen is enabled for apps and files
- [ ] SmartScreen is enabled for Microsoft Edge (and Chrome if applicable)

### Firewall & Network
- [ ] Windows Firewall is on for Domain, Private, and Public profiles
- [ ] Remote Desktop is disabled (unless you specifically need it)
- [ ] Remote Assistance is disabled (unless you specifically need it)

### Updates
- [ ] Windows Update is set to automatic
- [ ] Optional updates are reviewed periodically
- [ ] Microsoft Store apps are kept up to date
- [ ] Third-party applications (including Chrome) are updated regularly

### Privacy
- [ ] Location services disabled or restricted to specific apps
- [ ] Advertising ID is turned off
- [ ] Activity history is disabled
- [ ] Diagnostic data is set to the minimum acceptable level
- [ ] App permissions (camera, microphone, contacts, etc.) are reviewed

### System Hygiene
- [ ] Unnecessary startup programs are disabled (Task Manager → Startup)
- [ ] Optional Windows features you don’t use are removed (e.g., SMB 1.0, IIS, legacy media components)
- [ ] Unneeded services that increase attack surface are disabled or set to Manual
- [ ] Temporary files and downloads folder are periodically cleaned

---

## Google Chrome

### Core Security Settings
- [ ] **Enhanced Safe Browsing** is enabled (`chrome://settings/security`)
- [ ] **HTTPS-Only Mode** is enabled
- [ ] Safe Browsing is not set to “No protection”
- [ ] Automatic updates for Chrome are enabled

### Privacy & Permissions
- [ ] Site permissions reviewed (`chrome://settings/content`)
- [ ] Camera set to “Ask” or “Block” by default
- [ ] Microphone set to “Ask” or “Block” by default
- [ ] Location set to “Ask” or “Block” by default
- [ ] Notifications set to “Ask” or “Block” by default
- [ ] Clipboard access is restricted
- [ ] Third-party cookies are blocked
- [ ] “Offer to save passwords” is disabled if using an external password manager
- [ ] Chrome Sync is intentionally enabled or disabled (with strong Google account + 2FA if enabled)

### Extensions & Content
- [ ] Only necessary extensions are installed
- [ ] All extensions are from the Chrome Web Store
- [ ] Unused or untrusted extensions have been removed
- [ ] uBlock Origin (or equivalent reputable blocker) is installed if desired
- [ ] Experimental flags (`chrome://flags`) are left at defaults unless fully understood

### Data & Sessions
- [ ] Decision made on “Clear cookies and site data when you close all windows”
- [ ] Download location is set intentionally (prompt or a specific folder)
- [ ] Autofill for credit cards is disabled
- [ ] Autofill for addresses is reviewed and limited if not needed

---

## Broader Security Hygiene

- [ ] Multi-factor authentication (MFA/2FA) is enabled on the Microsoft account
- [ ] Multi-factor authentication is enabled on the Google account (if used)
- [ ] A reputable password manager is in use
- [ ] Unique, strong passwords are used for important accounts
- [ ] Regular backups are configured (File History, OneDrive, external drive, or equivalent)
- [ ] At least one offline/offsite backup copy exists
- [ ] Caution is practiced with email attachments and unexpected downloads
- [ ] Public Wi-Fi is used with a VPN when handling sensitive activity

---

## Quick Verification Commands / Locations

| Item | How to Check |
|------|----------------|
| BitLocker status | `manage-bde -status` or Settings → Privacy & security → Device encryption |
| Defender status | Windows Security → Virus & threat protection |
| Firewall status | Windows Security → Firewall & network protection |
| Memory Integrity | Windows Security → Device security → Core isolation |
| Controlled Folder Access | Windows Security → Virus & threat protection → Ransomware protection |
| Chrome security | `chrome://settings/security` |
| Chrome policies (if set) | `chrome://policy/` |
| Startup apps | Task Manager → Startup apps |
| Optional features | Settings → Apps → Optional features |

---

*Checklist created for personal use. Adjust based on your threat model and workflow. Enterprise/CIS Level 2 settings may be more restrictive than needed on a home PC.*
