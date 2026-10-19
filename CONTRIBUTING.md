# Contributing to OllamaBar

Thanks for taking the time to contribute! This project is small on purpose —
keep changes focused and easy to review.

## Ways to contribute

- **Bug reports** — use the [bug report template](https://github.com/yutna/ollama-bar/issues/new?template=bug_report.yml).
- **Feature requests** — open an issue first so we can discuss the design.
- **Translations** — add a `resources/<language>.lproj/Localizable.strings`
  (copy `resources/en.lproj/` as the reference for keys) and list the language
  in `resources/Info.plist`.
- **Pull requests** — bug fixes and small improvements are welcome.

## Development setup

Requirements: macOS 13+, Xcode Command Line Tools. For linting you need an
Xcode toolchain that ships `swift-format` (`xcode-select` / full Xcode).

```sh
git clone https://github.com/yutna/ollama-bar.git
cd ollama-bar
make build      # builds build/OllamaBar.app via SwiftPM
make run        # build and launch
make test       # unit tests (SwiftPM)
make lint       # swift-format lint (CI runs this)
make format     # apply Swift formatting in place
```

Test the CLI paths after changes:

```sh
BIN=build/OllamaBar.app/Contents/MacOS/OllamaBar
$BIN --start && $BIN --status   # running
$BIN --warm && $BIN --status    # running model-loaded
$BIN --stop  && $BIN --status   # stopped
```

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/OllamaBar/main.swift` | Entry point: CLI flags vs. menu bar app |
| `Sources/OllamaBar/AppDelegate.swift` | Menu bar UI, user actions |
| `Sources/OllamaBarCore/OllamaService.swift` | Server lifecycle + `/api` calls |
| `Sources/OllamaBarCore/Config.swift` | Env-overridable defaults |
| `Sources/OllamaBarCore/Shell.swift` | Small `Process` helpers |
| `Sources/OllamaBarCore/CLI.swift` | Scriptable `--start/--stop/--status/--warm` |
| `Sources/OllamaBarCore/L10n.swift` | Typed access to user-facing strings |
| `Tests/OllamaBarCoreTests/` | Unit tests for `OllamaBarCore` |
| `scripts/` | CI helpers (fake Ollama API, smoke test) |
| `resources/*.lproj/` | Localized strings |
| `resources/Info.plist` | Bundle metadata |
| `Makefile` | build / install / test / lint / release-zip targets |
| `Package.swift` | SwiftPM manifest |

## Code style

- Apple's [`swift-format`](https://github.com/swiftlang/swift-format) with the
  repo's `.swift-format` config — run `make format` before committing, CI runs
  `make lint`.
- Prefer small, explicit types and dependency injection by constructor where it
  makes behavior testable; keep UI strings in `L10n.swift`, never inline.
- User-facing strings must be localizable: add the key to **every**
  `Localizable.strings` and keep the English default in `L10n.swift`.

## Commit messages

- One logical change per commit.
- Imperative subject line, ≤ 72 chars, e.g. `Add warm-up retry on timeout`.
- Reference issues when relevant (`Fixes #12`).

## Pull requests

- Keep the diff focused; explain the *why* in the description.
- Make sure `make lint` and `make build` pass, and describe how you tested.
- The PR template checklist mirrors this.

## Screenshots (docs)

The app has a documentation helper: launched with `OLLAMABAR_SCREENSHOT=1` it
opens its menu after launch and prints the status item's frame, so captures can
be scripted. To regenerate `docs/menu-en.png` / `docs/menu-th.png`:

```sh
BIN=build/OllamaBar.app/Contents/MacOS/OllamaBar
OLLAMABAR_SCREENSHOT=1 "$BIN" -AppleLanguages "(en)"   # or "(th)"
# while the menu is open, capture the region around the printed OLLAMABAR_FRAME
screencapture -x -R"x,y,w,h" docs/menu-en.png
```

## Release process (maintainers)

```sh
# 1. bump versions: resources/Info.plist and CHANGELOG.md
# 2. build the universal zip and checksum
make release-zip
# 3. commit, tag, push
git tag vX.Y.Z && git push origin main vX.Y.Z
# 4. create the GitHub release (or let the release workflow attach assets)
gh release create vX.Y.Z build/OllamaBar.app.zip build/OllamaBar.app.zip.sha256 --generate-notes
```
