#!/bin/sh
# Interval (-i) behaviour on both send and recv: bounded send with
# -D/-E, quantized cadence timing, and rate-limited pull.

. "$(dirname "$0")/support.sh"

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
