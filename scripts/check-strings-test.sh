#!/bin/sh
# Guards the format-specifier rules of check-strings.pl with fixtures: safe
# translations must pass, unsafe ones must fail. Run from the repository root
# (`make lint` does); exits non-zero on a fixture that behaves unexpectedly.
set -u
CHECK=$(cd "$(dirname "$0")" && pwd)/check-strings.pl
if [ ! -f "$CHECK" ]; then
    echo "check-strings-test.sh: cannot find check-strings.pl at $CHECK" >&2
    exit 1
fi
DIR=$(mktemp -d) || exit 1
trap 'rm -rf "$DIR"' EXIT
cd "$DIR" || exit 1

printf '%s\n' \
    '"warm" = "Warmed %@ in %d s";' \
    '"plain" = "Just %@";' \
    '"two" = "%@ and %d";' \
    '"pct" = "100%% of %d";' > ref.strings

# write4 <file> <warm> <two> <plain>: four keys, one per line, like the real
# .strings files the checker parses.
write4() {
    printf '%s\n' \
        "\"warm\" = \"$2\";" \
        "\"plain\" = \"$4\";" \
        "\"two\" = \"$3\";" \
        '"pct" = "100%% ของ %d";' > "$1"
}

write4 same-plain.strings "อุ่น %@ ใน %d วินาที" "%@ กับ %d" "แค่ %@"
write4 reorder-positional.strings "ใช้เวลา %2\$d วินาที กับ %1\$@" "%@ กับ %d" "แค่ %@"
write4 positional-same-order.strings "อุ่น %1\$@ ใน %2\$d วินาที" "%@ กับ %d" "แค่ %@"
write4 duplicate-same.strings "%1\$@ แล้ว %1\$@ อีกครั้งใน %2\$d วินาที" "%@ กับ %d" "แค่ %@"
write4 swap-plain.strings "อบอุ่น %@ ใน %d วินาที" "%d กับ %@" "แค่ %@"
write4 missing-arg.strings "อุ่น %@" "%@ กับ %d" "แค่ %@"
write4 extra-arg.strings "อุ่น %@ ใน %d วินาที" "%@ กับ %d" "แค่ %@ และ %d"
write4 duplicate-conflict.strings "%1\$@ กับ %1\$d ใน %2\$d วินาที" "%@ กับ %d" "แค่ %@"

failures=0
expect() {
    expected=$1
    file=$2
    if perl "$CHECK" ref.strings "$file" >/dev/null 2>&1; then
        got=pass
    else
        got=fail
    fi
    if [ "$got" != "$expected" ]; then
        printf 'BAD: %s should %s (got %s)\n' "$file" "$expected" "$got"
        failures=$((failures + 1))
    fi
}

# Safe translations: same order, positional reorders, repeated use of one
# argument, and a literal %% must all pass.
expect pass same-plain.strings
expect pass reorder-positional.strings
expect pass positional-same-order.strings
expect pass duplicate-same.strings
# Unsafe ones: swapped plain specifiers (String(format:) would read an Int as
# an object pointer), dropped or added arguments, one argument used with two
# types.
expect fail swap-plain.strings
expect fail missing-arg.strings
expect fail extra-arg.strings
expect fail duplicate-conflict.strings

if [ "$failures" -ne 0 ]; then
    echo "check-strings fixtures: $failures unexpected result(s)"
    exit 1
fi
echo "check-strings fixtures OK: 8 cases"
