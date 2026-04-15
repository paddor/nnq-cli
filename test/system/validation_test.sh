#!/bin/sh
# CLI argument validation: errors on duplicate endpoints and on
# half-configured pipe invocations.

. "$(dirname "$0")/support.sh"

echo "Validation:"
$NNQ push -c tcp://x:1 -b tcp://x:1 2>$TMPDIR/val_dup.txt && EXITCODE=0 || EXITCODE=$?
check "duplicate endpoints errors" "1" "$EXITCODE"

$NNQ pipe --in -c tcp://x:1 2>$TMPDIR/val_pipe_in.txt && EXITCODE=0 || EXITCODE=$?
check "pipe --in without --out errors" "1" "$EXITCODE"
