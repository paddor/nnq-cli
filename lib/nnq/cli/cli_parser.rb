# frozen_string_literal: true

require "socket"

module NNQ
  module CLI
    # Parses and validates command-line arguments for the nnq CLI.
    #
    class CliParser
      EXAMPLES = <<~'TEXT'
        -- Request / Reply ------------------------------------------

          +-----+   "hello"    +-----+
          | REQ |------------->| REP |
          |     |<-------------|     |
          +-----+   "HELLO"    +-----+

          # terminal 1: echo server
          nnq rep --bind tcp://:5555 --recv-eval 'it.upcase'

          # terminal 2: send a request
          echo "hello" | nnq req --connect tcp://localhost:5555

          # or over IPC (unix socket, single machine)
          nnq rep --bind ipc:///tmp/echo.sock --echo &
          echo "hello" | nnq req --connect ipc:///tmp/echo.sock

        -- Publish / Subscribe --------------------------------------

          +-----+   "weather.nyc 72F"  +-----+
          | PUB |--------------------->| SUB | --subscribe "weather."
          +-----+                      +-----+

          # terminal 1: subscriber (all topics by default)
          nnq sub --bind tcp://:5556

          # terminal 2: publisher (needs --delay for subscription to propagate)
          echo "weather.nyc 72F" | nnq pub --connect tcp://localhost:5556 --delay 1

        -- Periodic Publish -------------------------------------------

          +-----+   "tick 1"    +-----+
          | PUB |--(every 1s)-->| SUB |
          +-----+               +-----+

          # terminal 1: subscriber
          nnq sub --bind tcp://:5556

          # terminal 2: publish a tick every second (wall-clock aligned)
          nnq pub --connect tcp://localhost:5556 --delay 1 \
            --data "tick" --interval 1

          # 5 ticks, then exit
          nnq pub --connect tcp://localhost:5556 --delay 1 \
            --data "tick" --interval 1 --count 5

        -- Pipeline -------------------------------------------------

          +------+            +------+
          | PUSH |----------->| PULL |
          +------+            +------+

          # terminal 1: worker
          nnq pull --bind tcp://:5557

          # terminal 2: send tasks
          echo "task 1" | nnq push --connect tcp://localhost:5557

          # or over IPC (unix socket)
          nnq pull --bind ipc:///tmp/pipeline.sock &
          echo "task 1" | nnq push --connect ipc:///tmp/pipeline.sock

        -- Pipe (PULL -> eval -> PUSH) --------------------------------

          +------+          +------+          +------+
          | PUSH |--------->| pipe |--------->| PULL |
          +------+          +------+          +------+

          # terminal 1: producer
          echo -e "hello\nworld" | nnq push --bind ipc://@work

          # terminal 2: worker -- uppercase each message
          nnq pipe -c ipc://@work -c ipc://@sink -e 'it.upcase'
          # terminal 3: collector
          nnq pull --bind ipc://@sink

          # 4 Ractor workers in a single process (-P)
          nnq pipe -c ipc://@work -c ipc://@sink -P4 -r./fib -e 'fib(Integer(it)).to_s'

          # exit when producer disconnects (--transient)
          nnq pipe -c ipc://@work -c ipc://@sink --transient -e 'it.upcase'

          # fan-in: multiple sources -> one sink
          nnq pipe --in -c ipc://@work1 -c ipc://@work2 \
            --out -c ipc://@sink -e 'it.upcase'

          # fan-out: one source -> multiple sinks (round-robin)
          nnq pipe --in -b tcp://:5555 --out -c ipc://@sink1 -c ipc://@sink2 -e 'it'

        -- Formats --------------------------------------------------

          # ascii (default) -- non-printable replaced with dots
          nnq pull --bind tcp://:5557 --ascii

          # quoted -- lossless, round-trippable (uses String#dump escaping)
          nnq pull --bind tcp://:5557 --quoted

          # raw -- emit the body verbatim (no framing, no newline)
          nnq pull --bind tcp://:5557 --raw

        -- Compression ----------------------------------------------

          # both sides must use --compress
          nnq pull --bind tcp://:5557 --compress &
          echo "compressible data" | nnq push --connect tcp://localhost:5557 --compress

        -- Ruby Eval ------------------------------------------------

          # filter incoming: only pass messages containing "error"
          nnq pull -b tcp://:5557 --recv-eval 'it.include?("error") ? it : nil'

          # transform incoming with gems
          nnq sub -c tcp://localhost:5556 -rjson -e 'JSON.parse(it)["temperature"]'

          # require a local file, use its methods
          nnq rep --bind tcp://:5555 --require ./transform.rb -e 'transform(it)'

          # next skips, break stops
          nnq pull -b tcp://:5557 -e 'next if /^#/; break if it =~ /quit/; it'

          # BEGIN/END blocks (like awk) -- accumulate and summarize
          nnq pull -b tcp://:5557 -e 'BEGIN{@sum = 0} @sum += Integer(it); nil END{puts @sum}'

          # transform outgoing messages (with explicit block variable msg)
          echo hello | nnq push -c tcp://localhost:5557 --send-eval '|msg| msg.upcase'

          # REQ: transform request and reply independently
          echo hello | nnq req -c tcp://localhost:5555 -E 'it.upcase' -e 'it'

        -- Script Handlers (-r) ------------------------------------

          # handler.rb -- register transforms from a file
          #   db = PG.connect("dbname=app")
          #   NNQ.incoming { |msg| db.exec(msg).values.flatten.first }
          #   at_exit { db.close }
          nnq pull --bind tcp://:5557 -r./handler.rb

          # combine script handlers with inline eval
          nnq req -c tcp://localhost:5555 -r./handler.rb -E 'it.upcase'

          # NNQ.outgoing { |msg| ... }   -- registered outgoing transform
          # NNQ.incoming { |msg| ... }   -- registered incoming transform
          # CLI flags (-e/-E) override registered handlers
      TEXT


      DEFAULT_OPTS = {
        type_name:     nil,
        endpoints:     [],
        connects:      [],
        binds:         [],
        in_endpoints:  [],
        out_endpoints: [],
        data:          nil,
        file:          nil,
        format:        :ascii,
        subscribes:    [],
        interval:      nil,
        count:         nil,
        delay:         nil,
        timeout:       nil,
        linger:        5,
        reconnect_ivl: nil,
        send_hwm:      nil,
        sndbuf:        nil,
        rcvbuf:        nil,
        compress:      nil,
        compress_in:   nil,
        compress_out:  nil,
        send_expr:     nil,
        recv_expr:     nil,
        parallel:      nil,
        transient:     false,
        verbose:       0,
        quiet:         false,
        echo:          false,
        scripts:       [],
        recv_maxsz:    nil,
      }.freeze


      # Parses +argv+ and returns a mutable options hash.
      #
      def self.parse(argv)
        new.parse(argv)
      end


      # Validates option combinations, aborting on bad combos.
      #
      def self.validate!(opts)
        new.validate!(opts)
      end


      # Validates option combinations that depend on socket type.
      #
      def self.validate_gems!(config)
        if config.recv_only? && (config.data || config.file)
          abort "--data/--file not valid for #{config.type_name} (receive-only)"
        end
      end


      # Parses +argv+ and returns a mutable options hash.
      #
      # @param argv [Array<String>] command-line arguments (mutated in place)
      # @return [Hash] parsed options
      def parse(argv)
        opts      = DEFAULT_OPTS.transform_values { |v| v.is_a?(Array) ? v.dup : v }
        pipe_side = nil  # nil = legacy positional mode; :in/:out = modal

        parser = OptionParser.new do |o|
          o.banner = "Usage: nnq TYPE [options]\n\n" \
                     "Types:    req, rep, pub, sub, push, pull, pair\n" \
                     "Virtual:  pipe (PULL -> eval -> PUSH)\n\n"

          o.separator "Connection:"
          o.on("-c", "--connect URL", "Connect to endpoint (repeatable)") { |v|
            v = expand_endpoint(v)
            ep = Endpoint.new(v, false)
            case pipe_side
            when :in
              opts[:in_endpoints] << ep
            when :out
              opts[:out_endpoints] << ep
            else
              opts[:endpoints] << ep
              opts[:connects]  << v
            end
          }
          o.on("-b", "--bind URL", "Bind to endpoint (repeatable)") { |v|
            v = expand_endpoint(v)
            ep = Endpoint.new(v, true)
            case pipe_side
            when :in
              opts[:in_endpoints] << ep
            when :out
              opts[:out_endpoints] << ep
            else
              opts[:endpoints] << ep
              opts[:binds]     << v
            end
          }
          o.on("--in",  "Pipe: subsequent -b/-c attach to input (PULL) side")  { pipe_side = :in }
          o.on("--out", "Pipe: subsequent -b/-c attach to output (PUSH) side") { pipe_side = :out }

          o.separator "\nData source (REP: reply source):"
          o.on(      "--echo",        "Echo received messages back (REP)")   { opts[:echo] = true }
          o.on("-D", "--data DATA",   "Message data (literal string)")      { |v| opts[:data] = v }
          o.on("-F", "--file FILE",   "Read message from file (- = stdin)") { |v| opts[:file] = v }

          o.separator "\nFormat (input + output):"
          o.on("-A", "--ascii",   "Safe ASCII, non-printable as dots (default)") { opts[:format] = :ascii }
          o.on("-Q", "--quoted",  "C-style quoted with escapes")                 { opts[:format] = :quoted }
          o.on(      "--raw",     "Raw binary body, no framing, no newline")    { opts[:format] = :raw }
          o.on(      "--msgpack", "MessagePack (binary stream)")                 { require "msgpack"; opts[:format] = :msgpack }
          o.on("-M", "--marshal", "Ruby Marshal stream (binary)")                 { opts[:format] = :marshal }

          o.separator "\nSubscription:"
          o.on("-s", "--subscribe PREFIX", "Subscribe prefix (SUB, default all)") { |v| opts[:subscribes] << v }

          o.separator "\nTiming:"
          o.on("-i", "--interval SECS", Float,   "Repeat interval")                   { |v| opts[:interval] = v }
          o.on("-n", "--count COUNT",   Integer,  "Max iterations (0=inf)")            { |v| opts[:count] = v }
          o.on("-d", "--delay SECS",    Float,   "Delay before first send")            { |v| opts[:delay] = v }
          o.on("-t", "--timeout SECS",  Float,   "Send/receive timeout")               { |v| opts[:timeout] = v }
          o.on("-l", "--linger SECS",   Float,   "Drain time on close (default 5)")   { |v| opts[:linger] = v }
          o.on("--reconnect-ivl IVL", "Reconnect interval: SECS or MIN..MAX (default 0.1)") { |v|
            opts[:reconnect_ivl] = if v.include?("..")
                                     lo, hi = v.split("..", 2)
                                     Float(lo)..Float(hi)
                                   else
                                     Float(v)
                                   end
          }
          o.on("--recv-maxsz SIZE", "Max inbound message size, e.g. 4096, 64K, 1M, 2G (default 1M, 0=unlimited; larger messages drop the connection)") { |v| opts[:recv_maxsz] = parse_byte_size(v) }
          o.on("--hwm N", Integer, "Send high water mark (default 100, 0=unbounded)") { |v| opts[:send_hwm] = v }
          o.on("--sndbuf N", "SO_SNDBUF kernel buffer size (e.g. 4K, 1M)") { |v| opts[:sndbuf] = parse_byte_size(v) }
          o.on("--rcvbuf N", "SO_RCVBUF kernel buffer size (e.g. 4K, 1M)") { |v| opts[:rcvbuf] = parse_byte_size(v) }

          o.separator "\nCompression:"
          load_zstd = -> { require "nnq/zstd" }
          set_compress = lambda do |sym|
            load_zstd.call
            target = case pipe_side
                     when :in  then :compress_in
                     when :out then :compress_out
                     else           :compress
                     end
            if opts[target] && opts[target] != sym
              abort "nnq: -z and -Z are mutually exclusive"
            end
            opts[target] = sym
          end
          o.on("-z", "--compress", "Zstd compression (fast, level -3; modal with --in/--out)") do
            set_compress.call(:fast)
          end
          o.on("-Z", "--compress-high", "Zstd compression (balanced, level 3; modal with --in/--out)") do
            set_compress.call(:balanced)
          end

          o.separator "\nProcessing (-e = incoming, -E = outgoing):"
          o.on("-e", "--recv-eval EXPR", "Eval Ruby for each incoming message (it = msg)") { |v| opts[:recv_expr] = v }
          o.on("-E", "--send-eval EXPR", "Eval Ruby for each outgoing message (it = msg)") { |v| opts[:send_expr] = v }
          o.on("-r", "--require LIB",  "Require lib/file in Async context; use '-' for stdin. Scripts can register NNQ.outgoing/incoming") { |v|
            require "nnq" unless defined?(NNQ::VERSION)
            opts[:scripts] << (v == "-" ? :stdin : (v.start_with?("./", "../") ? File.expand_path(v) : v))
          }
          o.on("-P", "--parallel N", Integer, "Parallel Ractor workers, 1..16 (0 = nproc, capped at 16)") { |v|
            require "etc"
            resolved = v.zero? ? Etc.nprocessors : v
            opts[:parallel] = [resolved, 16].min
          }

          o.separator "\nOther:"
          o.on("-v", "--verbose",   "Verbosity: -v endpoints, -vv events, -vvv messages, -vvvv timestamps") { opts[:verbose] += 1 }
          o.on("-q", "--quiet",     "Suppress message output")           { opts[:quiet] = true }
          o.on(      "--transient", "Exit when all peers disconnect")    { opts[:transient] = true }
          o.on("-V", "--version") {
            if ENV["NNQ_DEV"]
              require_relative "../../../../nnq/lib/nnq/version"
            else
              require "nnq/version"
            end
            puts "nnq-cli #{NNQ::CLI::VERSION} (nnq #{NNQ::VERSION})"
            exit
          }
          o.on("-h")             { puts o
                                   exit }
          o.on("--help")        { CLI.page "#{o}\n#{EXAMPLES}"
                                   exit }
          o.on("--examples")    { CLI.page EXAMPLES
                                   exit }

          o.separator "\nExit codes: 0 = success, 1 = error, 2 = timeout, 3 = eval error"
        end

        begin
          parser.parse!(argv)
        rescue OptionParser::ParseError => e
          abort e.message
        end

        type_name = argv.shift
        if type_name.nil?
          abort parser.to_s if opts[:scripts].empty?
          # bare script mode -- type_name stays nil
        elsif !SOCKET_TYPE_NAMES.include?(type_name.downcase)
          abort "Unknown socket type: #{type_name}. Known: #{SOCKET_TYPE_NAMES.join(', ')}"
        else
          opts[:type_name] = type_name.downcase
        end

        # Normalize shorthand hostnames to concrete addresses.
        #
        # Binds:    tcp://:PORT  → loopback (::1 if IPv6 available, else 127.0.0.1)
        #           tcp://*:PORT → 0.0.0.0 (all interfaces, IPv4)
        #
        # Connects: tcp://:PORT  → localhost (Happy Eyeballs)
        #           tcp://*:PORT → localhost
        loopback          = self.class.loopback_bind_host
        normalize_bind    = ->(url) { url.sub(%r{\Atcp://\*:}, "tcp://0.0.0.0:").sub(%r{\Atcp://:}, "tcp://#{loopback}:") }
        normalize_connect = ->(url) { url.sub(%r{\Atcp://(\*|):}, "tcp://localhost:") }
        normalize_ep      = ->(ep)  { Endpoint.new(ep.bind? ? normalize_bind.call(ep.url) : normalize_connect.call(ep.url), ep.bind?) }
        opts[:binds].map!(&normalize_bind)
        opts[:connects].map!(&normalize_connect)
        opts[:endpoints].map!(&normalize_ep)
        opts[:in_endpoints].map!(&normalize_ep)
        opts[:out_endpoints].map!(&normalize_ep)

        opts
      end


      # Parses a byte size string with an optional K/M/G suffix (binary,
      # i.e. 1K = 1024 bytes).
      #
      # @param str [String] e.g. "4096", "4K", "1M", "2G"
      # @return [Integer] size in bytes
      #
      def parse_byte_size(str)
        case str
        when /\A(\d+)[kK]\z/ then $1.to_i * 1024
        when /\A(\d+)[mM]\z/ then $1.to_i * 1024 * 1024
        when /\A(\d+)[gG]\z/ then $1.to_i * 1024 * 1024 * 1024
        when /\A\d+\z/       then str.to_i
        else
          abort "invalid byte size: #{str} (use e.g. 4096, 4K, 1M, 2G)"
        end
      end


      # Returns the loopback address for bind normalization.
      # Prefers IPv6 loopback ([::1]) when the host has at least one
      # non-loopback, non-link-local IPv6 address, otherwise 127.0.0.1.
      def self.loopback_bind_host
        @loopback_bind_host ||= begin
          has_ipv6 = ::Socket.getifaddrs.any? { |ifa|
            addr = ifa.addr
            addr&.ipv6? && !addr.ipv6_loopback? && !addr.ipv6_linklocal?
          }
          has_ipv6 ? "[::1]" : "127.0.0.1"
        end
      end


      # Validates option combinations, aborting on invalid combos.
      #
      # @param opts [Hash] parsed options from {#parse}
      # @return [void]
      def validate!(opts)
        return if opts[:type_name].nil?  # bare script mode

        abort "-r- (stdin script) and -F- (stdin data) cannot both be used" if opts[:scripts]&.include?(:stdin) && opts[:file] == "-"

        type_name = opts[:type_name]

        if type_name == "pipe"
          has_in_out = opts[:in_endpoints].any? || opts[:out_endpoints].any?
          if has_in_out
            # Promote bare endpoints into the missing side:
            # `pipe -c SRC --out -c DST` → bare SRC becomes --in
            if opts[:in_endpoints].empty? && opts[:endpoints].any?
              opts[:in_endpoints] = opts[:endpoints]
              opts[:endpoints]    = []
            elsif opts[:out_endpoints].empty? && opts[:endpoints].any?
              opts[:out_endpoints] = opts[:endpoints]
              opts[:endpoints]     = []
            end
            abort "pipe --in requires at least one endpoint"             if opts[:in_endpoints].empty?
            abort "pipe --out requires at least one endpoint"            if opts[:out_endpoints].empty?
            abort "pipe: don't mix --in/--out with bare -b/-c endpoints" unless opts[:endpoints].empty?
          else
            abort "pipe requires exactly 2 endpoints (pull-side and push-side), or use --in/--out" if opts[:endpoints].size != 2
          end
        else
          abort "--in/--out are only valid for pipe" if opts[:in_endpoints].any? || opts[:out_endpoints].any?
          abort "At least one --connect or --bind is required" if opts[:connects].empty? && opts[:binds].empty?
        end
        abort "--data and --file are mutually exclusive"        if opts[:data] && opts[:file]
        abort "--subscribe is only valid for SUB"               if !opts[:subscribes].empty? && type_name != "sub"
        abort "--recv-eval is not valid for send-only sockets (use --send-eval / -E)" if opts[:recv_expr] && SEND_ONLY.include?(type_name)
        abort "--send-eval is not valid for recv-only sockets (use --recv-eval / -e)" if opts[:send_expr] && RECV_ONLY.include?(type_name)
        abort "--send-eval is not valid for REP (the reply is the result of --recv-eval / -e)" if opts[:send_expr] && type_name == "rep"

        if opts[:parallel]
          parallel_types = %w[pipe]
          abort "-P/--parallel is only valid for #{parallel_types.join(", ")}" unless parallel_types.include?(type_name)
          abort "-P/--parallel must be 1..16" unless (1..16).include?(opts[:parallel])
          all_eps = if type_name == "pipe"
                      opts[:in_endpoints] + opts[:out_endpoints] + opts[:endpoints]
                    else
                      opts[:endpoints]
                    end
          abort "-P/--parallel requires all endpoints to use --connect (not --bind)" if all_eps.any?(&:bind?)
        end

        (opts[:connects] + opts[:binds]).each do |url|
          abort "inproc not supported, use tcp:// or ipc://" if url.include?("inproc://")
        end

        all_urls = if type_name == "pipe"
                     (opts[:in_endpoints] + opts[:out_endpoints] + opts[:endpoints]).map(&:url)
                   else
                     opts[:connects] + opts[:binds]
                   end
        dups = all_urls.tally.select { |_, n| n > 1 }.keys
        abort "duplicate endpoint: #{dups.first}" if dups.any?
      end


      # Expands shorthand `@name` to `ipc://@name` (Linux abstract namespace).
      # Only triggers when the value starts with `@` and has no `://` scheme.
      def expand_endpoint(url)
        url.start_with?("@") && !url.include?("://") ? "ipc://#{url}" : url
      end
    end
  end
end
