# frozen_string_literal: true

class StatsD::Instrument::StatsDDatagramBuilder < StatsD::Instrument::DatagramBuilder
  unsupported_datagram_types :h, :d, :kv

  protected

  def normalize_tags(tags)
    raise NotImplementedError, "#{self.class.name} does not support tags" if tags
    super
  end
end
