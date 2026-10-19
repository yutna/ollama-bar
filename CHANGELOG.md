# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] — 2026-10-19

### Added

- `OLLAMABAR_LOG_MAX_BYTES` sets the cap for `~/.ollama/logs/server.log`
  (10 MB by default)

### Changed

- `server.log` is rotated while the server runs instead of only at the next
  start, so a long session can no longer grow the log without bound; the file
  it replaces is kept as `server.log.1`
- Quitting no longer blocks the menu bar: the server is stopped off the main
  thread, and termination skips the per-model `ollama stop` round-trips —
  the server is killed anyway and SIGTERM reclaims the memory
- Warm-up (and `--warm`) preloads a model only when none is loaded, so it can
  no longer evict the model in use under the default
  `OLLAMA_MAX_LOADED_MODELS=1`
- Warm-up skips embedding-only models using the `capabilities` the server
  reports, falling back to the name/family heuristic on older servers
- `make lint` also fails when a `defaultValue:` in `L10n.swift` drifts from
  `resources/en.lproj`; each pull request runs the checks once instead of twice

## [1.1.1] — 2026-10-19

### Fixed

- `--version` / `-v` prints the app version, and an unknown `--option` prints
  the usage and exits 2 instead of silently launching the menu bar app (which
  made scripts and CI hang); the smoke test covers both
- `start()` and `stop()` are serialized, so overlapping calls from menu
  actions, the termination signal handler and the CLI can no longer spawn two
  servers or kill a server that is still starting up
- `OLLAMABAR_KEEP_ALIVE=0` is honoured (unload immediately) instead of falling
  back to `-1` (keep models loaded forever)
- The `ollama` binary is also found in MacPorts, `~/.local/bin`, `~/bin` and
  asdf/mise shims, with a login-shell fallback for `PATH` entries added in
  shell profiles, so the GUI app no longer reports "Ollama not found" for
  those installs
- The menu bar app shows an alert when **Stop** fails instead of quietly
  keeping the running state

## [1.1.0] — 2026-10-19

### Added

- Six more UI languages — 日本語, 简体中文, 한국어, Español, Français and Deutsch —
  bringing the app to eight languages; it still follows your system language and
  falls back to English when yours is not translated yet
- `make lint` now verifies that every `resources/*.lproj` is declared in
  `CFBundleLocalizations` (and vice versa) and that all translations share the
  same keys and format specifiers

### Changed

- The app bundle ships every `resources/*.lproj` directory instead of a
  hardcoded list, so adding a language is a one-directory change

## [1.0.1] — 2026-10-19

### Fixed

- Only a real Ollama counts as running: health checks and model calls require
  HTTP 200 with valid JSON, so another app on the port can no longer be
  mistaken for the server (or put the menu into a wrong state)
- `--start`, `--stop` and `--warm` exit non-zero when the action fails; `--stop`
  waits for `ollama` to actually exit and escalates SIGTERM → SIGKILL
- `OLLAMABAR_PORT` is honoured end-to-end: the server is started with
  `OLLAMA_HOST=127.0.0.1:<port>` and every `ollama` call targets that port
- Environment overrides (`OLLAMABAR_*`) are validated and fall back to the
  default when invalid instead of starting an unusable server
- Start failures now include the tail of `server.log`; **Warm up model** reports
  real success, preloads over HTTP, skips embedding-only models and pins the
  model with `keep_alive`
- Menu actions no longer block the UI thread; alerts and login-item actions run
  on the main thread
- User-owned `ollama serve` / `ollama runner` processes are matched by
  executable name and terminated on stop, quit and SIGTERM/SIGINT/SIGHUP
- `server.log` rotates at 10 MB so it cannot grow without bound

### Added

- App icon (regenerable with `scripts/make-icon.sh`)
- 47 unit tests for config validation, the HTTP client, process matching,
  warm-up selection, log rotation and localization
- Integration smoke test that runs the CLI against a fake Ollama API
  (`scripts/fake_ollama.pl`), including the "another app on 404" case
- CI hardening: dependency cache, concurrency limits, job timeouts, and a
  release gate that verifies the tag matches `Info.plist` and the CHANGELOG

### Changed

- Health checks use `URLSession` with short timeouts instead of shelling out to
  `curl`
- Error messages are localized (English/Thai); CI checks key parity and format
  specifiers between translations

## [1.0.0] — 2026-10-19

### Added

- Menu bar app with one-click **Start Ollama** / **Stop Ollama**
- **Stop** unloads every model and terminates the server, freeing memory immediately
- **Warm up model** preloads the first installed model
- Optimized server defaults: `OLLAMA_KEEP_ALIVE=-1`, 64k context, one loaded model,
  Flash Attention, `q8_0` K/V cache (all overridable via `OLLAMABAR_*` env vars)
- CLI mode: `--start`, `--stop`, `--status`, `--warm`, `--help`
- Localized UI (English, Thai) with `.lproj` resources
- "Show icon at login" login item
- Homebrew (Apple Silicon / Intel) and official-app binary auto-detection
- GitHub Actions CI (build + `swift-format` lint) and tag-driven release workflow

[Unreleased]: https://github.com/yutna/ollama-bar/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/yutna/ollama-bar/releases/tag/v1.2.0
[1.1.1]: https://github.com/yutna/ollama-bar/releases/tag/v1.1.1
[1.1.0]: https://github.com/yutna/ollama-bar/releases/tag/v1.1.0
[1.0.1]: https://github.com/yutna/ollama-bar/releases/tag/v1.0.1
[1.0.0]: https://github.com/yutna/ollama-bar/releases/tag/v1.0.0
