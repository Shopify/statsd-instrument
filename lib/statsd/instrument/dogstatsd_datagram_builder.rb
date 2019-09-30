# frozen_string_literal: true

class StatsD::Instrument::DogStatsDDatagramBuilder < StatsD::Instrument::DatagramBuilder
  unsupported_datagram_types :kv

  def latency_metric_type
    :d
  end
end
