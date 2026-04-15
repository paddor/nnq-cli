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
          msg = read_next
          break unless msg
          msg = eval_send_expr(msg)
          next unless msg
          survey_and_collect(msg)
          i += 1
          break if n && n > 0 && i >= n
          break if !config.interval && (config.data || config.file)
          wait_for_interval if config.interval
        end
      end


      def survey_and_collect(msg)
        return if msg.nil? || msg.empty?
        body = config.format == :marshal ? Marshal.dump(msg) : msg
        @sock.send_survey(body)
        transient_ready!
        collect_replies
      end


      def collect_replies
        loop do
          body = @sock.receive
          break if body.nil?
          reply = config.format == :marshal ? Marshal.load(body) : body
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
          abort "RESPONDENT needs a reply source: --echo, --data, --file, -e, or stdin pipe"
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
