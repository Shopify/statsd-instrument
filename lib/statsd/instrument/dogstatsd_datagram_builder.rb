# frozen_string_literal: true

class StatsD::Instrument::DogStatsDDatagramBuilder < StatsD::Instrument::DatagramBuilder
  unsupported_datagram_types :kv
end
