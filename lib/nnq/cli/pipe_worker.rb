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
        NNQ::CLI::SocketSetup.attach_endpoints(
          @pull, @in_eps,
          compress_level: @config.compress_in || @config.compress,
          verbose: 0,
        )
        NNQ::CLI::SocketSetup.attach_endpoints(
          @push, @out_eps,
          compress_level: @config.compress_out || @config.compress,
          verbose: 0,
        )
      end


      def log_endpoints
        ts = @config.timestamps
        @in_eps.each { |ep| @log_port.send(NNQ::CLI::Term.format_attach(ep.bind? ? :bind : :connect, ep.url, ts)) }
        @out_eps.each { |ep| @log_port.send(NNQ::CLI::Term.format_attach(ep.bind? ? :bind : :connect, ep.url, ts)) }
      end


      def start_monitors
        trace = @config.verbose >= 3
        ts = @config.timestamps
        [@pull, @push].each do |sock|
          sock.monitor(verbose: trace) do |event|
            @log_port.send(NNQ::CLI::Term.format_event(event, ts))
          end
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
