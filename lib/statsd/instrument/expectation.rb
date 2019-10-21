# frozen_string_literal: true

# @private
class StatsD::Instrument::Expectation
  class << self
    def increment(name, **options)
      new(type: :c, name: name, **options)
    end

    def measure(name, **options)
      new(type: :ms, name: name, **options)
    end

    def gauge(name, **options)
      new(type: :g, name: name, **options)
    end

    def set(name, **options)
      new(type: :s, name: name, **options)
    end

    def key_value(name, **options)
      new(type: :kv, name: name, **options)
    end

    def distribution(name, **options)
      new(type: :d, name: name, **options)
    end

    def histogram(name, **options)
      new(type: :h, name: name, **options)
    end
  end

  attr_accessor :times, :type, :name, :value, :sample_rate, :tags
  attr_reader :ignore_tags

  def initialize(client: StatsD.singleton_client, type:, name:, value: nil, sample_rate: nil,
    tags: nil, ignore_tags: nil, no_prefix: false, times: 1)

    @type = type
    @name = client.prefix ? "#{client.prefix}.#{name}" : name unless no_prefix
    @value = normalized_value_for_type(type, value) if value
    @sample_rate = sample_rate
    @tags = StatsD::Instrument::Metric.normalize_tags(tags)
    @ignore_tags = StatsD::Instrument::Metric.normalize_tags(ignore_tags)
    @times = times
  end

  def normalized_value_for_type(type, value)
    case type
    when :c then Integer(value)
    when :g, :h, :d, :kv, :ms then Float(value)
    when :s then String(value)
    else value
    end
  end

  def matches(actual_metric)
    return false if sample_rate && sample_rate != actual_metric.sample_rate
    return false if value && value != normalized_value_for_type(actual_metric.type, actual_metric.value)

    if tags
      expected_tags = Set.new(tags)
      actual_tags = Set.new(actual_metric.tags)

      if ignore_tags
        ignored_tags = Set.new(ignore_tags) - expected_tags
        actual_tags -= ignored_tags

        if ignore_tags.is_a?(Array)
          actual_tags.delete_if { |key| ignore_tags.include?(key.split(":").first) }
        end
      end

      return expected_tags.subset?(actual_tags)
    end
    true
  end

  def to_s
    str = +"#{name}:#{value || '<anything>'}|#{type}"
    str << "|@#{sample_rate}" if sample_rate
    str << "|#" << tags.join(',') if tags
    str << " (expected #{times} times)" if times > 1
    str
  end

  def inspect
    "#<StatsD::Instrument::Expectation:\"#{self}\">"
  end
end

# For backwards compatibility
StatsD::Instrument::MetricExpectation = StatsD::Instrument::Expectation
