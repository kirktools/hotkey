# Hotkey

English · [简体中文](README.md)

A lightweight, native macOS menu bar utility for global keyboard shortcuts. Launch, focus and hide your everyday apps without searching for them. Built with Swift, SwiftUI and AppKit; configuration stays on your Mac, with no account or analytics.

## Features

- Assign global shortcuts to apps. Launch when stopped, focus from the background, and hide when already in front.
- Record custom combinations; Command + Option is the suggested prefix.
- Detect internal duplicates, known system combinations and global registration failures.
- Pause shortcuts, export/import configuration and restore a backup.
- An internal app-switching plugin and an experimental external native plugin system.

## Download and use

Download a ZIP from [GitHub Releases](https://github.com/kirktools/hotkey/releases), unzip it and place Hotkey.app in Applications. Open settings from the menu bar, add an app and record a shortcut.

Requires **macOS 14+**. Current release packages target **Apple Silicon / arm64**; Intel and Universal builds are not provided. Builds use free ad-hoc signing and are **not notarized**. macOS may block the first launch; follow its per-app verification process only after checking the source. Do not disable system security protections.

## Development

Requires Swift 6 with Xcode or Command Line Tools.

```sh
make dev
make check test
make build CONFIG=release
make package
```

Hotkey Dev has a separate name, Bundle ID and data directory, an orange DEV icon badge and a DEV menu bar label. `make package` generates versioned and fixed-name archives with SHA-256 checksums, without publishing.

## Limits

Window restoration across minimized windows, fullscreen apps and Spaces follows macOS and the target app. App-specific shortcut conflicts cannot be fully enumerated. External plugins are experimental, including outstanding pipe backpressure and update identity checks; use trusted local plugins only. Screenshot support and in-app automatic updates are not implemented. The current host does not request Accessibility, Input Monitoring or Screen Recording permissions.

See [plugin development](docs/plugins.md), [signing and updates](docs/signing-and-updates.md) and [website maintenance](docs/site.md) for details. The website uses only synthetic demo data, with no tracking or external runtime dependencies.

## License

[MIT License](LICENSE).
