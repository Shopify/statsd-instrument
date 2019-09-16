require 'statsd-instrument'
require 'benchmark/ips'

StatsD.logger = Logger.new('/dev/null')

class Suite
  def warming(*args)
    StatsD.default_tags = if args[0] == "with default tags"
                            {:first_tag => 'first_value', :second_tag => 'second_value'}
                          else
                            nil
                          end
    puts "warming with default tags: #{StatsD.default_tags}"
  end

  def running(*args)
    StatsD.default_tags = if args[0] == "with default tags"
                            {:first_tag => 'first_value', :second_tag => 'second_value'}
                          else
                            nil
                          end
    puts "running with default tags: #{StatsD.default_tags}"
  end

  def warmup_stats(*)
  end

  def add_report(*)
  end
end

suite = Suite.new

Benchmark.ips do |bench|
  bench.config(:suite => suite)
  bench.report("without default tags") do
    StatsD.increment('GoogleBase.insert', tags: { :first_tag => 'first_value', :second_tag => 'second_value', :third_tag => 'third_value' })
  end

  bench.report("with default tags") do
    StatsD.increment('GoogleBase.insert', tags: { :third_tag => 'third_value' })
  end

  bench.compare!
end
