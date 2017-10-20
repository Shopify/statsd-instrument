module StatsD::Instrument::Protocols
  class Statsite
    def supports?(metric)
      [:c, :ms, :g, :s, :kv].include?(metric.type)
    end

    def generate_packet(metric)
      packet = "#{metric.name}:#{metric.value}|#{metric.type}"
      packet << "|@#{metric.sample_rate}" unless metric.sample_rate == 1
      packet << "\n"
      packet
    end
  end
end
