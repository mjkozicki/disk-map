# Disk Map

A native macOS disk explorer in development, focused on interactive treemaps and finding large files, folders, and bundles.

**[Explore the GitHub Pages preview](https://mjkozicki.github.io/disk-map/)**

The website is an interactive prototype with fictional sample files. The native Swift app scans real folders on your Mac and can be built locally. There is no notarized public release yet.

- [Feature specification](features.md)
- [Implementation phases](phases.md)
- [Wireframe screens and interactions](wireframes/README.md)
- [Native architecture and accounting](docs/architecture.md)

## Build and run the macOS app

Requires macOS 14 or later and Swift 5.9+ (Xcode or Apple's Command Line Tools).

```sh
bash scripts/build-app.sh
open "build/Disk Map.app"
```

Choose a folder or volume, scan Home, or drop a folder into the window. Use the treemap, Largest Items, or Bundles & Packages to explore results. Select a package and choose **Inspect Package Contents** to open it. **Reveal in Finder** and **Copy Path** act on the selected item. Scans are read-only and stay local.

The build script uses ad-hoc signing by default for local execution. An optional `DISKMAP_SIGN_IDENTITY` selects an installed Developer ID identity; notarization is a separate release step. Full Disk Access can be granted manually if you want to scan protected locations.

Keyboard shortcuts: `⌘O` choose location, `⌘R` rescan, `⌘.` cancel, `⌘F` search, `⌘G` next match, `⌘[` back, `⌘↑` parent, `⌘0` root, `⌘Return` inspect, `⌘⇧R` reveal, `⌘⌥C` copy path.

## Native validation

Run these after implementation:

```sh
swift run disk-map-check
swift run disk-map-check --scan /path/to/a/test/folder
```

The core checks create and remove their own temporary fixtures, covering packages, hard links, symlinks, hidden files, permission denial, cancellation, unknown allocation, and treemap geometry.

## Website development

Requires Python 3 and Node.js for JavaScript syntax validation; no third-party packages are needed.

```sh
python3 scripts/build-site.py
python3 -m http.server 8000 --directory dist
```

Open `http://localhost:8000`. Edit `site/` for the website framing and `wireframes/disk-map-ui.html` for the interactive prototype. The build inserts the shared prototype into the page, so there is only one source for its behavior.

## GitHub Pages

The Pages workflow builds and validates pull requests. Pushes to `main` also publish the `dist/` artifact. The repository's Pages publishing source is **GitHub Actions**. Generated output is not committed.

GitHub Pages serves the static preview only; the planned native scanner is a separate macOS application.
