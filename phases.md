# Disk Map — Implementation Phases

## Delivery approach

Implement the native macOS explorer described in [features.md](features.md). The MVP is complete after Phase 5: select a location, scan it, explore a treemap, find large packages, inspect them, and reveal them in Finder.

All phases below are planned; no application implementation exists yet. Follow the dependencies in order. Later enhancements are optional and do not block the MVP.

## Phase 0 — Establish the app and filesystem contract

**Scope:** Foundations for F01, F05, and F06.

- Create a Swift/SwiftUI macOS app with separate scanning, data-model, layout, and presentation modules.
- Confirm the proposed macOS 14 minimum and supported architectures against available test hardware.
- Prototype access to a selected folder and local volume. Choose and record a distribution/access model before adding entitlements: a sandboxed folder-first app or a notarized direct-distribution app for broader scanning.
- Verify denied-access behavior and the role of Full Disk Access for the chosen model. Do not assume it bypasses sandbox restrictions.
- Define a scan node with identity, parent, name/path reference, kind, package flag, logical/allocated bytes, attributed bytes, timestamps, counts, and completeness/errors. Use 64-bit sizes and avoid retaining redundant full paths for every node.
- Define scan states and cancellation semantics; keep the UI independent of scanner implementation details.
- Create small deterministic fixtures: nested folders, empty and hidden files, a large synthetic `.app`, a document package, a nested package, symlinks, and hard links.

**Exit gate:** The app launches, a selected directory can be enumerated, denied access is reported, and a short architecture decision records access, distribution, minimum OS, and size-accounting choices consistent with F05.

## Phase 1 — Build a trustworthy scanner

**Scope:** F01, F05, F06; package aggregation from F03.

- Implement background metadata enumeration, bounded work queues, progress events, cancel, and full rescan.
- Traverse package contents for accounting while preserving package boundaries in the model.
- Aggregate folder sizes and completeness; implement both size metrics and deterministic hard-link attribution.
- Skip symlink/alias targets and other mounted volumes; record unreadable, vanished, and unsupported entries.
- Add a basic results table and scan summary so accounting can be inspected before visualization.
- Exercise sparse/compressed files, missing metadata, cloud placeholders, and disconnects with suitable fixtures or manual cases. Keep platform-dependent cases explicit.

**Exit gate:** Fixture totals match an independent expected-byte manifest; packages count once; a symlink loop terminates; cancellation keeps partial results; permission failures do not abort unrelated branches. Investigate differences with Finder or `du` using matched semantics rather than assuming either is an exact oracle.

## Phase 2 — Deliver the treemap explorer

**Scope:** F02 and initial F07.

