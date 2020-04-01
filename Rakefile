# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

GEMSPEC = eval(File.read('statsd-instrument.gemspec'))

require 'rake/extensiontask'
Rake::ExtensionTask.new('statsd', GEMSPEC) do |ext|
  ext.ext_dir = 'ext/statsd'
  ext.lib_dir = 'lib/statsd/instrument/ext'
end
task :build => :compile

Rake::TestTask.new('test') do |t|
  t.ruby_opts << '-r rubygems'
  t.libs << 'lib' << 'test'
  t.test_files = FileList['test/**/*_test.rb']
end

task :test => :build

task default: :test
