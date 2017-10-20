# frozen_string_literal: true
# @private
class StatsD::Instrument::MetricExpectation < SimpleDelegator
  attr_reader(
    :ignore_tags,
    :times,
  )

  def self.build(**options)
    metric = StatsD::Instrument::Metric.build(**options)

    new(
      metric,
      times: options.fetch(:times, 1),
      ignore_tags: options[:ignore_tags],
    )
  end

  def initialize(metric, times: nil, ignore_tags: nil)
    super(metric)
    @times = times
    @ignore_tags = ignore_tags
  end

  def matches(actual_metric)
    return false if sample_rate && (sample_rate != actual_metric.sample_rate)
    return false if value && (value != actual_metric.value)

    if tags
      expected_tags = Set.new(tags)
      actual_tags = Set.new(actual_metric.tags)

      if ignore_tags
        ignored_tags = Set.new(ignore_tags) - expected_tags
        actual_tags -= ignored_tags

        if ignore_tags.is_a?(Array)
          actual_tags.delete_if{ |key| ignore_tags.include?(key.split(":").first) }
        end
      end

      return expected_tags.subset?(actual_tags)
    end
    true
  end

  def to_s
    str = [__getobj__.to_s]
    str << "times:#{times}" if times > 1
    str.join(" ")
  end

  def inspect
    "#<StatsD::Instrument::MetricExpectation #{self}>"
  end
end
