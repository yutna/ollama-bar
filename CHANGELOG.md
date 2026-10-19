# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/yutna/ollama-bar/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/yutna/ollama-bar/releases/tag/v1.0.1
[1.0.0]: https://github.com/yutna/ollama-bar/releases/tag/v1.0.0
