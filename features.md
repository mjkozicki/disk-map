# Disk Map — Features

## Purpose

Build a native macOS file-space explorer that makes it easy to answer: **What is taking up space, and which large files, folders, or bundles should I inspect?** An interactive treemap is the primary view, supported by a sortable list and an item inspector.

The user-provided inspiration is [DiskView for Windows](http://www.diskview.com/). Its [screenshots page](http://www.diskview.com/screenshots.htm) and linked images were accessed over HTTP and reviewed on September 12, 2026.

## Screenshot reference and macOS adaptation

The reviewed DiskView screenshots show a folder tree beside a file list and visualizer, size and relative-size columns, pie/bar charts, a selected-folder disk summary, and chart context menus. Reference images: [window components](http://www.diskview.com/dvimages/diskview-components.gif), [size bars](http://www.diskview.com/dvimages/viz/barchart450.gif), [summary](http://www.diskview.com/dvimages/viz/summary.gif), and [context menu](http://www.diskview.com/dvimages/context_menu.gif).

For Disk Map, adapt these ideas into a native window with an expandable folder outline, synchronized treemap and results list, inline size bars, and a compact volume summary. The requested treemap remains the primary visualization. Use native typography, flat colors, and package-aware navigation. Context menus expose the same inspection and Finder actions as the toolbar. Pie charts, Windows Explorer integration, disk-health monitoring, and fragmentation tools are outside the MVP.

### Sysinternals DiskView reference

[Microsoft Sysinternals DiskView](https://learn.microsoft.com/en-us/sysinternals/downloads/diskview) is a separate product from the DiskView above. Microsoft's description covers locating files on a disk map, selecting a cluster to identify its file, and inspecting file details. Its [screenshot](https://learn.microsoft.com/en-us/sysinternals/downloads/media/diskview/diskview.gif), reviewed September 12, 2026, shows a path highlight field, Show Next, a detailed map above an overview strip, and volume, refresh, and zoom controls.

Adapt its direct exploration into **Show in Map**, persistent selection, next/previous search matches, and an overview that preserves orientation while drilling down. Disk Map's rectangles represent hierarchical file sizes; their positions do not represent physical clusters. The overview uses the same size metric as the main treemap. Physical allocation mapping remains outside the MVP.

## Product direction

- Proposed baseline: macOS 14 or later, Swift and SwiftUI, with AppKit for Finder integration and custom drawing where needed. Confirm the deployment target during Phase 0.
- Scan local folders and mounted local volumes. All analysis happens on the Mac; no account, cloud service, or file uploads.
- Scanning is read-only. Development Cleanup offers reviewed Move to Trash for recognized generated development folders; other items can be revealed in Finder.
- Treat a macOS bundle/package as one meaningful item by default, while still scanning its accessible contents to calculate its size.
- A large item is an inspection candidate, never automatically classified as safe to remove.

## Primary workflow

1. Choose a folder or volume, or drag a folder into the window.
2. Watch scan progress and explore results as they become available.
3. Find the largest areas in the treemap or open the Largest Items list.
4. Select an item to see its path, size, type, and scan status.
5. Drill into a folder or explicitly inspect a bundle's contents.
6. Reveal the selected item in Finder, then rescan after any external changes.

## MVP features

### F01 — Choose and scan a location

- Provide a folder picker, drag-and-drop target, and a list of mounted local volumes.
- Enumerate files in the background with bounded concurrency and batched UI updates.
- Show the current location, discovered item count, elapsed time, and measured bytes. Use indeterminate progress until a meaningful total is known.
- Support cancel and rescan. Cancellation preserves discovered results with an incomplete status.
- Include hidden files in accounting; allow their display to be toggled without silently changing scan totals.
- Stay on the selected volume unless the user explicitly selects another root. Do not follow symbolic links or Finder aliases.
- Handle unreadable directories, files disappearing during enumeration, and disconnected volumes without losing the rest of the scan.

### F02 — Interactive treemap

- Draw nested rectangles proportional to the selected size metric using a deterministic squarified layout.
- Use consistent file-kind colors with a visible legend; retain folder boundaries and highlight selection independently of color.
- Single-click selects; double-click drills into a folder. Provide breadcrumbs, Back, Up, and return-to-root actions.
- Hover or keyboard focus shows name, path, size, and percentage of the current view.
- Keep selection synchronized across the map, list, and inspector.
- Provide **Show in Map** for list and search results: navigate to the containing folder, highlight the item, and preserve a Back destination. For an item inside a collapsed package, highlight the package and offer Inspect Package Contents before navigating inside it.
- Add a compact scan-root overview treemap with the current subtree highlighted. Selecting a region navigates to it; a root control restores the full view. Keep it stable while navigating within a completed scan.
- Double-clicking a regular-file tile focuses its inspector; folder tiles retain drill-down behavior and packages use the explicit contents action. Provide equivalent keyboard commands.
- Aggregate tiles too small to draw into a labeled, navigable group whose size equals its members' sum. Zero-byte and unknown-size items remain available in the list.
- Update progressively without constant rearrangement; use stable ordering and throttle layout changes during scanning.

### F03 — Find large bundles and packages

- Detect packaged directories through macOS resource metadata, including `isPackage`; use type information and extension fallbacks where appropriate. Apple exposes package detection through [URLResourceValues.isPackage](https://developer.apple.com/documentation/foundation/urlresourcevalues/ispackage).
- Recognize applications (`.app`), frameworks (`.framework`), plug-ins (`.bundle`), photo libraries (`.photoslibrary`), and supported document or virtual-machine packages. These are examples, not an extension-only definition.
- Display each package as a single tile and list row with the aggregate size of its accessible descendants. Mark partially scanned packages clearly.
- Provide a **Bundles & Packages** filter, descending size sorting, and adjustable size thresholds with 100 MB, 1 GB, and 10 GB presets.
- An explicit **Inspect Package Contents** action expands a package into an internal treemap without changing its aggregate size or counting it twice.
- Identify nested packages in the inspector. Largest Items hides descendants of collapsed packages by default; an optional contents view labels the parent package.
- Treat ordinary large directories as folders. Archives and disk-image files appear as files and are not unpacked or mounted automatically.
- Explain that an application's bundle size excludes related data elsewhere, such as Application Support and Containers.

### F04 — Ranked list, search, and inspector

- Offer Largest Items modes for files, folders, and bundles/packages, scoped to the selected scan root or current folder.
- Show name, full path, kind, size, percentage, modification date, and completeness; sort by size by default.
- Add inline relative-size bars in the list and expandable folder outline. Label the denominator as the current folder or scan root and use that same denominator for adjacent percentages.
- Search names and paths; filter by kind, minimum size, and hidden status.
- Provide next/previous match navigation with a current-match count, keeping the chosen result visible in the map and inspector. Report out-of-scope or unscanned paths explicitly rather than selecting a similarly named file.
- Search highlights matches in the existing map. An explicit filtered-map mode may reflow matches, with matching and total bytes both labeled.
- The inspector shows logical size, reported allocated size, descendant count, package status, and any access or metadata errors.
- Folder rankings may contain both ancestors and descendants; do not sum overlapping rows as if they were independent storage.
- Support Copy Path and Reveal in Finder. Revalidate that an item still exists before revealing it.
- Expose Copy Path, Reveal in Finder, and applicable folder/package inspection actions through consistent context menus in the map, outline, and list.

### F05 — Clear size accounting

- Default to **Reported Size on Disk** and allow switching to **Logical Size**. Map, list, percentages, and thresholds always use the same active metric.
- Preserve unavailable metadata as unknown. Never silently substitute logical size into an allocated-size total or present inaccessible contents as zero.
- Aggregate regular-file sizes bottom-up for folders and packages. Report directory/filesystem overhead as outside the measured file total rather than inventing per-folder values.
- Show exact bytes in the inspector and consistent decimal units (KB, MB, GB, TB) in the main UI.
- Foundation provides `totalFileSize` and `totalFileAllocatedSize` for regular files; the latter can be unavailable and can differ for compressed resources. See Apple's [size metadata](https://developer.apple.com/documentation/foundation/urlresourcevalues/totalfileallocatedsize).
- Track hard links by volume and file identity. Logical mode counts path entries; allocated mode attributes each known hard-linked file once per scan to a deterministic canonical path. Other links remain visible with a shared-file badge and an explanation of their zero attributed contribution.
- APFS clones may share blocks. Per-file allocated sizes do not establish unique physical usage or guaranteed reclaimable space; do not claim exact space savings. Apple exposes possible sharing through [URL resource metadata](https://developer.apple.com/documentation/foundation/urlresourcevalues).
- Show volume capacity and available space separately from scanned totals. Do not force totals to match volume usage or draw unknown space as a sized file tile.
- Cloud placeholders are metadata-only scan targets: do not deliberately download their contents. Show remote/unknown allocation where supported and validate behavior against the providers tested for release.

### F06 — Access and scan completeness

- Support user-selected folder access and useful results when broader access is denied.
- Explain skipped locations with a count and expandable path/error list. Distinguish complete, scanning, canceled, inaccessible, and stale results.
- Give contextual instructions for Full Disk Access when appropriate. It is granted by the user in System Settings; it does not replace sandbox permissions or other filesystem restrictions. See Apple's [macOS file-access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- A scan is a best-effort observation of a changing filesystem, not an atomic snapshot. Show its timestamp and offer rescan when actions encounter changed items.

### F07 — Native usability and accessibility

- Resizable window with location sidebar, central map/list, and item inspector; support light and dark appearance.
- Include an expandable, size-sortable folder outline in the sidebar and toolbar controls to show or hide the sidebar and inspector.
- Provide a compact summary for the selected volume with capacity and available space; show the selected folder's measured size separately so incomplete scans and shared allocation remain clear.
- Keyboard navigation for selection, drill-down, parent navigation, search, and Finder reveal.
- Provide a VoiceOver-accessible list for every item represented by the treemap, meaningful focus labels, sufficient contrast, and reduced-motion behavior.
- Show useful empty, no-match, no-permission, and interrupted-scan states.
- Keep file paths and scan data local; omit raw paths from diagnostic logs by default.

## After the MVP

| ID | Feature | Scope |
| --- | --- | --- |
| F08 | Recent locations and saved scans | Remember authorized roots; optionally save local scan metadata with timestamps and a delete-history control. |
| F09 | Scan comparison | Compare compatible scans of the same root and size metric; surface growth, new items, and removed items without treating moves as certain growth. |
| F10 | Faster refresh | Rescan selected subtrees and use filesystem change notifications to mark results stale; recover with a full scan when needed. |
| F11 | Export | Export the current ranked view as CSV and the treemap as an image, with scope, metric, timestamp, and completeness included. |
| F12 | Optional Move to Trash | Separate later milestone: explicit review, current-path/identity checks, whole-package actions, and no permanent-delete fallback. |

## Out of scope for the first release

- Automatic cleanup, permanent deletion, app uninstallation, or editing bundle contents.
- Duplicate-content hashing, archive expansion, or automatic disk-image mounting.
- Physical sector maps, defragmentation, APFS snapshot management, or exact reclaimable-space estimates.
- Privileged helper installation, background surveillance, network-share optimization, or cloud synchronization.

## MVP acceptance

- On a known fixture, the map and list agree on measured totals, and changing package presentation never changes those totals.
- A user can locate the largest bundle, inspect its contents, and reveal it in Finder from one completed scan.
- A user can move from a search result to its map location and details, then return to the prior view; the overview correctly identifies the current subtree.
- Denied access, cancellation, unknown sizes, and filesystem changes produce explicit partial results without crashes.
- Scanning does not modify source files or intentionally hydrate cloud placeholders.
- Performance and accessibility meet the release gates in [phases.md](phases.md).
