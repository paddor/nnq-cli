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
          msg = read_next
          break unless msg
          msg = eval_send_expr(msg)
          next unless msg
          reply = request_and_receive(msg)
          break if reply.nil?
          output(eval_recv_expr(reply))
          i += 1
          break if n && n > 0 && i >= n
          break if !config.interval && (config.data || config.file)
          wait_for_interval if config.interval
        end
      end


      def request_and_receive(msg)
        return nil if msg.nil? || msg.empty?
        body = config.format == :marshal ? Marshal.dump(msg) : msg
        reply_body = @sock.send_request(body)
        transient_ready!
        return nil if reply_body.nil?
        config.format == :marshal ? Marshal.load(reply_body) : reply_body
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
            send_reply(reply || "")
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


      def send_reply(msg)
        return if msg.nil?
        body = config.format == :marshal ? Marshal.dump(msg) : msg
        @sock.send_reply(body)
        transient_ready!
      end
    end
  end
end
