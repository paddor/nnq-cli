# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "minitest"
gem "rake"
gem "async-debug" if ENV["NNQ_DEV"]

gem "nnq",           path: ENV["NNQ_DEV"] ? "../nnq" : nil
gem "protocol-sp",   path: ENV["NNQ_DEV"] ? "../protocol-sp" : nil
gem "rlz4",          path: ENV["NNQ_DEV"] ? "../rlz4" : nil
