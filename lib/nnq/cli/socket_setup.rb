# frozen_string_literal: true

module NNQ
  module CLI
    # Stateless helper for socket construction and configuration.
    # All methods are module-level so callers compose rather than inherit.
    module SocketSetup
      # Default high water mark applied when the user does not pass
      # --hwm. Lower than nnq's default (1000) to keep memory footprint
      # small for typical CLI use cases (interactive debugging,
      # short-lived pipelines). Pipe worker sockets override this with
      # a still-smaller value for tighter backpressure.
      DEFAULT_HWM = 100

      # Default max inbound message size (1 MiB) so a misconfigured or
      # malicious peer can't force arbitrary memory allocation on a
      # terminal user. Users can raise it with --recv-maxsz N, or
      # disable it entirely with --recv-maxsz 0.
      DEFAULT_RECV_MAXSZ = 1 << 20

      # Apply post-construction socket options from +config+ to +sock+.
      # send_hwm and linger are construction-time kwargs (see {.build});
      # the rest of the options are set here and read later by the
      # engine/transports.
      def self.apply_options(sock, config)
        sock.options.read_timeout       = config.timeout       if config.timeout
        sock.options.write_timeout      = config.timeout       if config.timeout
        sock.options.reconnect_interval = config.reconnect_ivl if config.reconnect_ivl
        sock.options.max_message_size =
          case config.recv_maxsz
          when nil then DEFAULT_RECV_MAXSZ
          when 0   then nil
          else          config.recv_maxsz
          end
      end


      # Create and fully configure a socket from +klass+ and +config+.
      # nnq's Socket constructor takes linger + send_hwm directly
      # (send_hwm is captured during routing init and can't be changed
      # after the fact), so we pass them there.
      def self.build(klass, config)
        sock = klass.new(
          linger:   config.linger,
          send_hwm: config.send_hwm || DEFAULT_HWM,
        )
        apply_options(sock, config)
        sock
      end


      # Bind/connect +sock+ using URL strings from +config.binds+ / +config.connects+.
      def self.attach(sock, config, verbose: false)
        config.binds.each do |url|
          sock.bind(url)
          $stderr.puts "Bound to #{sock.last_endpoint}" if verbose
        end
        config.connects.each do |url|
          sock.connect(url)
          $stderr.puts "Connecting to #{url}" if verbose
        end
      end


      # Bind/connect +sock+ from an Array of Endpoint objects.
      # Used by PipeRunner, which works with structured endpoint lists.
      def self.attach_endpoints(sock, endpoints, verbose: false)
        endpoints.each do |ep|
          if ep.bind?
            sock.bind(ep.url)
            $stderr.puts "Bound to #{sock.last_endpoint}" if verbose
          else
            sock.connect(ep.url)
            $stderr.puts "Connecting to #{ep.url}" if verbose
          end
        end
      end


      # Subscribe to prefixes on a SUB socket.
      #
      # Unlike ZeroMQ, nng's sub0 starts with an empty subscription set,
      # meaning *no* messages match. If the user passed no `--subscribe`
      # flags, default to subscribing to the empty prefix so the CLI
      # feels like `nngcat` / `omq sub`: receive everything by default.
      def self.setup_subscriptions(sock, config)
        return unless config.type_name == "sub"
        prefixes = config.subscribes.empty? ? [""] : config.subscribes
        prefixes.each { |p| sock.subscribe(p) }
      end
    end
  end
end
