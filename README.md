# HomeNetAudit

A SwiftUI iOS/iPadOS app for auditing the security posture of **your own**
home Wi‑Fi router and IoT devices.

> ⚠️ **Authorized use only.** Only scan networks and devices you own or have
> explicit written permission to test. Port scanning and credential checks on
> networks you don't control may be illegal in your jurisdiction. The app shows
> a consent gate on first launch for this reason.

## What it does (and what it honestly can't)

iOS is heavily sandboxed. There are **no raw sockets**, so there is no ICMP
ping, no ARP table access, and no packet crafting. HomeNetAudit works entirely
within what Apple's `Network.framework` allows, which is still plenty for a
real assessment of a home network:

| Capability | How | Status |
|---|---|---|
| Local subnet detection | `getifaddrs` on `en0` | ✅ |
| Host discovery | TCP connect sweep (open **or** refused ⇒ host up) | ✅ |
| Bonjour / mDNS enumeration | `NWBrowser` | ✅ |
| TCP port scan | `NWConnection` connect scan | ✅ |
| Service / banner fingerprint | Light banner grab + HTTP headers | ✅ |
| Admin interface detection | HTTP/HTTPS probing | ✅ |
| TLS inspection | `sec_protocol` metadata (version, self‑signed) | ✅ |
| UPnP / SSDP exposure | SSDP multicast query | ✅ |
| Known‑default credential check | Opt‑in, dictionary-based, your gear only | ✅ |
| ICMP ping / ARP / packet capture | — | ❌ Not possible on stock iOS |

Checks are **passive-to-light-touch**: the app connects to services and reads
what they volunteer. It does not exploit vulnerabilities or attempt to pivot.

## Build

This project uses [XcodeGen](https://github.com/yonki/XcodeGen) so the repo
stays free of a huge `.pbxproj`.

```bash
brew install xcodegen
cd wifi-scanner
xcodegen generate
open HomeNetAudit.xcodeproj
```

Then set your development team in **Signing & Capabilities** and run on a
device (the simulator can't reach your LAN the same way; use a real iPhone/iPad
joined to the Wi‑Fi you want to audit).

### Required Info.plist keys (already configured)

- `NSLocalNetworkUsageDescription` — iOS 14+ gates all local network access.
- `NSBonjourServices` — the mDNS service types we browse for.

Without these, iOS silently drops local-network connections.

## Project layout

```
Sources/HomeNetAudit/
  App/            App entry point + first-run consent gate
  Models/         Device, PortInfo, Finding, Severity
  Networking/     LocalNetwork, TCPProbe, HostDiscovery, PortScanner,
                  ServiceFingerprinter, BonjourBrowser, SSDPProbe
  Audit/          VulnerabilityRules, AuditEngine, default-creds dictionary
  ViewModels/     ScanViewModel
  Views/          ContentView, DeviceDetailView, FindingsView
  Resources/      Info.plist
```

## Roadmap ideas

- Export reports as PDF/JSON (share sheet).
- Scheduled re-scans + diff ("what changed on my network").
- CVE lookup by fingerprinted firmware (requires a network data source).
- Wi‑Fi encryption check (WPA2/WPA3) — limited by iOS APIs, best-effort via
  `NEHotspotNetwork` with the Hotspot entitlement.
