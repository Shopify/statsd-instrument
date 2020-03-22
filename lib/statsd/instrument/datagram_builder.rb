# frozen_string_literal: true

# @note This class is part of the new Client implementation that is intended
#   to become the new default in the next major release of this library.
class StatsD::Instrument::DatagramBuilder
  unless Regexp.method_defined?(:match?) # for ruby 2.3
    module RubyBackports
      refine Regexp do
        def match?(str)
          match(str) != nil
        end
      end
    end

    using RubyBackports
  end

  def self.unsupported_datagram_types(*types)
    types.each do |type|
      define_method(type) do |_, _, _, _|
        raise NotImplementedError, "Type #{type} metrics are not supported by #{self.class.name}."
      end
    end
  end

  def self.datagram_class
    StatsD::Instrument::Datagram
  end

  def initialize(prefix: nil, default_tags: nil)
    @prefix = prefix.nil? ? "" : "#{normalize_name(prefix)}."
    @default_tags = normalize_tags(default_tags)
    @tags_cache = {}
  end

  def c(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, 'c', sample_rate, tags)
  end

  def g(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, 'g', sample_rate, tags)
  end

  def ms(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, 'ms', sample_rate, tags)
  end

  def s(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, 's', sample_rate, tags)
  end

  def h(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, 'h', sample_rate, tags)
  end

  def d(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, 'd', sample_rate, tags)
  end

  def kv(name, value, sample_rate, tags)
    generate_generic_datagram(name, value, 'kv', sample_rate, tags)
  end

  def latency_metric_type
    :ms
  end

  protected

  attr_reader :prefix, :default_tags

  # Utility function to convert tags to the canonical form.
  #
  # - Tags specified as key value pairs will be converted into an array
  # - Tags are normalized to remove unsupported characters
  #
  # @param tags [Array<String>, Hash<String, String>, nil] Tags specified in any form.
  # @return [Array<String>, nil] the list of tags in canonical form.
  def normalize_tags(tags)
    return [] unless tags
    tags = tags.map { |k, v| "#{k}:#{v}" } if tags.is_a?(Hash)

    # Fast path when no string replacement is needed
    return tags unless tags.any? { |tag| /[|,]/.match?(tag) }
    tags.map { |tag| tag.tr('|,', '') }
  end

  # Utility function to remove invalid characters from a StatsD metric name
  def normalize_name(name)
    # Fast path when no normalization is needed to avoid copying the string
    return name unless /[:|@]/.match?(name)
    name.tr(':|@', '_')
  end

  def generate_generic_datagram(name, value, type, sample_rate, tags)
    tags = normalize_tags(tags) + default_tags
    datagram = +"#{@prefix}#{normalize_name(name)}:#{value}|#{type}"
    datagram << "|@#{sample_rate}" if sample_rate && sample_rate < 1
    datagram << "|##{tags.join(',')}" unless tags.empty?
    datagram
  end
end
