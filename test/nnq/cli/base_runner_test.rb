# frozen_string_literal: true

require_relative "support"

# -- Output ----------------------------------------------------------

describe "output" do
  before do
    @runner = NNQ::CLI::PullRunner.new(
      make_config(type_name: "pull"),
      NNQ::PULL
    )
  end

  it "skips nil parts" do
    out      = StringIO.new
    $stdout  = out
    @runner.send(:output, nil)
    $stdout  = STDOUT
    assert_equal "", out.string
  end

  it "prints the message body" do
    out      = StringIO.new
    $stdout  = out
    @runner.send(:output, ["hello"])
    $stdout  = STDOUT
    assert_equal "hello\n", out.string
  end
end


# -- Config ----------------------------------------------------------

describe "NNQ::CLI::Config" do
  it "is frozen" do
    config = make_config(type_name: "push")
    assert config.frozen?
  end

  it "knows send-only types" do
    assert make_config(type_name: "push").send_only?
    assert make_config(type_name: "pub").send_only?
    refute make_config(type_name: "pull").send_only?
    refute make_config(type_name: "req").send_only?
  end

  it "knows recv-only types" do
    assert make_config(type_name: "pull").recv_only?
    assert make_config(type_name: "sub").recv_only?
    refute make_config(type_name: "push").recv_only?
    refute make_config(type_name: "rep").recv_only?
  end
end
