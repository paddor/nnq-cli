# frozen_string_literal: true

require_relative "support"

describe NNQ::CLI::Formatter do

  # -- ASCII format -------------------------------------------------

  describe "ascii" do
    before { @fmt = NNQ::CLI::Formatter.new(:ascii) }

    it "encodes single-frame message" do
      assert_equal "hello\n", @fmt.encode(["hello"])
    end

    it "replaces non-printable bytes with dots" do
      assert_equal "hel.o\n", @fmt.encode(["hel\x00o"])
      assert_equal "ab..cd\n", @fmt.encode(["ab\x01\x02cd"])
    end

    it "preserves tabs in output" do
      assert_equal "a\tb\n", @fmt.encode(["a\tb"])
    end

    it "encodes empty message" do
      assert_equal "\n", @fmt.encode([""])
    end

    it "decodes into 1-element array" do
      assert_equal ["hello"], @fmt.decode("hello\n")
    end

    it "round-trips printable text" do
      parts = ["hello"]
      assert_equal parts, @fmt.decode(@fmt.encode(parts))
    end
  end

  # -- Quoted format ------------------------------------------------

  describe "quoted" do
    before { @fmt = NNQ::CLI::Formatter.new(:quoted) }

    it "encodes printable text unchanged" do
      assert_equal "hello world\n", @fmt.encode(["hello world"])
    end

    it "escapes newlines" do
      assert_equal "line1\\nline2\n", @fmt.encode(["line1\nline2"])
    end

    it "escapes carriage returns" do
      assert_equal "a\\rb\n", @fmt.encode(["a\rb"])
    end

    it "escapes tabs" do
      assert_equal "a\\tb\n", @fmt.encode(["a\tb"])
    end

    it "escapes backslashes" do
      assert_equal "a\\\\b\n", @fmt.encode(["a\\b"])
    end

    it "hex-escapes other non-printable bytes" do
      assert_equal "\\x00\\x01\\x7F\n", @fmt.encode(["\x00\x01\x7f"])
    end

    it "decodes escaped newlines" do
      assert_equal ["line1\nline2"], @fmt.decode("line1\\nline2\n")
    end

    it "decodes escaped carriage returns" do
      assert_equal ["a\rb"], @fmt.decode("a\\rb\n")
    end

    it "decodes escaped tabs" do
      assert_equal ["a\tb"], @fmt.decode("a\\tb\n")
    end

    it "decodes escaped backslashes" do
      assert_equal ["a\\b"], @fmt.decode("a\\\\b\n")
    end

    it "decodes hex escapes" do
      assert_equal ["\x00\xff".b], @fmt.decode("\\x00\\xFF\n").map(&:b)
    end

    it "round-trips text with special characters" do
      parts = ["line1\nline2\ttab\\back"]
      assert_equal parts, @fmt.decode(@fmt.encode(parts))
    end

    it "round-trips binary data" do
      binary  = (0..255).map(&:chr).join.b
      encoded = @fmt.encode([binary])
      decoded = @fmt.decode(encoded).first.b
      assert_equal binary, decoded
    end
  end

  # -- Raw format ---------------------------------------------------

  describe "raw" do
    before { @fmt = NNQ::CLI::Formatter.new(:raw) }

    it "encodes body verbatim" do
      assert_equal "hello", @fmt.encode(["hello"])
    end

    it "encodes empty message as empty string" do
      assert_equal "", @fmt.encode([""])
    end

    it "decodes line unchanged" do
      assert_equal ["hello\n"], @fmt.decode("hello\n")
    end

    it "preserves binary data" do
      binary = "\x00\x01\xff".b
      assert_equal [binary], @fmt.decode(binary)
    end
  end

  # -- JSONL format -------------------------------------------------

  describe "jsonl" do
    before { @fmt = NNQ::CLI::Formatter.new(:jsonl) }

    it "encodes as JSON array" do
      assert_equal "[\"hello\"]\n", @fmt.encode(["hello"])
    end

    it "encodes empty body" do
      assert_equal "[\"\"]\n", @fmt.encode([""])
    end

    it "decodes JSON array into 1-element parts" do
      assert_equal ["hello"], @fmt.decode("[\"hello\"]\n")
    end

    it "drops extra elements from multi-element JSON arrays" do
      assert_equal ["a"], @fmt.decode("[\"a\",\"b\"]\n")
    end

    it "round-trips single-frame messages" do
      parts = ["frame1"]
      assert_equal parts, @fmt.decode(@fmt.encode(parts))
    end

    it "handles special JSON characters" do
      parts = ["line\nnew\ttab\"quote"]
      assert_equal parts, @fmt.decode(@fmt.encode(parts))
    end
  end

  # -- MessagePack format ------------------------------------------

  describe "msgpack" do
    before { @fmt = NNQ::CLI::Formatter.new(:msgpack) }

    it "encodes as MessagePack array" do
      encoded = @fmt.encode(["hello"])
      assert_equal ["hello"], MessagePack.unpack(encoded)
    end

    it "decodes from IO stream" do
      data   = MessagePack.pack(["hello"])
      io     = StringIO.new(data)
      result = @fmt.decode_msgpack(io)
      assert_equal ["hello"], result
    end

    it "decodes multiple messages from stream" do
      data = MessagePack.pack(["msg1"]) + MessagePack.pack(["msg2"])
      io   = StringIO.new(data)
      assert_equal ["msg1"], @fmt.decode_msgpack(io)
      assert_equal ["msg2"], @fmt.decode_msgpack(io)
    end

    it "returns nil at EOF" do
      io = StringIO.new("")
      assert_nil @fmt.decode_msgpack(io)
    end
  end

  # -- Compression -------------------------------------------------

  describe "compression" do
    it "passes through when disabled" do
      fmt   = NNQ::CLI::Formatter.new(:ascii)
      parts = ["hello"]
      assert_same parts, fmt.compress(parts)
      assert_same parts, fmt.decompress(parts)
    end

    it "round-trips with compression enabled" do
      fmt        = NNQ::CLI::Formatter.new(:ascii, compress: true)
      parts      = ["hello world, hello world, hello world"]
      compressed = fmt.compress(parts)
      refute_equal parts, compressed
      assert_equal parts, fmt.decompress(compressed)
    end

    it "compresses large data" do
      fmt   = NNQ::CLI::Formatter.new(:ascii, compress: true)
      big   = ["x" * 10_000]
      small = fmt.compress(big)
      assert_operator small.first.bytesize, :<, big.first.bytesize
      assert_equal big, fmt.decompress(small)
    end

    it "raises DecompressError on corrupted input" do
      fmt = NNQ::CLI::Formatter.new(:ascii, compress: true)
      assert_raises(NNQ::CLI::DecompressError) do
        fmt.decompress(["not lz4 data"])
      end
    end
  end

  # -- Preview -----------------------------------------------------

  describe "preview" do
    it "renders a single printable frame" do
      assert_equal "(3B) foo", NNQ::CLI::Formatter.preview(["foo"])
    end

    it "renders an empty frame as [0B] marker" do
      assert_equal "(0B) [0B]", NNQ::CLI::Formatter.preview([""])
    end

    it "truncates long printable frames" do
      preview = NNQ::CLI::Formatter.preview(["abcdefghijklmnop"])
      assert_equal "(16B) abcdefghijkl...", preview
    end

    it "shows byte length for binary frames" do
      assert_equal "(4B) [4B]", NNQ::CLI::Formatter.preview(["\x00\x01\x02\x03"])
    end
  end
end
