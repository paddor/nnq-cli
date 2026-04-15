#!/bin/sh
# Output format options: quoted (-Q) escapes non-printable bytes.

. "$(dirname "$0")/support.sh"

echo "Quoted format:"
U=$(ipc)
$NNQ pull -b $U -n 1 -Q $T > $TMPDIR/quoted_out.txt 2>>"$STDERR_LOG" &
printf 'hello\001world' | $NNQ push -c $U --raw $T 2>>"$STDERR_LOG"
wait
check "quoted format escapes non-printable" 'hello\x01world' "$(cat $TMPDIR/quoted_out.txt)"
