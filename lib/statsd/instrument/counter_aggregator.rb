# frozen_string_literal: true

class CounterAggregator
  def initialize(sink)
    @sink = sink
    @counters = {}
  end

  def increment(name, value = 1, sample_rate: 1.0, tags: nil)
    key = packet_key(name, tags)
    if @counters.has_key?(key)
      if sample_rate < 1.0
        value = (value.to_f / sample_rate).round.to_i
      end
      @counters[key][:value] += value
    else
      @counters[key] = {
        name: name,
        value: value,
        tags: tags,
      }
    end
    @counters[key] ||= {
      name: name,
      tags: tags,
    }
  end

  def flush

  end

  private
  def packet_key(name, tags)
    if tags.is_a?(Hash)
      "#{name}#{tags.sort_by { |k, v| k.to_s }.to_s}"
    else
      tags.sort!
      "#{name}#{tags.join('')}"
    end
  end
end
