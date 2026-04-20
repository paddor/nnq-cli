# frozen_string_literal: true

module NNQ
  module CLI
    # Handles encoding/decoding a single-body message in the configured
    # format. Compression is handled by the NNQ::Zstd decorator around
    # the socket, not by the formatter.
    #
    # Unlike omq-cli's Formatter, nnq messages are not multipart — one
    # `String` body per message. The API takes and returns a plain
    # `String`.
    class Formatter
      # @param format [Symbol] wire format (:ascii, :quoted, :raw, :msgpack, :marshal)
      def initialize(format)
        @format = format
      end


      # Encodes a message body into a printable string for output.
      #
      # @param msg [String] message body
      # @return [String] formatted output line
      #
      def encode(msg)
        case @format
        when :ascii
          msg.b.gsub(/[^[:print:]\t]/, ".") << "\n"
        when :quoted
          msg.b.dump[1..-2] << "\n"
        when :raw
          msg # FIXME: are these really the wire bytes?
        when :msgpack
          MessagePack.pack(msg)
        when :marshal
          msg.inspect << "\n"
        end
      end


      # Decodes a formatted input line into a message body.
      #
      # @param line [String] input line (newline-terminated)
      # @return [String] message
      #
      def decode(line)
        case @format
        when :ascii, :marshal
          line.chomp
        when :quoted
          "\"#{line.chomp}\"".undump
        when :raw
          line
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
      # When +wire_size+ is given and differs from the plaintext size,
      # the header shows the compressed on-the-wire size too, e.g.
      # "(1000B wire=27B) ZZZZZZZZZZZZ...".
      #
      # @param body [String] message body
      # @param wire_size [Integer, nil] compressed bytes on the wire
      # @return [String] truncated preview
      def self.preview(body, wire_size: nil)
        body   = body.to_s
        size   = "#{body.bytesize}B"
        size   = "#{size} wire=#{wire_size}B" if wire_size && wire_size != body.bytesize
        "(#{size}) #{preview_body(body)}"
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
