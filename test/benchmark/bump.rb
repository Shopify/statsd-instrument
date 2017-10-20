require "statsd-instrument"
require "benchmark/ips"

ref = `git rev-parse --abbrev-ref HEAD`

StatsD.backend = StatsD::Instrument::Backends::NullBackend.new

Benchmark.ips do |bench|
  bench.report("measure on #{ref}") do
    StatsD.measure("patate", sample_rate: 1, tags: { a: "1", b: "2", c: "3" }) do
      1 + 2
    end
  end

  bench.report("increment on #{ref}") do
    StatsD.increment("poil")
  end
end
