# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/nnq/cli"
require "json"
require "stringio"

require "msgpack"

# Suppress stderr/stdout from abort/puts during validation tests.
def quietly
  orig_stderr = $stderr
  orig_stdout = $stdout
  $stderr = StringIO.new
  $stdout = StringIO.new
  yield
ensure
  $stderr = orig_stderr
  $stdout = orig_stdout
end

# Helper to build a minimal Config for unit tests.
def make_config(type_name:, **overrides)
  defaults = {
    type_name:     type_name,
    endpoints:     [],
    connects:      [],
    binds:         [],
    in_endpoints:  [],
    out_endpoints: [],
    data:          nil,
    file:          nil,
    format:        :ascii,
    subscribes:    [],
    interval:      nil,
    count:         nil,
    delay:         nil,
    timeout:       nil,
    linger:        5,
    reconnect_ivl: nil,
    send_hwm:      nil,
    sndbuf:        nil,
    rcvbuf:        nil,
    compress:      false,
    compress_in:   false,
    compress_out:  false,
    send_expr:     nil,
    recv_expr:     nil,
    parallel:      nil,
    transient:     false,
    verbose:       0,
    timestamps:    nil,
    quiet:         false,
    echo:          false,
    scripts:       [],
    recv_maxsz:    nil,
    stdin_is_tty:  true,
  }
  NNQ::CLI::Config.new(**defaults.merge(overrides))
end
