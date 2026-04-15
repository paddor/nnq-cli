# frozen_string_literal: true

module NNQ
  module CLI
    # Template runner base class for all socket-type CLI runners.
    # Subclasses override {#run_loop} to implement socket-specific behaviour.
    #
    # nnq carries one String body per message (no multipart).
    #
    class BaseRunner
      # @return [Config] frozen CLI configuration
      attr_reader :config


      # @return [Object] the NNQ socket instance
      attr_reader :sock


      # @param config [Config] frozen CLI configuration
      # @param socket_class [Class] NNQ socket class to instantiate (e.g. NNQ::PUSH)
      def initialize(config, socket_class)
        @config = config
        @klass  = socket_class
        @fmt    = Formatter.new(config.format)
      end


      # Runs the full lifecycle: socket setup, peer wait, BEGIN/END blocks, and the main loop.
      #
      # @param task [Async::Task] the parent async task
      # @return [void]
      def call(task)
        set_process_title
        setup_socket
        start_event_monitor if config.verbose >= 2
        maybe_start_transient_monitor(task)
        sleep(config.delay) if config.delay && config.recv_only?
        wait_for_peer if needs_peer_wait?
        run_begin_blocks
        run_loop(task)
        run_end_blocks
      ensure
        @sock&.close
      end


      private


      # Subclasses override this.
      def run_loop(task)
        raise NotImplementedError
      end


      # -- Socket creation ---------------------------------------------


      def setup_socket
        @sock = create_socket
        attach_endpoints
        setup_subscriptions
        compile_expr
      end


      def create_socket
        sock = SocketSetup.build(@klass, config)
        SocketSetup.maybe_wrap_zstd(sock, config.compress)
      end


      def attach_endpoints
        SocketSetup.attach(@sock, config, verbose: config.verbose)
      end


      # -- Transient disconnect monitor --------------------------------


      def maybe_start_transient_monitor(task)
        return unless config.transient
        @transient_monitor = TransientMonitor.new(@sock, config, task, method(:log))
        Async::Task.current.yield  # let monitor start waiting
      end


      def transient_ready!
        @transient_monitor&.ready!
      end


      # -- BEGIN / END blocks ------------------------------------------


      def run_begin_blocks
        @sock.instance_exec(&@send_begin_proc) if @send_begin_proc
        @sock.instance_exec(&@recv_begin_proc) if @recv_begin_proc
      end


      def run_end_blocks
        @sock.instance_exec(&@send_end_proc) if @send_end_proc
        @sock.instance_exec(&@recv_end_proc) if @recv_end_proc
      end


      # -- Peer wait with grace period ---------------------------------


      def needs_peer_wait?
        return false if config.recv_only?
        return true if config.connects.any?

        # Bind-mode senders with a bounded or scheduled send plan:
        # wait for the first peer so a one-shot `-d` / `-E` doesn't
        # just queue into HWM and then exit before anyone is
        # listening. Interactive stdin still goes through unwaited
        # so typing isn't gated on a peer.
        config.binds.any? && bounded_or_scheduled_send?
      end


      def bounded_or_scheduled_send?
        config.interval || config.data || config.file || @send_eval_proc
      end


      def wait_for_peer
        wait_body = proc do
          @sock.peer_connected.wait
          log "peer connected"
          apply_grace_period
        end

        if config.timeout
          Fiber.scheduler.with_timeout(config.timeout, &wait_body)
        else
          wait_body.call
        end
      end


      # Grace period: when multiple peers may be connecting (bind or
      # multiple connect URLs), wait one reconnect interval so
      # latecomers finish their handshake before we start sending.
      def apply_grace_period
        return unless config.binds.any? || config.connects.size > 1

        ri = @sock.options.reconnect_interval
        sleep(ri.is_a?(Range) ? ri.begin : ri)
      end


      # -- Socket setup ------------------------------------------------


      def setup_subscriptions
        SocketSetup.setup_subscriptions(@sock, config)
      end


      # -- Shared loop bodies ------------------------------------------


      def run_send_logic
        n = config.count

        sleep config.delay if config.delay

        if config.interval
          run_interval_send(n)
        elsif config.data || config.file
          # One-shot from -d/-f. --count N fires the same payload N times.
          msg = eval_send_expr(read_next)
          (n && n > 0 ? n : 1).times { send_msg(msg) } if msg
        elsif stdin_ready?
          run_stdin_send(n)
        elsif @send_eval_proc
          # Pure generator: -e/-E with no stdin input. Fire once by
          # default, --count N fires N times.
          (n && n > 0 ? n : 1).times do
            msg = eval_send_expr(nil)
            send_msg(msg) if msg
          end
        elsif config.stdin_is_tty
          # Bare interactive invocation on a terminal: read lines from
          # the tty until the user hits ^D.
          run_stdin_send(n)
        end
      end


      def run_interval_send(n)
        i = send_tick

        if @send_tick_eof || (n && n > 0 && i >= n)
          return
        end

        Async::Loop.quantized(interval: config.interval) do
          i += send_tick

          if @send_tick_eof || (n && n > 0 && i >= n)
            break
          end
        end
      end


      def run_stdin_send(n)
        i = 0

        loop do
          msg = read_next or break
          msg = eval_send_expr(msg)

          send_msg(msg) if msg

          i += 1
          break if n && n > 0 && i >= n
        end
      end


      def send_tick
        raw = read_next_or_nil

        if raw.nil?
          if @send_eval_proc && !@stdin_ready
            # Pure generator mode: no stdin, eval produces output from nothing.
            msg = eval_send_expr(nil)
            send_msg(msg) if msg
            return 1
          end

          @send_tick_eof = true
          return 0
        end

        msg = eval_send_expr(raw)
        send_msg(msg) if msg
        1
      end


      def run_recv_logic
        n = config.count
        i = 0

        if config.interval
          run_interval_recv(n)
        else
          loop do
            msg = recv_msg or break
            msg = eval_recv_expr(msg)

            output(msg)

            i += 1
            break if n && n > 0 && i >= n
          end
        end
      end


      def run_interval_recv(n)
        i = recv_tick

        return if i == 0
        return if n && n > 0 && i >= n

        Async::Loop.quantized(interval: config.interval) do
          i += recv_tick

          if @recv_tick_eof || (n && n > 0 && i >= n)
            break
          end
        end
      end


      def recv_tick
        msg = recv_msg

        if msg.nil?
          @recv_tick_eof = true
          return 0
        end

        msg = eval_recv_expr(msg)
        output(msg)
        1
      end


      def wait_for_loops(receiver, sender)
        if config.data || config.file || config.send_expr || config.recv_expr
          sender.wait
          receiver.stop
        elsif config.count && config.count > 0
          receiver.wait
          sender.stop
        else
          sender.wait
          receiver.stop
        end
      end


      # -- Message I/O -------------------------------------------------


      # @param msg [String]
      #
      def send_msg(msg)
        body = msg

        case config.format
        when :marshal
          body = Marshal.dump(msg)
        end

        @sock.send(body)
        transient_ready!
      end


      # @return [String, nil] message body, or nil on close.
      def recv_msg
        msg = @sock.receive or return

        case config.format
        when :marshal
          msg = Marshal.load msg
        end

        transient_ready!
        msg
      end


      def read_next
        config.data || config.file ? read_inline_data : read_stdin_input
      end


      def read_inline_data
        if config.data
          @fmt.decode(config.data + "\n")
        else
          @file_data ||= (config.file == "-" ? $stdin.read : File.read(config.file)).chomp
          @fmt.decode(@file_data + "\n")
        end
      end


      def read_stdin_input
        case config.format
        when :msgpack
          @fmt.decode_msgpack($stdin)
        when :marshal
          @fmt.decode_marshal($stdin)
        when :raw
          data = $stdin.read
          data.nil? || data.empty? ? nil : data
        else
          line = $stdin.gets
          line.nil? ? nil : @fmt.decode(line)
        end
      end


      def stdin_ready?
        return @stdin_ready unless @stdin_ready.nil?

        @stdin_ready = !$stdin.closed? &&
                       !config.stdin_is_tty &&
                       IO.select([$stdin], nil, nil, 0.01) &&
                       !$stdin.eof?
      end


      def read_next_or_nil
        if config.data || config.file
          read_next
        elsif stdin_ready?
          read_stdin_input
        else
          nil
        end
      end


      def output(msg)
        return if config.quiet || msg.nil?

        $stdout.write(@fmt.encode(msg))
        $stdout.flush
      end


      # -- Eval --------------------------------------------------------


      def compile_expr
        @send_evaluator = compile_evaluator(config.send_expr, fallback: NNQ.outgoing_proc)
        @recv_evaluator = compile_evaluator(config.recv_expr, fallback: NNQ.incoming_proc)
        assign_send_aliases
        assign_recv_aliases
      end


      def compile_evaluator(src, fallback:)
        ExpressionEvaluator.new(src, format: config.format, fallback_proc: fallback)
      end


      def assign_send_aliases
        # Keep ivar aliases -- subclasses check these directly
        @send_begin_proc = @send_evaluator.begin_proc
        @send_eval_proc  = @send_evaluator.eval_proc
        @send_end_proc   = @send_evaluator.end_proc
      end


      def assign_recv_aliases
        @recv_begin_proc = @recv_evaluator.begin_proc
        @recv_eval_proc  = @recv_evaluator.eval_proc
        @recv_end_proc   = @recv_evaluator.end_proc
      end


      def eval_send_expr(msg)
        @send_evaluator.call(msg, @sock)
      end


      def eval_recv_expr(msg)
        @recv_evaluator.call(msg, @sock)
      end


      SENT = ExpressionEvaluator::SENT


      # -- Process title -------------------------------------------------


      def set_process_title(endpoints: nil)
        eps = endpoints || config.endpoints
        title = ["nnq", config.type_name]
        title << (config.compress == :balanced ? "-Z" : "-z") if config.compress
        title << "-P#{config.parallel}" if config.parallel

        eps.each do |ep|
          title << (ep.respond_to?(:url) ? ep.url : ep.to_s)
        end

        Process.setproctitle(title.join(" "))
      end


      # -- Logging -----------------------------------------------------


      def log(msg)
        return unless config.verbose >= 1

        $stderr.write("#{Term.log_prefix(config.verbose)}nnq: #{msg}\n")
      end


      # -vv: log connect/disconnect/retry/timeout events via Socket#monitor
      # -vvv: also log message sent/received traces
      # -vvvv: prepend ISO8601 timestamps
      def start_event_monitor
        verbose = config.verbose >= 3
        v       = config.verbose

        @sock.monitor(verbose: verbose) do |event|
          CLI::Term.write_event(event, v)
        end
      end

    end
  end
end
