# frozen_string_literal: true

module NNQ
  module CLI
    # Worker that runs inside a Ractor for pipe -P parallel mode.
    # Each worker owns its own Async reactor, PULL socket, and PUSH socket.
    #
    class PipeWorker
      def initialize(config, in_eps, out_eps, log_port, error_port = nil)
        @config     = config
        @in_eps     = in_eps
        @out_eps    = out_eps
        @log_port   = log_port
        @error_port = error_port
      end


      def call
        Async do
          setup_sockets
          log_endpoints if @config.verbose >= 1
          start_monitors if @config.verbose >= 2
          wait_for_peers
          compile_expr
          run_message_loop
          run_end_block
        rescue NNQ::Zstd::ProtocolError => e
          @error_port&.send("zstd protocol error: #{e.message}")
        ensure
          @pull&.close
          @push&.close
        end
      end


      private


      def setup_sockets
        @pull = NNQ::CLI::SocketSetup.build(NNQ::PULL0, @config)
        @push = NNQ::CLI::SocketSetup.build(NNQ::PUSH0, @config)
        NNQ::CLI::SocketSetup.attach_endpoints(@pull, @in_eps, verbose: 0)
        NNQ::CLI::SocketSetup.attach_endpoints(@push, @out_eps, verbose: 0)
        @pull = NNQ::CLI::SocketSetup.maybe_wrap_zstd(@pull, @config.compress_in || @config.compress)
        @push = NNQ::CLI::SocketSetup.maybe_wrap_zstd(@push, @config.compress_out || @config.compress)
      end


      def log_endpoints
        @in_eps.each { |ep| @log_port.send(ep.bind? ? "Bound to #{ep.url}" : "Connecting to #{ep.url}") }
        @out_eps.each { |ep| @log_port.send(ep.bind? ? "Bound to #{ep.url}" : "Connecting to #{ep.url}") }
      end


      def start_monitors
        trace = @config.verbose >= 3
        [@pull, @push].each do |sock|
          sock.monitor(verbose: trace) do |event|
            @log_port.send(format_event(event))
          end
        end
      end


      def format_event(event)
        case event.type
        when :message_sent
          "nnq: >> #{NNQ::CLI::Formatter.preview(event.detail[:body])}"
        when :message_received
          "nnq: << #{NNQ::CLI::Formatter.preview(event.detail[:body])}"
        else
          ep     = event.endpoint ? " #{event.endpoint}" : ""
          detail = event.detail ? " #{event.detail}" : ""
          "nnq: #{event.type}#{ep}#{detail}"
        end
      end


      def wait_for_peers
        Async::Barrier.new.tap do |barrier|
          barrier.async { @pull.peer_connected.wait }
          barrier.async { @push.peer_connected.wait }
          barrier.wait
        end
      end


      def compile_expr
        @begin_proc, @end_proc, @eval_proc =
          NNQ::CLI::ExpressionEvaluator.compile_inside_ractor(@config.recv_expr)
        @ctx = Object.new
        @ctx.instance_exec(&@begin_proc) if @begin_proc
      end


      def run_message_loop
        n = @config.count
        if @eval_proc
          loop do
            body = @pull.receive
            break if body.nil?
            msg = NNQ::CLI::ExpressionEvaluator.normalize_result(
              @ctx.instance_exec(body, &@eval_proc)
            )
            @push.send(msg) if msg
            n -= 1 if n && n > 0
            break if n == 0
          end
        else
          loop do
            body = @pull.receive
            break if body.nil?
            @push.send(body)
            n -= 1 if n && n > 0
            break if n == 0
          end
        end
      rescue IO::TimeoutError, Async::TimeoutError
        # recv timed out -- fall through to END block
      end


      def run_end_block
        return unless @end_proc
        out = NNQ::CLI::ExpressionEvaluator.normalize_result(
          @ctx.instance_exec(&@end_proc)
        )
        @push.send(out) if out
      end
    end
  end
end
