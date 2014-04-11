class StatsD::Instrument::Metric

  attr_accessor :type, :name, :value, :sample_rate, :tags

  def initialize(options = {})
    @type = options[:type] or raise ArgumentError, "Metric :type is required."
    @name = options[:name] or raise ArgumentError, "Metric :name is required."
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

  def self.normalize_tags(tags)
    return if tags.nil?
    tags = tags.map { |k, v| "#{k}:#{v}" } if tags.is_a?(Hash)
    tags.map do |tag| 
      components = tag.split(':', 2)
      components.map { |c| c.gsub(/[^\w\.-]+/, '_') }.join(':')
    end
  end
end