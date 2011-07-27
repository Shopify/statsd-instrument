Gem::Specification.new do |s|
  s.name        = "statsd-instrument"
  s.version     = '1.0.0'
  s.authors     = ["Jesse Storimer"]
  s.email       = ["jstorimer@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{TODO: Write a gem summary}
  s.description = %q{TODO: Write a gem description}

  s.rubyforge_project = "statsd-instrument"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
