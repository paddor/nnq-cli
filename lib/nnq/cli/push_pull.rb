# frozen_string_literal: true

module NNQ
  module CLI
    # Runner for PUSH sockets (send-only pipeline producer).
    class PushRunner < BaseRunner
      def run_loop(task) = run_send_logic
    end


    # Runner for PULL sockets (receive-only pipeline consumer).
    class PullRunner < BaseRunner
      private


      def run_loop(task) = run_recv_logic
    end
  end
end
