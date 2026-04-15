#!/bin/sh
# PUSH/PULL patterns: basic fan-out, PUSH -E generator, delay (-d),
# --transient, --hwm.

. "$(dirname "$0")/support.sh"

echo "PUSH/PULL:"
U=$(ipc)
$NNQ pull -b $U -n 1 $T > $TMPDIR/pull_out.txt 2>>"$STDERR_LOG" &
echo task-1 | $NNQ push -c $U $T 2>>"$STDERR_LOG"
wait
check "pull receives message" "task-1" "$(cat $TMPDIR/pull_out.txt)"

# PUSH with -E and no stdin input generates messages from the eval
# alone — same shape as the REQ -E generator test.
echo "PUSH -E generator:"
U=$(ipc)
$NNQ pull -b $U -n 3 $T > $TMPDIR/push_gen_out.txt 2>>"$STDERR_LOG" &
$NNQ push -c $U -E '"tick"' -n 3 $T 2>>"$STDERR_LOG"
wait
check "push -E generator sends N messages" "tick
tick
tick" "$(cat $TMPDIR/push_gen_out.txt)"

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

echo "HWM option:"
U=$(ipc)
$NNQ pull -b $U --hwm 10 -n 1 $T > $TMPDIR/hwm_out.txt 2>>"$STDERR_LOG" &
echo 'hwm test' | $NNQ push -c $U --hwm 10 $T 2>>"$STDERR_LOG"
wait
check "--hwm accepted" "hwm test" "$(cat $TMPDIR/hwm_out.txt)"
