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

# `--stop` signals every `ollama serve` / `ollama runner` process by name (the
# port does not matter: Stop means "nothing is left running"). On a developer
# machine that may be a real server with loaded models, so detect it up front
# and skip that one step instead of killing someone's work. CI has no ollama,
# so the step still runs there.
SKIP_STOP=""
if pgrep -f "ollama serve" >/dev/null 2>&1; then
    SKIP_STOP=1
    echo "note: a real ollama server is running; skipping the --stop step"
fi

# Runs "$@" with a 10s watchdog so a regression that turns an option into a
# running GUI app fails the smoke test instead of hanging until job timeout.
# Sets CLI_RC and CLI_OUTPUT; exits on a watchdog kill.
run_cli() {
    cli_out="${TMPDIR:-/tmp}/ollamabar-cli-$$.out"
    "$@" >"$cli_out" 2>&1 &
    cli_pid=$!
    ( sleep 10; kill -9 "$cli_pid" 2>/dev/null ) &
    cli_watchdog=$!
    set +e
    wait "$cli_pid"
    CLI_RC=$?
    set -e
    kill "$cli_watchdog" 2>/dev/null || true
    wait "$cli_watchdog" 2>/dev/null || true
    CLI_OUTPUT=$(cat "$cli_out")
    rm -f "$cli_out"
    if [ "$CLI_RC" -eq 137 ]; then
        echo "FAIL: '$*' did not exit within 10s"
        exit 1
    fi
}

echo "== --help prints usage =="
"$BIN" --help >/dev/null

echo "== --version prints the bundle version =="
run_cli "$BIN" --version
echo "version: $CLI_OUTPUT"
case "$CLI_OUTPUT" in
    "OllamaBar "*) ;;
    *)
        echo "FAIL: unexpected --version output '$CLI_OUTPUT'"
        exit 1
        ;;
esac

echo "== unknown option fails instead of launching the app =="
run_cli "$BIN" --bogus
if [ "$CLI_RC" -eq 0 ]; then
    echo "FAIL: --bogus exited 0"
    exit 1
fi
case "$CLI_OUTPUT" in
    *"unknown option '--bogus'"*) ;;
    *)
        echo "FAIL: --bogus did not report the unknown option"
        exit 1
        ;;
esac

echo "== log pump drains stdin and rotates past the cap =="
pump_dir="${TMPDIR:-/tmp}/ollamabar-pump-$$"
pump_log="$pump_dir/server.log"
mkdir -p "$pump_dir"
# ~9 KB of input with a 1 KB cap must rotate at least once.
i=0
while [ "$i" -lt 200 ]; do
    echo "line $i 0123456789abcdefghijklmnopqrstuvwxyz"
    i=$((i + 1))
done | OLLAMABAR_LOG_MAX_BYTES=1024 "$BIN" --log-pump "$pump_log"
if [ ! -s "$pump_log.1" ]; then
    echo "FAIL: log pump did not rotate past the 1 KB cap"
    exit 1
fi
grep -q "line 0 " "$pump_log.1" || {
    echo "FAIL: rotated log does not contain the first lines"
    exit 1
}
current=$(wc -c <"$pump_log" | tr -d ' ')
if [ "$current" -gt 1024 ]; then
    echo "FAIL: log pump left $current bytes, above the 1 KB cap"
    exit 1
fi
previous=$(wc -c <"$pump_log.1" | tr -d ' ')
echo "log: $current bytes, rotated: $previous bytes"
rm -rf "$pump_dir"

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
echo "== --warm preloads a model on a cold server =="
start_fake "$PORT" cold
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
if [ -n "$SKIP_STOP" ]; then
    echo "SKIPPED: a real ollama server is running, --stop would have stopped it"
else
    if ! OLLAMABAR_PORT="$((BASE_PORT + 3))" "$BIN" --stop >/dev/null; then
        echo "FAIL: --stop exited non-zero with nothing running"
        exit 1
    fi
fi

echo "smoke: OK"
