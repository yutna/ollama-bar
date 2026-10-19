#!/bin/sh
# Integration smoke test for the OllamaBar CLI against scripts/fake_ollama.pl.
#
# Usage: scripts/ci-smoke.sh
#   BIN  path to the built binary (default: build/OllamaBar.app/Contents/MacOS/OllamaBar)
#   PORT base port for the fake servers (default: 18134)
set -eu

BIN="${BIN:-build/OllamaBar.app/Contents/MacOS/OllamaBar}"
BASE_PORT="${PORT:-18134}"
PERL="${PERL:-/usr/bin/perl}"
[ -x "$PERL" ] || PERL=perl
FAKE_PID=""
FAKE_LOG=""

start_fake() {
    port="$1"
    mode="$2"
    FAKE_LOG="${TMPDIR:-/tmp}/ollamabar-fake-${port}.log"
    "$PERL" scripts/fake_ollama.pl "$port" "$mode" >"$FAKE_LOG" 2>&1 &
    FAKE_PID=$!
    n=0
    while [ "$n" -lt 20 ]; do
        if curl -s --max-time 1 "http://127.0.0.1:$port/api/version" >/dev/null 2>&1; then
            return 0
        fi
        if ! kill -0 "$FAKE_PID" 2>/dev/null; then
            break
        fi
        n=$((n + 1))
        sleep 0.5
    done
    echo "FAIL: fake server (mode $mode) did not start on port $port"
    if kill -0 "$FAKE_PID" 2>/dev/null; then
        echo "process is still running:"
        ps -p "$FAKE_PID" -o pid,stat,command || true
    else
        echo "process exited during startup:"
    fi
    lsof -nP -iTCP:"$port" -sTCP:LISTEN || true
    cat "$FAKE_LOG" || true
    exit 1
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

PORT="$BASE_PORT"
echo "== healthy fake server =="
start_fake "$PORT" healthy
status=$(OLLAMABAR_PORT="$PORT" "$BIN" --status)
echo "status: $status"
if [ "$status" != "running model-loaded" ]; then
    echo "FAIL: expected 'running model-loaded', got '$status'"
    exit 1
fi
stop_fake

PORT=$((BASE_PORT + 1))
echo "== --warm preloads the fake model =="
start_fake "$PORT" healthy
set +e
warmed=$(OLLAMABAR_PORT="$PORT" "$BIN" --warm)
warm_rc=$?
set -e
echo "warm: $warmed (exit $warm_rc)"
if [ "$warm_rc" -ne 0 ] || [ "$warmed" != "loaded" ]; then
    echo "FAIL: expected 'loaded' with exit 0, got '$warmed' (exit $warm_rc)"
    exit 1
fi
stop_fake

PORT=$((BASE_PORT + 2))
echo "== impostor server (404) is not mistaken for Ollama =="
start_fake "$PORT" impostor
status=$(OLLAMABAR_PORT="$PORT" "$BIN" --status)
echo "status: $status"
if [ "$status" != "stopped" ]; then
    echo "FAIL: expected 'stopped' for a non-Ollama server, got '$status'"
    exit 1
fi
stop_fake

echo "== --stop with nothing running =="
if ! OLLAMABAR_PORT="$((BASE_PORT + 3))" "$BIN" --stop >/dev/null; then
    echo "FAIL: --stop exited non-zero with nothing running"
    exit 1
fi

echo "smoke: OK"
