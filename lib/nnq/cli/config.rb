# frozen_string_literal: true

module NNQ
  module CLI
    # Socket type names that only send messages.
    SEND_ONLY = %w[pub push].freeze
    # Socket type names that only receive messages.
    RECV_ONLY = %w[sub pull].freeze


    # A bind or connect endpoint with its URL and direction.
    Endpoint = Data.define(:url, :bind?) do
      # @return [Boolean] true if this endpoint connects rather than binds
      def connect? = !bind?
    end


    # Frozen, Ractor-shareable configuration data class for a CLI invocation.
    Config = Data.define(
      :type_name,
      :endpoints,
      :connects,
      :binds,
      :in_endpoints,
      :out_endpoints,
      :data,
      :file,
      :format,
      :subscribes,
      :interval,
      :count,
      :delay,
      :timeout,
      :linger,
      :reconnect_ivl,
      :send_hwm,
      :sndbuf,
      :rcvbuf,
      :compress,
      :compress_in,
      :compress_out,
      :send_expr,
      :recv_expr,
      :parallel,
      :transient,
      :verbose,
      :timestamps,
      :quiet,
      :echo,
      :scripts,
      :recv_maxsz,
      :stdin_is_tty,
    ) do
      # @return [Boolean] true if this socket type only sends
      def send_only? = SEND_ONLY.include?(type_name)
      # @return [Boolean] true if this socket type only receives
      def recv_only? = RECV_ONLY.include?(type_name)
    end
  end
end
