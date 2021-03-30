# frozen_string_literal: true

require "statsd-instrument"
require "benchmark/ips"

def helper_function
  a = 10
  a += a
  a -= a
  a * a
end

Benchmark.ips do |bench|
  bench.report("increment metric benchmark") do
    StatsD.increment("GoogleBase.insert", 10)
  end

  bench.report("measure metric benchmark") do
    StatsD.measure("helper_function") do
      helper_function
    end
  end

  bench.report("gauge metric benchmark") do
    StatsD.gauge("GoogleBase.insert", 12)
  end

  bench.report("set metric benchmark") do
    StatsD.set("GoogleBase.customers", "12345", sample_rate: 1.0)
  end

  bench.report("event metric benchmark") do
    StatsD.event("Event Title", "12345")
  end

  bench.report("service check metric benchmark") do
    StatsD.service_check("shipit.redis_connection", "ok")
  end
end
