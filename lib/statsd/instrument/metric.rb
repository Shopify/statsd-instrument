class StatsD::Instrument::Metric

  attr_accessor :type, :name, :value, :sample_rate, :tags

  def initialize(options = {})
    @type = options[:type] or raise ArgumentError, "Metric :type is required."
    @name = options[:name] or raise ArgumentError, "Metric :name is required."
    @name = StatsD.prefix ? "#{StatsD.prefix}.#{@name}" : @name unless options[:no_prefix]
    @value       = options[:value] || default_value
    @sample_rate = options[:sample_rate] || StatsD.default_sample_rate
    @tags        = StatsD::Instrument::Metric.normalize_tags(options[:tags])
  end

  def default_value
    case type
      when :c; 1
      else raise ArgumentError, "A value is required for metric type #{type.inspect}."
    end
  end

  def to_s
    str = "#{TYPES[type]} #{name}:#{value}"
    str << " @#{sample_rate}" if sample_rate != 1.0
    str << " " << tags.map { |t| "##{t}"}.join(' ') if tags
    str
  end

  def inspect
    "#<StatsD::Instrument::Metric #{self.to_s}>"
  end

  TYPES = {
    c:  'increment',
    ms: 'measure',
    g:  'gauge',
    h:  'histogram',
    kv: 'key/value',
    s:  'set',
  }

  def self.normalize_tags(tags)
    return if tags.nil?
    tags = tags.map { |k, v| "#{k}:#{v}" } if tags.is_a?(Hash)
    tags.map do |tag| 
      components = tag.split(':', 2)
      components.map { |c| c.gsub(/[^\w\.-]+/, '_') }.join(':')
    end
  end
end