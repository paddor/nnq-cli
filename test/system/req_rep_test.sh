#!/bin/sh
# REQ/REP patterns: basic send/receive, echo mode, eval reply modes,
# verbose trace order, REQ -E generator mode, REQ -E+-e split.

. "$(dirname "$0")/support.sh"

echo "REQ/REP:"
U=$(ipc)
$NNQ rep -b $U -D "PONG" -n 1 $T > $TMPDIR/rep_out.txt 2>>"$STDERR_LOG" &
REQ_OUT=$(echo hello | $NNQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "req receives reply" "PONG" "$REQ_OUT"
check "rep receives request" "hello" "$(cat $TMPDIR/rep_out.txt)"

echo "REP echo:"
U=$(ipc)
$NNQ rep -b $U --echo -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_OUT=$(echo 'echo me' | $NNQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "rep --echo echoes back" "echo me" "$REQ_OUT"

echo "REP eval:"
U=$(ipc)
$NNQ rep -b $U -e 'it.upcase' -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_OUT=$(echo hello | $NNQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "rep -e 'it.upcase'" "HELLO" "$REQ_OUT"

echo "REP eval nil:"
U=$(ipc)
$NNQ rep -b $U -e 'nil' -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
EVAL_NIL_OUT=$(echo 'anything' | $NNQ req -c $U -n 1 $T 2>>"$STDERR_LOG")
wait
check "rep -e nil sends empty reply" "" "$EVAL_NIL_OUT"

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

# REQ with -E and no stdin input should produce requests from the
# eval alone, matching PUSH/PUB generator mode. -n bounds the run.
echo "REQ -E generator:"
U=$(ipc)
$NNQ rep -b $U -e 'it.upcase' -n 3 $T > $TMPDIR/rep_gen_out.txt 2>>"$STDERR_LOG" &
$NNQ req -c $U -E '"foo"' -n 3 $T > $TMPDIR/req_gen_out.txt 2>>"$STDERR_LOG"
wait
check "req -E generator sends N requests" "FOO
FOO
FOO" "$(cat $TMPDIR/req_gen_out.txt)"
check "rep sends N evaluated replies" "FOO
FOO
FOO" "$(cat $TMPDIR/rep_gen_out.txt)"

# -E upcases "hello" -> "HELLO", rep echoes, -e reverses -> "OLLEH"
echo "REQ -E and -e:"
U=$(ipc)
$NNQ rep -b $U --echo -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_SPLIT_OUT=$(echo 'hello' | $NNQ req -c $U -E 'it.upcase' -e 'it.reverse' -n 1 $T 2>>"$STDERR_LOG")
wait
check "req -E sends transformed, -e transforms reply" "OLLEH" "$REQ_SPLIT_OUT"
