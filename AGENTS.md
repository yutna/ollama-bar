# Notes for AI agents

OllamaBar is a macOS menu bar app plus a scriptable CLI for a local Ollama
server. Human-facing setup and contribution rules live in `CONTRIBUTING.md`;
this file records environment gotchas that are easy to rediscover the hard way.

**Privacy rule:** never commit, paste into issues or PRs, or document
machine-specific details — local usernames, full home-directory paths, installed
app versions, or anything else that describes someone's particular Mac. Stick to
standard macOS locations and generic instructions.

## Spotlight indexes the dev build

`make build` leaves `build/OllamaBar.app` inside the repository, and macOS
Spotlight/Launchpad index it. On a Mac that also has OllamaBar installed
(usually `/Applications` or `~/Applications`), search then shows **two** copies,
often with different icons or versions. It looks like a packaging bug in a
release but is only the local build sitting next to the installed app.

- Do **not** try to hide it with `.metadata_never_index` or `.noindex` files in
  `build/`: on current macOS neither keeps a freshly built bundle out of the
  index (verified), so shipping such a workaround would be misleading.
- To avoid the duplicate, delete the dev bundle when it is not needed
  (`rm -rf build/OllamaBar.app`) or add the folder to
  *System Settings → Siri & Spotlight → Spotlight Privacy*.
- CI and release builds are unaffected; this only affects interactive machines.

## The server log is written by a separate `--log-pump` process

`OllamaService` gives `ollama serve` a pipe and runs the same binary with
`--log-pump <path>` to drain it into `~/.ollama/logs/server.log`. The reader is
a separate process on purpose: `--start` exits right after spawning the server
and the GUI app can be replaced by a dev build, and an in-process reader would
close the pipe with it — the still-running server then gets SIGPIPE on its next
log write and dies (verified against real Ollama; the smoke test cannot catch
this because the Perl fake server never writes to stdout).

Rotating the log while the server runs is only possible because the app's side
of the pipe owns the file handle. Do not "simplify" this back to handing the
child a file handle: rotation would then be limited to start, and a long
session could grow the log without bound.

## The fake Ollama server is Perl on purpose

`scripts/fake_ollama.pl` is the test double used by `scripts/ci-smoke.sh`. It is
written in Perl — a system runtime that starts in milliseconds — because a
Python fake server was observed hanging before it bound its port on a managed
CI runner. Do not replace it with a Python implementation.

## Releases

Tags are annotated (and may be signed). Create them non-interactively so git
never opens an editor, e.g. `GIT_EDITOR=true git tag -a vX.Y.Z -m "..."`, then
`git push origin main vX.Y.Z`. The release workflow verifies that the tag
matches `CFBundleShortVersionString` in `resources/Info.plist` and a
`## [X.Y.Z]` heading in `CHANGELOG.md` before it publishes anything.

## Checks to run before proposing changes

- `make lint` — swift-format plus the localization key/specifier/`Info.plist`
  check
- `make test` — SwiftPM unit tests
- `./scripts/ci-smoke.sh` — CLI integration smoke test against the fake server
