require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new('test') do |t|
  t.ruby_opts << '-rubygems'
  t.libs << 'lib'
  t.test_files = FileList['test/*.rb']
end

task :default => :test
