# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/yutna/ollama-bar/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yutna/ollama-bar/releases/tag/v1.0.0
