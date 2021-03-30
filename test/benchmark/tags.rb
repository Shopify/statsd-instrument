# frozen_string_literal: true

require "statsd-instrument"
require "benchmark/ips"

Benchmark.ips do |bench|
  bench.report("normalized tags with simple hash") do
    StatsD::Instrument::Metric.normalize_tags(tag: "value")
  end

  bench.report("normalized tags with simple array") do
    StatsD::Instrument::Metric.normalize_tags(["test:test"])
  end

  bench.report("normalized tags with large hash") do
    StatsD::Instrument::Metric.normalize_tags(
      mobile: true,
      pod: "1",
      protocol: "https",
      country: "Langbortistan",
      complete: true,
      shop: "omg shop that has a longer name",
    )
  end

  bench.report("normalized tags with large array") do
    StatsD::Instrument::Metric.normalize_tags([
      "mobile:true",
      "pod:1",
      "protocol:https",
      "country:Langbortistan",
      "complete:true",
      "shop:omg_shop_that_has_a_longer_name",
    ])
  end
end
