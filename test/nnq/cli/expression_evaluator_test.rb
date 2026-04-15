# frozen_string_literal: true

require_relative "support"

describe "eval_send_expr" do
  before do
    @runner = NNQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "$F"),
      NNQ::PUSH
    )
    @runner.send(:compile_expr)
  end

  it "sets $F to a 1-element message array" do
    result = @runner.send(:eval_send_expr, ["hello"])
    assert_equal ["hello"], result
  end

  it "sets $_ to the body" do
    runner = NNQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "$_"),
      NNQ::PUSH
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_send_expr, ["first"])
    assert_equal ["first"], result
  end

  it "sets $_ to nil when msg is nil" do
    runner = NNQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "$_.nil? ? 'yes' : 'no'"),
      NNQ::PUSH
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_send_expr, nil)
    assert_equal ["yes"], result
  end

  it "returns nil when expression evaluates to nil" do
    runner = NNQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "nil"),
      NNQ::PUSH
    )
    runner.send(:compile_expr)
    assert_nil runner.send(:eval_send_expr, ["anything"])
  end

  it "returns SENT when expression returns the context (self)" do
    runner = NNQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "self"),
      NNQ::PUSH
    )
    runner.send(:compile_expr)
    stub_sock = Object.new
    runner.instance_variable_set(:@sock, stub_sock)
    result = runner.send(:eval_send_expr, ["hello"])
    assert_equal NNQ::CLI::BaseRunner::SENT, result
  end

  it "wraps string result in array" do
    runner = NNQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "'hello'"),
      NNQ::PUSH
    )
    runner.send(:compile_expr)
    assert_equal ["hello"], runner.send(:eval_send_expr, nil)
  end

  it "truncates multi-element array results to the first element" do
    runner = NNQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "['a', 'b', 'c']"),
      NNQ::PUSH
    )
    runner.send(:compile_expr)
    assert_equal ["a"], runner.send(:eval_send_expr, ["ignored"])
  end
end

describe "eval_recv_expr" do
  it "transforms incoming messages" do
    runner = NNQ::CLI::PullRunner.new(
      make_config(type_name: "pull", recv_expr: "$_.upcase"),
      NNQ::PULL
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["HELLO"], result
  end

  it "returns msg unchanged when no recv_expr" do
    runner = NNQ::CLI::PullRunner.new(
      make_config(type_name: "pull"),
      NNQ::PULL
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["hello"], result
  end

  it "returns nil when expression evaluates to nil (filtering)" do
    runner = NNQ::CLI::PullRunner.new(
      make_config(type_name: "pull", recv_expr: "nil"),
      NNQ::PULL
    )
    runner.send(:compile_expr)
    assert_nil runner.send(:eval_recv_expr, ["anything"])
  end

  it "sets $_ to the body" do
    runner = NNQ::CLI::PullRunner.new(
      make_config(type_name: "pull", recv_expr: "$_"),
      NNQ::PULL
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_recv_expr, ["first"])
    assert_equal ["first"], result
  end
end


describe "independent send and recv eval" do
  it "compiles send and recv procs independently" do
    runner = NNQ::CLI::ReqRunner.new(
      make_config(type_name: "req", send_expr: "$_.upcase", recv_expr: "$_.reverse"),
      NNQ::REQ
    )
    runner.send(:compile_expr)

    send_result = runner.send(:eval_send_expr, ["hello"])
    assert_equal ["HELLO"], send_result

    recv_result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["olleh"], recv_result
  end

  it "allows send_expr without recv_expr" do
    runner = NNQ::CLI::ReqRunner.new(
      make_config(type_name: "req", send_expr: "$_.upcase"),
      NNQ::REQ
    )
    runner.send(:compile_expr)

    send_result = runner.send(:eval_send_expr, ["hello"])
    assert_equal ["HELLO"], send_result

    recv_result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["hello"], recv_result
  end

  it "allows recv_expr without send_expr" do
    runner = NNQ::CLI::ReqRunner.new(
      make_config(type_name: "req", recv_expr: "$_.upcase"),
      NNQ::REQ
    )
    runner.send(:compile_expr)

    send_result = runner.send(:eval_send_expr, ["hello"])
    assert_equal ["hello"], send_result

    recv_result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["HELLO"], recv_result
  end
end


describe "BEGIN/END blocks per direction" do
  it "compiles BEGIN/END for send_expr" do
    runner = NNQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: 'BEGIN{ @count = 0 } @count += 1; $_ END{ }'),
      NNQ::PUSH
    )
    runner.send(:compile_expr)
    refute_nil runner.instance_variable_get(:@send_begin_proc)
    assert_nil runner.instance_variable_get(:@recv_begin_proc)
  end

  it "compiles BEGIN/END for recv_expr" do
    runner = NNQ::CLI::PullRunner.new(
      make_config(type_name: "pull", recv_expr: 'BEGIN{ @sum = 0 } @sum += Integer($_); next END{ puts @sum }'),
      NNQ::PULL
    )
    runner.send(:compile_expr)
    refute_nil runner.instance_variable_get(:@recv_begin_proc)
    assert_nil runner.instance_variable_get(:@send_begin_proc)
  end

  it "compiles BEGIN/END independently for both directions" do
    runner = NNQ::CLI::PairRunner.new(
      make_config(type_name: "pair",
                  send_expr: 'BEGIN{ @send_count = 0 } @send_count += 1; $_',
                  recv_expr: 'BEGIN{ @recv_count = 0 } @recv_count += 1; $_'),
      NNQ::PAIR
    )
    runner.send(:compile_expr)
    refute_nil runner.instance_variable_get(:@send_begin_proc)
    refute_nil runner.instance_variable_get(:@recv_begin_proc)
  end
