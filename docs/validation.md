# Native validation — September 12, 2026

Testing began after the initial implementation, as requested.

## Environment

- Apple M1 Pro, 16 GiB RAM, local internal storage.
- macOS 26.6.2; Apple Swift 6.4 command-line toolchain.
- Deployment target: macOS 14. Earlier supported macOS versions were not available for this run.

## Completed checks

- Debug compilation of the application and core-check executable.
- Release compilation and local `.app` generation with icon and Info.plist.
- Info.plist validation and strict verification of the ad-hoc app signature.
- Real temporary filesystem fixtures: package aggregation, nested packages, logical totals, deterministic hard-link attribution, allocated leaf totals, symbolic-link loop avoidance, hidden files, reconstructed paths, and enclosing-package detection.
- Unknown allocation remains unknown rather than being replaced by logical bytes.
- Denied-directory access leaves readable siblings intact and marks aggregate results partial.
- Cancellation retains discovered nodes and unfinished-directory status.
- Squarified layout: proportional area, containment, non-overlap, deterministic ordering, and empty/zero/invalid input handling, up to 300 visible entries.
- Native UI launch, folder picker, real fixture scan, package ranking, explicit package inspection, Back navigation, search inside packages, search-selection synchronization, and Show in Map respecting package boundaries.
- Final rebuild rechecked the sidebar hit area and empty-state layout. Reveal in Finder selected the exact test package in Finder.

## Scanner measurement

A temporary fixture contained 100,000 empty files across 100 subdirectories. The debug scanner and index accumulator processed 100,101 nodes in **17.307 seconds**, with **76,546,048 bytes (73.0 MiB) maximum resident memory**, zero metadata errors, and no unknown allocation. The temporary benchmark was removed afterward. This measurement includes scanning and aggregation, not interactive UI rendering, and was taken while a release compilation was also running.

## Remaining release qualification

- Million-entry app memory, UI latency percentiles, time to first visible results, and VoiceOver usability require dedicated measurements. The scanner benchmark does not establish those gates.
- Cloud-provider hydration behavior, APFS clone accounting, sparse/compressed files, live disconnects, and scanning while another process changes files need a broader filesystem matrix.
- Full Disk Access was not changed for this run. System privacy prompts remain controlled by the user.
- macOS 14 and other supported OS versions, Intel builds, and clean-account installation remain unverified.
- Local ad-hoc signing is complete. Developer ID signing and Apple notarization require the owner's release credentials and are not complete.

These are development-build results, not a claim that all production-release gates in `phases.md` have passed.

## Development cleanup — September 13, 2026

- Core checks cover JavaScript dependencies and framework caches, Python caches/environments, Swift, Rust, .NET, Maven, and Gradle output, plus unrelated folders whose names must not be enough to qualify.
- Disposable filesystem fixtures verify nested deduplication, package-interior roots, Git/Trash exclusions, symbolic links, partial candidates, replaced targets, redirected ancestors, and rejection of root/nested action IDs.
- Injected permission and unsupported-Trash failures leave contents intact and allow other selected folders to proceed.
- A real native Trash operation moved only a disposable fixture. Its contents were verified in Trash and restored immediately; rescan checks confirm moved folders disappear from candidates.
- The filesystem check and Trash move are separate operations, so simultaneous external modifications remain a race; this is not an atomic filesystem snapshot.
- Native UI validation covered fixture scanning, six recognized folders, individual selection, selection retained through search, exact-path review, cancellation, a successful Trash move, the per-batch report, and automatic rescan from six to five candidates. The UI move leaves its 16 KiB disposable fixture in Trash; the remaining temporary source fixture was removed.
- Release app generation and strict ad-hoc signature verification passed.
