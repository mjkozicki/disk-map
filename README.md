# Disk Map

A native macOS disk explorer in development, focused on interactive treemaps and finding large files, folders, and bundles.

**[Explore the GitHub Pages preview](https://mjkozicki.github.io/disk-map/)**

The website is an interactive prototype with fictional sample files. It does not scan your Mac. There is no native app release yet.

- [Feature specification](features.md)
- [Implementation phases](phases.md)
- [Wireframe screens and interactions](wireframes/README.md)

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
