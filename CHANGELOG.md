# Changelog

## 0.3.0 — 2026-04-15

- **Compression switched from LZ4 to Zstd** via the new
  [nnq-zstd](https://github.com/paddor/nnq-zstd) gem. `-z`
  (fast, level −3) and `-Z` (balanced, level 3) are mutually
  exclusive and map to transparent `NNQ::Zstd.wrap` decorators
  around each socket. Sender-side dictionary training and in-band
  dict shipping mean compression ratios on streams of similar
  small messages are now dramatically better than the old
  stateless LZ4 path. Both peers still have to pass `-z`/`-Z`;
  there is no negotiation.
- **`-Z` / `--compress-high`** flag for balanced Zstd.
- **Formatter no longer knows about compression.** All per-message
  compression state and logic moved out of `Formatter`; compression
  is applied transparently at the socket boundary via the new
  wrapper. Fewer code paths in runners.
- **`rlz4` dependency dropped** in favor of `nnq-zstd ~> 0.1`.
- **Lazy loading.** `nnq/zstd` (and therefore `rzstd` and the Rust
  extension) is only required when `-z`/`-Z` is actually used,
  keeping startup cost unchanged for non-compressing runs.

## 0.2.0 — 2026-04-15

- **Peer wait for bind-mode bounded senders** — `nnq push -b ... -d
  hello` now waits for the first peer before sending, so one-shot
  `-d`/`-f`/`-E` payloads don't just get queued into HWM and dropped on
  exit. Interactive stdin still sends without waiting.
- **`--count N` honored on one-shot sends** — `-d`/`-f` and pure-
  generator `-E` loop N times instead of firing once.
- **Interactive TTY fallback** — bare `nnq push -c tcp://...` on a
  terminal reads lines from the TTY until ^D (matching omq-cli).
  Pure-generator `-E` is checked before the TTY fallback.
- **`nnq:` log prefix** — `BaseRunner#log` routes through
  `Term.log_prefix` with an `nnq: ` prefix, so every stderr line from a
  CLI run looks consistent with attach/event lines.
- **No more "frames"/"parts"** — NNG has no multipart concept; all
  `parts` variables renamed to `msg`, and comments/docs updated from
  "frame" to "message"/"body".
- **Eval `#to_s` coercion** — non-string eval results (e.g.
  `-E 'Time.now'`) are coerced via `#to_s` instead of raising
  `NoMethodError` on `#to_str`. Array elements are coerced
  individually.
- **`@name` IPC shorthand** — `@foo` expands to `ipc://@foo`
  (Linux abstract namespace) in `-b`/`-c` arguments.
- **Pipe: bare endpoint promotion** — `pipe -c SRC --out -c DST`
  automatically promotes the bare `-c SRC` to `--in`.
- **Pipe: fan-out fairness yield** — multi-output pipes yield after
  each send so send-pump fibers distribute messages fairly across
  output peers.
- **Formatter: empty-frame preview** — empty bodies render as `''`
  instead of `[0B]` in verbose output.
- **Formatter: nil-safe compression** — `compress`/`decompress` skip
  nil and empty frames instead of crashing.
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
