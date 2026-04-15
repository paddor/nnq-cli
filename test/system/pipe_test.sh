#!/bin/sh
# Pipe virtual socket: PULL -> eval -> PUSH with an inline -e
# transform running between two independent endpoints.

. "$(dirname "$0")/support.sh"

echo "Pipe -e:"
PIPE_IN="ipc://@nnq_pipe_in_$$"
PIPE_OUT="ipc://@nnq_pipe_out_$$"
$NNQ push -b $PIPE_IN -D "piped" -d 0.5 -t 3 2>>"$STDERR_LOG" &
$NNQ pull -b $PIPE_OUT -n 1 -t 3 > $TMPDIR/pipe_e_out.txt 2>>"$STDERR_LOG" &
$NNQ pipe -c $PIPE_IN -c $PIPE_OUT -e 'it.upcase' -n 1 -t 3 2>>"$STDERR_LOG" &
wait
check "pipe -e transforms in pipeline" "PIPED" "$(cat $TMPDIR/pipe_e_out.txt)"
