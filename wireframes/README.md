# Disk Map UI wireframes

Open [disk-map-ui.html](disk-map-ui.html) in a browser or use its inline conversation preview. The file is self-contained and uses sample data; it does not scan or modify local files.

## Screens

1. **Explore:** folder navigation, proportional treemap, overview, synchronized size list, and inspector.
2. **Large bundles:** packages ranked by size with a minimum-size filter and explicit contents inspection.
3. **Inside a package:** internal treemap, breadcrumb trail, and return-to-package action.
4. **Scanning:** progressive-result layout, indeterminate completion, cancellation, and completed-scan preview.
5. **Partial access:** skipped-location disclosure with unknown sizes and access guidance.
6. **Choose location:** first-scan entry point.

Click tiles or table rows to inspect items. Open folders from the sidebar or inspector; package contents require the explicit inspection action. Search and next/previous controls select sample matches. Show in Map restores their surrounding context. Back restores the previous navigation view. Change the size metric to compare sample logical and allocated values.

The wireframe is intentionally neutral to focus review on hierarchy and navigation. The desktop layout prioritizes the map between a folder sidebar and an inspector, then stacks panels at narrow widths. Optional conversation design controls can hide the inspector or overview for comparison.

The folder chooser and Finder action are simulated. Copy Path copies a sample path where browser permissions allow it. Scan states are manually selected scenarios. Sizes and paths are illustrative; the binary treemap is a wireframe approximation of the planned squarified layout. Logical sizes use a uniform sample multiplier, not filesystem measurements. Context menus, live scanning, and physical disk allocation mapping are not implemented here.

Feature scope and implementation gates remain in [features.md](../features.md) and [phases.md](../phases.md).

## Validation

Checked in Chrome on September 12, 2026: desktop and narrow layouts, package filtering, package inspection and Back, double-click folder navigation, search match navigation and Show in Map, both size metrics, cancel, skipped-location disclosure, and the sample location-to-scan flow. No browser JavaScript errors were reported. JavaScript syntax validation passed.
