# frozen_string_literal: true

# @note This class is part of the new Client implementation that is intended
#   to become the new default in the next major release of this library.
class StatsD::Instrument::StatsDDatagramBuilder < StatsD::Instrument::DatagramBuilder
  unsupported_datagram_types :h, :d, :kv

  protected

  def normalize_tags(tags)
    raise NotImplementedError, "#{self.class.name} does not support tags" if tags
    super
  end
end
