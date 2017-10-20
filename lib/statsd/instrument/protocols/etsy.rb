module StatsD::Instrument::Protocols
  class Etsy
    def supports?(metric)
      [:c, :ms, :g, :s].include?(metric.type)
    end

    def generate_packet(metric)
      packet = "#{metric.name}:#{metric.value}|#{metric.type}"
      packet << "|@#{metric.sample_rate}" if metric.sample_rate < 1
      packet
    end
  end
end
