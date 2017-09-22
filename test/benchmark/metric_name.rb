require 'statsd-instrument'
require 'benchmark/ips'

Benchmark.ips do |bench|
  bench.report("normalize name") do
    StatsD::Instrument::Metric.normalize_name('metric::naaaaame')
  end
end
