# frozen_string_literal: true

require_relative "lib/nnq/cli/version"

Gem::Specification.new do |s|
  s.name        = "nnq-cli"
  s.version     = NNQ::CLI::VERSION
  s.authors     = ["Patrik Wenger"]
  s.email       = ["paddor@gmail.com"]
  s.summary     = "NNQ CLI — pipe, filter, and transform SP protocol messages"
  s.description = "Command-line tool for sending and receiving nanomsg SP " \
                  "messages on any NNQ socket type (REQ/REP, PUB/SUB, " \
                  "PUSH/PULL, PAIR). Supports Ruby eval (-e/-E), script " \
                  "handlers (-r), the virtual `pipe` socket with optional " \
                  "Ractor parallelism, multiple formats (ASCII, JSON Lines, " \
                  "msgpack, Marshal), and Zstd compression. Like nngcat from " \
                  "libnng, but with Ruby superpowers."
  s.homepage    = "https://github.com/paddor/nnq-cli"
  s.license     = "ISC"

  s.required_ruby_version = ">= 4.0"

  s.files       = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE", "CHANGELOG.md"]
  s.bindir      = "exe"
  s.executables = ["nnq"]

  s.add_dependency "nnq",      "~> 0.5"
  s.add_dependency "nnq-zstd", "~> 0.1"
  s.add_dependency "msgpack"
end
