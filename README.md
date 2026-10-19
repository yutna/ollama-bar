# OllamaBar

[![build](https://github.com/yutna/ollama-bar/actions/workflows/build.yml/badge.svg)](https://github.com/yutna/ollama-bar/actions/workflows/build.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A tiny macOS menu bar toggle for a **local Ollama server**.

Ollama normally installs itself as a login service that always runs in the
background. On a laptop you often don't want an 18 GB model sitting in unified
memory when you're not using it. OllamaBar gives you one click:

| Action | What happens |
| --- | --- |
| **▶︎ Start Ollama** | runs `ollama serve` with sensible macOS defaults (see below) |
| **🔥 Warm up model** | preloads your first installed model so the first request is instant |
| **■ Stop Ollama** | unloads all models and terminates the server — RAM is freed immediately |
| **Quit** | stops Ollama too (nothing keeps running in the background) |

It never auto-starts anything at boot; the menu bar icon is the only touch point.

## Features

- One-click start / stop for `ollama serve`
- Stop frees the model RAM instantly (not after a keep-alive timeout)
- Optimized defaults out of the box: keep-alive `-1`, 64k context, single loaded model
- Warm-up button to preload the model before you open your editor
- Optional "Show icon at login" (the icon only — Ollama itself stays off until you click Start)
- CLI mode for scripts (`--start`, `--stop`, `--status`, `--warm`, `--help`)
- Finds Ollama wherever it lives: Homebrew (Apple Silicon or Intel) or the official app

## Requirements

- macOS 13 or newer (Apple Silicon recommended)
- [Ollama](https://ollama.com) installed (via the app or Homebrew)
- Xcode Command Line Tools to build (`xcode-select --install`)

## Build & install

```sh
git clone https://github.com/yutna/ollama-bar.git
cd ollama-bar
make install              # installs to /Applications
# or: PREFIX=~/Applications make install
```

Then launch **OllamaBar** from Launchpad/Spotlight and look for the 🦙 icon in
the menu bar.

Other targets: `make build` (build only, into `build/`), `make run`, `make uninstall`.

## Usage

1. Click the 🦙 icon.
2. Choose **Start Ollama**.
3. Optionally choose **Warm up model**.
4. Open your editor / coding agent (OpenCode, Claude Code, [`ollama launch`](https://docs.ollama.com/integrations), …) and work.
5. When done, click 🦙 → **Stop Ollama**. RAM is back immediately.

The icon is dimmed while the server is stopped.

## Defaults

These are applied to the server that OllamaBar starts:

| Setting | Value | Why |
| --- | --- | --- |
| `OLLAMA_KEEP_ALIVE` | `-1` | keep the model resident for the whole session (no reload stalls) |
| `OLLAMA_CONTEXT_LENGTH` | `65536` | [Ollama recommends 64k+](https://docs.ollama.com/context-length) for agents/coding tools |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | never let a second model eat your unified memory |
| `OLLAMA_FLASH_ATTENTION` | `1` | (llama.cpp backend) |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | (llama.cpp backend) |

Override them with environment variables if you launch the binary yourself:

```sh
OLLAMABAR_CONTEXT_LENGTH=32768 ./build/OllamaBar.app/Contents/MacOS/OllamaBar --start
```

Supported overrides: `OLLAMABAR_PORT`, `OLLAMABAR_KEEP_ALIVE`,
`OLLAMABAR_CONTEXT_LENGTH`, `OLLAMABAR_MAX_LOADED_MODELS`,
`OLLAMABAR_FLASH_ATTENTION`, `OLLAMABAR_KV_CACHE_TYPE`.

## CLI mode

Handy for scripts or shell aliases:

```sh
BIN=/Applications/OllamaBar.app/Contents/MacOS/OllamaBar
$BIN --start    # start server with defaults
$BIN --status   # stopped | running | running model-loaded
$BIN --warm     # preload first installed model
$BIN --stop     # unload models + stop server
```

## How it works

- **Start** spawns `ollama serve` as a child process with the environment above
  and logs to `~/.ollama/logs/server.log`.
- **Stop** asks Ollama to unload each loaded model, then terminates the server
  (and any user-owned `ollama serve` / `ollama runner` process, so RAM is
  always freed).
- The app is ad-hoc code-signed locally when built. If you download a prebuilt
  binary instead, you may need `xattr -dr com.apple.quarantine OllamaBar.app`.

## Notes & limitations

- Not affiliated with [Ollama](https://ollama.com) — just a convenience wrapper
  around the CLI you already have.
- "Stop" terminates *all* of your user-owned `ollama serve` processes, including
  ones started outside the app (e.g. `brew services`). If you prefer the
  background service instead, don't run both.
- The app only manages the server lifecycle; pulling models and configuration
  files are still plain Ollama (`ollama pull …`, `~/.ollama/…`).

## License

[MIT](LICENSE)
