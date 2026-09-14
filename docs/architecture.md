# Native app architecture

Disk Map targets macOS 14+ using SwiftUI and AppKit, built with Swift Package Manager. It does not require third-party packages or a full Xcode installation to build locally.

## Access and distribution

The initial build is a direct-distribution app without App Sandbox. The user explicitly selects a folder or volume through the open panel, Home Folder action, or drag-and-drop. Scanning performs read-only metadata operations using the current user's permissions. The separate Development Cleanup flow moves explicitly reviewed generated folders to Trash. Full Disk Access is optional and is granted by the user in System Settings, never by the app. Scanning does not read file contents, launch helper processes, or request elevated privileges.

`scripts/build-app.sh` creates a locally runnable app bundle with an ad-hoc signature. Set `DISKMAP_SIGN_IDENTITY` to an available Developer ID identity for a hardened-runtime signature. Public distribution still requires notarization using the owner's Apple developer credentials; local builds are not represented as notarized releases.

## Data flow

- `DiskMapCore/FileScanner` performs iterative depth-first traversal on a background queue. Directory entries are ordered by name, package contents are traversed, symbolic-link targets are never followed, and another device boundary is recorded as an exclusion.
- Scanner events arrive in bounded batches. A semaphore limits the number awaiting UI delivery to two. A cancellation flag stops scheduling new filesystem work; an outstanding metadata call may finish first.
- `ScanIndex` applies additions and directory-completion events in order. Its flat array stores parent/child IDs and names, reconstructing paths on demand instead of retaining a full URL per node. Byte totals, unknown counters, issue counts, and pending-directory counts propagate to ancestors.
- The UI uses the same index for map, list, inspector, and navigation. Background filtering produces a generation-tagged result list, so stale searches cannot replace newer results.
- `TreemapLayout` computes deterministic squarified rectangles independently of AppKit. The native drawing view limits visible detail and groups tiny entries, which remain available in the results table.

## Accounting contract

Logical size uses Foundation's total-file-size metadata, or `lstat` file length when that metadata is unavailable. Allocated size uses Foundation's total allocated size. Missing allocation remains unknown; it is never replaced with logical size. Folders and packages sum descendant regular-file metadata; directory overhead and symbolic-link targets are excluded.

The first path encountered for each known hard-linked file receives its reported allocation; later paths point to that node and contribute zero additional allocated bytes. Traversal order makes attribution deterministic within the selected root. Logical size counts each path. Per-file APFS clone allocation can still overlap, so totals do not claim exact physical usage or reclaimable space.

Unfinished traversal and access errors make ancestor totals partial. `+` indicates a measured lower bound or unavailable metadata. Volume capacity and free space remain separate from the sum of scanned files. Cloud items are inspected through metadata only and are not intentionally downloaded.

## Current limits

The app does not permanently delete files, save scan history, compare scans, watch changes, or export reports. Scanner observations are not atomic snapshots. Finder reveal rechecks device/inode identity; unrelated external edits require a rescan. Display filtering, especially searches during very large scans, can retain a copy-on-write snapshot until the filter completes. Large-scale memory and latency targets require measured validation before being claimed as release guarantees.

## Development cleanup

`DevelopmentCleanup` derives non-overlapping candidates from a completed index on a background queue. Specific dependency/cache names are recognized directly; ambiguous build folders require adjacent project markers. Packages, Git internals, Trash, cloud-marked directories, known protected system paths, incomplete candidates, and the scan root are excluded. The app canonicalizes the root before scanning and checks package ancestors even when scanning a package interior directly.

The UI keeps cleanup selection separate from explorer selection and freezes exact paths and sizes for review. Before each native `FileManager.trashItem` call, the core checks every scanned ancestor and target with `lstat`, rejects links or changed identities, and confirms eligibility. Failures are per item and never invoke permanent deletion. A full rescan follows every batch, including failed batches, so allocated hard-link attribution is recomputed. Reported sizes describe measured allocation, not promised space savings. Filesystem observations and the Trash operation are not atomic; stop tools modifying the projects before cleanup.
