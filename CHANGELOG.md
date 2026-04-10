# Changelog

## Unreleased

- **`NNQ::CLI::Term` module** — consolidates verbose log formatting
  (timestamps at `-vvvv`, monitor events, endpoint attach lines) into a
  stateless module. Replaces four duplicated inline formatting blocks
  across BaseRunner, PipeRunner, PipeWorker, and SocketSetup.
- **Default HWM → 64** — down from 100. 64 matches the send pump's
  per-fairness-batch limit (one batch exactly fills a full queue).
  Pipe sockets no longer use a separate `PIPE_HWM = 16`; they go
  through `SocketSetup.build` like every other socket type.
- **Pipe: drop peer wait unless `--timeout`** — without `--timeout`,
  `PULL#receive` blocks naturally and `PUSH` buffers up to `send_hwm`.
  Only wait for peers in fail-fast mode.
- **Endpoint normalization** — binds: `tcp://:PORT` normalizes to
  loopback (`[::1]` on IPv6-capable hosts, `127.0.0.1` otherwise);
  `tcp://*:PORT` normalizes to `0.0.0.0`. Connects: both `tcp://:PORT`
  and `tcp://*:PORT` normalize to `tcp://localhost:PORT` (preserving
  Happy Eyeballs).
- **YJIT by default** — `exe/nnq` calls `RubyVM::YJIT.enable` before
  loading the CLI (skipped if `RUBYOPT` is set, interpreter lacks YJIT,
  or YJIT is already on).
- **Consistent `nnq:` prefix** on all attach and event log lines.
- **`-vvvv` timestamps** — ISO8601 UTC with µs precision.
- **3 new socket runners** — `nnq bus`, `nnq surveyor`, `nnq respondent`.
- **Versioned socket symbols** — RUNNER_MAP uses `:PUSH0`, `:PULL0`, etc.

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
