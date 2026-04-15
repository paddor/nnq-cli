#!/bin/sh
# Scripting knobs: -F file input, -E send-side eval transforms, -E
# nil filter (skip message on nil).

. "$(dirname "$0")/support.sh"

echo "File input:"
U=$(ipc)
echo "from file" > $TMPDIR/nnq_file_input.txt
$NNQ pull -b $U -n 1 $T > $TMPDIR/file_out.txt 2>>"$STDERR_LOG" &
$NNQ push -c $U -F $TMPDIR/nnq_file_input.txt $T 2>>"$STDERR_LOG"
wait
check "-F reads from file" "from file" "$(cat $TMPDIR/file_out.txt)"

echo "Ruby eval on send (-E):"
U=$(ipc)
$NNQ pull -b $U -n 1 $T > $TMPDIR/eval_send_out.txt 2>>"$STDERR_LOG" &
echo 'hello' | $NNQ push -c $U -E 'it.upcase' $T 2>>"$STDERR_LOG"
wait
check "push -E transforms before send" "HELLO" "$(cat $TMPDIR/eval_send_out.txt)"

echo "Ruby eval filter nil:"
U=$(ipc)
$NNQ pull -b $U -n 1 $T > $TMPDIR/eval_filter_out.txt 2>>"$STDERR_LOG" &
printf 'skip\nkeep\n' | $NNQ push -c $U -E 'it == "skip" ? nil : it' $T 2>>"$STDERR_LOG"
wait
check "push -E nil skips message" "keep" "$(cat $TMPDIR/eval_filter_out.txt)"
