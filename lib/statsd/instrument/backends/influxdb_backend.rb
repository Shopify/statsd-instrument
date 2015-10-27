module StatsD::Instrument::Backends
  # InfluxDB backend is actually a udp-compatible backend. However, it adds tag
  # support. The tag is include in metric name with this format
  # metricname#tag1=val1,tag2=val2:metricvalue|metrictype|@sample
  # It's very similar to datadog backend, however, it move the tags into metric
  # name. The backend where stat is flushed to is responsible to parse metric
  # name for getting tag values
  class InfluxDBBackend < StatsD::Instrument::Backends::UDPBackend

    def generate_packet(metric)
      command = "#{metric.name}"
      if metric.tags
        command << "##{metric.tags.join(',')}"
      end
      command << ":#{metric.value}|#{metric.type}"
      command << "|@#{metric.sample_rate}" if metric.sample_rate < 1 || (implementation == :statsite && metric.sample_rate > 1)
    end

    def tags_supported?
      true
    end
  end
end
