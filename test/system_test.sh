#!/bin/sh
#
# System tests for nnq-cli. Run from the repo root:
#   sh test/system_test.sh
#

set -eu

TMPDIR=$(mktemp -d)
export NNQ_DEV=1
NNQ="bundle exec ruby -Ilib exe/nnq"
T="-t 1"  # default timeout for all commands
PASS=0
FAIL=0

STDERR_LOG="$TMPDIR/stderr.log"
> "$STDERR_LOG"
echo "stderr log: $TMPDIR/stderr.log"

cleanup() {
	if [ $? -eq 0 ]
	then
		rm -rf "$TMPDIR"
	else
		cat $TMPDIR/stderr.log >&2
	fi
}

trap cleanup EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() {
  echo "  FAIL: $1 -- expected: '$2', got: '$3'"
  if [ -s "$STDERR_LOG" ]; then
    echo "        stderr: $(cat "$STDERR_LOG")"
  fi
  FAIL=$((FAIL + 1))
}

check() {
  name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name" "$expected" "$actual"
  fi
  > "$STDERR_LOG"
}

IPC_CTR="$TMPDIR/ipc_ctr"
echo 0 > "$IPC_CTR"
ipc() {
	N=$(cat "$IPC_CTR")
	N=$((N + 1))
	echo "$N" > "$IPC_CTR"
	echo "ipc://@nnq_test_${$}_${N}"
}

# @name shortcut — resolves to ipc://@nnq_test_$$_N
at_ipc() {
	N=$(cat "$IPC_CTR")
	N=$((N + 1))
	echo "$N" > "$IPC_CTR"
	echo "@nnq_test_${$}_${N}"
}

echo "=== nnq-cli system tests ==="
echo

# -- REQ/REP ---------------------------------------------------------

