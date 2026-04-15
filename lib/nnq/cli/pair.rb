# frozen_string_literal: true

module NNQ
  module CLI
    # Runner for PAIR sockets (bidirectional messaging).
    class PairRunner < BaseRunner
      private


      def run_loop(task)
        receiver = recv_async(task)
        sender   = task.async { run_send_logic }
        wait_for_loops(receiver, sender)
      end


      def recv_async(task)
        task.async do
          n = config.count
          i = 0
          loop do
            msg = recv_msg
            break if msg.nil?
            msg = eval_recv_expr(msg)
            output(msg)
            i += 1
            break if n && n > 0 && i >= n
          end
        end
      end
    end
  end
end
