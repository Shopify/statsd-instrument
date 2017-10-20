# frozen_string_literal: true
# The Metric class represents a metric sample to be send by a backend.
#
# @!attribute type
#   @return [Symbol] The metric type. Must be one of {StatsD::Instrument::Metric::TYPES}
# @!attribute name
#   @return [String] The name of the metric. {StatsD#prefix} will automatically be applied
#     to the metric in the constructor, unless the <tt>:no_prefix</tt> option is set.
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
  class << self
    def build(client:, type:, name:, **options)
      if StatsD.prefix && !options[:no_prefix]
        name = "#{client.prefix}.#{name}"
      end

      value = options.fetch(:value) do
        case type
        when :c
          1
        when :ms
          nil
        else
          raise ArgumentError, "A value is required for metric type #{type.inspect}."
        end
      end
      metadata = options.reject do |k, _|
        [:type, :name, :value, :sample_rate, :tags].include?(k)
      end
      tags = normalize_tags(options[:tags])
      sample_rate = options[:sample_rate] || client.default_sample_rate
      discarded = options.fetch(:discarded, false)

      new(
        type: type,
        name: name,
        value: value,
        sample_rate: sample_rate,
        tags: tags,
        metadata: metadata,
        discarded: discarded,
      )
    end

    private

    def normalize_tags(tags)
      return unless tags
      if tags.is_a?(Hash)
        tags.map { |k, v| "#{k}:#{v}".tr("|,", "") }
      else
        tags.map { |tag| tag.tr("|,", "") }
      end
    end
  end

  attr_accessor(
    :type,
    :name,
    :value,
    :sample_rate,
    :tags,
    :metadata,
  )

  # Initializes a new metric instance.
  # Normally, you don't want to call this method directly, but use one of the metric collection
  # methods on the {StatsD} module.
  #
  # @option options [Symbol] :type The type of the metric.
  # @option options [String] :name The name of the metric without prefix.
  # @option options [Boolean] :no_prefix Set to <tt>true</tt> if you don't want to apply {StatsD#prefix}
  # @option options [Numeric, String, nil] :value The value to collect for the metric. If set to
  #   <tt>nil>/tt>, {#default_value} will be used.
  # @option options [Numeric, nil] :sample_rate The sample rate to use. If not set, it will use
  #   {StatsD#default_sample_rate}.
  # @option options [Array<String>, Hash<String, String>, nil] :tags The tags to apply to this metric.
  #   See {.normalize_tags} for more information.
  def initialize(
    type:,
    name:,
    value:,
    discarded: false,
    metadata: nil,
    tags: nil,
    sample_rate: nil
  )
    @type = type
    @name = name
    @value = value
    @discarded = discarded
    @metadata = metadata
    @tags = tags
    @sample_rate = sample_rate
  end

  # @private
  # @return [String]
  def to_s
    str = [TYPES[type].to_s, "#{name}:#{value}"]
    str << "@#{sample_rate}" if sample_rate != 1.0
    str << tags.map { |t| "##{t}" } if tags
    str.join(" ")
  end

  # @private
  # @return [String]
  def inspect
    "#<StatsD::Instrument::Metric #{self}>"
  end

  def discard
    @discarded = true
  end

  def discarded?
    !!@discarded
  end

  private

  TYPES = {
    c:  'increment',
    ms: 'measure',
    g:  'gauge',
    h:  'histogram',
    kv: 'key/value',
    s:  'set',
  }
end
