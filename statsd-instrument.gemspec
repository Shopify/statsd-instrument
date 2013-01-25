Gem::Specification.new do |s|
  s.name        = "statsd-instrument"
  s.version     = '1.5.0'
  s.authors     = ["Jesse Storimer", "Tobias Lutke"]
  s.email       = ["jesse@shopify.com"]
  s.homepage    = "http://github.com/shopify/statsd-instrument"

  s.summary     = %q{A StatsD client for Ruby apps}
  s.description = %q{A StatsD client for Ruby apps. Provides metaprogramming methods to inject StatsD instrumentation into your code.}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")

  s.add_development_dependency 'mocha'
end
