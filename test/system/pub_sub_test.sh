#!/bin/sh
# PUB/SUB patterns: basic subscribe-prefix match, PUB -E generator.

. "$(dirname "$0")/support.sh"

echo "PUB/SUB:"
U=$(ipc)
$NNQ sub -b $U -s "weather." -n 1 $T > $TMPDIR/sub_out.txt 2>>"$STDERR_LOG" &
$NNQ pub -c $U -D "weather.nyc 72F" -n 1 $T 2>>"$STDERR_LOG"
wait
check "sub receives matching message" "weather.nyc 72F" "$(cat $TMPDIR/sub_out.txt)"

# PUB with -E and no stdin input should produce messages from the
# eval alone. -i keeps firing so SUB has time to subscribe before
# messages go out.
echo "PUB -E generator:"
U=$(ipc)
$NNQ sub -b $U -s "" -n 3 $T > $TMPDIR/sub_gen_out.txt 2>>"$STDERR_LOG" &
$NNQ pub -c $U -E '"tick"' -i 0.05 -n 3 $T 2>>"$STDERR_LOG"
wait
check "pub -E generator, sub receives N" "tick
tick
tick" "$(cat $TMPDIR/sub_gen_out.txt)"
