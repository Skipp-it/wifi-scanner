# HANDOFF — HomeNetAudit (read me first on the Mac)

This file exists so a fresh Claude Code session (e.g. on macOS) can pick up exactly where
the Windows session left off. **Claude Code does not sync conversation history across
machines — this repo + this file ARE the context.**

## What the project is

HomeNetAudit: a SwiftUI iOS/iPadOS app that audits the owner's **own** Wi‑Fi router and
IoT devices for security weaknesses. Authorized-use only (there's a non-skippable consent
gate on first launch). Everything works inside Apple's `Network.framework` sandbox — no
raw sockets, so no ICMP/ARP/packet capture; it uses TCP connect scans, Bonjour/mDNS,
service/TLS fingerprinting, and an opt-in default-credential check.

## How to build (do this first on the Mac)

```bash
brew install xcodegen
cd wifi-scanner
xcodegen generate
open HomeNetAudit.xcodeproj   # set a signing team, run on a REAL device on your home Wi‑Fi
```
The code has **never been compiled against the iOS SDK** (it was written on Windows). The
first real task is to build it and fix any SDK nits.

## Current state

- **Shipped (committed):** full scan pipeline, device inventory, findings with remediation,
  consent gate, scan history persistence (`ScanStore`), scan-to-scan diff (`ScanDiff`),
  security score (`ScanSnapshot.securityScore`), PDF/JSON export (`ReportExporter`).
- **Phase 0 of the current plan is DONE:** the scan pipeline was extracted from
  `ScanViewModel.runScan()` into `Sources/HomeNetAudit/Services/ScanService.swift`, and the
  view model now calls it. This is the foundation the remaining phases build on.

## Remaining work — see `PLAN.md` in this repo (full detail)

The user approved all four, in this order:
1. **Phase 1 — CI build on macOS** (`.github/workflows/ios-build.yml`): xcodegen + xcodebuild
   compile check. Highest priority: it's how we verify the code compiles.
2. **Phase 2 — Security Score UI** (`Views/ScoreGaugeView.swift` + `ContentView` + a
   shareable score card via `ImageRenderer`). Score math already exists.
3. **Phase 3 — Continuous monitoring** (`Monitoring/BackgroundScanner.swift` +
   `NotificationManager.swift`, `BGAppRefreshTask`, local notifications; Info.plist +
   project.yml background-mode keys). Reuses `ScanService`.
4. **Phase 4 — CVE intelligence** (`Audit/CVELookup.swift` + `Persistence/CVECache.swift`):
   opt-in NVD 2.0 API lookups by fingerprinted product/version, no custom backend yet.

## Suggested first prompt for the Mac session

> Read HANDOFF.md, PLAN.md, and CLAUDE.md. Build the project with xcodegen + xcodebuild,
> fix any compile errors from the Windows-authored code, then continue the approved plan
> starting at Phase 1 (CI). Commit each phase separately.

## Monetization direction (context for product decisions)

Free tier: scan + security score (shareable). Subscription trigger: continuous monitoring +
push alerts. Retention: CVE intelligence. Pro/B2B: multi-network + branded compliance PDFs.
The CVE phase is the natural backend/paid boundary.
