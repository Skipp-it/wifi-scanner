# HomeNetAudit — Next Build Phase Plan

## Context

HomeNetAudit is a SwiftUI iOS/iPadOS app (built earlier this session) that audits the
owner's own Wi‑Fi router and IoT devices: subnet detection, TCP connect-scan discovery,
Bonjour/mDNS enumeration, port + service/TLS fingerprinting, rule-based findings, an
opt-in default-credential check, persisted scan history, scan-to-scan diff, and PDF/JSON
export. The repo is initialized (commit `028f67b`).

The user approved building **all four** next features: CI build on macOS, Continuous
monitoring, Security Score UI, and CVE intelligence. These move the app from a one-shot
utility toward the monetizable "continuous safety service" described in the roadmap.

**Key constraint:** the scan pipeline currently lives inside `ScanViewModel.runScan()`.
Three of the four features (monitoring, score UI reuse, CVE) need to invoke scanning
outside the view model. So this plan begins with a small extraction refactor, then layers
the features on top. Work is sequenced by dependency and by shipping value (free-tier hooks
first, backend-touching CVE last).

**Build caveat:** this is a Windows dev box; the code has never been compiled against the
iOS SDK. CI (Phase 1) is therefore the first priority — it becomes the compile-check for
everything that follows.

---

## Phase 0 — Refactor: extract `ScanService` (foundation)

Pull the pipeline out of `ScanViewModel` so it can run headless (background task) and be
reused by the score/CVE code.

- **New `Sources/HomeNetAudit/Services/ScanService.swift`**
  - A `struct`/`actor` with `func run(options: AuditEngine.Options, progress: (ScanProgress) -> Void) async -> ScanSnapshot?`.
  - Move the body of `ScanViewModel.runScan()` here: `LocalNetwork.current()` → `BonjourBrowser` → `HostDiscovery.discover` → per-host `AuditEngine.audit` → build `ScanSnapshot`.
  - Returns the snapshot; does NOT touch UI or persistence (caller decides).
- **Edit `ScanViewModel.swift`**: `runScan()` becomes a thin wrapper that calls
  `ScanService`, streams progress to `@Published` props, then persists via `store.save`
  and computes `lastDiff` (logic already present, just relocated to the caller side).

Reuses: everything in `Networking/`, `Audit/AuditEngine.swift`, `Models/ScanSnapshot.swift`,
`Persistence/ScanStore.swift`, `Audit/ScanDiff.swift`.

---

## Phase 1 — CI build on macOS (validates all later work)

- **New `.github/workflows/ios-build.yml`**
  - `runs-on: macos-14`; `Select Xcode` via `sudo xcode-select -s /Applications/Xcode_15.*.app`.
  - `brew install xcodegen` → `xcodegen generate`.
  - `xcodebuild -project HomeNetAudit.xcodeproj -scheme HomeNetAudit -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` (no signing needed for a compile check).
  - Trigger on `push` + `pull_request`.
- XcodeGen auto-generates a shared scheme for the `HomeNetAudit` target, so no scheme
  config change is needed.

Verification: push to GitHub; the Actions run must go green. This is the primary way we
confirm the Swift actually compiles.

---

## Phase 2 — Security Score UI (free-tier hook)

The score math already exists (`ScanSnapshot.securityScore`, `.scoreGrade`). This is
presentation only.

- **New `Sources/HomeNetAudit/Views/ScoreGaugeView.swift`**
  - Circular gauge (SwiftUI `Canvas` or `Gauge` with `.accessoryCircularCapacity`) showing
    `0–100` + large letter grade, color-coded (reuse `Severity.color` scale / a green→red ramp).
  - Consult the **dataviz** skill before choosing the gauge color ramp so it reads well in
    light + dark.
- **Edit `ContentView.swift`**: show `ScoreGaugeView` prominently at the top of
  `summarySection` once `model.devices` is non-empty. Compute the live score by building
  `model.currentSnapshot?.securityScore` (already available).
- **Shareable score card**: add a "Share Score" action that renders a compact card via
  `ImageRenderer` (iOS 16+) to a PNG and presents it through the existing
  `ActivityView`/`ShareItem` path (`Views/ShareSupport.swift`).

Reuses: `ScanSnapshot.securityScore/scoreGrade`, `SeverityBadge`/`Severity.color`,
`ShareSupport.swift`.

---

## Phase 3 — Continuous monitoring + local push alerts (subscription trigger)

