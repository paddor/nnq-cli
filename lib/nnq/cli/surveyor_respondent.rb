# frozen_string_literal: true

module NNQ
  module CLI
    # Runner for SURVEYOR sockets (broadcast survey, collect replies).
    #
    # Sends each input line as a survey, then collects replies until
    # the survey window expires.
    class SurveyorRunner < BaseRunner
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
          survey_and_collect(parts)
          i += 1
          break if n && n > 0 && i >= n
          break if !config.interval && (config.data || config.file)
          wait_for_interval if config.interval
        end
      end


      def survey_and_collect(parts)
        return if parts.empty?
        parts = [Marshal.dump(parts.first)] if config.format == :marshal
        parts = @fmt.compress(parts)
        @sock.send_survey(parts.first)
        transient_ready!
        collect_replies
      end


      def collect_replies
        loop do
          body = @sock.receive
          break if body.nil?
          reply = @fmt.decompress([body])
          reply = [Marshal.load(reply.first)] if config.format == :marshal
          output(eval_recv_expr(reply))
        rescue NNQ::TimedOut
          break
        end
      end


      def wait_for_interval
        wait = config.interval - (Time.now.to_f % config.interval)
        sleep(wait) if wait > 0
      end
    end


    # Runner for RESPONDENT sockets (receive surveys, send replies).
    #
    # Mirrors REP: strict alternation of #receive then #send_reply.
    class RespondentRunner < BaseRunner
      private


      def run_loop(task)
        n = config.count
        i = 0
        loop do
          msg = recv_msg
          break if msg.nil?
          break unless handle_survey(msg)
          i += 1
          break if n && n > 0 && i >= n
        end
      end


      def handle_survey(msg)
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
          abort "RESPONDENT needs a reply source: --echo, --data, --file, -e, or stdin pipe"
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