end

# -- Registration API (NNQ.outgoing / NNQ.incoming) --------------

describe "NNQ.outgoing / NNQ.incoming registration" do
  after do
    NNQ.instance_variable_set(:@outgoing_proc, nil)
    NNQ.instance_variable_set(:@incoming_proc, nil)
  end

  it "registers an outgoing proc" do
    NNQ.outgoing { |msg| msg.upcase }
    refute_nil NNQ.outgoing_proc
  end

  it "registers an incoming proc" do
    NNQ.incoming { |msg| msg.downcase }
    refute_nil NNQ.incoming_proc
  end

  it "picks up registered procs during compile_expr" do
    NNQ.outgoing { |msg| msg.upcase }
    NNQ.incoming { |msg| msg.reverse }

    runner = NNQ::CLI::ReqRunner.new(
      make_config(type_name: "req"),
      NNQ::REQ
    )
    runner.send(:compile_expr)

    refute_nil runner.instance_variable_get(:@send_eval_proc)
    refute_nil runner.instance_variable_get(:@recv_eval_proc)
  end

  it "CLI flags take precedence over registered procs" do
    NNQ.outgoing { |_msg| raise "should not be called" }

    runner = NNQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "'cli_wins'"),
      NNQ::PUSH
    )
    runner.send(:compile_expr)

    result = runner.send(:eval_send_expr, ["anything"])
    assert_equal ["cli_wins"], result
  end

  it "uses registered proc when no CLI flag" do
    NNQ.incoming { |msg| msg.upcase }

    runner = NNQ::CLI::PullRunner.new(
      make_config(type_name: "pull"),
      NNQ::PULL
    )
    runner.send(:compile_expr)

    result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["HELLO"], result
  end

  it "registered outgoing works without incoming" do
    NNQ.outgoing { |msg| msg.upcase }

    runner = NNQ::CLI::ReqRunner.new(
      make_config(type_name: "req"),
      NNQ::REQ
    )
    runner.send(:compile_expr)

    refute_nil runner.instance_variable_get(:@send_eval_proc)
    assert_nil runner.instance_variable_get(:@recv_eval_proc)
  end

  it "mixes registered proc on one direction with CLI flag on the other" do
    NNQ.incoming { |msg| msg.downcase }

    runner = NNQ::CLI::ReqRunner.new(
      make_config(type_name: "req", send_expr: "$_.upcase"),
      NNQ::REQ
    )
    runner.send(:compile_expr)

    send_result = runner.send(:eval_send_expr, ["Hello"])
    assert_equal ["HELLO"], send_result

    recv_result = runner.send(:eval_recv_expr, ["Hello"])
    assert_equal ["hello"], recv_result
  end
end


# -- BEGIN/END block extraction -------------------------------------

describe "extract_blocks" do
  def ev(src = nil)
    NNQ::CLI::ExpressionEvaluator.new(src, format: :ascii)
  end

  it "extracts BEGIN and END bodies" do
    expr, begin_body, end_body = ev.send(:extract_blocks,
      'BEGIN{ @s = 0 } @s += 1 END{ puts @s }')
    assert_equal " @s = 0 ", begin_body
    assert_equal " puts @s ", end_body
    assert_equal "@s += 1", expr.strip
  end

  it "handles nested braces" do
    expr, begin_body, end_body = ev.send(:extract_blocks,
      'BEGIN{ @h = {} } $_ END{ @h.each { |k,v| puts k } }')
    assert_equal " @h = {} ", begin_body
    assert_equal " @h.each { |k,v| puts k } ", end_body
    assert_equal "$_", expr.strip
  end

  it "returns nil for missing blocks" do
    expr, begin_body, end_body = ev.send(:extract_blocks, '$_')
    assert_nil begin_body
    assert_nil end_body
    assert_equal "$_", expr
  end

  it "handles BEGIN only" do
    _, begin_body, end_body = ev.send(:extract_blocks,
      'BEGIN{ @x = 1 } $_')
    assert_equal " @x = 1 ", begin_body
    assert_nil end_body
  end

  it "handles END only" do
    _, begin_body, end_body = ev.send(:extract_blocks,
      '$_ END{ puts "done" }')
    assert_nil begin_body
    assert_equal ' puts "done" ', end_body
  end
end
