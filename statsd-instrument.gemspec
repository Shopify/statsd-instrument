# frozen-string-literal: true
# encoding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'statsd/instrument/version'

Gem::Specification.new do |spec|
  spec.name = "statsd-instrument"
  spec.version = StatsD::Instrument::VERSION
  spec.authors = ["Jesse Storimer", "Tobias Lutke", "Willem van Bergen"]
  spec.email = ["jesse@shopify.com"]
  spec.homepage = "https://github.com/Shopify/statsd-instrument"
  spec.summary = %q{A StatsD client for Ruby apps}
  spec.description = %q{A StatsD client for Ruby apps. Provides metaprogramming methods to inject StatsD instrumentation into your code.}
  spec.license = "MIT"

  spec.files = `git ls-files`.split($/)
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files = spec.files.grep(%r{^(test|spec|features)/})
  spec.extensions = ['ext/statsd/extconf.rb']
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'mocha'
  spec.add_development_dependency 'yard'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'benchmark-ips'
  spec.add_development_dependency 'rake-compiler'
end