- Implement and unit-test a deterministic squarified treemap independently of the UI.
- Add nested folder boundaries, file-kind colors, legend, labels, tooltips, and visible selection.
- Adapt the reviewed DiskView screenshots into a native folder outline, synchronized map/list, and collapsible sidebar/inspector; keep the requested treemap central.
- Adapt the [Sysinternals DiskView reference](https://learn.microsoft.com/en-us/sysinternals/downloads/diskview) into a scan-root overview with current-subtree highlighting, Show in Map navigation, and direct file inspection. Use hierarchical size geometry throughout.
- Connect selection to the list and inspector; add drill-down, breadcrumbs, Back, Up, and root navigation.
- Render only useful visible detail, aggregate subpixel tiles, and keep zero/unknown-size items discoverable in the list.
- Batch scan updates and preserve interaction while results grow. Add window resizing, dark appearance, and keyboard navigation.

**Exit gate:** Positive-size rectangles remain within their parent, do not overlap, and preserve relative area within pixel-rounding tolerance. Synthetic known-size trees, empty trees, and highly skewed trees render correctly. Map/list selection stays synchronized while navigating and resizing.

Verify that the overview highlights the correct subtree after drill-down and Back, and that Show in Map reveals a selected item without losing the previous navigation destination.

## Phase 3 — Make large bundles easy to find

**Scope:** Complete F03 and F04; finish the main user workflow.

- Add package detection, package badges, and collapsed package tiles with aggregate sizes.
- Implement Bundles & Packages and Largest Items views with type, scope, size threshold, and search controls.
- Add Inspect Package Contents and return-to-package navigation; distinguish nested packages from ordinary folders.
- Complete the inspector and add Copy Path and Reveal in Finder with stale-item handling.
- Add relative-size bars with explicit denominators to the list and size-sortable folder outline; expose consistent context menus across all three views.
- Define search highlighting versus filtered-map behavior and label overlapping ancestor/descendant results.
- Add next/previous search matches and a match counter; handle Show in Map for package descendants, unscanned paths, and results outside the current view.

**Exit gate:** In a fixture containing a 2 GB application package, a larger ordinary folder, and a large standalone file, the package filter ranks only packages correctly. Inspecting or collapsing the application preserves scan totals. Its largest internal file and original package can each be revealed in Finder. Incomplete packages carry their status into every view.

Verify that repeated filenames in separate directories navigate to the exact selected path, match navigation updates the map and inspector together, and package contents stay behind the explicit inspection action.

## Phase 4 — Handle real Mac disks and scale

**Scope:** Harden F01–F07.

- Validate the chosen access flow on internal APFS and a removable local volume, including denied access, disconnect/reconnect, and protected folders.
- Verify hard links, possible clone sharing, sparse files, hidden files, cloud placeholders, and unknown allocation do not produce misleading totals or savings claims.
- Add completeness summaries, scan timestamps, changed-item behavior, and separate volume-space indicators.
- Profile traversal, model memory, sorting, and layout; reduce redundant metadata reads and virtualize large lists.
- Complete VoiceOver, contrast, focus, reduced-motion, and error/empty-state review.

**Proposed performance gates:** Record the reference Mac, OS, storage, build mode, and dataset before measuring. These are targets, not current results.

| Scenario | Release target |
| --- | --- |
| Local fixture with 100,000 entries | First partial results within 2 seconds; completed scan within 30 seconds on the recorded SSD baseline. |
| Interaction during scan | Selection and navigation response below 100 ms at the 95th percentile. |
| Cancel | UI acknowledges within 250 ms and stops scheduling new traversal work; outstanding filesystem calls may finish later. |
| Completed million-entry fixture | Peak app memory below 1 GB; current-folder navigation below 200 ms at the 95th percentile. |

**Exit gate:** Correctness cases pass, performance is measured against the recorded baseline, and the complete find/inspect/reveal workflow works by keyboard and VoiceOver. Resolve missed targets or document and approve a revised target before release.

## Phase 5 — Package and release the MVP

**Scope:** Ship F01–F07.

- Finalize the app icon, menu commands, help text, first-scan guidance, and settings appropriate to the chosen access model.
- Produce a signed release build and complete notarization or the selected distribution process.
- Validate install, launch, folder/volume selection, denied permissions, scanning, package inspection, Finder reveal, and relaunch on the minimum and current supported macOS versions.
- Document known limitations: partial access, reported allocation versus unique physical usage, external changes, and application data outside bundles.
- Confirm all MVP acceptance criteria in `features.md` and record validation results and remaining limitations in release notes.

**Exit gate:** An installable build completes the core workflow on a clean test account, passes the Phase 4 gates, and contains no unfinished essential UI actions.

## Phase 6 — Add investigation conveniences

**Scope:** F08–F11 after MVP feedback.

- Add recent locations with access renewal; use security-scoped bookmarks where required by the selected sandbox model.
- Add explicitly saved local scans and metadata retention controls before implementing comparisons.
- Compare scans only when scope, exclusions, and size semantics are compatible; label uncertainty from moves, incomplete scans, and changing identities.
- Add subtree refresh with correct ancestor aggregation, then filesystem notifications with full-rescan recovery.
- Export ranked results and treemap images with scope and completeness context.

**Exit gate:** Saved scans reopen without being mistaken for live data; controlled additions/removals produce correct comparison results; refresh agrees with a fresh full scan; exported values match the displayed view.

## Phase 7 — Optional cleanup actions

**Scope:** F12; separate from the read-only MVP.

- Design a review screen showing exact selected paths, types, and measured sizes before Move to Trash.
- Revalidate file identity and access immediately before acting; require reselection when the item has changed.
- Treat packages as whole units, prevent parent/child duplicate actions, and disable cleanup inside packages or protected system locations.
- Handle partial failures individually. If Trash is unavailable, report failure without falling back to permanent deletion.
- Refresh affected results and explain that moving to Trash does not immediately reclaim its contents' space.

**Exit gate:** Dedicated disposable fixtures cover changed paths, nested selections, package boundaries, permission failures, and unavailable Trash. No operation permanently deletes data or reports guaranteed reclaimed bytes.
