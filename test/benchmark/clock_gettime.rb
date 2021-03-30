# frozen_string_literal: true

require "benchmark/ips"

Benchmark.ips do |bench|
  bench.report("Process.clock_gettime in milliseconds (int)") do
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
  end

  bench.report("Process.clock_gettime in milliseconds (float)") do
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
  end

  bench.report("Process.clock_gettime in seconds (float), multiplied by 1000") do
    1000 * Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  bench.report("Process.clock_gettime in seconds (float), multiplied by 1000.0") do
    1000.0 * Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  bench.report("Time.now, multiplied by 1000") do
    1000 * Time.now.to_f
  end

  bench.compare!
end
