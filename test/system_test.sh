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

# -- Summary ---------------------------------------------------------

echo
echo "=== $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ]
