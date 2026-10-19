# Security Policy

## Supported versions

Only the latest release is supported with security fixes.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Use GitHub's
private reporting instead:

1. Go to the [Security tab](https://github.com/yutna/ollama-bar/security)
2. Click **Report a vulnerability**
3. Describe the issue, reproduction steps, and impact

You can expect an initial response within a few days.

## Scope

OllamaBar is a local convenience wrapper with a deliberately small surface:

- It starts and stops a locally installed `ollama` binary and talks to its API
  on `127.0.0.1` only.
- It collects no data, has no network features of its own, no auto-update
  mechanism, and stores no credentials.
- Relevant reports include: command injection through configuration values,
  privilege issues around the spawned processes, or unintended handling of
  user data.

Vulnerabilities in [Ollama](https://github.com/ollama/ollama) itself should be
reported to that project.
