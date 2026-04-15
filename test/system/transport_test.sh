#!/bin/sh
# Transport shortcuts and endpoints: @name abstract-namespace
# shortcut (both -b and -c), raw TCP endpoint, filesystem IPC path.

. "$(dirname "$0")/support.sh"

echo "@name shortcut:"
A=$(at_ipc)
$NNQ rep -b "$A" --echo -n 1 $T > /dev/null 2>>"$STDERR_LOG" &
REQ_OUT=$(echo 'shortcut' | $NNQ req -c "$A" -n 1 $T 2>>"$STDERR_LOG")
wait
check "@name resolves for -b and -c" "shortcut" "$REQ_OUT"

echo "TCP transport:"
$NNQ pull -b tcp://127.0.0.1:17299 -n 1 $T > $TMPDIR/tcp_out.txt 2>>"$STDERR_LOG" &
echo "tcp works" | $NNQ push -c tcp://127.0.0.1:17299 $T 2>>"$STDERR_LOG"
wait
check "tcp transport" "tcp works" "$(cat $TMPDIR/tcp_out.txt)"

echo "IPC filesystem:"
IPC_PATH="$TMPDIR/nnq_test.sock"
$NNQ pull -b "ipc://$IPC_PATH" -n 1 $T > $TMPDIR/ipc_fs_out.txt 2>>"$STDERR_LOG" &
echo "ipc works" | $NNQ push -c "ipc://$IPC_PATH" $T 2>>"$STDERR_LOG"
wait
check "ipc filesystem transport" "ipc works" "$(cat $TMPDIR/ipc_fs_out.txt)"
