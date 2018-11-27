# The Metric class represents a metric sample to be send by a backend.
#
# @!attribute type
#   @return [Symbol] The metric type. Must be one of {StatsD::Instrument::Metric::TYPES}
# @!attribute name
#   @return [String] The name of the metric. {StatsD.prefix} will automatically be applied
#     to the metric in the constructor, unless the <tt>:no_prefix</tt> option is set or is 
#     overridden by the <tt>:prefix</tt> option.
# @!attribute value
#   @see #default_value
#   @return [Numeric, String] The value to collect for the metric. Depending on the metric
#     type, <tt>value</tt> can be a string, integer, or float.
# @!attribute sample_rate
#   The sample rate to use for the metric. How the sample rate is handled differs per backend.
#   The UDP backend will actually sample metric submissions based on the sample rate, while
#   the logger backend will just include the sample rate in its output for debugging purposes.
#   @see StatsD#default_sample_rate
#   @return [Float] The sample rate to use for this metric. This should be a value between
#     0 and 1. If not set, it will use the default sample rate set to {StatsD#default_sample_rate}.
# @!attribute tags
#   The tags to associate with the metric.
#   @note Only the Datadog implementation supports tags.
#   @see .normalize_tags
#   @return [Array<String>, Hash<String, String>, nil] the tags to associate with the metric.
#     You can either specify the tags as an array of strings, or a Hash of key/value pairs.
#
# @see StatsD The StatsD module contains methods that generate metric instances.
# @see StatsD::Instrument::Backend A StatsD::Instrument::Backend is used to collect metrics.
#
class StatsD::Instrument::Metric

  attr_accessor :type, :name, :value, :sample_rate, :tags, :metadata

  # Initializes a new metric instance.
  # Normally, you don't want to call this method directly, but use one of the metric collection
  # methods on the {StatsD} module.
  #
  # @option options [Symbol] :type The type of the metric.
  # @option options [String] :name The name of the metric without prefix.
  # @option options [String] :prefix Override the default StatsD prefix.
  # @option options [Boolean] :no_prefix Set to <tt>true</tt> if you don't want to apply prefix
  # @option options [Numeric, String, nil] :value The value to collect for the metric. If set to
  #   <tt>nil>/tt>, {#default_value} will be used.
  # @option options [Numeric, nil] :sample_rate The sample rate to use. If not set, it will use
  #   {StatsD#default_sample_rate}.
  # @option options [Array<String>, Hash<String, String>, nil] :tags The tags to apply to this metric.
  #   See {.normalize_tags} for more information.
  def initialize(options = {})
    @type = options[:type] or raise ArgumentError, "Metric :type is required."
    @name = options[:name] or raise ArgumentError, "Metric :name is required."
    @name = normalize_name(@name)
    @name = if options[:prefix]
      "#{options[:prefix]}.#{@name}"
    else
      StatsD.prefix && !options[:no_prefix] ? "#{StatsD.prefix}.#{@name}" : @name
    end

    @value       = options[:value] || default_value
    @sample_rate = options[:sample_rate] || StatsD.default_sample_rate
    @tags        = StatsD::Instrument::Metric.normalize_tags(options[:tags])
    @metadata    = options.reject { |k, _| [:type, :name, :value, :sample_rate, :tags].include?(k) }
  end

  # The default value for this metric, which will be used if it is not set.
  #
  # A default value is only defined for counter metrics (<tt>1</tt>). For all other
  # metric types, this emthod will raise an <tt>ArgumentError</tt>.
  #
  # @return [Numeric, String] The default value for this metric.
  # @raise ArgumentError if the metric type doesn't have a default value
  def default_value
    case type
      when :c; 1
      else raise ArgumentError, "A value is required for metric type #{type.inspect}."
    end
  end

  # @private
  # @return [String]
  def to_s
    str = "#{TYPES[type]} #{name}:#{value}"
    str << " @#{sample_rate}" if sample_rate != 1.0
    str << " " << tags.map { |t| "##{t}"}.join(' ') if tags
    str
  end

  # @private
  # @return [String]
  def inspect
    "#<StatsD::Instrument::Metric #{self.to_s}>"
  end

  # The metric types that are supported by this library. Note that every StatsD server
  # implementation only supports a subset of them.
  TYPES = {
    c:  'increment',
    ms: 'measure',
    g:  'gauge',
    h:  'histogram',
    d:  'distribution',
    kv: 'key/value',
    s:  'set',
  }

  # Strip metric names of special characters used by StatsD line protocol, replace with underscore
  #
  # @param name [String]
  # @return [String]
  def normalize_name(name)
    name.tr(':|@'.freeze, '_')
  end

  # Utility function to convert tags to the canonical form.
  #
  # - Tags specified as key value pairs will be converted into an array
  # - Tags are normalized to only use word characters and underscores.
  #
  # @param tags [Array<String>, Hash<String, String>, nil] Tags specified in any form.
  # @return [Array<String>, nil] the list of tags in canonical form.
  def self.normalize_tags(tags)
    return unless tags
    tags = tags.map { |k, v| k.to_s + ":".freeze + v.to_s } if tags.is_a?(Hash)
    tags.map { |tag| tag.tr('|,'.freeze, ''.freeze) }
  end
end
