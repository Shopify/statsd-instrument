# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new('test') do |t|
  t.ruby_opts << '-r rubygems'
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/**/*_test.rb']
end

task(default: :test)
