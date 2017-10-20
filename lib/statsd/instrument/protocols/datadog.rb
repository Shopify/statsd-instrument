module StatsD::Instrument::Protocols
  class Datadog
    def supports?(metric)
      [:c, :ms, :g, :h, :s, :_e, :_sc].include?(metric.type)
    end

    def generate_packet(metric)
      packet = ""

      case metric.type
      when :_e
        escaped_title = metric.name.tr('\n', '\\n')
        escaped_text = metric.value.tr('\n', '\\n')

        packet << "_e{#{escaped_title.size},#{escaped_text.size}}:#{escaped_title}|#{escaped_text}"
        packet << generate_metadata(metric, EVENT_OPTIONS)
      when :_sc
        packet << "_sc|#{metric.name}|#{metric.value}"
        packet << generate_metadata(metric, SERVICE_CHECK_OPTIONS)
      else
        packet << "#{metric.name}:#{metric.value}|#{metric.type}"
      end

      packet << "|@#{metric.sample_rate}" if metric.sample_rate < 1
      packet << "|##{metric.tags.join(',')}" if metric.tags
      packet
    end

    private

    EVENT_OPTIONS = {
      date_happened: 'd',
      hostname: 'h',
      aggregation_key: 'k',
      priority: 'p',
      source_type_name: 's',
      alert_type: 't',
    }

    SERVICE_CHECK_OPTIONS = {
      timestamp: 'd',
      hostname: 'h',
      message: 'm',
    }

    def generate_metadata(metric, options)
      (metric.metadata.keys & options.keys).map do |key|
        "|#{options[key]}:#{metric.metadata[key]}"
      end.join
    end
  end
end
