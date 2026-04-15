# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

namespace :test do
  desc "Run shell-based system tests under test/system/"
  task :system do
    sh "sh test/system/run_all.sh"
  end
end

task default: :test
