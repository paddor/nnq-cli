#!/bin/sh
# Per-frame zstd compression (-z / -Z): large and small payload
# round-trips, REQ/REP regression (the wrapper used to return the
# encoded reply untouched, leaking a NUL preamble rendered as dots),
# a byte-level NO-DOTS assertion on stdout, and a wire-size trace
# check proving compression actually shrinks the wire.

. "$(dirname "$0")/support.sh"

echo "Compression (large):"
U=$(ipc)
PAYLOAD=$(ruby -e "puts 'x' * 200")
$NNQ pull -b $U -n 1 -z $T > $TMPDIR/compress_out.txt 2>>"$STDERR_LOG" &
echo "$PAYLOAD" | $NNQ push -c $U -z $T 2>>"$STDERR_LOG"
wait
check "compression round-trip (large)" "$PAYLOAD" "$(cat $TMPDIR/compress_out.txt)"

echo "Compression (small):"
U=$(ipc)
$NNQ pull -b $U -n 1 -z $T > $TMPDIR/compress_small_out.txt 2>>"$STDERR_LOG" &
echo 'tiny' | $NNQ push -c $U -z $T 2>>"$STDERR_LOG"
wait
check "compression round-trip (small)" "tiny" "$(cat $TMPDIR/compress_small_out.txt)"

# Regression: nnq-zstd Wrapper#send_request used to return the raw
# encoded reply wire, so REQ printed "....HELLO" (NUL preamble)
# instead of "HELLO".
echo "Compression REQ/REP:"
U=$(ipc)
$NNQ rep -b $U -e 'it.upcase' -z -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_Z_OUT=$(echo hello | $NNQ req -c $U -z -n 1 $T 2>>"$STDERR_LOG")
wait
check "req/rep -z round-trip" "HELLO" "$REQ_Z_OUT"

# Strict byte-level NO-DOTS assertion: the NUL preamble / zstd magic
# must never leak into stdout. "HELLO\n" = 48454c4c4f0a, exactly.
echo "Compression REQ/REP hex (NO DOTS):"
U=$(ipc)
$NNQ rep -b $U --echo -z -n 1 $T > $TMPDIR/rep_hex_out.bin 2>>"$STDERR_LOG" &
echo HELLO | $NNQ req -c $U -z -n 1 $T > $TMPDIR/req_hex_out.bin 2>>"$STDERR_LOG"
wait
REP_HEX=$(xxd -p < $TMPDIR/rep_hex_out.bin | tr -d '\n')
REQ_HEX=$(xxd -p < $TMPDIR/req_hex_out.bin | tr -d '\n')
check "rep -z stdout is clean HELLO (hex)" "48454c4c4f0a" "$REP_HEX"
check "req -z stdout is clean HELLO (hex)" "48454c4c4f0a" "$REQ_HEX"

echo "Compression REQ/REP -Z (balanced):"
U=$(ipc)
$NNQ rep -b $U -e 'it.upcase' -Z -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_ZZ_OUT=$(echo hello | $NNQ req -c $U -Z -n 1 $T 2>>"$STDERR_LOG")
wait
check "req/rep -Z round-trip" "HELLO" "$REQ_ZZ_OUT"

# 1000 Zs should compress to far less than 1000 bytes; the pull
# side's -vvv trace must log a wire size < 1000.
echo "Compression wire size trace:"
U=$(ipc)
PAYLOAD=$(ruby -e "print 'Z' * 1000")
PULL_LOG="$TMPDIR/wire_pull.log"
$NNQ pull -b $U -n 1 -z -vvv $T > $TMPDIR/wire_out.txt 2>"$PULL_LOG" &
printf '%s' "$PAYLOAD" | $NNQ push -c $U -z $T 2>>"$STDERR_LOG"
wait
# nnq -vvv trace format: "nnq: << (NB) preview"
PULL_WIRE=$(grep -oE '<<[[:space:]]+\([0-9]+B\)' "$PULL_LOG" | head -1 | grep -oE '[0-9]+' || echo "")
if [ -n "$PULL_WIRE" ] && [ "$PULL_WIRE" -lt 1000 ]; then
  pass "pull -vvv logs wire=${PULL_WIRE}B < 1000"
else
  fail "pull -vvv wire size" "<1000" "$PULL_WIRE"
  [ -f "$PULL_LOG" ] && cat "$PULL_LOG" >&2
fi
