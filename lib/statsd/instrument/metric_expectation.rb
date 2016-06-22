# @private
class StatsD::Instrument::MetricExpectation

  attr_accessor :times, :type, :name, :value, :sample_rate, :tags
  attr_reader :ignore_tags

  def initialize(options = {})
    @type = options[:type] or raise ArgumentError, "Metric :type is required."
    @name = options[:name] or raise ArgumentError, "Metric :name is required."
    @name = StatsD.prefix ? "#{StatsD.prefix}.#{@name}" : @name unless options[:no_prefix]
    @tags = StatsD::Instrument::Metric.normalize_tags(options[:tags])
    @times = options[:times] or raise ArgumentError, "Metric :times is required."
    @sample_rate = options[:sample_rate]
    @value = options[:value]
    @ignore_tags = StatsD::Instrument::Metric.normalize_tags(options[:ignore_tags])
  end

  def matches(actual_metric)
    return false if sample_rate && sample_rate != actual_metric.sample_rate
    return false if value && value != actual_metric.value

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

  def default_value
    case type
      when :c; 1
    end
  end

  TYPES = {
      c:  'increment',
      ms: 'measure',
      g:  'gauge',
      h:  'histogram',
      kv: 'key/value',
      s:  'set',
  }

  def to_s
    str = "#{TYPES[type]} #{name}:#{value}"
    str << " @#{sample_rate}" if sample_rate != 1.0
    str << " " << tags.map { |t| "##{t}"}.join(' ') if tags
    str << " times:#{times}" if times > 1
    str
  end

  def inspect
    "#<StatsD::Instrument::MetricExpectation #{self.to_s}>"
  end
end