- **project.yml / Info.plist additions**
  - `UIBackgroundModes` → `fetch`, `processing`.
  - `BGTaskSchedulerPermittedIdentifiers` → e.g. `com.homenetaudit.app.rescan`.
- **New `Sources/HomeNetAudit/Monitoring/NotificationManager.swift`**
  - Wrap `UNUserNotificationCenter`: request authorization, post a local notification.
    (Local notifications need no APNs/entitlement.)
- **New `Sources/HomeNetAudit/Monitoring/BackgroundScanner.swift`**
  - Register a `BGAppRefreshTaskRequest` handler at launch; on fire, run a *lightweight*
    `ScanService` pass (discovery + port scan, skip the credential check), load the latest
    snapshot via `ScanStore`, compute `ScanDiff.between`, and if `diff.regressions > 0`
    fire a notification ("New device joined" / "New exposed service").
  - Persist the new snapshot and reschedule the next refresh.
  - Guard on subnet match so we only alert on the user's known home network.
- **Edit `HomeNetAuditApp.swift`**: register the background task + notification auth on
  launch; schedule on `scenePhase == .background`.
- **Edit `SettingsView` (in ContentView.swift)**: toggle "Continuous monitoring"
  (`@AppStorage`), request notification permission when enabled.

Documented limitation in README: iOS only grants opportunistic background windows
(`BGAppRefreshTask`), so this is periodic best-effort, not 24/7. A future always-on
companion agent (Pi/home server) is the Pro upsell.

Reuses: `ScanService` (Phase 0), `ScanStore`, `ScanDiff`, `ScanSnapshot`.

---

## Phase 4 — CVE intelligence (retention engine; largest scope)

Recommended approach: **on-device lookups against the public NVD 2.0 REST API with local
caching — no custom backend yet.** Opt-in, since it sends product/version strings off-device.

- **New `Sources/HomeNetAudit/Audit/CVELookup.swift`**
  - Parse product/version from existing fingerprints (`Fingerprint.httpServerHeader`,
    `.banner`) into a keyword/CPE-ish query.
  - Query `https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=...`; map CVSS
    base score → `Severity`; produce `Finding`s (reuse the `Finding` model + `reference`
    field for the CVE id).
  - Handle the unauthenticated rate limit (~5 req / 30s) with throttling + an optional
    user-supplied NVD API key in settings.
- **New `Sources/HomeNetAudit/Persistence/CVECache.swift`**: cache responses by
  product+version with a TTL to avoid refetching and respect rate limits.
- **Edit `AuditEngine.swift`**: when the CVE toggle is on, enrich each fingerprinted
  service with CVE findings after the existing rule evaluation.
- **Edit `SettingsView`**: opt-in toggle + optional API key field, with a privacy note.

Reuses: `Finding`, `ServiceFingerprinter.Fingerprint`, `VulnerabilityRules` severity model.

Note: this is the natural paid-tier / backend boundary. Starting with direct NVD calls keeps
it shippable now; a later server-side CVE service (caching, enrichment, no client rate limits)
is the monetization/scaling step.

---

## Files summary

New: `Services/ScanService.swift`, `.github/workflows/ios-build.yml`,
`Views/ScoreGaugeView.swift`, `Monitoring/NotificationManager.swift`,
`Monitoring/BackgroundScanner.swift`, `Audit/CVELookup.swift`, `Persistence/CVECache.swift`.

Edited: `ViewModels/ScanViewModel.swift`, `Views/ContentView.swift`,
`App/HomeNetAuditApp.swift`, `Audit/AuditEngine.swift`, `project.yml`,
`Sources/HomeNetAudit/Resources/Info.plist`, `README.md`.

---

## Verification

1. **Compile (primary, from here):** push; GitHub Actions `ios-build` must pass. This is the
   compile check we can't run on Windows.
2. **Score UI:** run on device/simulator, confirm gauge + grade render in light/dark and the
   share card exports.
3. **Monitoring:** on device, enable monitoring, grant notifications; trigger a background
   refresh via Xcode's `e -l objc -- (void)[...]` debug launch or
   `_simulateBackgroundFetch`, change the network (plug in a new device), confirm a
   notification fires.
4. **CVE:** enable toggle on a device with a known-old-firmware target; confirm CVE findings
   appear and caching prevents rate-limit errors.
5. Commit each phase separately with the standard co-author trailer.

## Sequencing recommendation

Phase 0 → 1 first (refactor + CI so everything compiles-checks), then 2 (quick visible win),
then 3 (the monetization trigger), then 4 (largest, backend-adjacent). Each phase is
independently shippable.
