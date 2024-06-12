# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new("test") do |t|
  t.ruby_opts << "-r rubygems"
  t.libs << "lib" << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

RuboCop::RakeTask.new(:lint) do |task|
  task.options = ["-D", "-S", "-E"]
end

RuboCop::RakeTask.new(:lint_fix) do |task|
  task.options = ["-a"]
end

task lf: :lint_fix

task(default: :test)
