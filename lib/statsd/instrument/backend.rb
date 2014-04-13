class StatsD::Instrument::Backend
  def collect_metric(metric)
    raise NotImplementedError, "Use a concerete backend implementation"
  end
end

require 'statsd/instrument/backends/logger_backend'
require 'statsd/instrument/backends/null_backend'
require 'statsd/instrument/backends/capture_backend'
require 'statsd/instrument/backends/udp_backend'
