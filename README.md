# nnq — nanomsg SP CLI

[![Gem Version](https://img.shields.io/gem/v/nnq-cli?color=e9573f)](https://rubygems.org/gems/nnq-cli)
[![License: ISC](https://img.shields.io/badge/License-ISC-blue.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%204.0-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org)

Command-line tool for sending and receiving nanomsg SP protocol messages on
any nnq socket type. Like `nngcat` from libnng, but with Ruby eval, Ractor
parallelism, and message handlers.

Built on [nnq](https://github.com/paddor/nnq) — pure Ruby SP wire protocol, no
C dependencies. Wire-compatible with libnng peers.

## Install

```sh
gem install nnq-cli
```

## Quick Start

```sh
# Echo server
nnq rep -b tcp://:5555 --echo

# Client
echo "hello" | nnq req -c tcp://localhost:5555

# Upcase server — -e evals Ruby on each incoming message
nnq rep -b tcp://:5555 -e 'it.upcase'
```

```
Usage: nnq TYPE [options]

Types:    req, rep, pub, sub, push, pull, pair, bus, surveyor, respondent
Virtual:  pipe (PULL → eval → PUSH)
```

## Connection

Every socket needs at least one `--bind` or `--connect`:

```sh
nnq pull --bind tcp://:5557          # listen on port 5557
nnq push --connect tcp://host:5557   # connect to host
nnq pull -b ipc:///tmp/feed.sock     # IPC (unix socket)
nnq push -c ipc://@abstract          # IPC (abstract namespace, Linux)
```

The `@name` shortcut expands to `ipc://@name` (Linux abstract namespace):

```sh
nnq rep -b @echo --echo
echo hi | nnq req -c @echo
```

Bind/connect order doesn't matter — `connect` is non-blocking and the engine
retries with exponential back-off until the peer is reachable. Multiple
endpoints are allowed: `nnq pull -b tcp://:5557 -b tcp://:5558` binds both.

Pipe takes two positional endpoints (input, output) or uses `--in`/`--out` for
multiple per side.

## Socket types

### Unidirectional (send-only / recv-only)

| Send | Recv | Pattern |
|------|------|---------|
| `push` | `pull` | Pipeline — round-robin to workers |
| `pub`  | `sub`  | Publish/subscribe — fan-out with topic prefix filtering |

Send-only sockets read from stdin (or `--data`/`--file`/`-E`) and send.
Recv-only sockets receive and write to stdout.

```sh
echo "task" | nnq push -c tcp://worker:5557
nnq pull -b tcp://:5557
```

### Bidirectional (request-reply)

| Type | Behavior |
|------|----------|
| `req` | Sends a request, waits for reply, prints reply |
| `rep` | Receives request, sends reply (from `--echo`, `-e`, `--data`, `--file`, or stdin) |

```sh
# echo server
nnq rep -b tcp://:5555 --echo

# upcase server
nnq rep -b tcp://:5555 -e 'it.upcase'

# client
echo "hello" | nnq req -c tcp://localhost:5555
```

### Bidirectional (survey)

| Type | Behavior |
|------|----------|
| `surveyor`   | Broadcasts a survey, collects replies within a time window |
| `respondent` | Receives survey, sends a reply |

### Bidirectional (bus)

| Type | Behavior |
|------|----------|
| `bus` | Every-to-every — all peers see each other's messages |

### Bidirectional (concurrent send + recv)

| Type | Behavior |
|------|----------|
| `pair` | Exclusive 1-to-1 — concurrent send and recv tasks |

These spawn two concurrent tasks: a receiver (prints incoming) and a sender
(reads stdin). `-e` transforms incoming, `-E` transforms outgoing.

### Pipe (virtual)

Pipe creates an internal PULL → eval → PUSH pipeline:

```sh
nnq pipe -c ipc://@work -c ipc://@sink -e 'it.upcase'

# with Ractor workers for CPU parallelism
nnq pipe -c ipc://@work -c ipc://@sink -P 4 -r./fib.rb -e 'fib(Integer(it)).to_s'

# auto-detect cores (-P 0 = nproc, capped at 16)
nnq pipe -c ipc://@work -c ipc://@sink -P 0 -e 'it.upcase'
```

The first endpoint is the pull-side (input), the second is the push-side
(output). For parallel mode (`-P`) all endpoints must be `--connect`.

## Eval: -e and -E

`-e` (alias `--recv-eval`) runs a Ruby expression for each **incoming** message.
`-E` (alias `--send-eval`) runs a Ruby expression for each **outgoing** message.

The message body is available as `it` (Ruby 3.4's default block variable) or
via explicit block-parameter syntax `|msg| msg.upcase`:

```sh
nnq rep -b tcp://:5555 -e 'it.upcase'
nnq rep -b tcp://:5555 -e '|msg| msg.upcase'
```

### Return value

| Return | Effect |
|--------|--------|
| `String` | Used as the message body |
| `nil` | Message is skipped (filtered) |
| `self` (the socket) | Signals "I already sent" (REP only) |

### Control flow

```sh
# skip messages matching a pattern
nnq pull -b tcp://:5557 -e 'next if it.start_with?("#"); it'

# stop on "quit"
nnq pull -b tcp://:5557 -e 'break if it =~ /quit/; it'
```

### BEGIN/END blocks

Like awk — `BEGIN{}` runs once before the message loop, `END{}` runs after:

```sh
nnq pull -b tcp://:5557 -e 'BEGIN{ @sum = 0 } @sum += Integer(it); nil END{ puts @sum }'
```

Local variables won't share state between blocks. Use `@ivars` instead.

### Generator mode

`-E` without stdin input produces messages from the eval alone, for any
send-capable socket (PUSH, PUB, REQ). Bounded by `-n` or paced by `-i`:

```sh
# generate 10 requests with no stdin
nnq req -c tcp://localhost:5555 -E '"ping"' -n 10

# publish a tick every second
nnq pub -c tcp://localhost:5556 -E 'Time.now.to_s' -i 1
```

### Which sockets accept which flag

| Socket | `-E` (send) | `-e` (recv) |
|--------|-------------|-------------|
| push, pub | transforms outgoing | error |
| pull, sub | error | transforms incoming |
| req       | transforms request | transforms reply |
| rep       | error | transforms request → return = reply |
| pair      | transforms outgoing | transforms incoming |
| pipe      | error | transforms in pipeline |

### Examples

```sh
# upcase echo server
nnq rep -b tcp://:5555 -e 'it.upcase'

# transform before sending
echo hello | nnq push -c tcp://localhost:5557 -E 'it.upcase'

# filter incoming
nnq pull -b tcp://:5557 -e 'it.include?("error") ? it : nil'

# REQ: different transforms per direction
echo hello | nnq req -c tcp://localhost:5555 \
  -E 'it.upcase' -e 'it.reverse'

# use gems
nnq sub -c tcp://localhost:5556 -s "" -rjson -e 'JSON.parse(it)["temperature"]'
```

## Script handlers (-r)

For non-trivial transforms, put the logic in a Ruby file and load it with `-r`:

```ruby
# handler.rb
db = PG.connect("dbname=app")

NNQ.outgoing { |msg| msg.upcase }
NNQ.incoming { |msg| db.exec(msg).values.flatten.first }

at_exit { db.close }
```

```sh
nnq req -c tcp://localhost:5555 -r./handler.rb
```

### Registration API

| Method | Effect |
|--------|--------|
| `NNQ.outgoing { |msg| ... }` | Register outgoing message transform |
| `NNQ.incoming { |msg| ... }` | Register incoming message transform |

- `msg` is a `String` (the message body)
- Setup: use local variables and closures at the top of the script
- Teardown: use Ruby's `at_exit { ... }`
- CLI flags (`-e`/`-E`) override script-registered handlers for the same direction
- A script can register one direction while the CLI handles the other

## Data sources

| Flag | Behavior |
|------|----------|
| (stdin) | Read lines from stdin, one message per line |
| `-D "text"` | Send literal string (one-shot or repeated with `-i`) |
| `-F file` | Read message from file (`-F -` reads stdin as blob) |
| `-E expr` | Generate messages from eval (no stdin needed) |
| `--echo` | Echo received messages back (REP only) |

`-D` and `-F` are mutually exclusive.

## Formats

| Flag | Format |
|------|--------|
| `-A` / `--ascii` | Safe ASCII, non-printable → dots (default) |
| `-Q` / `--quoted` | C-style escapes, lossless round-trip |
| `--raw` | Raw body, newline-delimited |
| `-J` / `--jsonl` | JSON Lines — `["body"]` per line |
| `--msgpack` | MessagePack arrays (binary stream) |
| `-M` / `--marshal` | Ruby Marshal (binary stream) |

```sh
nnq push -c tcp://localhost:5557 < data.txt
nnq pull -b tcp://:5557 -J
```

## Timing

| Flag | Effect |
|------|--------|
| `-i SECS` | Repeat send every N seconds (wall-clock aligned) |
| `-n COUNT` | Max messages to send/receive (0 = unlimited) |
| `-d SECS` | Delay before first send |
| `-t SECS` | Send/receive timeout |
| `-l SECS` | Linger time on close (default 5s) |
| `--reconnect-ivl` | Reconnect interval: `SECS` or `MIN..MAX` (default 0.1) |

```sh
# publish a tick every second, 10 times
nnq pub -c tcp://localhost:5556 -D "tick" -i 1 -n 10 -d 1

# receive with 5s timeout
nnq pull -b tcp://:5557 -t 5
```

## Compression

Transparent [Zstd](https://github.com/paddor/nnq-zstd) compression with
sender-side dictionary training and in-band dict shipping. The receiver just
needs `-z` — decompression is level-agnostic:

| Flag | Level | Use case |
|------|-------|----------|
| `-z` | −3 | Fast (default) |
| `-Z` | 3  | Better ratio |
| `--compress=N` | −7..19 | Custom level |

```sh
# sender picks level, receiver just decompresses
nnq push -c tcp://remote:5557 -z < data.txt
nnq pull -b tcp://:5557 -z

# better compression ratio
nnq push -c tcp://remote:5557 -Z < data.txt
nnq pull -b tcp://:5557 -z

# custom level (e.g. max compression)
nnq push -c tcp://remote:5557 --compress=19 < data.txt
nnq pull -b tcp://:5557 -z
```

Streams of similar small messages benefit from the automatic dictionary
training — the sender collects samples, trains a dict, and ships it in-band
to the receiver.

## Subscriptions

```sh
# subscribe to topic prefix
nnq sub -b tcp://:5556 -s "weather."

# subscribe to all (default)
nnq sub -b tcp://:5556

# multiple subscriptions
nnq sub -b tcp://:5556 -s "weather." -s "sports."
```

## Pipe

Pipe creates an in-process PULL → eval → PUSH pipeline:

```sh
# basic pipe (positional: first = input, second = output)
nnq pipe -c ipc://@work -c ipc://@sink -e 'it.upcase'

# auto-detect CPU count
nnq pipe -c ipc://@work -c ipc://@sink -P 0 -e 'it.upcase'

# fixed number of workers
nnq pipe -c ipc://@work -c ipc://@sink -P 4 -e 'it.upcase'

# exit when producer disconnects
nnq pipe -c ipc://@work -c ipc://@sink --transient -e 'it.upcase'
```

### Multi-peer pipe with `--in`/`--out`

Use `--in` and `--out` to attach multiple endpoints per side. These are modal
switches — subsequent `-b`/`-c` flags attach to the current side:

```sh
# fan-in: 2 producers → 1 consumer
nnq pipe --in -c ipc://@work1 -c ipc://@work2 --out -c ipc://@sink -e 'it'

# fan-out: 1 producer → 2 consumers (round-robin)
nnq pipe --in -b tcp://:5555 --out -c ipc://@sink1 -c ipc://@sink2 -e 'it'

# parallel workers with fan-in (all must be -c)
nnq pipe --in -c ipc://@a -c ipc://@b --out -c ipc://@sink -P 4 -e 'it'
```

`-P`/`--parallel` requires all endpoints to be `--connect`. In parallel mode,
each Ractor worker gets its own PULL/PUSH pair connecting to all endpoints.

## Transient mode

`--transient` makes the socket exit when all peers disconnect. Useful for
pipeline workers and sinks:

```sh
# worker exits when producer is done
nnq pipe -c ipc://@work -c ipc://@sink --transient -e 'it.upcase'

# sink exits when all workers disconnect
nnq pull -b tcp://:5557 --transient
```

## Verbose / monitor mode

Pass `-v` (repeatable) for increasingly chatty output on stderr:

| Level | Output |
|-------|--------|
| `-v`    | Bind/connect endpoints |
| `-vv`   | Lifecycle events (`:listening`, `:connected`, `:disconnected`, ...) |
| `-vvv`  | Per-message trace (`:message_sent`, `:message_received` with byte size) |

Add `--timestamps` to prefix log lines with UTC time (default ms precision):

```sh
nnq pub -b tcp://:5556 -vv --timestamps
nnq pull -b tcp://:5557 -vvv --timestamps=us
```

Supported precisions: `s`, `ms` (default), `us`.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (connection, argument, runtime) |
| 2 | Timeout |
| 3 | Eval error (`-e`/`-E` expression raised) |

## Interop with libnng / nngcat

nnq-cli speaks the SP wire protocol, so it interoperates with `nngcat` and any
libnng-based peer over `tcp://` and `ipc://`:

```sh
# nnq → nngcat
nngcat --pull0 --listen tcp://127.0.0.1:5555 --quoted &
echo hello | nnq push -c tcp://127.0.0.1:5555

# nngcat → nnq
nnq pull -b tcp://127.0.0.1:5555 &
nngcat --push0 --dial tcp://127.0.0.1:5555 --data "hello-from-nngcat"
```

## License

[ISC](LICENSE)
