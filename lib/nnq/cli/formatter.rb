# frozen_string_literal: true

module NNQ
  module CLI
    # Handles encoding/decoding a single-body message in the configured
    # format. Compression is handled by the NNQ::Zstd decorator around
    # the socket, not by the formatter.
    #
    # Unlike omq-cli's Formatter, nnq messages are not multipart — one
    # `String` body per message. The API still accepts/returns a
    # 1-element array so that `$F`-based eval expressions work the same
    # way.
    class Formatter
      # @param format [Symbol] wire format (:ascii, :quoted, :raw, :jsonl, :msgpack, :marshal)
      def initialize(format)
        @format = format
      end


      # Encodes a message body into a printable string for output.
      #
      # @param msg [Array<String>] single-element array (the body)
      # @return [String] formatted output line
      def encode(msg)
        body = msg.first.to_s
        case @format
        when :ascii
          body.b.gsub(/[^[:print:]\t]/, ".") + "\n"
        when :quoted
          body.b.dump[1..-2] + "\n"
        when :raw
          body
        when :jsonl
          JSON.generate([body]) + "\n"
        when :msgpack
          MessagePack.pack([body])
        when :marshal
          body.inspect + "\n"
        end
      end


      # Decodes a formatted input line into a 1-element message array.
      #
      # @param line [String] input line (newline-terminated)
      # @return [Array<String>] 1-element array
      def decode(line)
        case @format
        when :ascii, :marshal
          [line.chomp]
        when :quoted
          ["\"#{line.chomp}\"".undump]
        when :raw
          [line]
        when :jsonl
          arr = JSON.parse(line.chomp)
          unless arr.is_a?(Array) && arr.all? { |e| e.is_a?(String) }
            abort "JSON Lines input must be an array of strings"
          end
          arr.first(1)
        end
      end


      # Decodes one Marshal object from the given IO stream.
      #
      # @param io [IO] input stream
      # @return [Object, nil] deserialized object, or nil on EOF
      def decode_marshal(io)
        Marshal.load(io)
      rescue EOFError, TypeError
        nil
      end


      # Decodes one MessagePack object from the given IO stream.
      #
      # @param io [IO] input stream
      # @return [Object, nil] deserialized object, or nil on EOF
      def decode_msgpack(io)
        @msgpack_unpacker ||= MessagePack::Unpacker.new(io)
        @msgpack_unpacker.read
      rescue EOFError
        nil
      end


      # Formats a message body for human-readable preview (logging).
      #
      # @param msg [Array<String>] single-element array
      # @return [String] truncated preview
      def self.preview(msg)
        body = msg.first.to_s
        "(#{body.bytesize}B) #{preview_body(body)}"
      end


      def self.preview_body(body)
        bytes = body.b
        return "''" if bytes.empty?

        sample    = bytes[0, 12]
        printable = sample.count("\x20-\x7e")

        if printable < sample.bytesize / 2
          "[#{bytes.bytesize}B]"
        elsif bytes.bytesize > 12
          "#{sample.gsub(/[^[:print:]]/, ".")}..."
        else
          sample.gsub(/[^[:print:]]/, ".")
        end
      end
    end
  end
end
