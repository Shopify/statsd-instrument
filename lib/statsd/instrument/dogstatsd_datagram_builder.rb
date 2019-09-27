# frozen_string_literal: true

# @note This class is part of the new Client implementation that is intended
#   to become the new default in the next major release of this library.
class StatsD::Instrument::DogStatsDDatagramBuilder < StatsD::Instrument::DatagramBuilder
  unsupported_datagram_types :kv

  def latency_metric_type
    :d
  end
end
