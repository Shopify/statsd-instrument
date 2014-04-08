class StatsD::Instrument::Metric

  attr_accessor :type, :name, :value, :sample_rate, :tags

  def initialize(options = {})
    @type = options[:type] or raise ArgumentError, "Metric :type is required."
    
    @name = if options[:name]
    else
      raise ArgumentError, "Metric :name is required."
    end

    @value = options[:value] || default_value
    @tags  = normalize_tags(options[:tags])
  end

  def default_value
    case type
      when :c; 1
      else raise ArgumentError, "A value is required for metric type #{type.inspect}."
    end
  end

  def normalize_tags(raw_tags)

  end
end