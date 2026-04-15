# frozen_string_literal: true

require "optparse"

# Forward-declare NNQ::Zstd::ProtocolError so the rescue clause below
# resolves even when compression wasn't requested and `nnq/zstd` was
# never required. The real class is defined in nnq-zstd; re-opening it
# here with the same StandardError superclass is benign.
module NNQ
  module Zstd
    class ProtocolError < StandardError; end
  end
end

require_relative "cli/version"
require_relative "cli/config"
require_relative "cli/cli_parser"
require_relative "cli/formatter"
require_relative "cli/expression_evaluator"
require_relative "cli/socket_setup"
require_relative "cli/term"
require_relative "cli/transient_monitor"
require_relative "cli/base_runner"
require_relative "cli/push_pull"
require_relative "cli/pub_sub"
require_relative "cli/req_rep"
require_relative "cli/pair"
require_relative "cli/bus"
require_relative "cli/surveyor_respondent"
require_relative "cli/ractor_helpers"
require_relative "cli/pipe_worker"
require_relative "cli/pipe"

module NNQ

  class << self
    # @return [Proc, nil] registered outgoing message transform
    attr_reader :outgoing_proc
    # @return [Proc, nil] registered incoming message transform
    attr_reader :incoming_proc

    # Registers an outgoing message transform (used by -r scripts).
    #
    # @yield [Array<String>] 1-element message array before sending
    # @return [Proc]
    def outgoing(&block) = @outgoing_proc = block

    # Registers an incoming message transform (used by -r scripts).
    #
    # @yield [Array<String>] 1-element message array after receiving
    # @return [Proc]
    def incoming(&block) = @incoming_proc = block
  end


  # Command-line interface for NNQ socket operations.
  module CLI
    SOCKET_TYPE_NAMES = %w[req rep pub sub push pull pair bus surveyor respondent pipe].freeze


    RUNNER_MAP = {
      "push"       => [PushRunner,       :PUSH0],
      "pull"       => [PullRunner,       :PULL0],
      "pub"        => [PubRunner,        :PUB0],
      "sub"        => [SubRunner,        :SUB0],
      "req"        => [ReqRunner,        :REQ0],
      "rep"        => [RepRunner,        :REP0],
      "pair"       => [PairRunner,       :PAIR0],
      "bus"        => [BusRunner,        :BUS0],
      "surveyor"   => [SurveyorRunner,   :SURVEYOR0],
      "respondent" => [RespondentRunner, :RESPONDENT0],
      "pipe"       => [PipeRunner,       nil],
    }.freeze


    module_function


    # Displays text through the system pager, or prints directly
    # when stdout is not a terminal.
    #
    def page(text)
      if $stdout.tty?
        if ENV["PAGER"]
          pager = ENV["PAGER"]
        else
          ENV["LESS"] ||= "-FR"
          pager = "less"
        end
        IO.popen(pager, "w") { |io| io.puts text }
      else
        puts text
      end
    rescue Errno::ENOENT
      puts text
    rescue Errno::EPIPE
      # user quit pager early
    end


    # Main entry point.
    #
    # @param argv [Array<String>] command-line arguments
    # @return [void]
    def run(argv = ARGV)
      run_socket(argv)
    end


    # Parses CLI arguments, validates options, and runs the main
    # event loop inside an Async reactor.
    #
    def run_socket(argv)
      config = build_config(argv)

      require "nnq"
      require "async"
      require "json"
      require "console"

      CliParser.validate_gems!(config)
      trap("INT")  { Process.exit!(0) }
      trap("TERM") { Process.exit!(0) }

      Console.logger = Console::Logger.new(Console::Output::Null.new) unless config.verbose >= 1

      debug_ep = nil

      if ENV["NNQ_DEBUG_URI"]
        begin
          require "async/debug"
          debug_ep = Async::HTTP::Endpoint.parse(ENV["NNQ_DEBUG_URI"])
          if debug_ep.scheme == "https"
            require "localhost"
            debug_ep = Async::HTTP::Endpoint.parse(ENV["NNQ_DEBUG_URI"],
              ssl_context: Localhost::Authority.fetch.server_context)
          end
        rescue LoadError
          abort "NNQ_DEBUG_URI requires the async-debug gem: gem install async-debug"
        end
      end

      if config.type_name.nil?
        Process.setproctitle("nnq script")
        Object.include(NNQ) unless Object.include?(NNQ)
        Async annotation: 'nnq' do
          Async::Debug.serve(endpoint: debug_ep) if debug_ep
          config.scripts.each { |s| load_script(s) }
        rescue => e
          $stderr.puts "nnq: #{e.message}"
          exit 1
        end
        return
      end

      runner_class, socket_sym = RUNNER_MAP.fetch(config.type_name)

      Async annotation: "nnq #{config.type_name}" do |task|
        Async::Debug.serve(endpoint: debug_ep) if debug_ep
        config.scripts.each { |s| load_script(s) }
        runner = if socket_sym
                   runner_class.new(config, NNQ.const_get(socket_sym))
                 else
                   runner_class.new(config)
                 end
        runner.call(task)
      rescue NNQ::Zstd::ProtocolError => e
        $stderr.puts "nnq: zstd protocol error: #{e.message}"
        exit 1
      rescue IO::TimeoutError, Async::TimeoutError
        $stderr.puts "nnq: timeout" unless config.quiet
        exit 2
      rescue ::Socket::ResolutionError => e
        $stderr.puts "nnq: #{e.message}"
        exit 1
      end
    end


    def load_script(s)
      if s == :stdin
        eval($stdin.read, TOPLEVEL_BINDING, "(stdin)", 1) # rubocop:disable Security/Eval
      else
        require s
      end
    end
    private_class_method :load_script


    # Builds a frozen Config from command-line arguments.
    #
    def build_config(argv)
      opts = CliParser.parse(argv)
      CliParser.validate!(opts)

      opts[:stdin_is_tty] = $stdin.tty?

      Ractor.make_shareable(Config.new(**opts))
    end
  end
end
