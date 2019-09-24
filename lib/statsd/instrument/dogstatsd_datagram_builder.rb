# frozen_string_literal: true

class StatsD::Instrument::DogStatsDDatagramBuilder < StatsD::Instrument::StatsDDatagramBuilder
  unsupported_datagram_types :kv
end
