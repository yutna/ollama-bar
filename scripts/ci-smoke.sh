#!/bin/sh
# Integration smoke test for the OllamaBar CLI against scripts/fake_ollama.py.
#
# Usage: scripts/ci-smoke.sh
#   BIN  path to the built binary (default: build/OllamaBar.app/Contents/MacOS/OllamaBar)
#   PORT port for the fake server (default: 18134)
set -eu

BIN="${BIN:-build/OllamaBar.app/Contents/MacOS/OllamaBar}"
PORT="${PORT:-18134}"
FAKE_PID=""

start_fake() {
    python3 scripts/fake_ollama.py "$PORT" "$1" &
    FAKE_PID=$!
    sleep 1
}

stop_fake() {
    if [ -n "$FAKE_PID" ]; then
        kill "$FAKE_PID" 2>/dev/null || true
        wait "$FAKE_PID" 2>/dev/null || true
        FAKE_PID=""
    fi
}
trap stop_fake EXIT

echo "== --help prints usage =="
"$BIN" --help >/dev/null

echo "== healthy fake server =="
start_fake healthy
status=$(OLLAMABAR_PORT="$PORT" "$BIN" --status)
echo "status: $status"
if [ "$status" != "running model-loaded" ]; then
    echo "FAIL: expected 'running model-loaded', got '$status'"
    exit 1
fi
stop_fake

echo "smoke: OK"
