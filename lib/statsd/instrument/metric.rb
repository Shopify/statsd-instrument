# frozen_string_literal: true

# The Metric class represents a metric sample to be send by a backend.
#
# @!attribute type
#   @return [Symbol] The metric type. Must be one of {StatsD::Instrument::Metric::TYPES}
# @!attribute name
#   @return [String] The name of the metric. {StatsD#prefix} will automatically be applied
#     to the metric in the constructor, unless the <tt>:no_prefix</tt> option is set or is
#     overridden by the <tt>:prefix</tt> option. Note that <tt>:no_prefix</tt> has greater
#     precedence than <tt>:prefix</tt>.
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
  unless Regexp.method_defined?(:match?) # for ruby 2.3
    module RubyBackports
      refine Regexp do
        def match?(str)
          (self =~ str) != nil
        end
      end
    end

    using RubyBackports
  end

  def self.new(type:, name:, value: default_value(type), tags: nil, metadata: nil,
    sample_rate: StatsD.legacy_singleton_client.default_sample_rate)

    # pass keyword arguments as positional arguments for performance reasons,
    # since MRI's C implementation of new turns keyword arguments into a hash
    super(type, name, value, sample_rate, tags, metadata)
  end

  # The default value for this metric, which will be used if it is not set.
  #
  # A default value is only defined for counter metrics (<tt>1</tt>). For all other
  # metric types, this method will raise an <tt>ArgumentError</tt>.
  #
  #
  # A default value is only defined for counter metrics (<tt>1</tt>). For all other
  # metric types, this method will raise an <tt>ArgumentError</tt>.
  #
  # @return [Numeric, String] The default value for this metric.
  # @raise ArgumentError if the metric type doesn't have a default value
  def self.default_value(type)
    case type
    when :c then 1
    else raise ArgumentError, "A value is required for metric type #{type.inspect}."
    end
  end

  attr_accessor :type, :name, :value, :sample_rate, :tags, :metadata

  # Initializes a new metric instance.
  # Normally, you don't want to call this method directly, but use one of the metric collection
  # methods on the {StatsD} module.
  #
  # @param type [Symbol] The type of the metric.
  # @option name [String] :name The name of the metric without prefix.
  # @option value [Numeric, String, nil] The value to collect for the metric.
  # @option sample_rate [Numeric, nil] The sample rate to use. If not set, it will use
  #   {StatsD#default_sample_rate}.
  # @option tags [Array<String>, Hash<String, String>, nil] :tags The tags to apply to this metric.
  #   See {.normalize_tags} for more information.
  def initialize(type, name, value, sample_rate, tags, metadata) # rubocop:disable Metrics/ParameterLists
    raise ArgumentError, "Metric :type is required." unless type
    raise ArgumentError, "Metric :name is required." unless name
    raise ArgumentError, "Metric :value is required." unless value

    @type = type
    @name = normalize_name(name)
    @value = value
    @sample_rate = sample_rate
    @tags = StatsD::Instrument::Metric.normalize_tags(tags)
    if StatsD.legacy_singleton_client.default_tags
      @tags = Array(@tags) + StatsD.legacy_singleton_client.default_tags
    end
    @metadata = metadata
  end

  # @private
  # @return [String]
  def to_s
    str = +"#{name}:#{value}|#{type}"
    str << "|@#{sample_rate}" if sample_rate && sample_rate != 1.0
    str << "|#" << tags.join(',') if tags && !tags.empty?
    str
  end

  # @private
  # @return [String]
  def inspect
    "#<StatsD::Instrument::Metric #{self}>"
  end

  # The metric types that are supported by this library. Note that every StatsD server
  # implementation only supports a subset of them.
  TYPES = {
    c: 'increment',
    ms: 'measure',
    g: 'gauge',
    h: 'histogram',
    d: 'distribution',
    kv: 'key/value',
    s: 'set',
  }

  # Strip metric names of special characters used by StatsD line protocol, replace with underscore
  #
  # @param name [String]
  # @return [String]
  def normalize_name(name)
    # fast path when no normalization is needed to avoid copying the string
    return name unless /[:|@]/.match?(name)

    name.tr(':|@', '_')
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
    tags = tags.map { |k, v| k.to_s + ":" + v.to_s } if tags.is_a?(Hash)

    # fast path when no string replacement is needed
    return tags unless tags.any? { |tag| /[|,]/.match?(tag) }

    tags.map { |tag| tag.tr('|,', '') }
  end
end
