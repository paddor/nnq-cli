# Changelog

## 0.3.2 — 2026-04-16

- **REQ generator mode (`-E`/`-e` with no stdin).** `nnq req` now
  produces each request from the send-eval alone when no `-d`/`-F`
  is given and stdin is not piped, matching the existing PUSH/PUB
  generator behaviour. Bounded by `-n` or paced by `-i` like the
  other generator-capable runners.
- **System tests split into themed files under `test/system/`.**
  Replaces the monolithic `test/system_test.sh` with 10 standalone
  files sharing `test/system/support.sh` helpers.
  `test/system/run_all.sh` chains them; each file also runs
  standalone. New `rake test:system` task invokes `run_all.sh`.
- **System tests for REQ/PUSH/PUB `-E` generator mode.** REQ fires
  `-E'"foo"' -n 3` against a REP running `-e 'it.upcase' -n 3` and
  verifies three `FOO` replies round-trip; PUSH and PUB get the
  same treatment.

## 0.3.1 — 2026-04-15

- **Messages are single `String`s, not 1-element arrays.** Every
  runner, the formatter, and the expression evaluator used to wrap
  each message body in a one-element array as a historical
  artifact of multipart thinking. That's gone now: `Formatter#pack`/
  `#unpack` take and return a `String`, `Formatter.preview` takes a
  `String`, and REQ/REP/SURVEYOR/RESPONDENT/pipe runners pass the
  body straight through without `.first` or array literals. Fixes
  an `undefined method 'first' for an instance of String` crash in
  `ReqRunner#request_and_receive` that was masked by the tests.
- **`-e` / `-E` expressions use Ruby 3.4's `it` default block
  variable** (and accept explicit `|msg|` block-parameter syntax
  via `proc { |msg| ... }`). The old implicit `$_`/`$F` aliasing is
  gone; expressions are compiled as plain `proc { EXPR }` and
  evaluated via `instance_exec(msg, &block)`, so `it.upcase` and
  `|msg| msg.upcase` both work. Cleaner, faster, and no global
  state.
- **Requires nnq >= 0.6.1** for the `-vvv` trace fixes — cooked
  REQ/REP/RESPONDENT now emit `>>` lines and recv previews strip
  the SP backtrace header so you see the actual payload.
- **`test/system_test.sh`** — new shell-based system test suite
  modeled on omq-cli's, covering REQ/REP (basic, `--echo`, `-e`),
  the ported `-vvv` REQ/REP verbose-trace assertion from omq-cli
  commit `950890911de078`, PUSH/PULL, PUB/SUB, and the `@name`
  abstract-namespace shortcut for both `-b` and `-c`.

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