echo "REQ/REP:"
U=$(ipc)
$NNQ rep -b $U -D "PONG" -n 1 $T > $TMPDIR/rep_out.txt 2>>"$STDERR_LOG" &
REQ_OUT=$(echo hello | $NNQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "req receives reply" "PONG" "$REQ_OUT"
check "rep receives request" "hello" "$(cat $TMPDIR/rep_out.txt)"

# -- REP echo mode ---------------------------------------------------

echo "REP echo:"
U=$(ipc)
$NNQ rep -b $U --echo -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_OUT=$(echo 'echo me' | $NNQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "rep --echo echoes back" "echo me" "$REQ_OUT"

# -- REP eval --------------------------------------------------------

echo "REP eval:"
U=$(ipc)
$NNQ rep -b $U -e 'it.upcase' -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_OUT=$(echo hello | $NNQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "rep -e 'it.upcase'" "HELLO" "$REQ_OUT"

# -- Verbose REQ/REP trace order ------------------------------------
# REQ should log >> (send request) then << (recv reply).
# REP should log << (recv request) then >> (send reply).

echo "REQ/REP verbose trace:"
U=$(ipc)
REP_LOG="$TMPDIR/rep_trace.log"
REQ_LOG="$TMPDIR/req_trace.log"
$NNQ rep -b $U -e 'it.upcase' -n 1 -vvv $T > /dev/null 2>"$REP_LOG" &
echo 'hi' | $NNQ req -c $U -n 1 -vvv $T > /dev/null 2>"$REQ_LOG"
wait

extract_trace() {
  grep -oE 'nnq: (>>|<<) \([^)]*\) .*' "$1" \
    | sed -E 's/^nnq: (>>|<<) \([^)]*\) /\1 /'
}

REQ_TRACE=$(extract_trace "$REQ_LOG" | tr '\n' '|' | sed 's/|$//')
REP_TRACE=$(extract_trace "$REP_LOG" | tr '\n' '|' | sed 's/|$//')

check "req -vvv trace (>> hi, << HI)" ">> hi|<< HI" "$REQ_TRACE"
check "rep -vvv trace (<< hi, >> HI)" "<< hi|>> HI" "$REP_TRACE"

# -- PUSH/PULL -------------------------------------------------------

echo "PUSH/PULL:"
U=$(ipc)
$NNQ pull -b $U -n 1 $T > $TMPDIR/pull_out.txt 2>>"$STDERR_LOG" &
echo task-1 | $NNQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "pull receives message" "task-1" "$(cat $TMPDIR/pull_out.txt)"

# -- PUB/SUB ---------------------------------------------------------

echo "PUB/SUB:"
U=$(ipc)
$NNQ sub -b $U -s "weather." -n 1 $T > $TMPDIR/sub_out.txt 2>>"$STDERR_LOG" &
$NNQ pub -c $U -D "weather.nyc 72F" -n 1 $T 2>>"$STDERR_LOG"
wait
check "sub receives matching message" "weather.nyc 72F" "$(cat $TMPDIR/sub_out.txt)"

# -- @name abstract-namespace shortcut (both -b and -c) -------------

echo "@name shortcut:"
A=$(at_ipc)
$NNQ rep -b "$A" --echo -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_OUT=$(echo 'shortcut' | $NNQ req -c "$A" -n 1 $T 2>>"$STDERR_LOG")
wait
check "@name resolves for -b and -c" "shortcut" "$REQ_OUT"

# -- File input (-F) ------------------------------------------------

echo "File input:"
U=$(ipc)
echo "from file" > $TMPDIR/nnq_file_input.txt
$NNQ pull -b $U -n 1 $T > $TMPDIR/file_out.txt 2>>"$STDERR_LOG" &
$NNQ push -c $U -F $TMPDIR/nnq_file_input.txt $T 2>>"$STDERR_LOG"
wait
check "-F reads from file" "from file" "$(cat $TMPDIR/file_out.txt)"

# -- Ruby eval on send side (-E) ------------------------------------

echo "Ruby eval on send (-E):"
U=$(ipc)
$NNQ pull -b $U -n 1 $T > $TMPDIR/eval_send_out.txt 2>>"$STDERR_LOG" &
echo 'hello' | $NNQ push -c $U -E 'it.upcase' $T 2>>"$STDERR_LOG"
wait
check "push -E transforms before send" "HELLO" "$(cat $TMPDIR/eval_send_out.txt)"

# -- Ruby eval filter (nil skips) -----------------------------------

echo "Ruby eval filter nil:"
U=$(ipc)
$NNQ pull -b $U -n 1 $T > $TMPDIR/eval_filter_out.txt 2>>"$STDERR_LOG" &
printf 'skip\nkeep\n' | $NNQ push -c $U -E 'it == "skip" ? nil : it' $T 2>>"$STDERR_LOG"
wait
check "push -E nil skips message" "keep" "$(cat $TMPDIR/eval_filter_out.txt)"

# -- REP eval nil (empty reply) -------------------------------------

echo "REP eval nil:"
U=$(ipc)
$NNQ rep -b $U -e 'nil' -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
EVAL_NIL_OUT=$(echo 'anything' | $NNQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "rep -e nil sends empty reply" "" "$EVAL_NIL_OUT"

# -- REQ: -E transforms outgoing, -e transforms reply ---------------

echo "REQ -E and -e:"
U=$(ipc)
$NNQ rep -b $U --echo -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_SPLIT_OUT=$(echo 'hello' | $NNQ req -c $U -E 'it.upcase' -e 'it.reverse' -n 1 $T 2>>"$STDERR_LOG")
wait
# -E upcases "hello" -> "HELLO", rep echoes, -e reverses -> "OLLEH"
check "req -E sends transformed, -e transforms reply" "OLLEH" "$REQ_SPLIT_OUT"

# -- Quoted format --------------------------------------------------

echo "Quoted format:"
U=$(ipc)
$NNQ pull -b $U -n 1 -Q $T > $TMPDIR/quoted_out.txt 2>>"$STDERR_LOG" &
printf 'hello\001world' | $NNQ push -c $U --raw $T 2>>"$STDERR_LOG"
wait
check "quoted format escapes non-printable" 'hello\x01world' "$(cat $TMPDIR/quoted_out.txt)"

# -- Compression (-z) -----------------------------------------------

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

# -- Compression with REQ/REP ---------------------------------------
# Regression: nnq-zstd wrapper's send_request used to return the raw
# encoded reply wire, so the REQ side printed "....HELLO" (NUL
# preamble) instead of "HELLO".

echo "Compression REQ/REP:"
U=$(ipc)
$NNQ rep -b $U -e 'it.upcase' -z -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_Z_OUT=$(echo hello | $NNQ req -c $U -z -n 1 $T 2>>"$STDERR_LOG")
wait
check "req/rep -z round-trip" "HELLO" "$REQ_Z_OUT"

echo "Compression REQ/REP -Z (balanced):"
U=$(ipc)
$NNQ rep -b $U -e 'it.upcase' -Z -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_ZZ_OUT=$(echo hello | $NNQ req -c $U -Z -n 1 $T 2>>"$STDERR_LOG")
wait
check "req/rep -Z round-trip" "HELLO" "$REQ_ZZ_OUT"

# -- Compression wire size trace (-z -vvv) --------------------------
# 1000 Zs compress to <1000 bytes; pull side logs wire=NB with N<1000.

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

# -- Interval sending (-i) ------------------------------------------

echo "Interval -i with -D:"
U=$(ipc)
$NNQ pull -b $U -n 3 $T > $TMPDIR/interval_out.txt 2>>"$STDERR_LOG" &
$NNQ push -c $U -D "tick" -i 0.1 -n 3 $T 2>>"$STDERR_LOG"
wait
check "interval sends N messages" "3" "$(wc -l < $TMPDIR/interval_out.txt | tr -d ' ')"

echo "Interval -i with -E (no stdin):"
U=$(ipc)
$NNQ pull -b $U -n 3 $T > $TMPDIR/interval_eval_out.txt 2>>"$STDERR_LOG" &
$NNQ push -c $U -E '"tick"' -i 0.1 -n 3 $T 2>>"$STDERR_LOG"
wait
check "interval -E generates messages without input" "3" "$(wc -l < $TMPDIR/interval_eval_out.txt | tr -d ' ')"

# -- Interval quantized timing --------------------------------------

echo "Interval timing:"
U=$(ipc)
$NNQ pull -b $U -n 3 $T > /dev/null 2>>"$STDERR_LOG" &
START=$(date +%s%N)
$NNQ push -c $U -D "tick" -i 0.2 -n 3 $T 2>>"$STDERR_LOG"
END=$(date +%s%N)
wait
ELAPSED_MS=$(( (END - START) / 1000000 ))
if [ "$ELAPSED_MS" -ge 300 ] && [ "$ELAPSED_MS" -le 1500 ]; then
  TIMING_OK="yes"
else
  TIMING_OK="no (${ELAPSED_MS}ms)"
fi
check "quantized interval keeps cadence" "yes" "$TIMING_OK"

# -- Pull with interval (rate-limited recv) -------------------------

echo "Pull -i rate-limited recv:"
U=$(ipc)
START=$(date +%s%N)
$NNQ pull -b $U -n 3 -i 0.2 $T > $TMPDIR/pull_interval_out.txt 2>>"$STDERR_LOG" &
PULL_PID=$!
sleep 0.1
seq 5 | $NNQ push -c $U $T 2>>"$STDERR_LOG"
wait $PULL_PID
END=$(date +%s%N)
ELAPSED_MS=$(( (END - START) / 1000000 ))
check "pull -i receives correct count" "3" "$(wc -l < $TMPDIR/pull_interval_out.txt | tr -d ' ')"
if [ "$ELAPSED_MS" -ge 300 ] && [ "$ELAPSED_MS" -le 2500 ]; then
  PULL_TIMING="yes"
else
  PULL_TIMING="no (${ELAPSED_MS}ms)"
fi
check "pull -i rate-limits recv cadence" "yes" "$PULL_TIMING"

# -- Delay (-d) before first send -----------------------------------

echo "Delay -d:"
U=$(ipc)
$NNQ pull -b $U -n 1 -t 3 > $TMPDIR/delay_out.txt 2>>"$STDERR_LOG" &
START=$(date +%s%N)
echo delayed | $NNQ push -c $U -d 0.3 -t 3 2>>"$STDERR_LOG"
END=$(date +%s%N)
wait
ELAPSED_MS=$(( (END - START) / 1000000 ))
check "push -d delivers message" "delayed" "$(cat $TMPDIR/delay_out.txt)"
if [ "$ELAPSED_MS" -ge 300 ]; then
  DELAY_OK="yes"
else
  DELAY_OK="no (${ELAPSED_MS}ms)"
fi
check "push -d waited at least 300ms" "yes" "$DELAY_OK"

# -- --transient: exit when peers disconnect -------------------------

echo "Transient:"
U=$(ipc)
$NNQ pull -b $U --transient -t 5 > $TMPDIR/trans_out.txt 2>>"$STDERR_LOG" &
TRANS_PID=$!
sleep 0.3
seq 3 | $NNQ push -c $U -t 3 2>>"$STDERR_LOG"
if wait $TRANS_PID 2>/dev/null; then
  check "pull --transient exits when sender disconnects" "3" "$(wc -l < $TMPDIR/trans_out.txt | tr -d ' ')"
else
  fail "pull --transient exits when sender disconnects" "clean exit + 3 msgs" "timeout"
fi

# -- HWM option -----------------------------------------------------

echo "HWM option:"
U=$(ipc)
$NNQ pull -b $U --hwm 10 -n 1 $T > $TMPDIR/hwm_out.txt 2>>"$STDERR_LOG" &
echo 'hwm test' | $NNQ push -c $U --hwm 10 $T 2>>"$STDERR_LOG"
wait
check "--hwm accepted" "hwm test" "$(cat $TMPDIR/hwm_out.txt)"

# -- TCP transport --------------------------------------------------

echo "TCP transport:"
$NNQ pull -b tcp://127.0.0.1:17299 -n 1 $T > $TMPDIR/tcp_out.txt 2>>"$STDERR_LOG" &
echo "tcp works" | $NNQ push -c tcp://127.0.0.1:17299 $T 2>>"$STDERR_LOG"
wait
check "tcp transport" "tcp works" "$(cat $TMPDIR/tcp_out.txt)"

# -- IPC filesystem transport ---------------------------------------

echo "IPC filesystem:"
IPC_PATH="$TMPDIR/nnq_test.sock"
$NNQ pull -b "ipc://$IPC_PATH" -n 1 $T > $TMPDIR/ipc_fs_out.txt 2>>"$STDERR_LOG" &
echo "ipc works" | $NNQ push -c "ipc://$IPC_PATH" $T 2>>"$STDERR_LOG"
wait
check "ipc filesystem transport" "ipc works" "$(cat $TMPDIR/ipc_fs_out.txt)"

# -- Pipe with -e ---------------------------------------------------

echo "Pipe -e:"
PIPE_IN="ipc://@nnq_pipe_in_$$"
PIPE_OUT="ipc://@nnq_pipe_out_$$"
$NNQ push -b $PIPE_IN -D "piped" -d 0.5 -t 3 2>>"$STDERR_LOG" &
$NNQ pull -b $PIPE_OUT -n 1 -t 3 > $TMPDIR/pipe_e_out.txt 2>>"$STDERR_LOG" &
$NNQ pipe -c $PIPE_IN -c $PIPE_OUT -e 'it.upcase' -n 1 -t 3 2>>"$STDERR_LOG" &
wait
check "pipe -e transforms in pipeline" "PIPED" "$(cat $TMPDIR/pipe_e_out.txt)"

# -- Validation: duplicate endpoints --------------------------------

echo "Validation:"
$NNQ push -c tcp://x:1 -b tcp://x:1 2>$TMPDIR/val_dup.txt && EXITCODE=0 || EXITCODE=$?
check "duplicate endpoints errors" "1" "$EXITCODE"

$NNQ pipe --in -c tcp://x:1 2>$TMPDIR/val_pipe_in.txt && EXITCODE=0 || EXITCODE=$?
check "pipe --in without --out errors" "1" "$EXITCODE"

# -- Summary ---------------------------------------------------------

echo
echo "=== $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
