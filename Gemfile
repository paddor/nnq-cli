# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "minitest"
gem "rake"
gem "async-debug" if ENV["NNQ_DEV"]

gem "nnq",           path: ENV["NNQ_DEV"] ? "../nnq" : nil
gem "nnq-zstd",      path: ENV["NNQ_DEV"] ? "../nnq-zstd" : nil
gem "protocol-sp",   path: ENV["NNQ_DEV"] ? "../protocol-sp" : nil
gem "rzstd",         path: ENV["NNQ_DEV"] ? "../rzstd" : nil
