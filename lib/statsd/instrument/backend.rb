# frozen_string_literal: true

# This abstract class specifies the interface a backend implementation should conform to.
# @abstract
class StatsD::Instrument::Backend
  # Collects a metric.
  #
  # @param metric [StatsD::Instrument::Metric] The metric to collect
  # @return [void]
  def collect_metric(_metric)
    raise NotImplementedError, "Use a concerete backend implementation"
  end

  def sample?(sample_rate)
    sample_rate >= 1.0 || rand < sample_rate
  end
end

require 'statsd/instrument/backends/logger_backend'
require 'statsd/instrument/backends/null_backend'
require 'statsd/instrument/backends/capture_backend'
require 'statsd/instrument/backends/udp_backend'
