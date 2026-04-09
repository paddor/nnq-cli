# frozen_string_literal: true

module NNQ
  module CLI
    # Runner for REQ sockets (synchronous request-reply client).
    #
    # nnq's REQ is cooked: #send_request takes the request body and
    # blocks until the matching reply arrives, returning the reply body.
    class ReqRunner < BaseRunner
      private


      def run_loop(task)
        n = config.count
        i = 0
        sleep(config.delay) if config.delay
        loop do
          parts = read_next
          break unless parts
          parts = eval_send_expr(parts)
          next unless parts
          reply = request_and_receive(parts)
          break if reply.nil?
          output(eval_recv_expr(reply))
          i += 1
          break if n && n > 0 && i >= n
          break if !config.interval && (config.data || config.file)
          wait_for_interval if config.interval
        end
      end


      def request_and_receive(parts)
        return nil if parts.empty?
        parts = [Marshal.dump(parts.first)] if config.format == :marshal
        parts = @fmt.compress(parts)
        reply_body = @sock.send_request(parts.first)
        transient_ready!
        return nil if reply_body.nil?
        reply = @fmt.decompress([reply_body])
        reply = [Marshal.load(reply.first)] if config.format == :marshal
        reply
      end


      def wait_for_interval
        wait = config.interval - (Time.now.to_f % config.interval)
        sleep(wait) if wait > 0
      end
    end


    # Runner for REP sockets (synchronous request-reply server).
    #
    # nnq's REP enforces strict alternation: #receive then #send_reply.
    # There is no #send at all, so we bypass BaseRunner's send helpers.
    class RepRunner < BaseRunner
      private


      def run_loop(task)
        n = config.count
        i = 0
        loop do
          msg = recv_msg
          break if msg.nil?
          break unless handle_rep_request(msg)
          i += 1
          break if n && n > 0 && i >= n
        end
      end


      def handle_rep_request(msg)
        if config.recv_expr || @recv_eval_proc
          reply = eval_recv_expr(msg)
          unless reply.equal?(SENT)
            output(reply)
            send_reply(reply || [""])
          end
        elsif config.echo
          output(msg)
          send_reply(msg)
        elsif config.data || config.file || !config.stdin_is_tty
          reply = read_next
          return false unless reply
          output(msg)
          send_reply(reply)
        else
          abort "REP needs a reply source: --echo, --data, --file, -e, or stdin pipe"
        end
        true
      end


      def send_reply(parts)
        return if parts.empty?
        parts = [Marshal.dump(parts.first)] if config.format == :marshal
        parts = @fmt.compress(parts)
        @sock.send_reply(parts.first)
        transient_ready!
      end
    end
  end
end
