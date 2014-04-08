module StatsD::Instrument::Backends
  class DatadogBackend < StatsD::Instrument::Backend
    def generate_packet(metric)
      command = metric.name
      command << "#{metric.}:#{metric.value}|#{metric.type}"
      command << "|@#{metric.sample_rate}" if metric.sample_rate < 1
      command << "|##{clean_tags(tags).join(',')}" if metric.tags
      command
    end
    end
  end
end
