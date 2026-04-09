# Changelog

## 0.1.0 — 2026-04-09

Initial release — NNQ command-line tool, sister of omq-cli for the SP
(nanomsg) wire protocol.

- 7 socket-type runners: push, pull, pub, sub, req, rep, pair.
- `pipe` virtual socket (PULL → eval → PUSH) with Ractor-based
  parallelism (`-P N`). Each worker owns its own Async reactor and
  PULL/PUSH pair; messages fan out via round-robin PUSH to workers and
  merge back through a shared PULL sink.
- Ruby eval (`-e` / `-E` with BEGIN/END blocks), `-r` script loading
  with `NNQ.outgoing` / `NNQ.incoming` handlers.
- 6 formats: ASCII, quoted, raw, JSON Lines, msgpack, Marshal.
- LZ4 compression (`--compress` / `--compress-in` / `--compress-out`).
- `--transient` mode — cleanly exits once all peers have disconnected.
- `-v` / `-vv` / `-vvv` monitor events piped to stderr.
- No CURVE, no heartbeat, no multipart — nnq is single-frame SP.

Requires `nnq ~> 0.4` (for `freeze_for_ractors!`, `Socket#monitor`,
`#all_peers_gone`, and `PULL#receive` `read_timeout` support).
