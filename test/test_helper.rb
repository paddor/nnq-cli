# frozen_string_literal: true

require "minitest/autorun"
require "securerandom"
require "nnq"
require "async"

require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)
Warning[:experimental] = false

# A background thread that raises during a test should abort the main
# thread immediately, not leave the test hanging on a receive from a
# dead peer. Minitest prints the exception + backtrace from the aborting
# thread, so the test fails loudly instead of silently timing out.
Thread.abort_on_exception = true
