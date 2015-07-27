module StatsD::Instrument::Backends
  class OpenTSDBBackend < UDPBackend

    DEFAULT_TAG_PREFIX = '_t_'.freeze

    def collect_metric(metric)
      unless implementation_supports_metric_type?(metric.type)
        StatsD.logger.warn("[StatsD] Metric type #{metric.type.inspect} not supported.")
        return false
      end

      if metric.sample_rate < 1.0 && rand > metric.sample_rate
        return false
      end

      write_packet(generate_packet(metric))
    end

    def implementation_supports_metric_type?(type)
      ![:h, :kv].include?(type)
    end

    def generate_packet(metric)
      command = metric.name

      if metric.tags
        command << metric.tags.map { |t| ".#{DEFAULT_TAG_PREFIX}#{t.tr(':'.freeze, '.'.freeze)}" }.join
      end

      command << ":#{metric.value}|#{metric.type}"
      command << "|@#{metric.sample_rate}" if metric.sample_rate < 1

      command
    end
  end
end
