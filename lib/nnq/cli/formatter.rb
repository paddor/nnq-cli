# frozen_string_literal: true

module NNQ
  module CLI
    # Raised when LZ4 decompression fails.
    class DecompressError < RuntimeError; end

    # Handles encoding/decoding a single-frame message in the configured
    # format, plus optional LZ4 compression.
    #
    # Unlike omq-cli's Formatter, nnq messages are single-frame (one
    # `String` body). The API still accepts/returns a 1-element array so
    # that `$F`-based eval expressions work the same way.
    class Formatter
      # @param format [Symbol] wire format (:ascii, :quoted, :raw, :jsonl, :msgpack, :marshal)
      # @param compress [Boolean] whether to apply LZ4 compression
      def initialize(format, compress: false)
        @format   = format
        @compress = compress
      end


      # Encodes a message body into a printable string for output.
      #
      # @param parts [Array<String>] single-element array (the body)
      # @return [String] formatted output line
      def encode(parts)
        body = parts.first.to_s
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


      # Decodes a formatted input line into a 1-element parts array.
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


      # Compresses the body with LZ4 if compression is enabled.
      #
      # @param parts [Array<String>] single-element array
      # @return [Array<String>] optionally compressed
      def compress(parts)
        @compress ? parts.map { |p| RLZ4.compress(p) } : parts
      end


      # Decompresses the body with LZ4 if compression is enabled.
      #
      # @param parts [Array<String>] possibly compressed single-element array
      # @return [Array<String>] decompressed
      def decompress(parts)
        @compress ? parts.map { |p| RLZ4.decompress(p) } : parts
      rescue RLZ4::DecompressError
        raise DecompressError, "decompression failed (did the sender use --compress?)"
      end


      # Formats a message body for human-readable preview (logging).
      #
      # @param parts [Array<String>] single-element array
      # @return [String] truncated preview
      def self.preview(parts)
        body = parts.first.to_s
        "(#{body.bytesize}B) #{preview_frame(body)}"
      end


      def self.preview_frame(part)
        bytes = part.b
        return "[0B]" if bytes.empty?

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
