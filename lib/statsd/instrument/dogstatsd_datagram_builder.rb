# frozen_string_literal: true

class StatsD::Instrument::DogStatsDDatagramBuilder < StatsD::Instrument::StatsDDatagramBuilder
  def initialize(prefix: nil, default_tags: nil)
    super
    @default_tags = normalize_tags(default_tags)
  end

  def h(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, -'h', sample_rate, tags)
  end

  def d(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, -'d', sample_rate, tags)
  end

  protected

  def generate_generic_datagram(name, value, type, sample_rate, tags)
    tags = normalize_tags(tags) + default_tags
    if tags.empty?
      super
    else
      super << "|#" << tags.join(',')
    end
  end
end
